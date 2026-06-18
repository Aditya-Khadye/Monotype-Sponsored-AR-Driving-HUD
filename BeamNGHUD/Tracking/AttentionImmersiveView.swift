import SwiftUI
import RealityKit
import UIKit

// ════════════════════════════════════════════════════════════
//  AttentionImmersiveView.swift
//  Immersive space that (a) renders PLACEHOLDER surfaces for road / HUD /
//  PsychoPy at the configured angular zones so you can see + verify the
//  head-direction classifier, and (b) drives HeadTracker while open.
//
//  Phase 1/2: replace the placeholder planes with the real video surfaces
//  (low-latency BeamNG stream, PsychoPy stream). See GAZE_TRACKING_PLAN.md.
// ════════════════════════════════════════════════════════════

struct AttentionImmersiveView: View {

    @EnvironmentObject var session:     SessionManager
    @EnvironmentObject var headTracker: HeadTracker
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    /// Distance of placeholder surfaces in front of the participant (meters).
    private let distance: Float = 2.0

    /// Reveal the recovery controls only when the head pitches below this
    /// (degrees). Keep it well below the lowest experimental zone so a normal
    /// glance at the HUD/PsychoPy never triggers it.
    private let revealPitchThreshold: Float = -30

    var body: some View {
        RealityView { content, attachments in
            for zone in headTracker.layout.zones where zone.region != .other {
                content.add(makePlane(for: zone))
            }
            // Recovery controls — added once, hidden, revealed on look-down.
            if let controls = attachments.entity(for: "controls") {
                controls.position = SIMD3<Float>(0, -0.75, -0.75)
                controls.isEnabled = false
                content.add(controls)
            }
        } update: { _, attachments in
            // Keep the scene clean during a trial: show the controls only when
            // the participant/experimenter looks down past the zones.
            attachments.entity(for: "controls")?.isEnabled =
                headTracker.pitchDeg < revealPitchThreshold
        } attachments: {
            Attachment(id: "controls") {
                HStack(spacing: 12) {
                    Button {
                        openWindow(id: "control")
                    } label: {
                        Label("Control Panel", systemImage: "slider.horizontal.3")
                    }
                    Button(role: .destructive) {
                        Task { await dismissImmersiveSpace() }
                    } label: {
                        Label("Exit Tracking", systemImage: "stop.circle")
                    }
                }
                .padding(14)
                .glassBackgroundEffect()
            }
        }
        .task {
            headTracker.start(session: session)
        }
        .onDisappear {
            headTracker.stop()
        }
    }

    /// A flat colored panel placed at the zone's azimuth/elevation, sized to
    /// roughly match its angular extent — purely a visual aid for Phase 0.
    private func makePlane(for zone: LookZone) -> Entity {
        let az = zone.azimuthCenter   * .pi / 180
        let el = zone.elevationCenter * .pi / 180

        // Position on a sphere of radius `distance` (origin = participant).
        let x =  distance * sin(az) * cos(el)
        let y =  distance * sin(el)
        let z = -distance * cos(az) * cos(el)

        let w = 2 * distance * tan(zone.azimuthHalfWidth   * .pi / 180)
        let h = 2 * distance * tan(zone.elevationHalfWidth * .pi / 180)

        let mesh = MeshResource.generatePlane(width: w, height: h, cornerRadius: 0.05)
        let mat  = SimpleMaterial(color: color(for: zone.region), isMetallic: false)
        let entity = ModelEntity(mesh: mesh, materials: [mat])
        entity.position = SIMD3<Float>(x, y, z)
        // Planes face +Z by default (toward the participant at the origin) —
        // left un-rotated so the front face is always visible. Good enough for
        // a Phase-0 zone indicator; real surfaces get proper orientation later.
        return entity
    }

    private func color(for region: LookRegion) -> UIColor {
        switch region {
        case .road:     return .systemGreen
        case .hud:      return .systemBlue
        case .psychopy: return .systemOrange
        case .other:    return .gray
        }
    }
}
