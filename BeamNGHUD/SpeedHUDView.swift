import SwiftUI
import RealityKit

// ════════════════════════════════════════════════════════════
//  SpeedHUDView.swift
//  World-anchored HUD placement + panel UI.
//  All visual decisions come from HUDTokens.
//  All visibility decisions come from HUDVisibility.
// ════════════════════════════════════════════════════════════

// MARK: - RealityKit anchor

struct SpeedHUDEntity: View {

    @EnvironmentObject var receiver:   UDPReceiver
    @EnvironmentObject var visibility: HUDVisibility

    var body: some View {
        RealityView { content, attachments in
            let anchor = AnchorEntity(.head, trackingMode: .once)
            anchor.transform.translation = SIMD3<Float>(0, -0.05, -1.5)

            if let panel = attachments.entity(for: "hudPanel") {
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
            }
        }
    }
}

// MARK: - Panel shell

struct HUDPanelView: View {

    let packet: OutGaugePacket?
    @EnvironmentObject var vis: HUDVisibility

    var body: some View {
        ZStack {
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
                        .padding(.horizontal, 40)
                        .clipShape(RoundedRectangle(cornerRadius: HUDTokens.Size.cornerRadius))
                    }
                    .transition(.opacity.animation(HUDTokens.Animation.visibility))
            }

            VStack(spacing: 0) {

                if vis.showStatus {
                    StatusRow(packet: packet)
                        .passthroughBackplate(panelVisible: vis.showPanel)
                        .padding(.bottom, HUDTokens.Spacing.lg)
                }

                HStack(alignment: .bottom) {
                    if vis.showSpeed {
                        SpeedBlock(packet: packet)
                            .passthroughBackplate(panelVisible: vis.showPanel, cornerRadius: 14)
                    }
                    Spacer()
                    if vis.showGear {
                        GearBlock(packet: packet)
                            .passthroughBackplate(panelVisible: vis.showPanel, cornerRadius: 12)
                    }
                }
                .padding(.bottom, HUDTokens.Spacing.lg)

                if vis.showRPM {
                    RPMBar(packet: packet)
                        .passthroughBackplate(panelVisible: vis.showPanel)
                        .padding(.bottom, HUDTokens.Spacing.lg)
                }

                if vis.showThrottle || vis.showBrake || vis.showFuel {
                    HStack(spacing: HUDTokens.Spacing.md) {
                        if vis.showThrottle {
                            MiniBar(label: "THR", value: packet?.throttle ?? 0, color: HUDTokens.Colors.positive)
                                .passthroughBackplate(panelVisible: vis.showPanel)
                        }
                        if vis.showBrake {
                            MiniBar(label: "BRK", value: packet?.brake ?? 0, color: HUDTokens.Colors.danger)
                                .passthroughBackplate(panelVisible: vis.showPanel)
                        }
                        if vis.showFuel {
                            MiniBar(label: "FUEL", value: packet?.fuel ?? 0, color: fuelColor(packet?.fuel ?? 0))
                                .passthroughBackplate(panelVisible: vis.showPanel)
                        }
                    }
                    .padding(.bottom, HUDTokens.Spacing.md)
                }

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
        .animation(HUDTokens.Animation.visibility, value: vis.showPanel)
    }

    private func fuelColor(_ v: Float) -> Color {
        v < 0.15 ? HUDTokens.Colors.danger : HUDTokens.Colors.warning
    }
}

// MARK: - StatusRow

struct StatusRow: View {
    let packet: OutGaugePacket?
    var body: some View {
        HStack(spacing: HUDTokens.Spacing.sm) {
            Circle()
                .fill(packet != nil ? HUDTokens.Colors.live : .red.opacity(0.5))
                .frame(width: 6, height: 6)
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

// MARK: - SpeedBlock

struct SpeedBlock: View {
    let packet: OutGaugePacket?
    private var speed: Int { Int(packet?.speedKMH ?? 0) }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(speed)")
                .font(HUDTokens.fontNumeric)
                .monospacedDigit()
                .foregroundStyle(.white.opacity(HUDTokens.Passthrough.primaryText))
                .contentTransition(.numericText(value: Double(speed)))
                .animation(HUDTokens.Animation.telemetry, value: speed)
            Text("KM / H")
                .font(HUDTokens.fontStatus)
                .foregroundStyle(.white.opacity(HUDTokens.Passthrough.secondaryText))
                .kerning(2)
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
                RoundedRectangle(cornerRadius: 12)
                    .fill(HUDTokens.Colors.accent.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
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

// MARK: - RPMBar

struct RPMBar: View {
    let packet: OutGaugePacket?
    private var rpm: Float  { packet?.rpm ?? 0 }
    private var norm: Float { min(rpm / 8000, 1.0) }
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
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(active ? activeColor.opacity(0.15) : .white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(
                                active ? activeColor.opacity(0.4) : .white.opacity(0.1),
                                lineWidth: 0.5
                            )
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
