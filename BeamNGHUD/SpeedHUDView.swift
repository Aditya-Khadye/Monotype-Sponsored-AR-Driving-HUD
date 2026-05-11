import SwiftUI
import RealityKit

// ════════════════════════════════════════════════════════════
//  SpeedHUDView.swift
//  - World-anchored but fully draggable/repositionable
//  - Display values smoothed so numbers are readable
//  - All sizes from HUDTokens
// ════════════════════════════════════════════════════════════

// MARK: - RealityKit anchor + drag

struct SpeedHUDEntity: View {

    @EnvironmentObject var receiver:   UDPReceiver
    @EnvironmentObject var visibility: HUDVisibility

    var body: some View {
        RealityView { content, attachments in
            let anchor = AnchorEntity(world: SIMD3<Float>(0, 0, -1.5))

            if let panel = attachments.entity(for: "hudPanel") {
                // Enable built-in visionOS drag to reposition
                panel.components.set(InputTargetComponent())
                panel.components.set(CollisionComponent(shapes: [
                    .generateBox(width: 0.6, height: 0.38, depth: 0.01)
                ]))
                anchor.addChild(panel)
            }
            content.add(anchor)

        } attachments: {
            Attachment(id: "hudPanel") {
                HUDPanelView(packet: receiver.latest)
                    .environmentObject(visibility)
                    .frame(
                        width:  HUDTokens.Size.panelWidth,
                        height: HUDTokens.Size.panelHeight
                    )
                    // visionOS native drag gesture — lets user grab and reposition
                    .gesture(DragGesture().targetedToAnyEntity().onChanged { _ in })
            }
        }
    }
}

// MARK: - Smoothed telemetry state

/// Holds lerped display values so numbers don't flicker at 60Hz
@MainActor
final class SmoothedTelemetry: ObservableObject {

    @Published var speed:    Double = 0
    @Published var rpm:      Double = 0
    @Published var throttle: Double = 0
    @Published var brake:    Double = 0
    @Published var fuel:     Double = 1

    private let k = HUDTokens.displayLerpFactor

    func update(from packet: OutGaugePacket?) {
        guard let p = packet else {
            return
        }
        speed    += (Double(p.speedMPH) - speed)    * k
        rpm      += (Double(p.rpm)      - rpm)      * k
        throttle += (Double(p.throttle) - throttle) * k
        brake    += (Double(p.brake)    - brake)    * k
        fuel     += (Double(p.fuel)     - fuel)     * k
    }
}

// MARK: - Panel shell

struct HUDPanelView: View {

    let packet: OutGaugePacket?
    @EnvironmentObject var vis: HUDVisibility
    @StateObject private var smooth = SmoothedTelemetry()

    // Timer drives the lerp at ~30Hz (enough for smooth visuals, not distracting)
    let timer = Timer.publish(every: 1/30, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {

            // ── Optional panel background ────────────────────
            if vis.showPanel {
                RoundedRectangle(cornerRadius: HUDTokens.Size.cornerRadius)
                    .fill(.black.opacity(HUDTokens.Passthrough.panelFill))
                    .overlay(
                        RoundedRectangle(cornerRadius: HUDTokens.Size.cornerRadius)
                            .strokeBorder(.white.opacity(HUDTokens.Passthrough.border), lineWidth: 0.5)
                    )
                    .overlay(alignment: .top) {
                        LinearGradient(
                            colors: [.clear, HUDTokens.Colors.accent.opacity(0.5), .clear],
                            startPoint: .leading, endPoint: .trailing
                        )
                        .frame(height: 1)
                        .padding(.horizontal, 50)
                        .clipShape(RoundedRectangle(cornerRadius: HUDTokens.Size.cornerRadius))
                    }
            }

            VStack(spacing: 0) {

                // ── Status row ───────────────────────────────
                if vis.showStatus {
                    StatusRow(packet: packet)
                        .passthroughBackplate(panelVisible: vis.showPanel)
                        .padding(.bottom, HUDTokens.Spacing.lg)
                }

                // ── Speed + gear ─────────────────────────────
                HStack(alignment: .bottom) {
                    if vis.showSpeed {
                        SmoothedSpeedBlock(speed: smooth.speed)
                            .passthroughBackplate(panelVisible: vis.showPanel, cornerRadius: 14)
                    }
                    Spacer()
                    if vis.showGear {
                        GearBlock(packet: packet)
                            .passthroughBackplate(panelVisible: vis.showPanel, cornerRadius: 12)
                    }
                }
                .padding(.bottom, HUDTokens.Spacing.lg)

                // ── RPM bar ──────────────────────────────────
                if vis.showRPM {
                    SmoothedRPMBar(rpm: smooth.rpm)
                        .passthroughBackplate(panelVisible: vis.showPanel)
                        .padding(.bottom, HUDTokens.Spacing.lg)
                }

                // ── Input bars ───────────────────────────────
                if vis.showThrottle || vis.showBrake || vis.showFuel {
                    HStack(spacing: HUDTokens.Spacing.md) {
                        if vis.showThrottle {
                            MiniBar(label: "THR",  value: Float(smooth.throttle), color: HUDTokens.Colors.positive)
                                .passthroughBackplate(panelVisible: vis.showPanel)
                        }
                        if vis.showBrake {
                            MiniBar(label: "BRK",  value: Float(smooth.brake),    color: HUDTokens.Colors.danger)
                                .passthroughBackplate(panelVisible: vis.showPanel)
                        }
                        if vis.showFuel {
                            MiniBar(label: "FUEL", value: Float(smooth.fuel),     color: fuelColor(Float(smooth.fuel)))
                                .passthroughBackplate(panelVisible: vis.showPanel)
                        }
                    }
                    .padding(.bottom, HUDTokens.Spacing.md)
                }

                // ── Footer ───────────────────────────────────
                if vis.showFlags || vis.showTemps {
                    Divider()
                        .opacity(vis.showPanel ? 0.15 : 0)
                        .padding(.vertical, HUDTokens.Spacing.sm)
                    HStack {
                        if vis.showFlags {
                            FlagsRow(packet: packet)
                                .passthroughBackplate(panelVisible: vis.showPanel)
                        }
                        Spacer()
                        if vis.showTemps {
                            TempsRow(packet: packet)
                                .passthroughBackplate(panelVisible: vis.showPanel)
                        }
                    }
                }
            }
            .padding(HUDTokens.Size.padding)
        }
        .onReceive(timer) { _ in
            smooth.update(from: packet)
        }
        .animation(HUDTokens.Animation.visibility, value: vis.showPanel)
    }

    private func fuelColor(_ v: Float) -> Color {
        v < 0.15 ? HUDTokens.Colors.danger : HUDTokens.Colors.warning
    }
}

// MARK: - Smoothed speed block

struct SmoothedSpeedBlock: View {
    let speed: Double
    private var speedInt: Int { Int(speed) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(speedInt)")
                .font(HUDTokens.fontNumeric)
                .monospacedDigit()
                .foregroundStyle(.white.opacity(HUDTokens.Passthrough.primaryText))
                .animation(HUDTokens.Animation.telemetry, value: speedInt)

            Text("MPH")
                .font(HUDTokens.fontStatus)
                .foregroundStyle(.white.opacity(HUDTokens.Passthrough.secondaryText))
                .kerning(2)
        }
    }
}

// MARK: - Smoothed RPM bar

struct SmoothedRPMBar: View {
    let rpm: Double
    private var norm: Double { min(rpm / 8000, 1.0) }

    var body: some View {
        VStack(spacing: HUDTokens.Spacing.xs) {
            HStack(alignment: .lastTextBaseline) {
                Text("RPM")
                    .font(HUDTokens.fontLabel)
                    .foregroundStyle(.white.opacity(HUDTokens.Passthrough.tertiaryText))
                    .kerning(2)
                Spacer()
                Text(String(format: "%.0f", rpm))
                    .font(HUDTokens.fontMono)
                    .foregroundStyle(.white.opacity(HUDTokens.Passthrough.secondaryText))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(HUDTokens.Passthrough.trackFill))
                    Capsule()
                        .fill(rpmGradient)
                        .frame(width: geo.size.width * CGFloat(norm))
                        .animation(HUDTokens.Animation.telemetry, value: norm)
                }
            }
            .frame(height: HUDTokens.Size.rpmBarHeight)
        }
    }

    private var rpmGradient: LinearGradient {
        LinearGradient(
            colors: norm > 0.85 ? [HUDTokens.Colors.rpmLow, HUDTokens.Colors.rpmHigh]
                  : norm > 0.70 ? [HUDTokens.Colors.rpmLow, HUDTokens.Colors.rpmMid]
                  : [HUDTokens.Colors.rpmLow, HUDTokens.Colors.accent],
            startPoint: .leading, endPoint: .trailing
        )
    }
}

// MARK: - StatusRow

struct StatusRow: View {
    let packet: OutGaugePacket?
    var body: some View {
        HStack(spacing: HUDTokens.Spacing.sm) {
            Circle()
                .fill(packet != nil ? HUDTokens.Colors.live : .red.opacity(0.5))
                .frame(width: 7, height: 7)
            Text(packet != nil ? "UDP LIVE · 60 HZ" : "WAITING…")
                .font(HUDTokens.fontStatus)
                .foregroundStyle(.white.opacity(HUDTokens.Passthrough.tertiaryText))
            Spacer()
            if let p = packet {
                Text(p.car.trimmingCharacters(in: .controlCharacters).uppercased())
                    .font(HUDTokens.fontStatus)
                    .foregroundStyle(HUDTokens.Colors.accent.opacity(0.6))
            }
        }
    }
}

// MARK: - GearBlock

struct GearBlock: View {
    let packet: OutGaugePacket?
    private var gear: String { packet?.gearLabel ?? "—" }
    var body: some View {
        VStack(spacing: HUDTokens.Spacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(HUDTokens.Colors.accent.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(HUDTokens.Colors.accent.opacity(0.3), lineWidth: 1.5)
                    )
                    .frame(width: HUDTokens.Size.gearBoxSize, height: HUDTokens.Size.gearBoxSize)
                Text(gear)
                    .font(HUDTokens.fontGear)
                    .foregroundStyle(gear == "R" ? HUDTokens.Colors.danger : HUDTokens.Colors.accent)
            }
            Text("GEAR")
                .font(HUDTokens.fontLabel)
                .foregroundStyle(.white.opacity(HUDTokens.Passthrough.tertiaryText))
                .kerning(2)
        }
    }
}

// MARK: - MiniBar

struct MiniBar: View {
    let label: String
    let value: Float
    let color: Color
    private var pct: Int { Int(max(0, min(1, value)) * 100) }
    var body: some View {
        VStack(spacing: HUDTokens.Spacing.xs) {
            HStack(alignment: .lastTextBaseline) {
                Text(label)
                    .font(HUDTokens.fontLabel)
                    .foregroundStyle(.white.opacity(HUDTokens.Passthrough.tertiaryText))
                    .kerning(1)
                Spacer()
                Text("\(pct)%")
                    .font(HUDTokens.fontMono)
                    .foregroundStyle(.white.opacity(HUDTokens.Passthrough.secondaryText))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(HUDTokens.Passthrough.trackFill))
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(max(0, min(1, value))))
                        .animation(HUDTokens.Animation.telemetry, value: value)
                }
            }
            .frame(height: HUDTokens.Size.miniBarHeight)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - FlagsRow

struct FlagsRow: View {
    let packet: OutGaugePacket?
    var body: some View {
        HStack(spacing: HUDTokens.Spacing.sm) {
            HUDFlag(label: "ABS", active: packet?.absActive ?? false, activeColor: HUDTokens.Colors.warning)
            HUDFlag(label: "TC",  active: packet?.tcActive  ?? false, activeColor: HUDTokens.Colors.positive)
            HUDFlag(label: "HB",  active: packet?.handbrake ?? false, activeColor: HUDTokens.Colors.danger)
        }
    }
}

struct HUDFlag: View {
    let label: String
    let active: Bool
    let activeColor: Color
    var body: some View {
        Text(label)
            .font(HUDTokens.fontLabel)
            .kerning(0.5)
            .foregroundStyle(active ? activeColor : .white.opacity(0.2))
            .padding(.horizontal, HUDTokens.Spacing.sm)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(active ? activeColor.opacity(0.15) : .white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(active ? activeColor.opacity(0.4) : .white.opacity(0.1), lineWidth: 0.5)
                    )
            )
            .animation(HUDTokens.Animation.flags, value: active)
    }
}

// MARK: - TempsRow

struct TempsRow: View {
    let packet: OutGaugePacket?
    var body: some View {
        HStack(spacing: HUDTokens.Spacing.md) {
            TempReadout(label: "ENG", value: packet?.engTemp ?? 0)
            TempReadout(label: "OIL", value: packet?.oilTemp ?? 0)
        }
    }
}

struct TempReadout: View {
    let label: String
    let value: Float
    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(label)
                .font(HUDTokens.fontLabel)
                .foregroundStyle(.white.opacity(HUDTokens.Passthrough.tertiaryText))
                .kerning(1)
            Text(String(format: "%.0f°C", value))
                .font(HUDTokens.fontMono)
                .foregroundStyle(.white.opacity(HUDTokens.Passthrough.secondaryText))
        }
    }
}

