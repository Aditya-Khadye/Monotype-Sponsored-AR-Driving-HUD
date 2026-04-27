import Foundation

/// Analyzes rolling telemetry windows to flag driving events.
///
/// Phase 1: Rule-based detection (current)
/// Phase 2: Replace with trained CoreML model (.mlmodel)
///
/// Detects both driving behavior events (hard braking, rapid
/// acceleration, swerving) and cognitive load indicators
/// (erratic inputs, delayed reactions, sustained high RPM).
actor DrivingAnalyzer {

    // ── Event types ──────────────────────────────────────────

    struct DrivingEvent: Sendable {
        let type: EventType
        let confidence: Float     // 0.0–1.0
        let details: [String: String]
        let sessionTimeMs: UInt64

        enum EventType: String, Codable, Sendable {
            // Driving behavior
            case hardBraking        = "HARD_BRAKING"
            case rapidAcceleration  = "RAPID_ACCELERATION"
            case highSpeedCorner    = "HIGH_SPEED_CORNER"
            case gearHunting        = "GEAR_HUNTING"

            // Cognitive load indicators
            case erraticThrottle    = "ERRATIC_THROTTLE"
            case prolongedHighRPM   = "PROLONGED_HIGH_RPM"
            case reactionDelay      = "REACTION_DELAY"
            case overcorrection     = "OVERCORRECTION"

            // Status
            case vehicleStopped     = "VEHICLE_STOPPED"
            case sessionSummary     = "SESSION_SUMMARY"
        }
    }

    // ── Rolling window ───────────────────────────────────────

    private var window: [TelemetryRecord] = []
    private let windowSize = 120   // ~2 seconds at 60Hz
    private var eventCooldowns: [DrivingEvent.EventType: UInt64] = [:]
    private let cooldownMs: UInt64 = 2000  // min 2s between same event type

    // ── Thresholds (tunable) ─────────────────────────────────

    private struct Thresholds {
        // Driving behavior
        static let hardBrakeDelta: Float = 0.4       // brake jumps 0→0.4+ in window
        static let rapidAccelDelta: Float = 0.5      // throttle jumps 0→0.5+ in window
        static let highSpeedThreshold: Float = 100.0  // km/h for corner detection
        static let gearChangeMax = 4                  // gear changes in 2s = hunting

        // Cognitive load
        static let throttleVariance: Float = 0.08     // high variance = erratic
        static let highRPMThreshold: Float = 6500.0
        static let highRPMDuration = 90               // frames (~1.5s at 60Hz)
        static let overcorrectThrottle: Float = 0.3   // large throttle oscillations
    }

    // ── Analysis entry point ─────────────────────────────────

    /// Feed a new record; returns a DrivingEvent if one is detected.
    func analyze(_ record: TelemetryRecord) -> DrivingEvent? {
        guard record.source == .outgauge else { return nil }

        // Maintain rolling window
        window.append(record)
        if window.count > windowSize {
            window.removeFirst(window.count - windowSize)
        }

        // Need minimum window before analysis
        guard window.count >= 30 else { return nil }

        let sessionTime = record.timestamp.sessionTimeMs

        // Run detectors in priority order (return first match)
        if let event = detectHardBraking(at: sessionTime) { return event }
        if let event = detectRapidAcceleration(at: sessionTime) { return event }
        if let event = detectGearHunting(at: sessionTime) { return event }
        if let event = detectErraticThrottle(at: sessionTime) { return event }
        if let event = detectProlongedHighRPM(at: sessionTime) { return event }

        return nil
    }

    /// Reset state between sessions
    func reset() {
        window.removeAll()
        eventCooldowns.removeAll()
    }

    // ── Detectors ────────────────────────────────────────────

    private func detectHardBraking(at time: UInt64) -> DrivingEvent? {
        guard canFire(.hardBraking, at: time) else { return nil }

        let recent = Array(window.suffix(15))  // last ~250ms
        guard let first = recent.first?.brake,
              let last = recent.last?.brake else { return nil }

        let delta = last - first
        if delta >= Thresholds.hardBrakeDelta {
            let speed = recent.last?.speedKMH ?? 0
            eventCooldowns[.hardBraking] = time

            return DrivingEvent(
                type: .hardBraking,
                confidence: min(1.0, delta / 0.8),
                details: [
                    "brake_delta": String(format: "%.2f", delta),
                    "speed_kmh": String(format: "%.1f", speed),
                    "brake_value": String(format: "%.2f", last)
                ],
                sessionTimeMs: time
            )
        }
        return nil
    }

    private func detectRapidAcceleration(at time: UInt64) -> DrivingEvent? {
        guard canFire(.rapidAcceleration, at: time) else { return nil }

        let recent = Array(window.suffix(15))
        guard let first = recent.first?.throttle,
              let last = recent.last?.throttle else { return nil }

        let delta = last - first
        if delta >= Thresholds.rapidAccelDelta {
            let rpm = recent.last?.rpm ?? 0
            eventCooldowns[.rapidAcceleration] = time

            return DrivingEvent(
                type: .rapidAcceleration,
                confidence: min(1.0, delta / 0.8),
                details: [
                    "throttle_delta": String(format: "%.2f", delta),
                    "rpm": String(format: "%.0f", rpm),
                    "throttle_value": String(format: "%.2f", last)
                ],
                sessionTimeMs: time
            )
        }
        return nil
    }

    private func detectGearHunting(at time: UInt64) -> DrivingEvent? {
        guard canFire(.gearHunting, at: time) else { return nil }

        let gears = window.compactMap(\.gear)
        guard gears.count >= 30 else { return nil }

        let recentGears = Array(gears.suffix(60))
        var changes = 0
        for i in 1..<recentGears.count {
            if recentGears[i] != recentGears[i - 1] { changes += 1 }
        }

        if changes >= Thresholds.gearChangeMax {
            eventCooldowns[.gearHunting] = time

            return DrivingEvent(
                type: .gearHunting,
                confidence: min(1.0, Float(changes) / 6.0),
                details: [
                    "gear_changes": "\(changes)",
                    "window_frames": "\(recentGears.count)"
                ],
                sessionTimeMs: time
            )
        }
        return nil
    }

    private func detectErraticThrottle(at time: UInt64) -> DrivingEvent? {
        guard canFire(.erraticThrottle, at: time) else { return nil }

        let throttles = window.compactMap(\.throttle)
        guard throttles.count >= 60 else { return nil }

        let recent = Array(throttles.suffix(60))
        let mean = recent.reduce(0, +) / Float(recent.count)
        let variance = recent.map { ($0 - mean) * ($0 - mean) }
            .reduce(0, +) / Float(recent.count)

        if variance >= Thresholds.throttleVariance {
            eventCooldowns[.erraticThrottle] = time

            return DrivingEvent(
                type: .erraticThrottle,
                confidence: min(1.0, variance / 0.15),
                details: [
                    "throttle_variance": String(format: "%.4f", variance),
                    "throttle_mean": String(format: "%.2f", mean)
                ],
                sessionTimeMs: time
            )
        }
        return nil
    }

    private func detectProlongedHighRPM(at time: UInt64) -> DrivingEvent? {
        guard canFire(.prolongedHighRPM, at: time) else { return nil }

        let rpms = window.compactMap(\.rpm)
        guard rpms.count >= Thresholds.highRPMDuration else { return nil }

        let recent = Array(rpms.suffix(Thresholds.highRPMDuration))
        let allHigh = recent.allSatisfy { $0 >= Thresholds.highRPMThreshold }

        if allHigh {
            let avgRPM = recent.reduce(0, +) / Float(recent.count)
            eventCooldowns[.prolongedHighRPM] = time

            return DrivingEvent(
                type: .prolongedHighRPM,
                confidence: min(1.0, (avgRPM - Thresholds.highRPMThreshold) / 1500),
                details: [
                    "avg_rpm": String(format: "%.0f", avgRPM),
                    "duration_frames": "\(Thresholds.highRPMDuration)"
                ],
                sessionTimeMs: time
            )
        }
        return nil
    }

    // ── Cooldown helper ──────────────────────────────────────

    private func canFire(_ type: DrivingEvent.EventType, at time: UInt64) -> Bool {
        guard let lastFired = eventCooldowns[type] else { return true }
        return time - lastFired >= cooldownMs
    }
}
