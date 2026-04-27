import SwiftUI

// ════════════════════════════════════════════════════════════
//  HUDTokens.swift
//  Single source of truth for ALL HUD visual decisions.
//  Change fonts, opacity, colors here — updates everywhere.
// ════════════════════════════════════════════════════════════

enum HUDTokens {

    // ── Typography ───────────────────────────────────────────
    // Swap these to change the entire HUD's font personality.

    /// Large numerics: speed, gear
    static let fontNumeric: Font = .system(
        size: HUDTokens.Size.speedDigit,
        weight: .bold,
        design: .rounded
    )

    /// Medium numerics: RPM value, percentages
    static let fontMono: Font = .system(
        size: HUDTokens.Size.monoReadout,
        weight: .regular,
        design: .monospaced
    )

    /// Small labels: BAR, RPM, THR, etc.
    static let fontLabel: Font = .system(
        size: HUDTokens.Size.label,
        weight: .medium,
        design: .monospaced
    )

    /// Gear display
    static let fontGear: Font = .system(
        size: HUDTokens.Size.gearDigit,
        weight: .bold,
        design: .rounded
    )

    /// Status / unit text
    static let fontStatus: Font = .system(
        size: HUDTokens.Size.status,
        weight: .medium,
        design: .monospaced
    )

    // ── Sizes ────────────────────────────────────────────────

    enum Size {
        static let speedDigit: CGFloat  = 80
        static let gearDigit: CGFloat   = 32
        static let monoReadout: CGFloat = 13
        static let label: CGFloat       = 10
        static let status: CGFloat      = 10
        static let panelWidth: CGFloat  = 420
        static let panelHeight: CGFloat = 270
        static let cornerRadius: CGFloat = 20
        static let padding: CGFloat     = 20
        static let rpmBarHeight: CGFloat = 6
        static let miniBarHeight: CGFloat = 4
        static let gearBoxSize: CGFloat  = 56
    }

    // ── Passthrough visibility ───────────────────────────────
    // These control how legible elements are against the real world.
    // Increase backplateOpacity if you need stronger contrast.

    enum Passthrough {
        /// Outer panel background — keep low so world shows through
        static let panelFill: CGFloat       = 0.72

        /// Per-element backplate (for hidden-element mode)
        /// Elements use this when panel bg is removed
        static let elementBackplate: CGFloat = 0.80

        /// Text contrast boost — primary text opacity
        static let primaryText: CGFloat     = 1.0

        /// Secondary text (labels, units)
        static let secondaryText: CGFloat   = 0.50

        /// Tertiary text (hints, car name)
        static let tertiaryText: CGFloat    = 0.30

        /// Bar track (unfilled portion)
        static let trackFill: CGFloat       = 0.12

        /// Border / outline opacity
        static let border: CGFloat          = 0.15
    }

    // ── Colors ───────────────────────────────────────────────

    enum Colors {
        static let accent      = Color(hex: "00D2FF")   // cyan
        static let positive    = Color(hex: "00D4A0")   // green
        static let danger      = Color(hex: "FF5252")   // red
        static let warning     = Color(hex: "FFB300")   // amber
        static let live        = Color(hex: "00D4A0")   // connection dot
        static let rpmLow      = Color(hex: "00D2FF")
        static let rpmMid      = Color(hex: "FF8800")
        static let rpmHigh     = Color(hex: "FF4444")
    }

    // ── Spacing ──────────────────────────────────────────────

    enum Spacing {
        static let xs: CGFloat  = 4
        static let sm: CGFloat  = 6
        static let md: CGFloat  = 10
        static let lg: CGFloat  = 14
        static let xl: CGFloat  = 18
    }

    // ── Animation ────────────────────────────────────────────

    enum Animation {
        static let telemetry: SwiftUI.Animation = .easeOut(duration: 0.08)
        static let flags: SwiftUI.Animation     = .easeOut(duration: 0.15)
        static let visibility: SwiftUI.Animation = .easeInOut(duration: 0.25)
    }
}

// ── Convenience Color init ───────────────────────────────────

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:  (a,r,g,b) = (255,(int>>8)*17,(int>>4&0xF)*17,(int&0xF)*17)
        case 6:  (a,r,g,b) = (255,int>>16,int>>8&0xFF,int&0xFF)
        case 8:  (a,r,g,b) = (int>>24,int>>16&0xFF,int>>8&0xFF,int&0xFF)
        default: (a,r,g,b) = (255,0,0,0)
        }
        self.init(.sRGB,
                  red:   Double(r)/255,
                  green: Double(g)/255,
                  blue:  Double(b)/255,
                  opacity: Double(a)/255)
    }
}
