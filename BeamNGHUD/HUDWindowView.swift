import SwiftUI

// ════════════════════════════════════════════════════════════
//  HUDWindowView.swift
//  The HUD panel rendered inside a native visionOS window.
//  visionOS adds the grab bar at the bottom automatically —
//  user can move it anywhere, resize it, pin it next to Moonlight.
//  No RealityKit, no world anchor needed.
// ════════════════════════════════════════════════════════════

struct HUDWindowView: View {

    @EnvironmentObject var receiver:   UDPReceiver
    @EnvironmentObject var visibility: HUDVisibility
    @EnvironmentObject var session:    SessionManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // Reading receiver.latest INSIDE the body makes the view
        // re-render whenever it changes (since UDPReceiver is @Published)
        let currentPacket = receiver.latest

        HUDPanelView(packet: currentPacket)
            .environmentObject(visibility)
            .frame(
                width:  HUDTokens.Size.panelWidth,
                height: HUDTokens.Size.panelHeight
            )
            .onChange(of: receiver.latest) { _, newPacket in
                if let pkt = newPacket {
                    session.ingestPacket(pkt)
                }
            }
            // Always-available way back to the control panel.
            .ornament(attachmentAnchor: .scene(.bottom)) {
                Button {
                    openWindow(id: "control")
                } label: {
                    Label("Control Panel", systemImage: "slider.horizontal.3")
                }
                .padding(10)
                .glassBackgroundEffect()
            }
    }
}
