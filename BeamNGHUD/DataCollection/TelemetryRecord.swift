import Foundation

/// A single timestamped telemetry record.
/// This is the canonical unit of data in the collection pipeline.
/// Every sensor reading (OutGauge, eye tracking, etc.) gets wrapped
/// in this structure with synchronized timestamps from SessionClock.
struct TelemetryRecord: Codable, Sendable {

    // ── Time-locking ─────────────────────────────────────────
    let timestamp: SessionClock.SessionTimestamp

    // ── Source identification ─────────────────────────────────
    let source: DataSource

    enum DataSource: String, Codable, Sendable {
        case outgauge       // BeamNG telemetry
        case eyeTracking    // ARKit eye tracking (future)
        case analysis       // CoreML analysis output
        case marker         // Manual event marker
    }

    // ── Vehicle telemetry (from OutGauge) ────────────────────
    var speedKMH: Float?
    var speedMS: Float?
    var rpm: Float?
    var gear: Int?
    var throttle: Float?
    var brake: Float?
    var clutch: Float?
    var fuel: Float?
    var engTemp: Float?
    var oilTemp: Float?
    var oilPressure: Float?
    var turbo: Float?

    // ── Flags ────────────────────────────────────────────────
    var absActive: Bool?
    var tcActive: Bool?
    var signalLeft: Bool?
    var signalRight: Bool?
    var handbrake: Bool?

    // ── Eye tracking (future) ────────────────────────────────
    var gazeX: Float?
    var gazeY: Float?
    var gazeZ: Float?
    var leftPupilDilation: Float?
    var rightPupilDilation: Float?
    var blinkDetected: Bool?

    // ── Analysis flags (from CoreML) ─────────────────────────
    var analysisLabel: String?
    var analysisConfidence: Float?
    var analysisDetails: [String: String]?

    // ── Event markers (manual) ───────────────────────────────
    var markerLabel: String?
    var markerNotes: String?

    // ── Factory: from OutGaugePacket ─────────────────────────

    static func from(
        packet: OutGaugePacket,
        clock: SessionClock
    ) -> TelemetryRecord {
        var record = TelemetryRecord(
            timestamp: clock.now(),
            source: .outgauge
        )
        record.speedKMH     = packet.speedKMH
        record.speedMS       = packet.speed
        record.rpm           = packet.rpm
        record.gear          = Int(packet.gear)
        record.throttle      = packet.throttle
        record.brake         = packet.brake
        record.clutch        = packet.clutch
        record.fuel          = packet.fuel
        record.engTemp       = packet.engTemp
        record.oilTemp       = packet.oilTemp
        record.oilPressure   = packet.oilPressure
        record.turbo         = packet.turbo
        record.absActive     = packet.absActive
        record.tcActive      = packet.tcActive
        record.signalLeft    = packet.signalLeft
        record.signalRight   = packet.signalRight
        record.handbrake     = packet.handbrake
        return record
    }

    // ── Factory: analysis event ──────────────────────────────

    static func analysisEvent(
        label: String,
        confidence: Float,
        details: [String: String]? = nil,
        clock: SessionClock
    ) -> TelemetryRecord {
        var record = TelemetryRecord(
            timestamp: clock.now(),
            source: .analysis
        )
        record.analysisLabel      = label
        record.analysisConfidence = confidence
        record.analysisDetails    = details
        return record
    }

    // ── Factory: manual marker ───────────────────────────────

    static func marker(
        label: String,
        notes: String? = nil,
        clock: SessionClock
    ) -> TelemetryRecord {
        var record = TelemetryRecord(
            timestamp: clock.now(),
            source: .marker
        )
        record.markerLabel = label
        record.markerNotes = notes
        return record
    }

    // ── CSV header ───────────────────────────────────────────

    static var csvHeader: String {
        [
            "session_time_ms", "utc", "epoch_s", "source",
            "speed_kmh", "speed_ms", "rpm", "gear",
            "throttle", "brake", "clutch", "fuel",
            "eng_temp", "oil_temp", "oil_pressure", "turbo",
            "abs", "tc", "signal_l", "signal_r", "handbrake",
            "gaze_x", "gaze_y", "gaze_z",
            "pupil_l", "pupil_r", "blink",
            "analysis_label", "analysis_confidence",
            "marker_label", "marker_notes"
        ].joined(separator: ",")
    }

    /// CSV row representation
    var csvRow: String {
        func f(_ v: Float?) -> String { v.map { String(format: "%.4f", $0) } ?? "" }
        func b(_ v: Bool?) -> String { v.map { $0 ? "1" : "0" } ?? "" }
        func s(_ v: String?) -> String {
            guard let v else { return "" }
            // Escape commas and quotes in strings
            if v.contains(",") || v.contains("\"") {
                return "\"\(v.replacingOccurrences(of: "\"", with: "\"\""))\""
            }
            return v
        }

        return [
            "\(timestamp.sessionTimeMs)",
            timestamp.utcISO,
            String(format: "%.3f", timestamp.epochSeconds),
            source.rawValue,
            f(speedKMH), f(speedMS), f(rpm),
            gear.map(String.init) ?? "",
            f(throttle), f(brake), f(clutch), f(fuel),
            f(engTemp), f(oilTemp), f(oilPressure), f(turbo),
            b(absActive), b(tcActive), b(signalLeft), b(signalRight), b(handbrake),
            f(gazeX), f(gazeY), f(gazeZ),
            f(leftPupilDilation), f(rightPupilDilation), b(blinkDetected),
            s(analysisLabel), f(analysisConfidence),
            s(markerLabel), s(markerNotes)
        ].joined(separator: ",")
    }
}
