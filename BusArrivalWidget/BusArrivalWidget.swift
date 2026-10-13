import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct BusArrivalWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BusActivityAttributes.self) { context in
            BusLockScreenView(target: context.attributes.target, state: context.state,
                              isStale: context.isStale, activityID: context.activityID)
            .activityBackgroundTint(TransitBrand.surface)
            .activitySystemActionForegroundColor(.primary)
            .widgetURL(context.attributes.target.deepLink)
        } dynamicIsland: { context in
            let display = BusActivityDisplay(target: context.attributes.target, state: context.state, isStale: context.isStale)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    BusIslandRoute(target: context.attributes.target)
                        .dynamicIsland(verticalPlacement: .belowIfTooWide)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    BusIslandExpandedArrival(display: display)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text("\(display.copy("to")) \(context.attributes.target.destination)")
                        .font(.headline).lineLimit(1).minimumScaleFactor(0.8)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    BusIslandExpandedDetails(display: display)
                }
            } compactLeading: {
                BusIslandRoute(target: context.attributes.target, compact: true)
                    .dynamicTypeSize(...DynamicTypeSize.large)
                    .frame(width: min(56, max(22, CGFloat(context.attributes.target.route.count) * 11)), alignment: .leading)
            } compactTrailing: {
                BusActivityCountdown(target: context.attributes.target, state: context.state, isStale: context.isStale)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(context.attributes.target.resolvedTheme.islandAccent)
                    .dynamicTypeSize(...DynamicTypeSize.large)
                    .environment(\.locale, context.attributes.target.locale)
                    .multilineTextAlignment(.trailing)
                    // Live-updating Text otherwise reserves the entire proposed
                    // region, making the system Island unnecessarily wide.
                    .frame(width: context.attributes.target.language == "en" ? 88 : 64, alignment: .trailing)
            } minimal: {
                Image(systemName: display.symbol).foregroundStyle(display.theme.islandAccent)
                    .font(.body).dynamicTypeSize(...DynamicTypeSize.large)
                    .accessibilityLabel("\(context.attributes.target.route) · \(display.copy(display.statusKey))")
            }
            .widgetURL(context.attributes.target.deepLink)
            .keylineTint(display.theme.identity)
        }
    }
}

#Preview("Lock Screen", as: .content, using: BusActivityAttributes.preview) {
    BusArrivalWidget()
} contentStates: {
    BusArrivalState.preview
    BusArrivalPreview.state(.approaching)
    BusArrivalPreview.state(.adjusted)
    BusArrivalPreview.state(.nextBus)
    BusArrivalPreview.state(.cancelled)
    BusArrivalPreview.state(.noService)
    BusArrivalPreview.state(.networkError)
    BusArrivalPreview.state(.unavailable)
    BusArrivalPreview.state(.arrived)
    BusArrivalPreview.state(.departed)
    BusArrivalPreview.state(.ended)
    BusArrivalPreview.state(.stale)
}

#Preview("Compact", as: .dynamicIsland(.compact), using: BusActivityAttributes.preview) {
    BusArrivalWidget()
} contentStates: {
    BusArrivalState.preview
    BusArrivalPreview.state(.networkError)
    BusArrivalPreview.state(.approaching)
}

#Preview("Expanded", as: .dynamicIsland(.expanded), using: BusActivityAttributes.preview) {
    BusArrivalWidget()
} contentStates: {
    BusArrivalState.preview
    BusArrivalPreview.state(.adjusted)
    BusArrivalPreview.state(.nextBus)
    BusArrivalPreview.state(.networkError)
    BusArrivalPreview.state(.noService)
    BusArrivalPreview.state(.cancelled)
}

#Preview("Minimal", as: .dynamicIsland(.minimal), using: BusActivityAttributes.preview) {
    BusArrivalWidget()
} contentStates: { BusArrivalState.preview }
