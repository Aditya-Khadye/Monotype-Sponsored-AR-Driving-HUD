import SwiftUI

@main
struct BeamNGHUDApp: App {

    @StateObject private var receiver:   UDPReceiver   = .shared
    @StateObject private var session:    SessionManager = SessionManager()
    @StateObject private var visibility: HUDVisibility  = HUDVisibility()

    var body: some Scene {

        // ── Main control panel ───────────────────────────────
        WindowGroup("BeamNG HUD", id: "control") {
            ControlPanelView()
                .environmentObject(receiver)
                .environmentObject(session)
                .environmentObject(visibility)
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
    }
}
