import SwiftUI

// ════════════════════════════════════════════════════════════
//  HUDVisibility.swift
//  Per-element show/hide toggles.
//  When an element is hidden, it collapses cleanly.
//  When shown in passthrough mode, it renders its own
//  backplate so it's legible against the real world.
// ════════════════════════════════════════════════════════════

/// Observable visibility state — inject via @EnvironmentObject
@MainActor
final class HUDVisibility: ObservableObject {

    // ── Panel mode ───────────────────────────────────────────

    /// true = full frosted panel behind all elements
    /// false = each element floats with its own backplate (passthrough-friendly)
    @Published var showPanel: Bool = true

    // ── Element toggles ──────────────────────────────────────

    @Published var showSpeed:    Bool = true
    @Published var showGear:     Bool = true
    @Published var showRPM:      Bool = true
    @Published var showThrottle: Bool = true
    @Published var showBrake:    Bool = true
    @Published var showFuel:     Bool = true
    @Published var showFlags:    Bool = true   // ABS / TC / HB
    @Published var showTemps:    Bool = true   // ENG / OIL
    @Published var showStatus:   Bool = true   // connection dot + car name

    // ── Presets ──────────────────────────────────────────────

    func preset(_ p: Preset) {
        switch p {
        case .full:
            showPanel = true
            showSpeed = true; showGear = true; showRPM = true
            showThrottle = true; showBrake = true; showFuel = true
            showFlags = true; showTemps = true; showStatus = true

        case .minimal:
            showPanel = false
            showSpeed = true; showGear = true; showRPM = false
            showThrottle = false; showBrake = false; showFuel = false
            showFlags = false; showTemps = false; showStatus = false

        case .passthroughClean:
            // No panel, just the critical numbers floating with backplates
            showPanel = false
            showSpeed = true; showGear = true; showRPM = true
            showThrottle = true; showBrake = true; showFuel = true
            showFlags = false; showTemps = false; showStatus = false

        case .dataOnly:
            showPanel = true
            showSpeed = false; showGear = false; showRPM = true
            showThrottle = true; showBrake = true; showFuel = true
            showFlags = true; showTemps = true; showStatus = true
        }
    }

    enum Preset: String, CaseIterable {
        case full             = "Full"
        case minimal          = "Minimal"
        case passthroughClean = "Passthrough"
        case dataOnly         = "Data only"
    }
}

// ════════════════════════════════════════════════════════════
//  PassthroughBackplate
//  Applied to any HUD element that needs to be legible
//  against the real world when showPanel = false.
// ════════════════════════════════════════════════════════════

struct PassthroughBackplate: ViewModifier {

    let visible: Bool      // is the panel showing?
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if visible {
            // Panel is on — no individual backplate needed
            content
        } else {
            // Panel is off — wrap in standalone backplate
            content
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.black.opacity(HUDTokens.Passthrough.elementBackplate))
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .strokeBorder(
                                    .white.opacity(HUDTokens.Passthrough.border),
                                    lineWidth: 0.5
                                )
                        )
                )
        }
    }
}

extension View {
    func passthroughBackplate(panelVisible: Bool, cornerRadius: CGFloat = 10) -> some View {
        modifier(PassthroughBackplate(visible: panelVisible, cornerRadius: cornerRadius))
    }
}
