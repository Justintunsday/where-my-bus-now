import SwiftUI

enum TransitTab: String, CaseIterable, Identifiable {
    case today, search, nearby, saved
    var id: String { rawValue }
    var title: String {
        L10n.t(self == .today ? "home.title" : (self == .saved ? "tab.favorites" : "tab.\(rawValue)"))
    }
    var symbol: String {
        switch self {
        case .today: "bus.fill"
        case .search: "magnifyingglass"
        case .nearby: "map"
        case .saved: "star"
        }
    }
}

struct RootView: View {
    @Environment(AppState.self) private var app
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: TransitTab = .today
    @State private var linkedTarget: BusTrackingTarget?
    @State private var invalidLink = false

    var body: some View {
        @Bindable var app = app
        Group {
            if sizeClass == .regular {
                NavigationSplitView {
                    List(TransitTab.allCases, selection: Binding<TransitTab?>(get: { tab }, set: { if let value = $0 { tab = value } })) { item in
                        Label(item.title, systemImage: item.symbol).tag(item)
                    }
                    .navigationTitle(L10n.t("app.name"))
                    .listStyle(.sidebar)
                } detail: { destination(tab) }
            } else {
                TabView(selection: $tab) {
                    ForEach(TransitTab.allCases) { item in
                        destination(item).tabItem { Label(item.title, systemImage: item.symbol) }.tag(item)
                    }
                }
            }
        }
        .tint(DesignTokens.accent)
        .sheet(item: $app.presentation) { sheet in
            if sheet == .settings { SettingsView() }
            else { RegionPickerView() }
        }
        .sheet(item: $linkedTarget) { target in
            NavigationStack {
                TrackingDestination(target: target)
                    .transitDestinations()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(L10n.t("common.done")) { linkedTarget = nil }
                        }
                    }
            }
        }
        .onOpenURL { url in
            if let target = BusTrackingTarget.decode(url: url), RegionCatalog.region(for: target.regionID) != nil {
                app.presentation = nil
                linkedTarget = target
            } else { invalidLink = true }
        }
        .alert(L10n.t("tracking.identityChanged"), isPresented: $invalidLink) {
            Button(L10n.t("common.done"), role: .cancel) { }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else {
                app.arrivals.cancelRequests()
                app.location.stopUpdating()
                return
            }
            app.location.startUpdating()
            app.resolveAutoRegion(location: app.location.location)
            while !Task.isCancelled {
                await app.activities.refreshActive(app: app)
                do { try await Task.sleep(for: .seconds(30)) } catch { break }
            }
        }
        .onChange(of: app.location.location) { app.resolveAutoRegion(location: app.location.location) }
        .onChange(of: app.settings.selectedRegionID) { app.settings.persist() }
        .onChange(of: app.settings.language) { app.settings.persist() }
        .onChange(of: app.settings.etaFormat) { app.settings.persist() }
        .onChange(of: app.settings.annotateScheduled) { app.settings.persist() }
    }

    @ViewBuilder private func destination(_ tab: TransitTab) -> some View {
        switch tab {
        case .today: HomeView(openSearch: { self.tab = .search })
        case .search: SearchView().id(app.region.id)
        case .nearby: NearbyView().id(app.region.id)
        case .saved: FavoritesView()
        }
    }
}

struct DataGate<Content: View>: View {
    @Environment(AppState.self) private var app
    @ViewBuilder let content: () -> Content

    private var byteText: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return "\(formatter.string(fromByteCount: app.data.downloadedBytes)) / \(formatter.string(fromByteCount: app.data.totalBytes))"
    }

    var body: some View {
        if app.data.db != nil {
            content()
        } else if app.data.isDownloading || app.data.isLoading {
            VStack(spacing: DesignTokens.Spacing.m) {
                if app.data.totalBytes > 0 {
                    ProgressView(value: app.data.downloadProgress)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 240)
                    Text("\(Int(app.data.downloadProgress * 100))% · \(byteText)")
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                        .tint(DesignTokens.accent)
                }
                Text(app.data.statusText.isEmpty ? L10n.t("status.loading") : app.data.statusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if app.data.db == nil {
                    Text(L10n.t("status.firstLaunchHint"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DesignTokens.Spacing.xl)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView {
                Label(L10n.t("error.noData.title"), systemImage: "wifi.exclamationmark")
            } description: {
                Text(app.data.errorMessage ?? L10n.t("error.noData.message"))
            } actions: {
                Button(L10n.t("common.retry")) {
                    Task { await app.data.refreshIfNeeded() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}
