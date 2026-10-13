import SwiftUI

struct TrackingSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let target: BusTrackingTarget
    let session: ArrivalSession

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    BusLockScreenView(target: target, state: session.activityState,
                                      isStale: !session.activityState.isFresh(at: Date()))
                        .background(DesignTokens.surface, in: RoundedRectangle(cornerRadius: 24))
                        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(DesignTokens.divider, lineWidth: 0.5))
                    Label(L10n.t(app.activities.supportsRemoteUpdates(for: target) ? "tracking.remoteNotice" : "tracking.foregroundNotice"), systemImage: "info.circle")
                        .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("tracking.disclosure")
                    if let error = app.activities.error {
                        Label(error, systemImage: "exclamationmark.circle").foregroundStyle(DesignTokens.warning)
                            .accessibilityIdentifier("tracking.error")
                    }
                    if app.activities.isTracking(target) {
                        Button(role: .destructive) {
                            Task { await app.activities.end(target); dismiss() }
                        } label: {
                            Label(L10n.t("tracking.end"), systemImage: "stop.circle").frame(maxWidth: .infinity, minHeight: 44)
                        }.buttonStyle(.bordered)
                        .accessibilityIdentifier("tracking.end")
                    } else {
                        Button { Task { await start() } } label: {
                            HStack {
                                if app.activities.isStarting { ProgressView() }
                                Label(L10n.t("tracking.start"), systemImage: "wave.3.right.circle.fill")
                            }.frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .disabled(app.activities.isStarting).transitPrimaryAction()
                        .accessibilityIdentifier("tracking.start")
                    }
                }
                .padding(16).frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
            .background(DesignTokens.background)
            .navigationTitle(L10n.t("tracking.title")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.t("common.done")) { dismiss() }.accessibilityIdentifier("tracking.done") } }
            .sensoryFeedback(.success, trigger: app.activities.isTracking(target))
            .tint(target.resolvedTheme.accent)
        }
    }

    private func start() async {
        if !app.bookmarks.isFavoriteRoute(target.routeKey), let entry = app.data.entry(target.routeKey) {
            app.bookmarks.toggleFavoriteRoute(entry: entry, routeKey: target.routeKey, modeRawValue: target.mode)
        }
        await app.activities.start(target: target, session: session)
        if app.activities.isTracking(target) { app.boarding.save(target); dismiss() }
    }
}
