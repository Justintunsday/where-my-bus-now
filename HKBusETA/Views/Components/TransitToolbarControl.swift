import SwiftUI

/// System toolbar styling supplies the installed OS's material and accessibility fallback.
private struct TransitToolbarControl: ViewModifier {
    func body(content: Content) -> some View {
        content.buttonStyle(.automatic).labelStyle(.iconOnly)
            .frame(minWidth: 44, minHeight: 44)
    }
}

extension View {
    func transitToolbarControl() -> some View { modifier(TransitToolbarControl()) }
}
