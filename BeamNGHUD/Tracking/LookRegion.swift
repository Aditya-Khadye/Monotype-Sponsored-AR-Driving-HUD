import Foundation

// ════════════════════════════════════════════════════════════
//  LookRegion.swift
//  Angular-zone model for head-direction attention classification.
//
//  NOTE: classification is by HEAD DIRECTION, not eye gaze — visionOS
//  does not expose gaze to apps. Place surfaces far enough apart that
//  switching attention requires a head turn for this to be reliable.
//  See GAZE_TRACKING_PLAN.md.
// ════════════════════════════════════════════════════════════

/// The visual surfaces a participant can attend to.
enum LookRegion: String, CaseIterable, Sendable {
    case road       // Moonlight / BeamNG driving stream (primary task)
    case hud        // BeamNG HUD
    case psychopy   // PsychoPy stream
    case other      // none of the above (looked away)
}

/// One rectangular angular zone, in degrees, centered on (azimuth, elevation).
struct LookZone: Sendable {
    let region: LookRegion
    let azimuthCenter: Float      // degrees, 0 = straight ahead, + = right
    let elevationCenter: Float    // degrees, + = up
    let azimuthHalfWidth: Float   // degrees
    let elevationHalfWidth: Float // degrees

    func contains(yaw: Float, pitch: Float) -> Bool {
        abs(yaw - azimuthCenter)   <= azimuthHalfWidth &&
        abs(pitch - elevationCenter) <= elevationHalfWidth
    }
}

/// Placeholder layout — tune these once the real surfaces are placed.
/// Default: road centered, HUD lower-right, PsychoPy lower-left, spread
/// ~32° apart so attention switches involve a head turn.
struct RegionLayout: Sendable {
    var zones: [LookZone]

    static let placeholder = RegionLayout(zones: [
        LookZone(region: .road,     azimuthCenter:   0, elevationCenter:   0, azimuthHalfWidth: 18, elevationHalfWidth: 14),
        LookZone(region: .hud,      azimuthCenter:  32, elevationCenter: -16, azimuthHalfWidth: 14, elevationHalfWidth: 12),
        LookZone(region: .psychopy, azimuthCenter: -32, elevationCenter: -16, azimuthHalfWidth: 14, elevationHalfWidth: 12),
    ])

    /// Classify a head direction into a region (first matching zone, else `.other`).
    func classify(yaw: Float, pitch: Float) -> LookRegion {
        for zone in zones where zone.contains(yaw: yaw, pitch: pitch) {
            return zone.region
        }
        return .other
    }
}
