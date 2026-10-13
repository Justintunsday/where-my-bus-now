import ActivityKit
import AppIntents

/// Included in both targets: LiveActivityIntent executes in the host app process.
struct EndBusTrackingIntent: LiveActivityIntent {
    static var title = LocalizedStringResource("End tracking", table: "BusIntents")
    static var description = IntentDescription(LocalizedStringResource("End the selected bus arrival Live Activity.", table: "BusIntents"))
    @Parameter(title: LocalizedStringResource("Activity", table: "BusIntents")) var activityID: String

    init() {}
    init(activityID: String) { self.activityID = activityID }

    func perform() async throws -> some IntentResult {
        for activity in Activity<BusActivityAttributes>.activities where activity.id == activityID {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        #if !BUS_WIDGET_EXTENSION
        // A LiveActivityIntent runs in the host. This is a bounded revocation request,
        // never periodic background work. Failed revocations are retried on reconciliation.
        try? await BusActivityRemoteConfiguration.registrar()?.revoke(activityID: activityID)
        #endif
        return .result()
    }
}
