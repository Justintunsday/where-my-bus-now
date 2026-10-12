import ActivityKit
import Foundation
import Observation

@MainActor @Observable
final class BusActivityManager {
    private(set) var activeTargets: [BusTrackingTarget] = []
    private(set) var isStarting = false
    private(set) var error: String?
    @ObservationIgnored private var observers: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var tokenObservers: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private let push: BusActivityPushCoordinator?
    // Default host configuration has no registrar until authenticated server deployment.
    var supportsRemoteUpdates: Bool { push != nil }

    init(registrar: (any BusActivityPushRegistering)? = nil) {
        push = registrar.map { BusActivityPushCoordinator(registrar: $0) }
        reconcile()
    }

    func isTracking(_ target: BusTrackingTarget) -> Bool { activeTargets.contains { $0.id == target.id } }

    func start(target: BusTrackingTarget, session: ArrivalSession) async {
        guard !isStarting else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            error = L10n.t("tracking.disabled"); return
        }
        isStarting = true
        defer { isStarting = false }
        error = nil
        await session.refresh()
        guard !Task.isCancelled else { return }
        let state = session.activityState
        guard state.isFresh(at: Date()) else { error = L10n.t("tracking.needsPrediction"); return }
        if isTracking(target) { return }
        do {
            // One trip at a time. Create first so a failed request does not destroy an existing trip.
            let activity = try Activity<BusActivityAttributes>.request(
                attributes: BusActivityAttributes(target: target, startedAt: Date()),
                content: ActivityContent(state: state, staleDate: state.staleDate), pushType: supportsRemoteUpdates ? .token : nil)
            for previous in Activity<BusActivityAttributes>.activities where previous.id != activity.id {
                push?.end(activityID: previous.id)
                await previous.end(nil, dismissalPolicy: .immediate)
            }
            reconcile()
        } catch { self.error = L10n.t("tracking.startFailed") }
    }

    func end(_ target: BusTrackingTarget) async {
        for activity in Activity<BusActivityAttributes>.activities where activity.attributes.target.id == target.id {
            push?.end(activityID: activity.id)
            var state = activity.content.state
            state.status = .ended
            state.arrivalEpoch = nil
            await activity.end(ActivityContent(state: state, staleDate: Date()), dismissalPolicy: .immediate)
        }
        reconcile()
    }

    func reconcile() {
        let activities = Activity<BusActivityAttributes>.activities.filter {
            $0.activityState == .active || $0.activityState == .stale
        }
        let targets = activities.map(\.attributes.target)
        if activeTargets != targets { activeTargets = targets }
        let ids = Set(activities.map(\.id))
        push?.reconcile(activeIDs: ids)
        for id in Array(observers.keys) where !ids.contains(id) { observers.removeValue(forKey: id)?.cancel() }
        for id in Array(tokenObservers.keys) where !ids.contains(id) { tokenObservers.removeValue(forKey: id)?.cancel() }
        for activity in activities where observers[activity.id] == nil {
            observers[activity.id] = Task { [weak self] in
                for await _ in activity.activityStateUpdates {
                    guard !Task.isCancelled else { return }
                    self?.reconcile()
                }
            }
        }
        if let push {
            for activity in activities where tokenObservers[activity.id] == nil {
                tokenObservers[activity.id] = Task {
                    for await token in activity.pushTokenUpdates {
                        guard !Task.isCancelled else { return }
                        push.receive(token: token, activityID: activity.id, target: activity.attributes.target,
                                     startedAt: activity.attributes.startedAt)
                    }
                }
            }
        }
    }

    /// Called by a scene-bound task only while active. No background polling promises.
    func refreshActive(app: AppState) async {
        #if DEBUG
        if app.data.isPreview { return }
        #endif
        reconcile()
        for activity in Activity<BusActivityAttributes>.activities {
            guard !Task.isCancelled else { return }
            if Date().timeIntervalSince(activity.attributes.startedAt) > 3600 {
                await end(activity.attributes.target)
                continue
            }
            guard let session = app.arrivals.session(for: activity.attributes.target, app: app) else {
                await end(activity.attributes.target); continue
            }
            await session.refresh()
            guard !Task.isCancelled else { return }
            let state = session.activityState
            if state.isTerminal || session.identityInvalid {
                push?.end(activityID: activity.id)
                await activity.end(ActivityContent(state: state, staleDate: state.staleDate),
                                   dismissalPolicy: .after(Date().addingTimeInterval(60)))
            } else {
                await activity.update(ActivityContent(state: state, staleDate: state.staleDate))
            }
        }
        reconcile()
    }
}
