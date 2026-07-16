import Foundation
import Combine

/// Orchestrates the full data collection pipeline:
/// SessionClock → TelemetryRecord → RingBuffer + NetworkStreamer + DrivingAnalyzer
///
/// Supports manual start/stop and auto-start on first packet.
@MainActor
final class SessionManager: ObservableObject {

    // ── Published state ──────────────────────────────────────

    @Published var isRecording = false
    @Published var sessionDuration: TimeInterval = 0
    @Published var recordCount: UInt64 = 0
    @Published var autoStartEnabled = true
    @Published var latestAnalysis: DrivingAnalyzer.DrivingEvent?

    // ── Subsystems ───────────────────────────────────────────

    let clock = SessionClock()
    let streamer = NetworkStreamer()
    let analyzer = DrivingAnalyzer()

    /// Ring buffer: ~60s at 60Hz = 3600 records
    let buffer = RingBuffer<TelemetryRecord>(capacity: 3600)

    // ── Config ───────────────────────────────────────────────

    /// Mac Mini IP — set before connecting
    var macMiniIP: String = "192.168.50.202"
    var macMiniPort: UInt16 = 5555

    /// Auto-stop after no packets for this duration
    private let autoStopTimeout: TimeInterval = 10.0
    private var lastPacketTime: Date = .distantPast
    private var timeoutTask: Task<Void, Never>?
    private var durationTimer: Task<Void, Never>?

    // ── Session lifecycle ────────────────────────────────────

    func startSession() {
        guard !isRecording else { return }

        clock.start()
        isRecording = true
        recordCount = 0
        sessionDuration = 0
        lastPacketTime = Date()

        // Connect to Mac Mini
        Task {
            streamer.connect(ip: macMiniIP, port: macMiniPort)
        }

        // Start duration timer
        durationTimer = Task { [weak self] in
            var elapsed: TimeInterval = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                elapsed += 1
                await MainActor.run {
                    self?.sessionDuration = elapsed
                }
            }
        }

        // Log session start marker
        let startMarker = TelemetryRecord.marker(
            label: "SESSION_START",
            notes: "Session \(clock.sessionID) started",
            clock: clock
        )
        processRecord(startMarker)

        print("[Session] Started: \(clock.sessionID)")
        startAutoStopMonitor()
    }

    func stopSession() {
        guard isRecording else { return }

        // Log session end marker
        let endMarker = TelemetryRecord.marker(
            label: "SESSION_END",
            notes: "Session \(clock.sessionID) ended. Records: \(recordCount)",
            clock: clock
        )
        processRecord(endMarker)

        clock.stop()
        isRecording = false
        durationTimer?.cancel()
        timeoutTask?.cancel()
        streamer.disconnect()

        print("[Session] Stopped: \(clock.sessionID) (\(recordCount) records)")
    }

    // ── Ingest telemetry ─────────────────────────────────────

    /// Call this every time a new OutGauge packet arrives
    func ingestPacket(_ packet: OutGaugePacket) {
        // Auto-start if enabled
        if autoStartEnabled && !isRecording {
            startSession()
        }

        guard isRecording else { return }

        lastPacketTime = Date()

        // Create timestamped record
        let record = TelemetryRecord.from(packet: packet, clock: clock)
        processRecord(record)

        // Run driving analysis on rolling window
        Task {
            if let event = await analyzer.analyze(record) {
                let analysisRecord = TelemetryRecord.analysisEvent(
                    label: event.type.rawValue,
                    confidence: event.confidence,
                    details: event.details,
                    clock: clock
                )
                await MainActor.run {
                    self.latestAnalysis = event
                }
                processRecord(analysisRecord)
            }
        }
    }

    /// Add a manual event marker (e.g., participant pressed a button)
    func addMarker(label: String, notes: String? = nil) {
        guard isRecording else { return }
        let record = TelemetryRecord.marker(label: label, notes: notes, clock: clock)
        processRecord(record)
    }

    // ── Ingest head-direction / attention sample ─────────────

    /// Called by `HeadTracker` (~15 Hz) with the current head pose + region.
    /// Pass `transition` only on the sample where the region changes.
    func ingestHeadSample(
        yaw: Float, pitch: Float, roll: Float,
        region: String, dwellMs: UInt64,
        transition: (from: String, to: String)? = nil
    ) {
        guard isRecording else { return }
        let record = TelemetryRecord.headSample(
            yaw: yaw, pitch: pitch, roll: roll,
            region: region, dwellMs: dwellMs,
            transition: transition, clock: clock
        )
        processRecord(record)
    }

    // ── Ingest click-based gaze sample ───────────────────────

    /// Called by `GazeClickManager` for every system tap on the gaze net
    /// (carries gaze x/y) and every raw controller event (timing only).
    func ingestGazeClick(x: Float?, y: Float?, kind: String, seq: UInt64) {
        guard isRecording else { return }
        let record = TelemetryRecord.gazeClick(
            x: x, y: y, kind: kind, seq: seq, clock: clock
        )
        processRecord(record)
    }

    // ── Internal pipeline ────────────────────────────────────

    private func processRecord(_ record: TelemetryRecord) {
        recordCount += 1

        // 1. Buffer locally (resilience)
        Task {
            await buffer.push(record)
        }

        // 2. Stream to Mac Mini
        streamer.send(record)
    }

    // ── Auto-stop monitor ────────────────────────────────────

    private func startAutoStopMonitor() {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // check every 2s
                await MainActor.run {
                    guard let self, self.isRecording else { return }
                    let elapsed = Date().timeIntervalSince(self.lastPacketTime)
                    if elapsed > self.autoStopTimeout {
                        print("[Session] Auto-stopping (no packets for \(self.autoStopTimeout)s)")
                        self.stopSession()
                    }
                }
            }
        }
    }
}
