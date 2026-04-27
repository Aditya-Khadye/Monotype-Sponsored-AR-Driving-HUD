import SwiftUI

@main
struct BeamNGHUDApp: App {

    @StateObject private var receiver:   UDPReceiver   = .shared
    @StateObject private var session:    SessionManager = SessionManager()
    @StateObject private var visibility: HUDVisibility  = HUDVisibility()

    @State private var immersiveSpaceOpen = false

    var body: some Scene {

        WindowGroup("BeamNG HUD", id: "control") {
            ControlPanelView(immersiveSpaceOpen: $immersiveSpaceOpen)
                .environmentObject(receiver)
                .environmentObject(session)
                .environmentObject(visibility)
                .onAppear { receiver.start() }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 420, height: 600)

        ImmersiveSpace(id: "SpeedHUD") {
            SpeedHUDEntity()
                .environmentObject(receiver)
                .environmentObject(visibility)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
