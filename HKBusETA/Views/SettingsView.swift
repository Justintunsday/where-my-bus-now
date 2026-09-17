import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var app
    @State private var isRefreshing = false
    @State private var appGroupIsOperational: Bool?
    @State private var widgetLastAccess: Date?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(selection: Binding(
                        get: { app.settings.selectedRegionID },
                        set: { app.settings.selectedRegionID = $0; app.selectRegion($0) }
                    )) {
                        Text(L10n.t("settings.region.auto")).tag(RegionCatalog.autoID)
                        ForEach(RegionCatalog.all) { region in
                            Text(region.name).tag(region.id)
                        }
                    } label: {
                        Text(L10n.t("settings.region"))
                    }
                    LabeledContent(L10n.t("settings.widget.extensionAccess")) {
                        if let widgetLastAccess {
                            Label(
                                widgetLastAccess.formatted(date: .omitted, time: .shortened),
                                systemImage: "checkmark.circle.fill"
                            )
                            .font(DesignTokens.captionMedium)
                            .foregroundStyle(DesignTokens.success)
                        } else {
                            Label(
                                L10n.t("settings.widget.extensionWaiting"),
                                systemImage: "clock"
                            )
                            .font(DesignTokens.captionMedium)
                            .foregroundStyle(DesignTokens.warning)
                        }
                    }
                    LabeledContent(L10n.t("settings.region.current"), value: app.region.name)
                    if app.region.isQueryMode {
                        if let mainland = app.mainlandProvider {
                            LabeledContent(
                                L10n.t("settings.region.dataSource"),
                                value: mainland.dataSource.localizedName
                            )
                        }
                        Text(L10n.t("settings.region.mainlandNotice"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(L10n.t("settings.region.realtimeNotice"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(L10n.t("settings.region.chelaileAPI"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(L10n.t("settings.region.amapKey"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section(L10n.t("settings.general")) {
                    Picker(selection: Binding(
                        get: { app.settings.language },
                        set: { app.settings.language = $0 }
                    )) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.title).tag(language)
                        }
                    } label: {
                        Text(L10n.t("settings.language"))
                    }
                    Picker(selection: Binding(
                        get: { app.settings.etaFormat },
                        set: { app.settings.etaFormat = $0 }
                    )) {
                        ForEach(EtaFormat.allCases) { format in
                            Text(format.title).tag(format)
                        }
                    } label: {
                        Text(L10n.t("settings.etaFormat"))
                    }
                    Toggle(L10n.t("settings.annotateScheduled"), isOn: Binding(
                        get: { app.settings.annotateScheduled },
                        set: { app.settings.annotateScheduled = $0 }
                    ))
                }

                Section(L10n.t("settings.data")) {
                    if let lastLoaded = app.data.lastLoaded {
                        LabeledContent(L10n.t("settings.data.lastUpdated")) {
                            Text(lastLoaded.formatted(date: .abbreviated, time: .shortened))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button {
                        Task {
                            isRefreshing = true
                            await app.data.refreshIfNeeded()
                            isRefreshing = false
                        }
                    } label: {
                        HStack {
                            Text(L10n.t("settings.data.refresh"))
                            Spacer()
                            if app.data.isDownloading || isRefreshing {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(app.data.isDownloading || isRefreshing)
                }

                Section(L10n.t("settings.widget")) {
                    LabeledContent(L10n.t("settings.widget.appGroup")) {
                        if let appGroupIsOperational {
                            Label(
                                L10n.t(appGroupIsOperational
                                    ? "settings.widget.appGroup.active"
                                    : "settings.widget.appGroup.unavailable"),
                                systemImage: appGroupIsOperational
                                    ? "checkmark.circle.fill"
                                    : "exclamationmark.triangle.fill"
                            )
                            .font(DesignTokens.captionMedium)
                            .foregroundStyle(
                                appGroupIsOperational
                                    ? DesignTokens.success
                                    : DesignTokens.warning
                            )
                        } else {
                            ProgressView()
                        }
                    }
                    Button {
                        checkAppGroup()
                    } label: {
                        Label(L10n.t("settings.widget.checkAppGroup"), systemImage: "arrow.clockwise")
                    }
                    Text(L10n.t("settings.widget.appGroup.help"))
                        .font(DesignTokens.caption)
                        .foregroundStyle(DesignTokens.textSecondary)
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                        Label(
                            L10n.t("settings.widget.sideStore.title"),
                            systemImage: "antenna.radiowaves.left.and.right"
                        )
                        .font(DesignTokens.bodyMedium)
                        .foregroundStyle(DesignTokens.accent)
                        Text(L10n.t("settings.widget.sideStore.hk"))
                            .font(DesignTokens.caption)
                            .foregroundStyle(DesignTokens.textSecondary)
                    }
                    .padding(.vertical, DesignTokens.Spacing.xs)
                    if appGroupIsOperational == false {
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                            Label(
                                L10n.t("settings.widget.sideStore.title"),
                                systemImage: "rectangle.stack.badge.plus"
                            )
                            .font(DesignTokens.bodyMedium)
                            .foregroundStyle(DesignTokens.accent)
                            Text(L10n.t("settings.widget.sideStore.help"))
                                .font(DesignTokens.caption)
                                .foregroundStyle(DesignTokens.textSecondary)
                        }
                        .padding(.vertical, DesignTokens.Spacing.xs)
                    }
                }

                Section(L10n.t("settings.about")) {
                    LabeledContent(L10n.t("settings.version"), value: appVersion)
                    Link(destination: URL(string: "https://hkbus.app")!) {
                        LabeledContent(L10n.t("settings.about.website"), value: "hkbus.app")
                    }
                    Link(destination: URL(string: "https://github.com/hkbus/hk-independent-bus-eta")!) {
                        LabeledContent(L10n.t("settings.about.source"), value: "GitHub")
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.t("settings.about.attribution"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text(L10n.t("settings.about.disclaimer"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(L10n.t("settings.title"))
            .onAppear(perform: checkAppGroup)
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func checkAppGroup() {
        appGroupIsOperational = WidgetSharedStore.appGroupIsOperational()
        widgetLastAccess = WidgetSharedStore.widgetLastAccess
        WidgetSnapshotUpdater.reload()
        Task {
            try? await Task.sleep(for: .seconds(1))
            widgetLastAccess = WidgetSharedStore.widgetLastAccess
        }
    }
}
