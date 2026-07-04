import SwiftUI
import UIKit

// MARK: - Palette (extracted from kenni-logo.png)
// Rule: chrome is black/white/gray. Color only means something — CTAs, trust,
// the verified check, scam alerts.

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }

    static let kenniInk = Color(hex: 0x0C0B1D)
    static let kenniAmber = Color(hex: 0xF4A72F)
    static let kenniCoral = Color(hex: 0xFA5B45)
    static let kenniPink = Color(hex: 0xF64081)
    static let kenniMagenta = Color(hex: 0xFB39B7)
    static let kenniViolet = Color(hex: 0x3D2DC4)
    static let kenniBlue = Color(hex: 0x307AF1)
    static let kenniSky = Color(hex: 0x1F9CE6)
    static let kenniCyan = Color(hex: 0x12BCD7)

    /// Ink in dark mode, system background in light mode.
    static let kenniBackground = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x0C / 255, green: 0x0B / 255, blue: 0x1D / 255, alpha: 1)
            : .systemBackground
    })

    static let kenniCard = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x17 / 255, green: 0x16 / 255, blue: 0x2C / 255, alpha: 1)
            : .secondarySystemBackground
    })
}

enum KenniGradient {
    /// The full sweep from the logo — HERO SIZE ONLY: big glyphs (≥ 44 pt), the large
    /// verified seal, thin card borders. Never on buttons or small chips.
    static let primary = LinearGradient(
        colors: [.kenniAmber, .kenniCoral, .kenniPink, .kenniViolet, .kenniBlue, .kenniCyan],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    /// The two-color brand pair — primary buttons and small interactive accents.
    static let brand = LinearGradient(
        colors: [.kenniPink, .kenniBlue],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Warm half — warnings, danger accents.
    static let warm = LinearGradient(
        colors: [.kenniAmber, .kenniCoral, .kenniPink],
        startPoint: .leading, endPoint: .trailing)

    /// Cool half — success, verified, trust.
    static let cool = LinearGradient(
        colors: [.kenniBlue, .kenniSky, .kenniCyan],
        startPoint: .leading, endPoint: .trailing)
}
