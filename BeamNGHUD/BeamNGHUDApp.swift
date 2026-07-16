import SwiftUI

@main
struct BeamNGHUDApp: App {

    @StateObject private var receiver:    UDPReceiver    = .shared
    @StateObject private var session:     SessionManager = SessionManager()
    @StateObject private var visibility:  HUDVisibility  = HUDVisibility()
    @StateObject private var headTracker: HeadTracker      = HeadTracker()
    @StateObject private var gazeClicks:  GazeClickManager = GazeClickManager()

    @State private var immersionStyle: ImmersionStyle = .mixed

    var body: some Scene {

        // ── Main control panel ───────────────────────────────
        WindowGroup("BeamNG HUD", id: "control") {
            ControlPanelView()
                .environmentObject(receiver)
                .environmentObject(session)
                .environmentObject(visibility)
                .environmentObject(headTracker)
                .environmentObject(gazeClicks)
                .onAppear { receiver.start() }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 420, height: 600)

        // ── HUD panel — movable visionOS window ──────────────
        // visionOS gives this a grab bar at the bottom automatically.
        // User can move it anywhere in space, resize it, and pin it
        // next to the Moonlight window.
        WindowGroup("HUD", id: "hud") {
            HUDWindowView()
                .environmentObject(receiver)
                .environmentObject(visibility)
                .environmentObject(session)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 480, height: 720)
        .windowStyle(.plain)  // no title bar — just the panel + grab bar

        // ── Gaze net — click-based gaze capture surface ──────
        // Near-transparent window the experimenter stretches over the study
        // layout; system taps land here with location = gaze point.
        WindowGroup("Gaze Net", id: "gazeNet") {
            GazeCaptureWindowView()
                .environmentObject(session)
                .environmentObject(gazeClicks)
        }
        .defaultSize(width: 1100, height: 700)
        .windowStyle(.plain)

        // ── Attention tracking immersive space (Phase 0) ─────
        // Head-direction region tracking. NOTE: opening this dismisses other
        // apps (Moonlight / PsychoPy) — see GAZE_TRACKING_PLAN.md.
        ImmersiveSpace(id: "attention") {
            AttentionImmersiveView()
                .environmentObject(session)
                .environmentObject(headTracker)
        }
        .immersionStyle(selection: $immersionStyle, in: .mixed)
    }
}
