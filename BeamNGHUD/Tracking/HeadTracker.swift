import Foundation
import ARKit
import QuartzCore
import simd

// ════════════════════════════════════════════════════════════
//  HeadTracker.swift
//  Samples head/device direction from ARKit (WorldTrackingProvider) while an
//  immersive space is open, classifies it into a LookRegion, tracks dwell
//  time, and pushes samples + transitions into the SessionManager pipeline.
//
//  IMPORTANT: this is HEAD direction, NOT eye gaze. visionOS never exposes
//  eye-tracking data to apps. WorldTracking (device pose) needs no privacy
//  authorization. See GAZE_TRACKING_PLAN.md.
// ════════════════════════════════════════════════════════════

@MainActor
final class HeadTracker: ObservableObject {

    // ── Published debug state (mirrored to the control panel) ─
    @Published var isTracking = false
    @Published var currentRegion: LookRegion = .other
    @Published var yawDeg: Float = 0
    @Published var pitchDeg: Float = 0
    @Published var dwellMs: UInt64 = 0
    @Published var lastError: String?

    // ── Config ───────────────────────────────────────────────
    var layout: RegionLayout = .placeholder
    /// Continuous sample rate (Hz). Transitions are always emitted immediately.
    var sampleHz: Double = 15

    // ── Pipeline sink ────────────────────────────────────────
    private weak var session: SessionManager?

    // ── ARKit ────────────────────────────────────────────────
    private let arSession = ARKitSession()
    private let worldTracking = WorldTrackingProvider()

    // ── Dwell / transition state ─────────────────────────────
    private var regionEnteredMach: UInt64 = 0
    private var loopTask: Task<Void, Never>?

    // ── Lifecycle ────────────────────────────────────────────

    func start(session: SessionManager) {
        guard loopTask == nil else { return }
        self.session = session
        loopTask = Task { await self.run() }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
        arSession.stop()
        isTracking = false
    }

    private func run() async {
        guard WorldTrackingProvider.isSupported else {
            lastError = "World tracking unsupported on this device."
            return
        }
        do {
            try await arSession.run([worldTracking])
        } catch {
            lastError = "ARKitSession.run failed: \(error.localizedDescription)"
            return
        }

        isTracking = true
        lastError = nil
        currentRegion = .other
        regionEnteredMach = mach_absolute_time()

        let intervalNs = UInt64(1_000_000_000 / max(1, sampleHz))
        while !Task.isCancelled {
            sample()
            try? await Task.sleep(nanoseconds: intervalNs)
        }
    }

    // ── One sample ───────────────────────────────────────────

    private func sample() {
        guard let anchor = worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime())
        else { return }

        let m = anchor.originFromAnchorTransform

        // The device looks down its local -Z axis; forward = -(3rd column).
        var forward = SIMD3<Float>(-m.columns.2.x, -m.columns.2.y, -m.columns.2.z)
        let len = simd_length(forward)
        if len > 0 { forward /= len }

        // azimuth: 0 = straight ahead, + = right; elevation: + = up.
        let yaw   = atan2(forward.x, -forward.z) * 180 / .pi
        let pitch = asin(max(-1, min(1, forward.y))) * 180 / .pi
        let roll  = atan2(m.columns.0.y, m.columns.1.y) * 180 / .pi

        let region   = layout.classify(yaw: yaw, pitch: pitch)
        let now      = mach_absolute_time()
        let previous = currentRegion
        let dwell    = Self.machToMs(now - regionEnteredMach)

        if region != previous {
            // transition: report dwell spent in the region just exited
            session?.ingestHeadSample(
                yaw: yaw, pitch: pitch, roll: roll,
                region: region.rawValue, dwellMs: dwell,
                transition: (from: previous.rawValue, to: region.rawValue)
            )
            regionEnteredMach = now
            dwellMs = 0
        } else {
            session?.ingestHeadSample(
                yaw: yaw, pitch: pitch, roll: roll,
                region: region.rawValue, dwellMs: dwell
            )
            dwellMs = dwell
        }

        yawDeg = yaw
        pitchDeg = pitch
        currentRegion = region
    }

    // ── Mach time → ms ───────────────────────────────────────
    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    private static func machToMs(_ mach: UInt64) -> UInt64 {
        let ns = mach * UInt64(timebase.numer) / UInt64(timebase.denom)
        return ns / 1_000_000
    }
}
