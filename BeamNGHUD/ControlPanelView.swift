import SwiftUI

struct ControlPanelView: View {

    @EnvironmentObject var receiver:   UDPReceiver
    @EnvironmentObject var session:    SessionManager
    @EnvironmentObject var visibility: HUDVisibility

    @Environment(\.openWindow) var openWindow

    @State private var macMiniIP: String = "192.168.50.202"
    @State private var hudOpen = false

    var body: some View {
        VStack(spacing: 0) {

            // ── Header ───────────────────────────────────────
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "car.fill")
                    Text("BeamNG HUD")
                        .font(.headline)
                }
                Spacer()
                connectionBadge
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    hudToggleSection
                    connectionSection
                    sessionSection
                    visibilitySection

                    if let pkt = receiver.latest {
                        telemetrySection(pkt)
                    }
                    if let event = session.latestAnalysis {
                        analysisSection(event)
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 420)
    }

    // ── HUD toggle ───────────────────────────────────────────

    private var hudToggleSection: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Floating HUD Window")
                        .font(.callout.weight(.semibold))
                    Text("Grab the bar at the bottom to move it anywhere · place next to Moonlight")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Button {
                openWindow(id: "hud")
                hudOpen = true
            } label: {
                Label("Open HUD Window", systemImage: "vision.pro")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)

            if hudOpen {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 12))
                    Text("HUD is open — grab the bottom bar to reposition it")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // ── Connection badge ─────────────────────────────────────

    private var connectionBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(receiver.isListening ? .green : .red)
                .frame(width: 8, height: 8)
            Text(receiver.isListening ? "UDP :4444" : "No UDP")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
    }

    // ── Connection section ───────────────────────────────────

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Mac Mini", systemImage: "desktopcomputer")
                .font(.subheadline.weight(.semibold))

            HStack {
                TextField("Mac Mini IP", text: $macMiniIP)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                Text(":5555")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(session.streamer.isConnected ? .green : .orange)
                    .frame(width: 7, height: 7)
                Text(session.streamer.isConnected ? "Streaming to Mac Mini" : "Not connected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if session.streamer.isConnected {
                    Text("\(session.streamer.recordsSent) sent")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // ── Session controls ─────────────────────────────────────

    private var sessionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Session", systemImage: "record.circle")
                .font(.subheadline.weight(.semibold))

            Toggle(isOn: $session.autoStartEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-start on packets")
                        .font(.callout)
                    Text("Starts recording when BeamNG data arrives")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            HStack(spacing: 12) {
                Button {
                    session.macMiniIP = macMiniIP
                    session.startSession()
                } label: {
                    Label("Start", systemImage: "record.circle")
                        .frame(minWidth: 70)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(session.isRecording)

                Button {
                    session.stopSession()
                } label: {
                    Label("Stop", systemImage: "stop.circle")
                        .frame(minWidth: 70)
                }
                .buttonStyle(.bordered)
                .disabled(!session.isRecording)

                Spacer()

                Button {
                    session.addMarker(label: "USER_MARK")
                } label: {
                    Label("Mark", systemImage: "flag")
                        .frame(minWidth: 70)
                }
                .buttonStyle(.bordered)
                .disabled(!session.isRecording)
            }

            if session.isRecording {
                HStack(spacing: 6) {
                    Image(systemName: "circle.fill")
                        .foregroundStyle(.red)
                        .font(.system(size: 8))
                        .symbolEffect(.pulse)
                    Text("Recording · \(session.recordCount) records")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                        .monospacedDigit()
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // ── Visibility controls ──────────────────────────────────

    private var visibilitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("HUD Elements", systemImage: "slider.horizontal.3")
                .font(.subheadline.weight(.semibold))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(HUDVisibility.Preset.allCases, id: \.self) { preset in
                        Button(preset.rawValue) {
                            withAnimation { visibility.preset(preset) }
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                    }
                }
            }

            Divider()

            Toggle(isOn: $visibility.showPanel) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Panel background")
                        .font(.callout)
                    Text("Off = floating elements against passthrough")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }

            let columns = [GridItem(.flexible()), GridItem(.flexible())]
            LazyVGrid(columns: columns, spacing: 8) {
                Toggle("Speed",    isOn: $visibility.showSpeed)
                Toggle("Gear",     isOn: $visibility.showGear)
                Toggle("RPM",      isOn: $visibility.showRPM)
                Toggle("Throttle", isOn: $visibility.showThrottle)
                Toggle("Brake",    isOn: $visibility.showBrake)
                Toggle("Fuel",     isOn: $visibility.showFuel)
                Toggle("Flags",    isOn: $visibility.showFlags)
                Toggle("Temps",    isOn: $visibility.showTemps)
                Toggle("Status",   isOn: $visibility.showStatus)
            }
            .font(.callout)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // ── Live telemetry ───────────────────────────────────────

    private func telemetrySection(_ pkt: OutGaugePacket) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Live", systemImage: "speedometer")
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 0) {
                miniStat("Speed", String(format: "%.0f", pkt.speedKMH), "km/h")
                Spacer()
                miniStat("RPM",   String(format: "%.0f", pkt.rpm), "")
                Spacer()
                miniStat("Gear",  pkt.gearLabel, "")
                Spacer()
                miniStat("Fuel",  String(format: "%.0f%%", pkt.fuel * 100), "")
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func miniStat(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                if !unit.isEmpty {
                    Text(unit).font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
        }
    }

    // ── Analysis feed ────────────────────────────────────────

    private func analysisSection(_ event: DrivingAnalyzer.DrivingEvent) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.type.rawValue.replacingOccurrences(of: "_", with: " "))
                    .font(.callout.weight(.medium))
                Text(String(format: "Confidence %.0f%%", event.confidence * 100))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
