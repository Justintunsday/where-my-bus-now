import SwiftUI

/// Opaque content surfaces keep the route and departure readable under system bars.
private struct TransitCardSurface: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
        content
            .padding(DesignTokens.Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignTokens.surface, in: shape)
            .overlay {
                shape.strokeBorder(contrast == .increased ? Color.primary : DesignTokens.divider,
                                   lineWidth: contrast == .increased ? 1.5 : 0.5)
            }
    }
}

struct TransitSectionHeading: View {
    let title: String
    var count: Int? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.title3.weight(.bold)).foregroundStyle(.primary)
            if let count {
                Text(count, format: .number).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .textCase(nil)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .padding(.vertical, 4)
    }
}

/// Route signs do not depend on the currently selected transit region.
struct BoardingRouteSign: View {
    let target: BusTrackingTarget

    var body: some View {
        Text(target.route)
            .font(.system(.title3, design: .rounded, weight: .bold)).monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .foregroundStyle(target.resolvedTheme.onIdentity)
            .background(target.resolvedTheme.identity, in: RoundedRectangle(cornerRadius: 10))
    }
}

extension View {
    func transitCardSurface() -> some View { modifier(TransitCardSurface()) }

    func transitCardRow() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
    }

    func transitReadableWidth() -> some View {
        frame(maxWidth: DesignTokens.Layout.readableWidth)
            .frame(maxWidth: .infinity)
            .background(DesignTokens.background)
    }
}
