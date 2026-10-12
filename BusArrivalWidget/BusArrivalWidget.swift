import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct BusArrivalWidgetBundle: WidgetBundle {
    var body: some Widget { BusArrivalWidget() }
}

struct BusArrivalWidget: Widget {
    var body: some WidgetConfiguration {
        if #available(iOS 18.0, *) {
            configuration.supplementalActivityFamilies([.small, .medium])
        } else { configuration }
    }

    private var configuration: some WidgetConfiguration {
        ActivityConfiguration(for: BusActivityAttributes.self) { context in
            Group {
                if #available(iOS 18.0, *) { AdaptiveBusActivity(context: context) }
                else {
                    BusLockScreenView(target: context.attributes.target, state: context.state,
                                      isStale: context.isStale, activityID: context.activityID)
                }
            }
            .activityBackgroundTint(TransitBrand.surface)
            .activitySystemActionForegroundColor(.primary)
            .widgetURL(context.attributes.target.deepLink)
        } dynamicIsland: { context in
            let display = BusActivityDisplay(target: context.attributes.target, state: context.state, isStale: context.isStale)
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    BusIslandRoute(target: context.attributes.target)
                        .dynamicIsland(verticalPlacement: .belowIfTooWide)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    BusIslandExpandedArrival(display: display)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    BusIslandExpandedDetails(display: display)
                }
            } compactLeading: {
                BusIslandRoute(target: context.attributes.target, compact: true)
            } compactTrailing: {
                BusActivityCountdown(target: context.attributes.target, state: context.state, isStale: context.isStale)
                    .font(.headline.monospacedDigit())
                    .environment(\.locale, context.attributes.target.locale)
            } minimal: {
                Image(systemName: display.symbol).foregroundStyle(TransitBrand.coral)
                    .accessibilityLabel("\(context.attributes.target.route) · \(display.copy(display.statusKey))")
            }
            .widgetURL(context.attributes.target.deepLink)
            .keylineTint(TransitBrand.coral)
        }
    }
}

@available(iOS 18.0, *)
private struct AdaptiveBusActivity: View {
    @Environment(\.activityFamily) private var family
    let context: ActivityViewContext<BusActivityAttributes>
    var body: some View {
        if family == .small {
            BusSmallActivityView(display: .init(target: context.attributes.target, state: context.state, isStale: context.isStale))
        } else {
            BusLockScreenView(target: context.attributes.target, state: context.state,
                              isStale: context.isStale, activityID: context.activityID)
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
