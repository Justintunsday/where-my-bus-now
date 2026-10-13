import SwiftUI

struct RouteColorInfo {
    let background: Color
    let foreground: Color
}

enum RouteStyle {
    static func info(for entry: RouteEntry, provider: any TransitProvider) -> RouteColorInfo {
        let hex = provider.routeColorHex(entry: entry)
        let theme = RouteTheme.resolve(route: entry.route, operators: entry.co, providerHex: hex)
        return RouteColorInfo(background: theme.identity, foreground: theme.onIdentity)
    }

    static func textColor(for hex: UInt32) -> Color {
        RouteTheme(identifier: "badge", colorHex: hex).onIdentity
    }
}

struct RouteBadge: View {
    @Environment(AppState.self) private var app
    let route: String
    let entry: RouteEntry?
    var fontSize: CGFloat = 17
    var colorHex: UInt32?
    @ScaledMetric(relativeTo: .headline) private var typeScale: CGFloat = 1

    private var info: RouteColorInfo {
        if let colorHex {
            return RouteColorInfo(background: Color(hex: colorHex), foreground: RouteStyle.textColor(for: colorHex))
        }
        if let entry {
            return RouteStyle.info(for: entry, provider: app.provider)
        }
        return RouteColorInfo(background: RouteTheme.global.identity, foreground: RouteTheme.global.onIdentity)
    }

    var body: some View {
        Text(route)
            .font(.system(size: fontSize * typeScale, weight: .bold, design: .rounded))
            .foregroundStyle(info.foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(info.background, in: RoundedRectangle(cornerRadius: 7))
            .lineLimit(1)
    }
}
