import AppIntents
import SwiftUI
import WidgetKit

struct WidgetTransitTargetEntity: AppEntity, Hashable, Sendable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "线路与车站 / Route & stop"
    static let defaultQuery = WidgetTransitTargetQuery()

    let id: String
    let record: WidgetTransitTargetRecord

    init(_ record: WidgetTransitTargetRecord) {
        self.id = record.id
        self.record = record
    }

    init?(id: String) {
        guard let record = WidgetTransitTargetRecord(id: id) else { return nil }
        self.init(record)
    }

    var displayRepresentation: DisplayRepresentation {
        let operatorText = WidgetTransitOperatorCatalog.displayName(record.operatorID)
        return DisplayRepresentation(
            title: "\(record.cityName) [\(record.cityID)]\(operatorText.map { " · \($0)" } ?? "") · \(record.lineName)",
            subtitle: "\(record.directionText) · \(record.stopName)"
        )
    }
}

struct WidgetTransitTargetQuery: EntityStringQuery, Sendable {
    func entities(for identifiers: [WidgetTransitTargetEntity.ID]) async throws -> [WidgetTransitTargetEntity] {
        identifiers.compactMap(WidgetTransitTargetEntity.init(id:))
    }

    func entities(matching string: String) async throws -> [WidgetTransitTargetEntity] {
        await WidgetTransitTargetResolver()
            .targets(for: string)
            .map(WidgetTransitTargetEntity.init)
    }

    /// There is no App Group-backed default. The configuration UI asks the
    /// user to search with a city prefix, which keeps the entity portable in
    /// SideStore installations.
    func suggestedEntities() async throws -> [WidgetTransitTargetEntity] { [] }
}

enum WidgetTransitCityOption: String, AppEnum, Sendable {
    case hongKong = "hk"
    case shenzhen = "014"
    case guangzhou = "040"
    case shanghai = "034"
    case beijing = "027"
    case tianjin = "006"
    case chongqing = "003"
    case chengdu = "007"
    case foshan = "019"
    case qingdao = "009"
    case shenyang = "035"
    case nanjing = "018"
    case xian = "076"

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "城市 / City"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .hongKong: DisplayRepresentation(title: "香港", subtitle: "香港营办商 API / Hong Kong operators"),
        .shenzhen: DisplayRepresentation(title: "深圳", subtitle: "城市 ID 014 / City ID 014"),
        .guangzhou: DisplayRepresentation(title: "广州", subtitle: "城市 ID 040 / City ID 040"),
        .shanghai: DisplayRepresentation(title: "上海", subtitle: "城市 ID 034 / City ID 034"),
        .beijing: DisplayRepresentation(title: "北京", subtitle: "城市 ID 027 / City ID 027"),
        .tianjin: DisplayRepresentation(title: "天津", subtitle: "城市 ID 006 / City ID 006"),
        .chongqing: DisplayRepresentation(title: "重庆", subtitle: "城市 ID 003 / City ID 003"),
        .chengdu: DisplayRepresentation(title: "成都", subtitle: "城市 ID 007 / City ID 007"),
        .foshan: DisplayRepresentation(title: "佛山", subtitle: "城市 ID 019 / City ID 019"),
        .qingdao: DisplayRepresentation(title: "青岛", subtitle: "城市 ID 009 / City ID 009"),
        .shenyang: DisplayRepresentation(title: "沈阳", subtitle: "城市 ID 035 / City ID 035"),
        .nanjing: DisplayRepresentation(title: "南京", subtitle: "城市 ID 018 / City ID 018"),
        .xian: DisplayRepresentation(title: "西安", subtitle: "城市 ID 076 / City ID 076"),
    ]

    var city: WidgetTransitCity {
        WidgetTransitCityCatalog.all.first { $0.id == rawValue }!
    }
}

enum WidgetTransitOperatorOption: String, AppEnum, Sendable {
    case kmb
    case citybus = "ctb"
    case greenMinibus = "gmb"
    case nlb

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "香港营办商 / Hong Kong operator"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .kmb: DisplayRepresentation(title: "九巴 / KMB", subtitle: "九龙巴士 / Kowloon Motor Bus"),
        .citybus: DisplayRepresentation(title: "城巴 / Citybus", subtitle: "Citybus Limited"),
        .greenMinibus: DisplayRepresentation(title: "专线小巴 / GMB", subtitle: "绿色专线小巴 / Green Minibus"),
        .nlb: DisplayRepresentation(title: "屿巴 / NLB", subtitle: "新大屿山巴士 / New Lantao Bus"),
    ]

    var id: String { rawValue }
}

enum WidgetTransitDirectionOption: String, AppEnum, Sendable {
    case outbound = "0"
    case inbound = "1"

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "方向 / Direction"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .outbound: DisplayRepresentation(title: "上行 / Outbound", subtitle: "方向 0 / Direction 0"),
        .inbound: DisplayRepresentation(title: "下行 / Inbound", subtitle: "方向 1 / Direction 1"),
    ]

    var apiValue: Int { Int(rawValue)! }
}

struct SelectSideStoreTransitTargetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "线路与车站 / Route & stop"
    static var description = IntentDescription(
        "依次选择城市；香港再选择营办商，然后填写线路、方向和可选站名。 / Choose a city; for Hong Kong, choose an operator, then enter the route, direction and optional stop."
    )

    @Parameter(title: "城市 / City")
    var city: WidgetTransitCityOption?

    @Parameter(title: "香港营办商（香港必填） / Operator (required for HK)")
    var transitOperator: WidgetTransitOperatorOption?

    @Parameter(title: "线路（必填） / Route (required)")
    var route: String?

    @Parameter(title: "方向（必填） / Direction (required)")
    var direction: WidgetTransitDirectionOption?

    @Parameter(title: "站名（可选） / Stop (optional)")
    var stop: String?

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$city) · \(\.$transitOperator) · \(\.$route) · \(\.$direction) · \(\.$stop)")
    }
}

struct SideStoreTransitEntry: TimelineEntry {
    let date: Date
    let target: WidgetTransitTargetRecord?
    let etas: [Date]
    let status: Status

    enum Status: Sendable, Equatable {
        case setup
        case ready
        case noData
        case unavailable
    }
}

struct SideStoreTransitProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SideStoreTransitEntry {
        SideStoreTransitEntry(
            date: Date(),
            target: WidgetTransitTargetRecord(
                cityID: "034",
                cityName: "上海",
                lineID: "sample-71",
                lineName: "71",
                direction: 0,
                origin: "起点",
                destination: "人民广场",
                stopID: "sample-stop",
                stopName: "人民广场",
                stationID: "034-sample",
                stopSequence: 2,
                latitude: 31.2304,
                longitude: 121.4737
            ),
            etas: [Date().addingTimeInterval(180)],
            status: .ready
        )
    }

    func snapshot(
        for configuration: SelectSideStoreTransitTargetIntent,
        in context: Context
    ) async -> SideStoreTransitEntry {
        let target = await resolvedTarget(for: configuration)
        return entry(for: target, etas: [], status: target == nil ? .setup : .noData)
    }

    func timeline(
        for configuration: SelectSideStoreTransitTargetIntent,
        in context: Context
    ) async -> Timeline<SideStoreTransitEntry> {
        let target = await resolvedTarget(for: configuration)
        guard let target else {
            let now = Date()
            return Timeline(
                entries: [entry(for: nil, etas: [], status: .setup)],
                policy: .after(now.addingTimeInterval(900))
            )
        }

        let result = await WidgetTransitTargetResolver().etaDates(for: target)
        let status: SideStoreTransitEntry.Status = result.unavailable
            ? .unavailable
            : result.dates.isEmpty ? .noData : .ready
        let now = Date()
        return Timeline(
            entries: [entry(for: target, etas: result.dates, status: status)],
            policy: .after(now.addingTimeInterval(900))
        )
    }

    private func resolvedTarget(
        for configuration: SelectSideStoreTransitTargetIntent
    ) async -> WidgetTransitTargetRecord? {
        guard let city = configuration.city,
              let route = configuration.route?.trimmingCharacters(in: .whitespacesAndNewlines),
              !route.isEmpty
        else { return nil }
        return await WidgetTransitTargetResolver().target(
            for: city.city,
            operatorID: configuration.transitOperator?.id,
            route: route,
            direction: configuration.direction?.apiValue ?? WidgetTransitManualDirection.outbound,
            stop: configuration.stop
        )
    }

    private func entry(
        for target: WidgetTransitTargetRecord?,
        etas: [Date],
        status: SideStoreTransitEntry.Status
    ) -> SideStoreTransitEntry {
        SideStoreTransitEntry(date: Date(), target: target, etas: etas, status: status)
    }
}

struct SideStoreTransitWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "SideStoreTransitWidget",
            intent: SelectSideStoreTransitTargetIntent.self,
            provider: SideStoreTransitProvider()
        ) { entry in
            SideStoreTransitWidgetView(entry: entry)
        }
        .configurationDisplayName("线路与车站 / Route & stop")
        .description("选择城市并填写线路、方向和可选站名；香港需选择营办商，不依赖动态搜索或 App Group。 / Choose a city, route, direction and optional stop; Hong Kong also needs an operator, without dynamic search or App Group.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
        ])
    }
}

struct SideStoreTransitWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SideStoreTransitEntry

    private var isAccessory: Bool {
        family == .accessoryCircular || family == .accessoryRectangular || family == .accessoryInline
    }

    var body: some View {
        content
            .widgetURL(entry.target.map { URL(string: "wmbn://transit/\($0.id)") } ?? URL(string: "wmbn://search"))
            .containerBackground(for: .widget) {
                isAccessory ? Color.clear : Color(uiColor: .systemBackground)
            }
    }

    @ViewBuilder
    private var content: some View {
        if let target = entry.target {
            switch family {
            case .accessoryCircular:
                VStack(spacing: 0) {
                    Text(target.lineName).font(.system(size: 11, weight: .semibold, design: .rounded)).lineLimit(1)
                    TransitCountdown(date: entry.date, eta: entry.etas.first, size: 20)
                }
            case .accessoryRectangular:
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(targetContextText(target)) · \(target.lineName)").font(.caption2).lineLimit(1)
                        Text(target.stopName).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        TransitStatusText(entry: entry, compact: true)
                    }
                    Spacer(minLength: 0)
                }
            case .accessoryInline:
                Text(inlineText(target))
            case .systemMedium:
                medium(target)
            default:
                small(target)
            }
        } else {
            VStack(spacing: 4) {
                Image(systemName: "slider.horizontal.3")
                    .font(.caption)
                Text(WidgetL10n.t("請填寫城市、線路和方向", "Enter city, route & direction"))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                Text(WidgetL10n.t("站名可留空，將使用該方向首站", "Stop is optional; the first stop in that direction is used"))
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func small(_ target: WidgetTransitTargetRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(targetContextText(target))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(target.lineName)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .lineLimit(1)
            Text(target.directionText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(target.stopName)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 0)
            TransitStatusText(entry: entry, compact: false)
        }
    }

    private func medium(_ target: WidgetTransitTargetRecord) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(targetContextText(target))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(target.lineName)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
            }
            Text(target.directionText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(alignment: .lastTextBaseline) {
                Text(target.stopName)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let eta = entry.etas.first {
                    TransitCountdown(date: entry.date, eta: eta, size: 28)
                } else {
                    TransitStatusText(entry: entry, compact: true)
                }
            }
            if entry.etas.count > 1 {
                Text(entry.etas.dropFirst().map { etaText($0) }.joined(separator: "  ·  "))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func inlineText(_ target: WidgetTransitTargetRecord) -> String {
        if let eta = entry.etas.first {
            let minutes = max(Int(ceil(eta.timeIntervalSince(entry.date) / 60)), 1)
            return "\(target.lineName) · \(target.stopName) \(minutes) \(WidgetL10n.t("分", "min"))"
        }
        return "\(target.lineName) · \(statusText(entry.status))"
    }

    private func etaText(_ date: Date) -> String {
        let minutes = max(Int(ceil(date.timeIntervalSince(entry.date) / 60)), 1)
        return "\(minutes)\(WidgetL10n.t("分", "m"))"
    }

    private func statusText(_ status: SideStoreTransitEntry.Status) -> String {
        switch status {
        case .setup: return WidgetL10n.t("請選擇", "Choose target")
        case .ready: return WidgetL10n.t("即將到站", "arriving")
        case .noData: return WidgetL10n.t("暫無 ETA", "No ETA")
        case .unavailable: return WidgetL10n.t("暫時無法更新", "Unable to update")
        }
    }
}

private func targetContextText(_ target: WidgetTransitTargetRecord) -> String {
    let city = "\(target.cityName) [\(target.cityID)]"
    guard let operatorName = WidgetTransitOperatorCatalog.displayName(target.operatorID) else {
        return city
    }
    return "\(city) · \(operatorName)"
}

private struct TransitCountdown: View {
    let date: Date
    let eta: Date?
    let size: CGFloat

    var body: some View {
        if let eta, eta > date {
            Text(timerInterval: date...eta, countsDown: true)
                .font(.system(size: size, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(WidgetAccent.color)
                .lineLimit(1)
        } else {
            Text(WidgetL10n.t("暫無 ETA", "No ETA"))
                .font(.system(size: max(size * 0.45, 12), weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private struct TransitStatusText: View {
    let entry: SideStoreTransitEntry
    let compact: Bool

    var body: some View {
        if let eta = entry.etas.first {
            TransitCountdown(date: entry.date, eta: eta, size: compact ? 23 : 35)
        } else {
            Text(statusText)
                .font(.system(size: compact ? 12 : 14, weight: .semibold, design: .rounded))
                .foregroundStyle(entry.status == .unavailable ? Color.secondary : WidgetAccent.color)
                .lineLimit(1)
        }
    }

    private var statusText: String {
        switch entry.status {
        case .setup: return WidgetL10n.t("請選擇目標", "Choose a target")
        case .ready: return WidgetL10n.t("即將到站", "Arriving")
        case .noData: return WidgetL10n.t("暫無 ETA", "No ETA")
        case .unavailable: return WidgetL10n.t("暫時無法更新", "Unable to update")
        }
    }
}
