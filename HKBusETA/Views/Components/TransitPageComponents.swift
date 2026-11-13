import SwiftUI

struct TransitSectionHeading: View {
    let title: String
    var count: Int? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
            if let count {
                Text(count, format: .number).monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .textCase(nil)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
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
    func transitDepartureContent() -> some View {
        padding(.vertical, 4).frame(maxWidth: .infinity, alignment: .leading)
    }

    func transitCardRow() -> some View {
        listRowBackground(DesignTokens.surface)
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
    }

    func transitReadableWidth() -> some View {
        frame(maxWidth: DesignTokens.Layout.readableWidth)
            .frame(maxWidth: .infinity)
            .background(DesignTokens.background)
    }
}
