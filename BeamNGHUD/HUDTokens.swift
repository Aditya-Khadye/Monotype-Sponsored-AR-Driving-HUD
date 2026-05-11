import SwiftUI

// ════════════════════════════════════════════════════════════
//  HUDTokens.swift — single source of truth for all visuals
// ════════════════════════════════════════════════════════════

enum HUDTokens {

    // ── Typography ───────────────────────────────────────────
    static let fontNumeric: Font = .system(size: Size.speedDigit,  weight: .bold,   design: .rounded)
    static let fontMono:    Font = .system(size: Size.monoReadout, weight: .regular, design: .monospaced)
    static let fontLabel:   Font = .system(size: Size.label,       weight: .medium,  design: .monospaced)
    static let fontGear:    Font = .system(size: Size.gearDigit,   weight: .bold,    design: .rounded)
    static let fontStatus:  Font = .system(size: Size.status,      weight: .medium,  design: .monospaced)

    // ── Sizes ────────────────────────────────────────────────
    enum Size {
        static let speedDigit:    CGFloat = 96
        static let gearDigit:     CGFloat = 42
        static let monoReadout:   CGFloat = 18
        static let label:         CGFloat = 13
        static let status:        CGFloat = 12
        static let panelWidth:    CGFloat = 560
        static let panelHeight:   CGFloat = 340
        static let cornerRadius:  CGFloat = 24
        static let padding:       CGFloat = 28
        static let rpmBarHeight:  CGFloat = 10
        static let miniBarHeight: CGFloat = 7
        static let gearBoxSize:   CGFloat = 72
    }

    // ── Passthrough visibility ───────────────────────────────
    enum Passthrough {
        static let panelFill:        CGFloat = 0.82
        static let elementBackplate: CGFloat = 0.82
        static let primaryText:      CGFloat = 1.0
        static let secondaryText:    CGFloat = 0.60
        static let tertiaryText:     CGFloat = 0.35
        static let trackFill:        CGFloat = 0.12
        static let border:           CGFloat = 0.15
    }

    // ── Colors ───────────────────────────────────────────────
    enum Colors {
        static let accent   = Color(hex: "00D2FF")
        static let positive = Color(hex: "00D4A0")
        static let danger   = Color(hex: "FF5252")
        static let warning  = Color(hex: "FFB300")
        static let live     = Color(hex: "00D4A0")
        static let rpmLow   = Color(hex: "00D2FF")
        static let rpmMid   = Color(hex: "FF8800")
        static let rpmHigh  = Color(hex: "FF4444")
    }

    // ── Spacing ──────────────────────────────────────────────
    enum Spacing {
        static let xs: CGFloat =  4
        static let sm: CGFloat =  8
        static let md: CGFloat = 12
        static let lg: CGFloat = 18
        static let xl: CGFloat = 24
    }

    // ── Animation ────────────────────────────────────────────
    enum Animation {
        static let telemetry:  SwiftUI.Animation = .easeOut(duration: 0.15)
        static let flags:      SwiftUI.Animation = .easeOut(duration: 0.15)
        static let visibility: SwiftUI.Animation = .easeInOut(duration: 0.25)
    }

    // ── Display smoothing ────────────────────────────────────
    // Lower = smoother but more lag. 0.12 ≈ ~8Hz visual update feel.
    static let displayLerpFactor: Double = 1
}

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
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255,
                  blue: Double(b)/255, opacity: Double(a)/255)
    }
}
