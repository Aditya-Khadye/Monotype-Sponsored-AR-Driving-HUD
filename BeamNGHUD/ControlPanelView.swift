import SwiftUI

struct ControlPanelView: View {

    @EnvironmentObject var receiver:    UDPReceiver
    @EnvironmentObject var session:     SessionManager
    @EnvironmentObject var visibility:  HUDVisibility
    @EnvironmentObject var headTracker: HeadTracker
    @EnvironmentObject var gazeClicks:  GazeClickManager

    @Environment(\.openWindow) var openWindow
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    @State private var macMiniIP: String = "192.168.50.202"
    @State private var hudOpen = false
    @State private var attentionOpen = false

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
                    gazeClickSection
                    attentionSection
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

    // ── Click-based gaze capture ─────────────────────────────

    private var gazeClickSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Gaze Capture (clicks)", systemImage: "cursorarrow.click.2")
                .font(.subheadline.weight(.semibold))
            Text("System taps (pinch / dwell / controller A) land on the gaze net with their gaze location. L3/R3/Menu/Options log raw timing for the rate bench.")
                .font(.caption2).foregroundStyle(.tertiary)

            Button {
                openWindow(id: "gazeNet")
            } label: {
                Label("Open Gaze Net", systemImage: "rectangle.dashed")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)

            Toggle("Show net chrome (border + stats)", isOn: $gazeClicks.showChrome)
                .font(.callout)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "taps %.0f/s", gazeClicks.tapRate))
                        .font(.caption.monospacedDigit().weight(.semibold))
                    Text("\(gazeClicks.totalTaps) total · last (\(Int(gazeClicks.lastTapLocation.x)), \(Int(gazeClicks.lastTapLocation.y)))")
                        .font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "raw %.0f/s", gazeClicks.rawRate))
                        .font(.caption.monospacedDigit().weight(.semibold))
                    Text("\(gazeClicks.totalRaw) total")
                        .font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                }
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(gazeClicks.controllerName != nil ? .green : .orange)
                    .frame(width: 7, height: 7)
                Text(gazeClicks.controllerName ?? "no controller paired")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // ── Attention tracking (head direction) ──────────────────

    private var attentionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Attention Tracking", systemImage: "scope")
                .font(.subheadline.weight(.semibold))
            Text("Head-direction only — visionOS does not expose eye gaze. Opening the tracking space hides other apps (Moonlight/PsychoPy).")
                .font(.caption2).foregroundStyle(.tertiary)

            Button {
                Task {
                    if attentionOpen {
                        await dismissImmersiveSpace()
                        attentionOpen = false
                    } else if case .opened = await openImmersiveSpace(id: "attention") {
                        attentionOpen = true
                    }
                }
            } label: {
                Label(attentionOpen ? "Stop Tracking Space" : "Open Tracking Space",
                      systemImage: attentionOpen ? "stop.circle" : "scope")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)

            if headTracker.isTracking {
                HStack {
                    regionChip(headTracker.currentRegion)
                    Spacer()
                    Text(String(format: "yaw %.0f°  pitch %.0f°", headTracker.yawDeg, headTracker.pitchDeg))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Text("\(headTracker.dwellMs) ms")
                        .font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                }
            }
            if let err = headTracker.lastError {
                Text(err).font(.caption2).foregroundStyle(.red)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func regionChip(_ r: LookRegion) -> some View {
        Text(r.rawValue.uppercased())
            .font(.caption.weight(.bold))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(regionColor(r).opacity(0.2), in: Capsule())
            .foregroundStyle(regionColor(r))
    }

    private func regionColor(_ r: LookRegion) -> Color {
        switch r {
        case .road:     return .green
        case .hud:      return .blue
        case .psychopy: return .orange
        case .other:    return .gray
        }
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
