import SwiftUI

/// A genuinely circular toolbar surface, independent of the bar's shared capsule.
private struct CircularToolbarControl: ViewModifier {
    @Environment(\.routeTheme) private var theme
    @Environment(\.transitReduceTransparency) private var reduceTransparency

    @ViewBuilder func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), !reduceTransparency {
            control(content).glassEffect(.regular.interactive(), in: Circle())
        } else if #available(iOS 26.0, *) { opaqueControl(content) }
        else { classicControl(content) }
        #else
        classicControl(content)
        #endif
    }

    private func control(_ content: Content) -> some View {
        content.buttonStyle(.plain).labelStyle(.iconOnly)
            .foregroundStyle(theme.accent)
            .frame(width: 44, height: 44).contentShape(Circle())
    }

    private func opaqueControl(_ content: Content) -> some View {
        control(content).background(DesignTokens.surface, in: Circle())
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
    }

    private func classicControl(_ content: Content) -> some View {
        content.buttonStyle(.automatic).labelStyle(.iconOnly)
            .foregroundStyle(theme.accent)
            .frame(minWidth: 44, minHeight: 44)
    }
}

extension View {
    func transitCircularToolbarControl() -> some View { modifier(CircularToolbarControl()) }
}

extension ToolbarContent {
    @ToolbarContentBuilder func transitIndependentToolbarItem() -> some ToolbarContent {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) { self.sharedBackgroundVisibility(.hidden) }
        else { self }
        #else
        self
        #endif
    }
}
