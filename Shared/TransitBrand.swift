import SwiftUI
import UIKit

/// The same Warm Minimal palette is linked into the app and its ActivityKit extension.
enum TransitBrand {
    static let coral = rgb("E85D3A")
    static let softAccent = adaptive("FBE9E2", "3B241C")
    static let background = adaptive("FAF9F7", "1C1C1E")
    static let surface = adaptive("FFFFFF", "2C2C2E")
    static let mutedSurface = adaptive("F2EFEB", "242426")
    static let primaryText = adaptive("1A1A1A", "F2F2F7")
    static let secondaryText = adaptive("6B6862", "9A9A9E")
    static let tertiaryText = adaptive("9A968F", "6E6E73")
    static let divider = adaptive("E9E5E0", "38383A")

    private static func rgb(_ hex: String) -> Color {
        let value = UInt32(hex, radix: 16)!
        return Color(.sRGB, red: Double((value >> 16) & 255) / 255,
                     green: Double((value >> 8) & 255) / 255,
                     blue: Double(value & 255) / 255, opacity: 1)
    }

    private static func adaptive(_ light: String, _ dark: String) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(rgb(traits.userInterfaceStyle == .dark ? dark : light))
        })
    }
}
