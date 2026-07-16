import SwiftUI
import GameController
import QuartzCore

// ════════════════════════════════════════════════════════════
//  GazeClickCapture.swift
//  Click-based gaze sampling (iTrace-style; B. Sawyer handoff 2026-07-07).
//
//  Two capture paths on deliberately different buttons:
//  - GAZE TAPS: A/B/X/Y stay system-owned (we do NOT call
//    .handlesGameControllerEvents), so the system delivers them as taps on
//    the gazed target. Landing on this window, each tap carries a location
//    = the gaze point. This is the only path that yields gaze coordinates;
//    its rate ceiling is the UI event pipeline, measured empirically here.
//  - RAW EVENTS: L3/R3/Menu/Options pass through to GCController's
//    valueChangedHandler (per HID event, not frame-polled) — a transport
//    bench (~125–250 Hz ceiling) and sync markers, but no gaze location.
// ════════════════════════════════════════════════════════════

@MainActor
final class GazeClickManager: ObservableObject {

    @Published var tapRate: Double = 0
    @Published var rawRate: Double = 0
    @Published var totalTaps: UInt64 = 0
    @Published var totalRaw: UInt64 = 0
    @Published var lastTapLocation: CGPoint = .zero
    @Published var controllerName: String?
    @Published var showChrome = true

    private weak var session: SessionManager?
    private var tapTimes: [TimeInterval] = []
    private var rawTimes: [TimeInterval] = []
    private var seq: UInt64 = 0
    private var rateTimer: Timer?
    private var observer: NSObjectProtocol?

    func start(session: SessionManager) {
        self.session = session
        guard rateTimer == nil else { return }

        rateTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateRates() }
        }

        observer = NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect, object: nil, queue: .main
        ) { [weak self] note in
            Task { @MainActor in
                if let c = note.object as? GCController { self?.attach(c) }
            }
        }
        GCController.controllers().forEach(attach)
    }

    func stop() {
        rateTimer?.invalidate()
        rateTimer = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    func recordTap(at p: CGPoint) {
        seq += 1
        totalTaps += 1
        lastTapLocation = p
        tapTimes.append(CACurrentMediaTime())
        session?.ingestGazeClick(x: Float(p.x), y: Float(p.y), kind: "gazeTap", seq: seq)
    }

    private func recordRaw(_ button: String, at t: TimeInterval) {
        seq += 1
        totalRaw += 1
        rawTimes.append(t)
        session?.ingestGazeClick(x: nil, y: nil, kind: "raw:\(button)", seq: seq)
    }

    private func attach(_ c: GCController) {
        controllerName = c.vendorName ?? "controller"
        guard let pad = c.extendedGamepad else { return }
        // Only the buttons the system leaves to apps by default —
        // A/B/X/Y stay system-owned so presses become gaze taps instead.
        let hook: (String) -> (GCControllerButtonInput, Float, Bool) -> Void = { name in
            { [weak self] _, _, pressed in
                guard pressed else { return }
                let t = CACurrentMediaTime()
                Task { @MainActor in self?.recordRaw(name, at: t) }
            }
        }
        pad.leftThumbstickButton?.valueChangedHandler  = hook("L3")
        pad.rightThumbstickButton?.valueChangedHandler = hook("R3")
        pad.buttonMenu.valueChangedHandler             = hook("menu")
        pad.buttonOptions?.valueChangedHandler         = hook("options")
    }

    private func updateRates() {
        let now = CACurrentMediaTime()
        tapTimes.removeAll { now - $0 > 1 }
        rawTimes.removeAll { now - $0 > 1 }
        tapRate = Double(tapTimes.count)
        rawRate = Double(rawTimes.count)
    }
}

// MARK: - The gaze-net window

/// Near-transparent, hit-testable surface placed in front of the study
/// layout. Every system tap (pinch, dwell, or controller A-button) lands
/// here with its location = the gaze point, and never leaks into the
/// Moonlight/PsychoPy windows behind it.
struct GazeCaptureWindowView: View {

    @EnvironmentObject var session: SessionManager
    @EnvironmentObject var gaze: GazeClickManager

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Near-invisible but hit-testable fill. If gaze targeting
                // ignores it on-device, raise the opacity until it doesn't.
                Rectangle()
                    .fill(.white.opacity(0.01))

                if gaze.showChrome {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(.purple.opacity(0.5),
                                      style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    VStack(spacing: 4) {
                        Text("gaze net · \(Int(geo.size.width))×\(Int(geo.size.height)) pt")
                        Text(String(format: "taps %.0f/s · raw %.0f/s", gaze.tapRate, gaze.rawRate))
                            .monospacedDigit()
                        Text("cover the layout with this window · hide chrome in control panel")
                            .font(.caption2)
                            .opacity(0.7)
                    }
                    .font(.caption)
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture(coordinateSpace: .local)
                    .onEnded { e in
                        gaze.recordTap(at: e.location)
                    }
            )
        }
        .task { gaze.start(session: session) }
    }
}
