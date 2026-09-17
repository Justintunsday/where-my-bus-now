import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum WidgetTransitAPIError: Error, Hashable, Sendable {
    case invalidURL
    case invalidRequest(String)
    case httpStatus(Int)
    case transport
    case decoding

    var canUseFallback: Bool {
        switch self {
        case .invalidURL, .transport, .decoding: return true
        case let .httpStatus(status): return status >= 500
        case .invalidRequest: return false
        }
    }
}

struct WidgetTransitAPITransportResponse: Sendable {
    let data: Data
    let statusCode: Int?
}

protocol WidgetTransitAPITransport: Sendable {
    func data(for request: URLRequest) async throws -> WidgetTransitAPITransportResponse
}

final class WidgetTransitAPIURLSessionTransport: WidgetTransitAPITransport, @unchecked Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> WidgetTransitAPITransportResponse {
        let (data, response) = try await session.data(for: request)
        return WidgetTransitAPITransportResponse(
            data: data,
            statusCode: (response as? HTTPURLResponse)?.statusCode
        )
    }
}

/// Minimal widget-owned client. It intentionally does not import app models
/// or use UserDefaults(suiteName:), so the SideStore configuration works when
/// the App Group entitlement is missing.
struct WidgetTransitAPIClient: Sendable {
    static let primaryBaseURL = URL(string: "https://ts-api.tundrey.com/v1")!
    static let fallbackBaseURL = URL(string: "https://chelaile-api-server.vercel.app/v1")!

    private enum Endpoint: String, Sendable {
        case search
        case lineDetail = "lines/detail"
        case realtime = "lines/realtime"

        var path: String { rawValue }
    }

    private let baseURLs: [URL]
    private let transport: any WidgetTransitAPITransport

    init(
        baseURLs: [URL]? = nil,
        transport: any WidgetTransitAPITransport = WidgetTransitAPIURLSessionTransport()
    ) {
        self.baseURLs = (baseURLs ?? [Self.primaryBaseURL, Self.fallbackBaseURL])
            .compactMap { Self.normalized($0) }
        self.transport = transport
    }

    func search(cityID: String, keyword: String) async throws -> WidgetTransitSearchResponse {
        let data = try await request(.search, parameters: [
            ("city_id", cityID),
            ("keyword", keyword),
        ])
        return try Self.decode(WidgetTransitSearchResponse.self, data: data)
    }

    func lineDetail(cityID: String, lineID: String) async throws -> WidgetTransitLineDetailResponse {
        let data = try await request(.lineDetail, parameters: [
            ("city_id", cityID),
            ("line_id", lineID),
        ])
        return try Self.decode(WidgetTransitLineDetailResponse.self, data: data)
    }

    func realtime(for target: WidgetTransitTargetRecord) async throws -> WidgetTransitRealtimeResponse {
        guard !target.cityID.isEmpty, !target.lineID.isEmpty, !target.stationID.isEmpty,
              target.stopSequence > 0,
              target.latitude.isFinite, target.longitude.isFinite,
              (-90...90).contains(target.latitude),
              (-180...180).contains(target.longitude)
        else { throw WidgetTransitAPIError.invalidRequest("incomplete target") }
        let data = try await request(.realtime, parameters: [
            ("city_id", target.cityID),
            ("line_id", target.lineID),
            ("target_order", String(target.stopSequence)),
            ("station_id", target.stationID),
            ("lat", coordinateString(target.latitude)),
            ("lng", coordinateString(target.longitude)),
        ])
        return try Self.decode(WidgetTransitRealtimeResponse.self, data: data)
    }

    static func makeURL(
        baseURL: URL?,
        path: String,
        parameters: [(String, String)]
    ) throws -> URL {
        guard let baseURL, baseURL.scheme != nil, baseURL.host != nil else {
            throw WidgetTransitAPIError.invalidURL
        }
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        let basePath = components?.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
        let endpointPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components?.path = "/\([basePath, endpointPath].filter { !$0.isEmpty }.joined(separator: "/"))"
        components?.queryItems = parameters.map { URLQueryItem(name: $0.0, value: $0.1) }
        guard let url = components?.url else { throw WidgetTransitAPIError.invalidURL }
        return url
    }

    private func request(
        _ endpoint: Endpoint,
        parameters: [(String, String)]
    ) async throws -> Data {
        for (name, value) in parameters where value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw WidgetTransitAPIError.invalidRequest("missing \(name)")
        }
        guard !baseURLs.isEmpty else { throw WidgetTransitAPIError.invalidURL }

        var lastError: WidgetTransitAPIError = .invalidURL
        for (index, baseURL) in baseURLs.enumerated() {
            do {
                return try await perform(endpoint, parameters: parameters, baseURL: baseURL)
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as WidgetTransitAPIError {
                lastError = error
                guard index < baseURLs.count - 1, error.canUseFallback else { throw error }
            } catch {
                lastError = .transport
                guard index < baseURLs.count - 1 else { throw lastError }
            }
        }
        throw lastError
    }

    private func perform(
        _ endpoint: Endpoint,
        parameters: [(String, String)],
        baseURL: URL
    ) async throws -> Data {
        let url = try Self.makeURL(baseURL: baseURL, path: endpoint.path, parameters: parameters)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let response: WidgetTransitAPITransportResponse
        do {
            response = try await transport.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw WidgetTransitAPIError.transport
        }
        guard let status = response.statusCode else { throw WidgetTransitAPIError.transport }
        guard (200...299).contains(status) else { throw WidgetTransitAPIError.httpStatus(status) }
        return response.data
    }

    private static func normalized(_ url: URL) -> URL? {
        guard url.scheme != nil, url.host != nil else { return nil }
        return url
    }

    private static func decode<T: Decodable>(_ type: T.Type, data: Data) throws -> T {
        guard let value = try? JSONDecoder().decode(type, from: data) else {
            throw WidgetTransitAPIError.decoding
        }
        return value
    }

    private func coordinateString(_ value: Double) -> String {
        String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}

struct WidgetTransitSearchResponse: Decodable, Sendable {
    let lines: [WidgetTransitSearchLine]
    let stations: [WidgetTransitSearchStation]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lines = try container.decodeIfPresent([WidgetTransitSearchLine].self, forKey: .lines) ?? []
        stations = try container.decodeIfPresent([WidgetTransitSearchStation].self, forKey: .stations) ?? []
    }

    private enum CodingKeys: String, CodingKey { case lines, stations }
}

struct WidgetTransitSearchLine: Decodable, Sendable {
    let name: String?
    let lineNo: String?
    let directions: [WidgetTransitDirection]
    let lineID: String?
    let direction: Int?
    let startName: String?
    let endName: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        lineNo = try container.decodeIfPresent(String.self, forKey: .lineNo)
        directions = try container.decodeIfPresent([WidgetTransitDirection].self, forKey: .directions) ?? []
        lineID = try container.decodeIfPresent(String.self, forKey: .lineID)
        direction = try container.decodeFlexibleInt(forKey: .direction)
        startName = try container.decodeIfPresent(String.self, forKey: .startName)
        endName = try container.decodeIfPresent(String.self, forKey: .endName)
    }

    private enum CodingKeys: String, CodingKey {
        case name, lineNo, directions, direction
        case lineID = "lineId"
        case startName = "startSn"
        case endName = "endSn"
    }
}

struct WidgetTransitDirection: Decodable, Sendable {
    let direction: Int?
    let lineID: String?
    let startName: String?
    let endName: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        direction = try container.decodeFlexibleInt(forKey: .direction)
        lineID = try container.decodeIfPresent(String.self, forKey: .lineID)
        startName = try container.decodeIfPresent(String.self, forKey: .startName)
        endName = try container.decodeIfPresent(String.self, forKey: .endName)
    }

    private enum CodingKeys: String, CodingKey {
        case direction
        case lineID = "lineId"
        case startName = "startSn"
        case endName = "endSn"
    }
}

struct WidgetTransitSearchStation: Decodable, Sendable {
    let stationID: String?
    let name: String?
    let physicalStopID: String?
    let latitude: Double?
    let longitude: Double?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stationID = try container.decodeIfPresent(String.self, forKey: .stationID)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        physicalStopID = try container.decodeIfPresent(String.self, forKey: .physicalStopID)
        latitude = try container.decodeFlexibleDouble(forKey: .latitude)
        longitude = try container.decodeFlexibleDouble(forKey: .longitude)
    }

    private enum CodingKeys: String, CodingKey {
        case stationID = "sId"
        case name = "sn"
        case physicalStopID = "physicalStId"
        case latitude = "lat"
        case longitude = "lng"
    }
}

struct WidgetTransitLineDetailResponse: Decodable, Sendable {
    let line: WidgetTransitLineInfo?
    let stations: [WidgetTransitStation]
    let empty: Bool

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        line = try container.decodeIfPresent(WidgetTransitLineInfo.self, forKey: .line)
        stations = try container.decodeIfPresent([WidgetTransitStation].self, forKey: .stations) ?? []
        empty = try container.decodeFlexibleBool(forKey: .empty) ?? false
    }

    private enum CodingKeys: String, CodingKey { case line, stations, empty }
}

struct WidgetTransitLineInfo: Decodable, Sendable {
    let lineID: String?
    let name: String?
    let startName: String?
    let endName: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lineID = try container.decodeIfPresent(String.self, forKey: .lineID)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        startName = try container.decodeIfPresent(String.self, forKey: .startName)
        endName = try container.decodeIfPresent(String.self, forKey: .endName)
    }

    private enum CodingKeys: String, CodingKey {
        case lineID = "lineId"
        case name
        case startName = "startSn"
        case endName = "endSn"
    }
}

struct WidgetTransitStation: Decodable, Sendable {
    let order: Int?
    let stationID: String?
    let name: String?
    let latitude: Double?
    let longitude: Double?
    let physicalStopID: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        order = try container.decodeFlexibleInt(forKey: .order)
        stationID = try container.decodeIfPresent(String.self, forKey: .stationID)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        latitude = try container.decodeFlexibleDouble(forKey: .latitude)
        longitude = try container.decodeFlexibleDouble(forKey: .longitude)
        physicalStopID = try container.decodeIfPresent(String.self, forKey: .physicalStopID)
    }

    private enum CodingKeys: String, CodingKey {
        case order
        case stationID = "sId"
        case name = "sn"
        case latitude = "wgsLat"
        case longitude = "wgsLng"
        case physicalStopID = "physicalStId"
    }
}

struct WidgetTransitRealtimeResponse: Decodable, Sendable {
    let buses: [WidgetTransitRealtimeBus]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        buses = try container.decodeIfPresent([WidgetTransitRealtimeBus].self, forKey: .buses) ?? []
    }

    private enum CodingKeys: String, CodingKey { case buses }
}

struct WidgetTransitRealtimeBus: Decodable, Sendable {
    let eta: WidgetTransitETA?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        eta = try container.decodeIfPresent(WidgetTransitETA.self, forKey: .eta)
    }

    private enum CodingKeys: String, CodingKey { case eta }
}

struct WidgetTransitETA: Decodable, Sendable {
    let travelTime: Int?
    let arrivalTime: Int64?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        travelTime = try container.decodeFlexibleInt(forKey: .travelTime)
        arrivalTime = try container.decodeFlexibleInt64(forKey: .arrivalTime)
    }

    private enum CodingKeys: String, CodingKey { case travelTime, arrivalTime }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleInt(forKey key: Key) throws -> Int? {
        if let value = try decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try decodeIfPresent(String.self, forKey: key) { return Int(value) }
        return nil
    }

    func decodeFlexibleInt64(forKey key: Key) throws -> Int64? {
        if let value = try decodeIfPresent(Int64.self, forKey: key) { return value }
        if let value = try decodeIfPresent(String.self, forKey: key) { return Int64(value) }
        return nil
    }

    func decodeFlexibleDouble(forKey key: Key) throws -> Double? {
        if let value = try decodeIfPresent(Double.self, forKey: key) { return value }
        if let value = try decodeIfPresent(String.self, forKey: key) { return Double(value) }
        return nil
    }

    func decodeFlexibleBool(forKey key: Key) throws -> Bool? {
        if let value = try decodeIfPresent(Bool.self, forKey: key) { return value }
        if let value = try decodeIfPresent(Int.self, forKey: key) { return value != 0 }
        if let value = try decodeIfPresent(String.self, forKey: key) {
            switch value.lowercased() {
            case "true", "1", "yes": return true
            case "false", "0", "no": return false
            default: return nil
            }
        }
        return nil
    }
}

struct WidgetTransitTargetResolver: Sendable {
    let client: WidgetTransitAPIClient
    let hongKongClient: WidgetHongKongAPIClient

    init(
        client: WidgetTransitAPIClient = WidgetTransitAPIClient(),
        hongKongClient: WidgetHongKongAPIClient = WidgetHongKongAPIClient()
    ) {
        self.client = client
        self.hongKongClient = hongKongClient
    }

    func targets(for input: String) async -> [WidgetTransitTargetRecord] {
        guard let query = WidgetTransitQueryParser.parse(input) else { return [] }
        return await targets(for: query)
    }

    /// Resolves the manual widget fields without relying on AppEntity query
    /// suggestions. The selected city is carried into the query directly and
    /// is checked again on the result so a response from another city cannot
    /// become a target for this configuration.
    func target(
        for city: WidgetTransitCity,
        route: String,
        direction: Int,
        stop: String?
    ) async -> WidgetTransitTargetRecord? {
        await target(
            for: city,
            operatorID: nil,
            route: route,
            direction: direction,
            stop: stop
        )
    }

    /// Resolves the manual fields. Hong Kong requires an explicit operator so
    /// a route number shared by KMB and Citybus cannot cross namespaces.
    func target(
        for city: WidgetTransitCity,
        operatorID: String?,
        route: String,
        direction: Int,
        stop: String?
    ) async -> WidgetTransitTargetRecord? {
        let route = clean(route)
        let stop = clean(stop)
        guard let route,
              direction == WidgetTransitManualDirection.outbound
                || direction == WidgetTransitManualDirection.inbound
        else { return nil }

        if city.id == "hk" {
            guard let operatorID else { return nil }
            return await WidgetHongKongTargetResolver(client: hongKongClient).target(
                operatorID: operatorID,
                route: route,
                direction: direction,
                stop: stop
            )
        }

        var keywordParts = [route]
        if let stop {
            keywordParts.append(stop)
        }
        let keyword = keywordParts.joined(separator: " ")
        let records = await targets(
            for: WidgetTransitParsedQuery(city: city, keyword: keyword)
        )
        let directionRecords = records.filter {
            $0.cityID == city.id && $0.direction == direction
        }
        guard !directionRecords.isEmpty else { return nil }

        // `targets(for:)` already applies the stop hint. Keeping this explicit
        // also protects this API if the search/detail implementation changes.
        if let stop {
            let foldedStop = WidgetTransitQueryParser.folded(stop)
            return directionRecords.first {
                WidgetTransitQueryParser.folded($0.stopName).contains(foldedStop)
            }
        }
        // Detail stations are sorted by sequence, so the first match is the
        // first stop in the selected direction.
        return directionRecords.first
    }

    private func targets(for query: WidgetTransitParsedQuery) async -> [WidgetTransitTargetRecord] {
        if query.city.id == "hk" {
            return await WidgetHongKongTargetResolver(client: hongKongClient).targets(for: query.keyword)
        }
        guard var response = try? await client.search(cityID: query.city.id, keyword: query.keyword) else {
            return []
        }
        // Some deployments index route names and stop names separately. If a
        // combined "route stop" query does not produce a line, retry only the
        // route token; the station hint is still applied to line detail below.
        if response.lines.isEmpty,
           let routeToken = query.keyword.split(whereSeparator: { $0.isWhitespace }).first,
           query.keyword.split(whereSeparator: { $0.isWhitespace }).count > 1,
           let routeOnly = try? await client.search(cityID: query.city.id, keyword: String(routeToken)) {
            response = routeOnly
        }

        let flattenedLines = response.lines.flatMap { line -> [WidgetTransitLineCandidate] in
            let directions = line.directions.isEmpty
                ? [WidgetTransitDirection(
                    direction: line.direction,
                    lineID: line.lineID,
                    startName: line.startName,
                    endName: line.endName
                )]
                : line.directions
            return directions.enumerated().compactMap { index, direction in
                guard let lineID = clean(direction.lineID ?? (index == 0 ? line.lineID : nil)) else { return nil }
                return WidgetTransitLineCandidate(
                    lineID: lineID,
                    name: clean(line.name ?? line.lineNo) ?? lineID,
                    direction: direction.direction ?? (index == 0 ? line.direction : nil) ?? index,
                    origin: clean(direction.startName ?? line.startName) ?? "",
                    destination: clean(direction.endName ?? line.endName) ?? ""
                )
            }
        }

        guard !flattenedLines.isEmpty else { return [] }
        let routeHint = query.keyword.split(whereSeparator: { $0.isWhitespace }).first.map { String($0) }
        let routeLines = flattenedLines.filter { line in
            guard let routeHint else { return true }
            let foldedHint = WidgetTransitQueryParser.folded(routeHint)
            return WidgetTransitQueryParser.folded(line.name).contains(foldedHint)
                || WidgetTransitQueryParser.folded(line.lineID).contains(foldedHint)
        }
        let candidates = routeLines.isEmpty ? flattenedLines : routeLines
        let keywordParts = query.keyword.split(whereSeparator: { $0.isWhitespace }).map { String($0) }
        let stopHint = keywordParts.count > 1 ? keywordParts.dropFirst().joined() : nil

        var records: [WidgetTransitTargetRecord] = []
        for candidate in candidates.prefix(12) {
            guard let detail = try? await client.lineDetail(cityID: query.city.id, lineID: candidate.lineID),
                  !detail.empty
            else { continue }
            let stations = detail.stations.enumerated().sorted { left, right in
                let leftOrder = left.element.order ?? Int.max
                let rightOrder = right.element.order ?? Int.max
                return leftOrder == rightOrder ? left.offset < right.offset : leftOrder < rightOrder
            }
            for (index, station) in stations {
                guard let stationID = clean(station.stationID),
                      let stopName = clean(station.name),
                      let latitude = station.latitude,
                      let longitude = station.longitude,
                      latitude.isFinite, longitude.isFinite
                else { continue }
                let stopSequence = station.order ?? (index + 1)
                guard stopSequence > 0 else { continue }
                // Realtime requests use `sId`. Some deployments omit
                // `physicalStId`, so keep an otherwise queryable stop.
                let stopID = clean(station.physicalStopID) ?? stationID
                if let stopHint, !WidgetTransitQueryParser.folded(stopName).contains(WidgetTransitQueryParser.folded(stopHint)) {
                    continue
                }
                records.append(
                    WidgetTransitTargetRecord(
                        cityID: query.city.id,
                        cityName: query.city.name,
                        lineID: clean(detail.line?.lineID) ?? candidate.lineID,
                        lineName: clean(detail.line?.name) ?? candidate.name,
                        direction: candidate.direction,
                        origin: clean(detail.line?.startName) ?? candidate.origin,
                        destination: clean(detail.line?.endName) ?? candidate.destination,
                        stopID: stopID,
                        stopName: stopName,
                        stationID: stationID,
                        stopSequence: stopSequence,
                        latitude: latitude,
                        longitude: longitude
                    )
                )
            }
        }

        var seen = Set<String>()
        return records.filter { seen.insert($0.id).inserted }.prefix(80).map { $0 }
    }

    func etaDates(for target: WidgetTransitTargetRecord) async -> (dates: [Date], unavailable: Bool) {
        if target.cityID == "hk" {
            return await WidgetHongKongTargetResolver(client: hongKongClient).etaDates(for: target)
        }
        guard let response = try? await client.realtime(for: target) else {
            return ([], true)
        }
        let dates = response.buses.compactMap { bus -> Date? in
            guard let eta = bus.eta else { return nil }
            if let arrivalTime = eta.arrivalTime, arrivalTime > 0 {
                return Date(timeIntervalSince1970: TimeInterval(arrivalTime) / 1_000)
            }
            if let travelTime = eta.travelTime, travelTime >= 0 {
                return Date().addingTimeInterval(TimeInterval(travelTime))
            }
            return nil
        }
        .filter { $0.timeIntervalSince1970.isFinite }
        .sorted()
        return (Array(dates.prefix(3)), false)
    }

    private func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct WidgetTransitLineCandidate: Sendable {
    let lineID: String
    let name: String
    let direction: Int
    let origin: String
    let destination: String
}

private extension WidgetTransitDirection {
    init(direction: Int?, lineID: String?, startName: String?, endName: String?) {
        self.direction = direction
        self.lineID = lineID
        self.startName = startName
        self.endName = endName
    }
}
