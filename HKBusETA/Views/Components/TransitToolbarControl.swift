import SwiftUI

/// Symbol-only, naturally sized items let the navigation bar draw its own circle.
/// A padded/custom-width label makes the shared iOS 26 platter a capsule instead.
private struct TransitToolbarControl: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.buttonStyle(.automatic).labelStyle(.iconOnly)
                .buttonBorderShape(.circle)
        } else {
            content.buttonStyle(.bordered).labelStyle(.iconOnly)
                .buttonBorderShape(.circle).controlSize(.large)
                .frame(minWidth: 44, minHeight: 44)
        }
    }
}

/// Content-area icon actions use a native bordered circle, without a glass layer.
private struct TransitInlineIconControl: ViewModifier {
    func body(content: Content) -> some View {
        content.buttonStyle(.bordered).labelStyle(.iconOnly)
            .buttonBorderShape(.circle).controlSize(.large)
            .frame(minWidth: 44, minHeight: 44).contentShape(Circle())
    }
}

private struct TransitRegionSubtitle: ViewModifier {
    @Environment(AppState.self) private var app

    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.navigationSubtitle(Text(app.region.localizedName))
        } else {
            content
        }
    }
}

extension View {
    func transitToolbarControl() -> some View { modifier(TransitToolbarControl()) }
    func transitInlineIconControl() -> some View { modifier(TransitInlineIconControl()) }
    func transitRegionSubtitle() -> some View { modifier(TransitRegionSubtitle()) }
}
