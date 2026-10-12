import SwiftUI

struct RouteZoomSource: ViewModifier {
    let id: String
    let namespace: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 18.0, *), !reduceMotion { content.matchedTransitionSource(id: id, in: namespace) }
        else { content }
    }
}

struct RouteZoomDestination: ViewModifier {
    let id: String
    let namespace: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 18.0, *), !reduceMotion { content.navigationTransition(.zoom(sourceID: id, in: namespace)) }
        else { content }
    }
}
