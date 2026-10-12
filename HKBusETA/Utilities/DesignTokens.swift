import SwiftUI
import UIKit

/// Native transit: semantic surfaces, readable type, operator identity and a quiet action tint.
enum DesignTokens {
    // MARK: Colors

    /// Adaptive transit blue for actions and selection.
    static let accent = Color(light: "005FCC", dark: "64A9FF")
    /// Soft accent background for selections and badges.
    static let accentSoft = Color(light: "EAF2FF", dark: "172B47")
    /// Text/icon color on top of the accent.
    static let onAccent = Color.white

    // Semantic system surfaces
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let surfaceMuted = Color(uiColor: .tertiarySystemGroupedBackground)
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let textTertiary = Color(uiColor: .secondaryLabel)
    static let divider = Color(uiColor: .separator)

    // Functional status tints
    static let success = Color(light: "2E8B57", dark: "4CD07D")
    static let warning = Color(light: "B26A00", dark: "FFB340")

    // MARK: Typography

    /// Rounded, tabular route and arrival numerals.
    static let displayNumerals = Font.system(.largeTitle, design: .rounded, weight: .bold)
    static let display = Font.system(.title, design: .default, weight: .bold)
    static let displaySmall = Font.system(.title2, design: .default, weight: .bold)

    static let heading = Font.headline
    static let subheading = Font.subheadline.weight(.medium)
    static let body = Font.body
    static let bodyMedium = Font.body.weight(.medium)
    static let caption = Font.caption
    static let captionMedium = Font.caption.weight(.medium)
    static let footnote = Font.footnote

    /// Monospaced digits for aligned ETA columns.
    static func tabular(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size >= 20 ? .title2 : (size >= 17 ? .headline : .subheadline),
                design: .rounded, weight: weight).monospacedDigit()
    }

    // MARK: Spacing (8pt grid)

    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
    }

    // MARK: Radius

    enum Radius {
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 20
    }
}

// MARK: - Color helpers

extension Color {
    /// Hex value initializer, e.g. `Color(hex: 0xE85D3A)`.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }

    /// Hex string initializer, e.g. `Color(hex: "E85D3A")`.
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    /// Adaptive light/dark color.
    init(light lightHex: String, dark darkHex: String) {
        self.init(uiColor: UIColor(
            light: UIColor(Color(hex: lightHex)),
            dark: UIColor(Color(hex: darkHex))
        ))
    }
}

extension UIColor {
    convenience init(light: UIColor, dark: UIColor) {
        self.init { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? dark : light
        }
    }
}
