import SwiftUI

/// Loads a mainland line detail from the active base-data provider, registers
/// it as a synthetic database entry and then shows the standard route screens.
struct MainlandLineLoaderView: View {
    @Environment(AppState.self) private var app
    let lineId: String
    let title: String
    let seq: Int?
    let modeHint: MainlandTransitMode
    let origin: String?
    let destination: String?
    let firstDeparture: String?
    let lastDeparture: String?
    let fare: String?

    @State private var routeKey: String?
    @State private var errorMessage: String?

    init(
        lineId: String,
        title: String,
        seq: Int? = nil,
        modeHint: MainlandTransitMode = .bus,
        origin: String? = nil,
        destination: String? = nil,
        firstDeparture: String? = nil,
        lastDeparture: String? = nil,
        fare: String? = nil
    ) {
        self.lineId = lineId
        self.title = title
        self.seq = seq
        self.modeHint = modeHint
        self.origin = origin
        self.destination = destination
        self.firstDeparture = firstDeparture
        self.lastDeparture = lastDeparture
        self.fare = fare
    }

    var body: some View {
        Group {
            if let routeKey {
                if let seq {
                    RouteEtaView(routeKey: routeKey, seq: seq)
                } else {
                    RouteDetailView(routeKey: routeKey)
                }
            } else if let errorMessage, modeHint == .metro {
                MainlandMetroInfoView(
                    name: title,
                    origin: origin ?? "",
                    destination: destination ?? "",
                    firstDeparture: firstDeparture,
                    lastDeparture: lastDeparture,
                    fare: fare,
                    errorMessage: errorMessage,
                    onRetry: retry
                )
            } else if errorMessage != nil {
                ContentUnavailableView {
                    Label(L10n.t("mainland.loadFailed"), systemImage: "exclamationmark.triangle")
                } description: {
                    if let errorMessage {
                        Text(errorMessage)
                    }
                } actions: {
                    Button(L10n.t("common.retry"), action: retry)
                }
            } else {
                VStack(spacing: DesignTokens.Spacing.m) {
                    ProgressView()
                    Text(L10n.t("status.loading"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task { await load() }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func load() async {
        guard let provider = app.mainlandProvider else {
            errorMessage = L10n.t("error.mainland.requestFailed")
            return
        }
        do {
            guard let payload = try await provider.linePayload(lineID: lineId, modeHint: modeHint) else {
                errorMessage = MainlandErrorPresentation.message(for: MainlandProviderError.noData)
                return
            }
            let normalizedPayload = payload.applying(modeHint: modeHint)
            guard let shared = MainlandRouteAdapter.makeSharedRoute(from: normalizedPayload) else {
                errorMessage = MainlandErrorPresentation.message(for: MainlandProviderError.noData)
                return
            }
            app.data.registerSynthetic(
                entry: shared.entry,
                stops: shared.stops,
                mainlandMetadata: shared.metadata
            )
            routeKey = shared.entry.routeKey
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = MainlandErrorPresentation.message(for: error)
        }
    }

    private func retry() {
        // Returning to the loading branch lets its `.task` perform exactly
        // one request; starting a second detached task here can duplicate the
        // line-detail request.
        errorMessage = nil
    }
}

/// Lightweight info page for a metro result when the active source has no
/// intermediate stop payload.
struct MainlandMetroInfoView: View {
    let name: String
    let origin: String
    let destination: String
    let firstDeparture: String?
    let lastDeparture: String?
    let fare: String?
    let errorMessage: String
    var onRetry: (() -> Void)? = nil

    init(
        name: String,
        origin: String,
        destination: String,
        firstDeparture: String? = nil,
        lastDeparture: String? = nil,
        fare: String? = nil,
        errorMessage: String,
        onRetry: (() -> Void)? = nil
    ) {
        self.name = name
        self.origin = origin
        self.destination = destination
        self.firstDeparture = firstDeparture
        self.lastDeparture = lastDeparture
        self.fare = fare
        self.errorMessage = errorMessage
        self.onRetry = onRetry
    }

    var body: some View {
        List {
            Section {
                LabeledContent(L10n.t("mainland.metroStart"), value: origin)
                LabeledContent(L10n.t("mainland.metroEnd"), value: destination)
            }
            if let firstDeparture, !firstDeparture.isEmpty {
                LabeledContent(L10n.t("mainland.firstDeparture"), value: firstDeparture)
            }
            if let lastDeparture, !lastDeparture.isEmpty {
                LabeledContent(L10n.t("mainland.lastDeparture"), value: lastDeparture)
            }
            if let fare, !fare.isEmpty {
                LabeledContent(L10n.t("route.fare"), value: "¥\(fare)")
            }
            Section {
                Label(L10n.t("mainland.metroPayloadUnavailable"), systemImage: "exclamationmark.triangle")
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                Label(L10n.t("mainland.metroNoRealtime"), systemImage: "tram.fill")
                    .foregroundStyle(.secondary)
            }
            if let onRetry {
                Section {
                    Button(L10n.t("common.retry"), action: onRetry)
                }
            }
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Stop departure board for mainland regions. Base providers may only expose
/// stop identity; ETA rows are supplied by the replaceable realtime provider.
struct MainlandStopBoardView: View {
    @Environment(AppState.self) private var app
    let stopID: String
    let namesakeStopID: String?
    let title: String
    let location: StopLocation?

    @State private var rows: [MainlandBoardLine] = []
    @State private var otherLines: [MainlandTransitLine] = []
    @State private var resolvedLocation: StopLocation?
    @State private var isLoading = false
    @State private var errorMessage: String?

    init(
        stopID: String,
        namesakeStopID: String? = nil,
        title: String,
        location: StopLocation? = nil
    ) {
        self.stopID = stopID
        self.namesakeStopID = namesakeStopID
        self.title = title
        self.location = location
    }

    var body: some View {
        Group {
            if isLoading && rows.isEmpty && otherLines.isEmpty {
                VStack(spacing: DesignTokens.Spacing.m) {
                    ProgressView()
                    Text(L10n.t("status.loading"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ContentUnavailableView {
                    Label(L10n.t("error.mainland.requestFailed"), systemImage: "wifi.exclamationmark")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button(L10n.t("common.retry")) { Task { await load() } }
                }
            } else if rows.isEmpty && otherLines.isEmpty {
                ContentUnavailableView {
                    Label(L10n.t("stop.noRoutes"), systemImage: "bus")
                } actions: {
                    Button(L10n.t("common.retry")) {
                        Task { await load() }
                    }
                }
            } else {
                List {
                    if !rows.isEmpty {
                        Section {
                            ForEach(rows) { row in
                                NavigationLink(value: MainlandLineTarget(
                                    lineId: row.lineID,
                                    title: row.lineName,
                                    seq: row.targetStopSequence.map { max($0 - 1, 0) }
                                )) {
                                    MainlandBoardRowView(row: row)
                                }
                            }
                        }
                    }
                    if !otherLines.isEmpty {
                        Section(L10n.t("mainland.metros")) {
                            ForEach(otherLines) { metro in
                                NavigationLink(value: MainlandLineTarget(
                                    lineId: metro.lineID,
                                    title: metro.name,
                                    modeHint: metro.mode
                                )) {
                                    HStack(spacing: DesignTokens.Spacing.s) {
                                        Circle()
                                            .fill(metroColor(metro.color))
                                            .frame(width: 9, height: 9)
                                        Text(metro.name)
                                    }
                                }
                            }
                        }
                    }
                }
                .refreshable { await load() }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let navigationLocation, navigationLocation.isValid {
                    StopNavigationButton(stopName: L10n.display(title), location: navigationLocation) {
                        Image(systemName: "map")
                    }
                }
            }
        }
        .task(id: stopID) { await load() }
    }

    private func load() async {
        guard let provider = app.mainlandProvider else { return }
        if rows.isEmpty && otherLines.isEmpty { isLoading = true }
        defer { isLoading = false }
        do {
            let result = try await provider.stopBoard(stopID: stopID, namesakeStopID: namesakeStopID)
            rows = result.rows
            otherLines = result.otherLines
            if let location = result.location {
                resolvedLocation = location
            }
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = MainlandErrorPresentation.message(for: error)
        }
    }

    private func metroColor(_ text: String?) -> Color {
        guard let text else { return .gray }
        let parts = text.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count >= 3 else { return .gray }
        return Color(.sRGB, red: parts[0] / 255, green: parts[1] / 255, blue: parts[2] / 255)
    }

    private var navigationLocation: StopLocation? {
        location ?? resolvedLocation
    }
}

struct MainlandBoardRowView: View {
    let row: MainlandBoardLine

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.s) {
            RouteBadge(route: row.lineName, entry: nil, colorHex: MainlandProviderPalette.color(for: row.lineName))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(L10n.t("route.to")) \(row.destination)")
                    .font(.body)
                    .lineLimit(1)
                if let status = row.status, !status.isEmpty {
                    Text(status)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: DesignTokens.Spacing.s)
            VStack(alignment: .trailing, spacing: 2) {
                if row.minutes.isEmpty {
                    Text(L10n.t("eta.noEta"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(row.minutes.prefix(3).enumerated()), id: \.offset) { index, minutes in
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text("\(minutes)")
                                .font(DesignTokens.tabular(17, weight: .bold))
                                .foregroundStyle(index == 0 ? DesignTokens.accent : Color.primary)
                            Text(L10n.t("unit.minutes"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}
