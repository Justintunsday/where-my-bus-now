import Foundation
#if canImport(SwiftUI) && canImport(UIKit) && !BUS_CONTRACT_TESTS
import SwiftUI
import UIKit
#endif

/// Serializable route identity. The extension needs neither a provider nor a database.
struct RouteTheme: Codable, Hashable, Sendable {
    let identifier: String
    let colorHex: UInt32

    static let global = Self(identifier: "warm-coral", colorHex: 0xE85D3A)

    static func resolve(route: String, operators: [String], providerHex: UInt32? = nil) -> Self {
        let route = route.uppercased()
        let line = lineColor(route: route, operators: operators)
        let hex = providerHex ?? line ?? operators.compactMap(operatorColor).first ?? global.colorHex
        return Self(identifier: "\(operators.sorted().joined(separator: "+"))/\(route)", colorHex: hex & 0xFFFFFF)
    }

    static func lineColor(route: String, operators: [String]) -> UInt32? {
        if operators.contains("mtr") {
            return ["AEL": 0x00888E, "TCL": 0xF3982D, "TML": 0x9C2E00, "TKL": 0x7E3C93,
                    "EAL": 0x5EB7E8, "SIL": 0xCBD300, "TWL": 0xE60012, "ISL": 0x0075C2,
                    "KTL": 0x00A040, "DRL": 0xEB6EA5][route.uppercased()]
        }
        if operators.contains("lightRail") {
            return ["505": 0xDA2127, "507": 0x00A652, "610": 0x551C15, "614": 0x00BFF3,
                    "614P": 0xF4858E, "615": 0xFFDD00, "615P": 0x016682, "705": 0x73BF43,
                    "706": 0xB47AB5, "751": 0xF48221, "761P": 0x6F2D91][route]
        }
        return nil
    }

    static func operatorColor(_ id: String) -> UInt32? {
        ["kmb": 0xFF4747, "ctb": 0xFFE15E, "nlb": 0x26A69A, "lrtfeeder": 0x8AC4FF,
         "gmb": 0x36C94D, "lightRail": 0xD3A809, "mtr": 0x9C2E00,
         "sunferry": 0xFF4747, "fortuneferry": 0xFF4747, "hkkf": 0xFF4747][id]
    }

    /// Existing deterministic mainland provider palette, also available to legacy activities.
    static func mainlandColor(for line: String) -> UInt32 {
        let palette: [UInt32] = [0x2F6FED, 0x0E9F6E, 0xE0245E, 0xF08C00, 0x7C3AED, 0x0E7490]
        var hash: UInt32 = 0
        for scalar in line.unicodeScalars { hash = hash &* 31 &+ scalar.value }
        return palette[Int(hash % UInt32(palette.count))]
    }

    static func luminance(_ hex: UInt32) -> Double {
        func linear(_ channel: UInt32) -> Double {
            let c = Double(channel) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear((hex >> 16) & 255)
            + 0.7152 * linear((hex >> 8) & 255) + 0.0722 * linear(hex & 255)
    }

    static func contrast(_ first: UInt32, _ second: UInt32) -> Double {
        let a = luminance(first), b = luminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// Preserve the hue while moving toward white/black only as far as readability needs.
    func readableHex(on background: UInt32, minimum: Double = 4.5) -> UInt32 {
        let endpoint: UInt32 = Self.luminance(background) < 0.4 ? 0xFFFFFF : 0
        for step in 0...100 {
            let amount = Double(step) / 100
            func channel(_ shift: UInt32) -> UInt32 {
                let a = Double((colorHex >> shift) & 255), b = Double((endpoint >> shift) & 255)
                return UInt32((a + (b - a) * amount).rounded())
            }
            let hex = (channel(16) << 16) | (channel(8) << 8) | channel(0)
            if Self.contrast(hex, background) >= minimum { return hex }
        }
        return endpoint
    }

    var foregroundHex: UInt32 {
        Self.contrast(colorHex, 0) >= Self.contrast(colorHex, 0xFFFFFF) ? 0 : 0xFFFFFF
    }
}

#if canImport(SwiftUI) && canImport(UIKit) && !BUS_CONTRACT_TESTS
extension RouteTheme {
    private static func color(_ hex: UInt32) -> Color {
        Color(.sRGB, red: Double((hex >> 16) & 255) / 255,
              green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1)
    }
    var identity: Color { Self.color(colorHex) }
    var onIdentity: Color { Self.color(foregroundHex) }
    var islandAccent: Color { Self.color(readableHex(on: 0)) }
    var accent: Color {
        Color(uiColor: UIColor { traits in
            UIColor(Self.color(readableHex(on: traits.userInterfaceStyle == .dark ? 0x2C2C2E : 0xFFFFFF)))
        })
    }
    var onAccent: Color {
        Color(uiColor: UIColor { traits in traits.userInterfaceStyle == .dark ? .black : .white })
    }
}

private struct RouteThemeKey: EnvironmentKey { static let defaultValue = RouteTheme.global }
extension EnvironmentValues {
    var routeTheme: RouteTheme {
        get { self[RouteThemeKey.self] }
        set { self[RouteThemeKey.self] = newValue }
    }
}
#endif
