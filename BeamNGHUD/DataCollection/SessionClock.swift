import Foundation
import QuartzCore

/// Provides synchronized timestamps across all data subsystems.
/// Every sensor reading, telemetry packet, and analysis event
/// gets both a monotonic session offset (for time-locking) and
/// a wall-clock UTC timestamp (for absolute reference).
///
/// Usage:
///   let clock = SessionClock()
///   clock.start()
///   let ts = clock.now()  // → SessionTimestamp
///
final class SessionClock: @unchecked Sendable {

    struct SessionTimestamp: Codable, Sendable {
        /// Monotonic offset from session start (ms) — use for time-locking
        let sessionTimeMs: UInt64
        /// Wall-clock UTC — use for absolute reference
        let utcISO: String
        /// Unix epoch seconds — use for sorting/merging
        let epochSeconds: Double
    }

    // ── State ────────────────────────────────────────────────

    private var startMach: UInt64 = 0
    private var startDate: Date = .distantPast
    private var _isRunning = false

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    var isRunning: Bool { _isRunning }

    /// Unique session ID (YYYYMMDD_HHmmss format)
    private(set) var sessionID: String = ""

    // ── Lifecycle ────────────────────────────────────────────

    func start() {
        startMach = mach_absolute_time()
        startDate = Date()
        _isRunning = true

        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd_HHmmss"
        df.timeZone = TimeZone(identifier: "UTC")
        sessionID = df.string(from: startDate)
    }

    func stop() {
        _isRunning = false
    }

    // ── Timestamp generation ─────────────────────────────────

    /// Returns a synchronized timestamp at the current instant
    func now() -> SessionTimestamp {
        let currentMach = mach_absolute_time()
        let elapsedNs = machToNanoseconds(currentMach - startMach)
        let elapsedMs = UInt64(elapsedNs / 1_000_000)

        let currentDate = Date()

        return SessionTimestamp(
            sessionTimeMs: elapsedMs,
            utcISO: Self.isoFormatter.string(from: currentDate),
            epochSeconds: currentDate.timeIntervalSince1970
        )
    }

    // ── Mach time conversion ─────────────────────────────────

    private static var timebaseInfo: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    private func machToNanoseconds(_ mach: UInt64) -> UInt64 {
        let info = Self.timebaseInfo
        return mach * UInt64(info.numer) / UInt64(info.denom)
    }
}
