import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Hong Kong operator IDs used by the extension-owned API client.
///
/// This file intentionally has no dependency on the app target, EtaDB, or
/// App Group storage. The widget can therefore resolve and refresh a target in
/// a SideStore installation with only Foundation and its own network request.
enum WidgetHongKongOperatorID: String, CaseIterable, Codable, Hashable, Sendable {
    case kmb
    case ctb
    case gmb
    case nlb
}

enum WidgetHongKongAPIError: Error, Hashable, Sendable {
    case invalidURL
    case invalidRequest(String)
    case httpStatus(Int)
    case transport
    case decoding
}

/// Foundation-only client for the four Hong Kong operators exposed by the
/// manual widget configuration.
struct WidgetHongKongAPIClient: Sendable {
    static let kmbBaseURL = URL(string: "https://data.etabus.gov.hk/v1/transport/kmb")!
    static let citybusBaseURL = URL(string: "https://rt.data.gov.hk/v1/transport/citybus-nwfb")!
    static let gmbBaseURL = URL(string: "https://data.etagmb.gov.hk")!
    static let nlbBaseURL = URL(string: "https://rt.data.gov.hk/v2/transport/nlb")!

    private let transport: any WidgetTransitAPITransport

    init(transport: any WidgetTransitAPITransport = WidgetTransitAPIURLSessionTransport()) {
        self.transport = transport
    }

    // MARK: KMB

    func kmbRoutes() async throws -> [WidgetKMBRoute] {
        let response: WidgetEnvelope<[WidgetKMBRoute]> = try await get(
            WidgetHongKongAPIClient.kmbBaseURL,
            path: path("route")
        )
        return response.data
    }

    func kmbStops() async throws -> [WidgetKMBStop] {
        let response: WidgetEnvelope<[WidgetKMBStop]> = try await get(
            WidgetHongKongAPIClient.kmbBaseURL,
            path: path("stop")
        )
        return response.data
    }

    func kmbRouteStops(route: String, direction: String, serviceType: String) async throws -> [WidgetKMBRouteStop] {
        let response: WidgetEnvelope<[WidgetKMBRouteStop]> = try await get(
            WidgetHongKongAPIClient.kmbBaseURL,
            path: path("route-stop", route, direction, serviceType)
        )
        return response.data
    }

    func kmbETAs(stopID: String, route: String, serviceType: String) async throws -> [WidgetKMBETA] {
        let response: WidgetEnvelope<[WidgetKMBETA]> = try await get(
            WidgetHongKongAPIClient.kmbBaseURL,
            path: path("eta", stopID, route, serviceType)
        )
        return response.data
    }

    // MARK: Citybus

    func citybusRoute(route: String) async throws -> WidgetCitybusRoute {
        let response: WidgetEnvelope<WidgetCitybusRoute> = try await get(
            WidgetHongKongAPIClient.citybusBaseURL,
            path: path("route", "CTB", route)
        )
        return response.data
    }

    func citybusStops(route: String, direction: String) async throws -> [WidgetCitybusRouteStop] {
        let response: WidgetEnvelope<[WidgetCitybusRouteStop]> = try await get(
            WidgetHongKongAPIClient.citybusBaseURL,
            path: path("route-stop", "CTB", route, direction)
        )
        return response.data
    }

    func citybusStopList() async throws -> [WidgetCitybusStop] {
        let response: WidgetEnvelope<[WidgetCitybusStop]> = try await get(
            WidgetHongKongAPIClient.citybusBaseURL,
            path: path("stop")
        )
        return response.data
    }

    func citybusETAs(stopID: String, route: String) async throws -> [WidgetCitybusETA] {
        let response: WidgetEnvelope<[WidgetCitybusETA]> = try await get(
            WidgetHongKongAPIClient.citybusBaseURL,
            path: path("eta", "CTB", stopID, route)
        )
        return response.data
    }

    // MARK: Green minibus

    func gmbRouteCodes() async throws -> [String: [String]] {
        let response: WidgetGMBRouteListResponse = try await get(
            WidgetHongKongAPIClient.gmbBaseURL,
            path: path("route")
        )
        return response.data?.routes ?? [:]
    }

    func gmbRoute(region: String, routeCode: String) async throws -> [WidgetGMBRoute] {
        let response: WidgetGMBRouteResponse = try await get(
            WidgetHongKongAPIClient.gmbBaseURL,
            path: path("route", region, routeCode)
        )
        return response.data ?? []
    }

    func gmbRouteStops(routeID: String, routeSequence: Int) async throws -> [WidgetGMBRouteStop] {
        let response: WidgetGMBRouteStopsResponse = try await get(
            WidgetHongKongAPIClient.gmbBaseURL,
            path: path("route-stop", routeID, String(routeSequence))
        )
        return response.data?.routeStops ?? []
    }

    func gmbStop(stopID: String) async throws -> WidgetGMBStop {
        let response: WidgetGMBStopResponse = try await get(
            WidgetHongKongAPIClient.gmbBaseURL,
            path: path("stop", stopID)
        )
        guard let stop = response.data else { throw WidgetHongKongAPIError.decoding }
        return stop
    }

    func gmbETA(routeID: String, routeSequence: Int, stopSequence: Int) async throws -> WidgetGMBETAData {
        let response: WidgetGMBETAResponse = try await get(
            WidgetHongKongAPIClient.gmbBaseURL,
            path: path("eta", "route-stop", routeID, String(routeSequence), String(stopSequence))
        )
        guard let data = response.data else { throw WidgetHongKongAPIError.decoding }
        return data
    }

    // MARK: New Lantao Bus

    func nlbRoutes() async throws -> [WidgetNLBRoute] {
        let response: WidgetNLBRouteResponse = try await get(
            WidgetHongKongAPIClient.nlbBaseURL,
            path: "route.php",
            parameters: [("action", "list")]
        )
        return response.routes ?? []
    }

    func nlbStops(routeID: String) async throws -> [WidgetNLBStop] {
        let response: WidgetNLBStopResponse = try await get(
            WidgetHongKongAPIClient.nlbBaseURL,
            path: "stop.php",
            parameters: [("action", "list"), ("routeId", routeID)]
        )
        return response.stops ?? []
    }

    func nlbETAs(routeID: String, stopID: String) async throws -> [WidgetNLBETA] {
        let response: WidgetNLBETAResponse = try await get(
            WidgetHongKongAPIClient.nlbBaseURL,
            path: "stop.php",
            parameters: [
                ("action", "estimatedArrivals"),
                ("routeId", routeID),
                ("stopId", stopID),
                ("language", "en"),
            ]
        )
        return response.estimatedArrivals ?? []
    }

    // MARK: Request boundary

    private func get<T: Decodable>(
        _ baseURL: URL,
        path: String,
        parameters: [(String, String)] = []
    ) async throws -> T {
        let url = try WidgetTransitAPIClient.makeURL(
            baseURL: baseURL,
            path: path,
            parameters: parameters
        )
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let response: WidgetTransitAPITransportResponse
        do {
            response = try await transport.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw WidgetHongKongAPIError.transport
        }
        guard let statusCode = response.statusCode else {
            throw WidgetHongKongAPIError.transport
        }
        guard (200...299).contains(statusCode) else {
            throw WidgetHongKongAPIError.httpStatus(statusCode)
        }
        do {
            return try JSONDecoder().decode(T.self, from: response.data)
        } catch {
            throw WidgetHongKongAPIError.decoding
        }
    }

    private func path(_ components: String...) -> String {
        // URLComponents performs the final escaping when makeURL assigns the
        // path. Keeping separators and ordinary hyphens unescaped here avoids
        // double-encoding endpoint names such as `route-stop`.
        components.joined(separator: "/")
    }
}

// MARK: - Foundation-only route models

struct WidgetKMBRoute: Decodable, Hashable, Sendable {
    let route: String?
    let bound: String?
    let serviceType: String?
    let origin: String?
    let destination: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        route = container.hkString(.route)
        bound = container.hkString(.bound)
        serviceType = container.hkString(.serviceType)
        origin = container.hkString(.origin)
        destination = container.hkString(.destination)
    }

    private enum CodingKeys: String, CodingKey {
        case route, bound
        case serviceType = "service_type"
        case origin = "orig_en"
        case destination = "dest_en"
    }
}

struct WidgetKMBStop: Decodable, Hashable, Sendable {
    let id: String?
    let name: String?
    let latitude: Double?
    let longitude: Double?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.hkString(.id)
        name = container.hkString(.name)
        latitude = container.hkDouble(.latitude)
        longitude = container.hkDouble(.longitude)
    }

    private enum CodingKeys: String, CodingKey {
        case id = "stop"
        case name = "name_en"
        case latitude = "lat"
        case longitude = "long"
    }
}

struct WidgetKMBRouteStop: Decodable, Hashable, Sendable {
    let sequence: Int?
    let stopID: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sequence = container.hkInt(.sequence)
        stopID = container.hkString(.stopID)
    }

    private enum CodingKeys: String, CodingKey {
        case sequence = "seq"
        case stopID = "stop"
    }
}

struct WidgetKMBETA: Decodable, Hashable, Sendable {
    let direction: String?
    let sequence: Int?
    let eta: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        direction = container.hkString(.direction)
        sequence = container.hkInt(.sequence)
        eta = container.hkString(.eta)
    }

    private enum CodingKeys: String, CodingKey { case direction = "dir", sequence = "seq", eta }
}

struct WidgetCitybusRoute: Decodable, Hashable, Sendable {
    let route: String?
    let origin: String?
    let destination: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        route = container.hkString(.route)
        origin = container.hkString(.origin)
        destination = container.hkString(.destination)
    }

    private enum CodingKeys: String, CodingKey {
        case route
        case origin = "orig_en"
        case destination = "dest_en"
    }
}

struct WidgetCitybusRouteStop: Decodable, Hashable, Sendable {
    let direction: String?
    let sequence: Int?
    let stopID: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        direction = container.hkString(.direction)
        sequence = container.hkInt(.sequence)
        stopID = container.hkString(.stopID)
    }

    private enum CodingKeys: String, CodingKey {
        case direction = "dir"
        case sequence = "seq"
        case stopID = "stop"
    }
}

struct WidgetCitybusStop: Decodable, Hashable, Sendable {
    let id: String?
    let name: String?
    let latitude: Double?
    let longitude: Double?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.hkString(.id)
        name = container.hkString(.name)
        latitude = container.hkDouble(.latitude)
        longitude = container.hkDouble(.longitude)
    }

    private enum CodingKeys: String, CodingKey {
        case id = "stop"
        case name = "name_en"
        case latitude = "lat"
        case longitude = "long"
    }
}

struct WidgetCitybusETA: Decodable, Hashable, Sendable {
    let direction: String?
    let sequence: Int?
    let eta: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        direction = container.hkString(.direction)
        sequence = container.hkInt(.sequence)
        eta = container.hkString(.eta)
    }

    private enum CodingKeys: String, CodingKey { case direction = "dir", sequence = "seq", eta }
}

struct WidgetGMBRouteListResponse: Decodable, Sendable {
    let data: DataValue?

    struct DataValue: Decodable, Sendable {
        let routes: [String: [String]]?
    }
}

struct WidgetGMBRouteResponse: Decodable, Sendable {
    let data: [WidgetGMBRoute]?
}

struct WidgetGMBRoute: Decodable, Hashable, Sendable {
    let region: String?
    let routeCode: String?
    let routeID: String?
    let directions: [WidgetGMBDirection]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        region = container.hkString(.region)
        routeCode = container.hkString(.routeCode)
        routeID = container.hkString(.routeID)
        directions = (try? container.decode([WidgetGMBDirection].self, forKey: .directions)) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case region
        case routeCode = "route_code"
        case routeID = "route_id"
        case directions
    }
}

struct WidgetGMBDirection: Decodable, Hashable, Sendable {
    let routeSequence: Int?
    let origin: String?
    let destination: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        routeSequence = container.hkInt(.routeSequence)
        origin = container.hkString(.origin)
        destination = container.hkString(.destination)
    }

    private enum CodingKeys: String, CodingKey {
        case routeSequence = "route_seq"
        case origin = "orig_en"
        case destination = "dest_en"
    }
}

struct WidgetGMBRouteStop: Decodable, Hashable, Sendable {
    let sequence: Int?
    let stopID: String?
    let name: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sequence = container.hkInt(.sequence)
        stopID = container.hkString(.stopID)
        name = container.hkString(.name)
    }

    private enum CodingKeys: String, CodingKey {
        case sequence = "stop_seq"
        case stopID = "stop_id"
        case name = "name_en"
    }
}

struct WidgetGMBRouteStopsResponse: Decodable, Sendable {
    let data: DataValue?

    struct DataValue: Decodable, Sendable {
        let routeStops: [WidgetGMBRouteStop]?

        private enum CodingKeys: String, CodingKey {
            case routeStops = "route_stops"
        }
    }
}

struct WidgetGMBStop: Decodable, Sendable {
    let coordinates: Coordinates?

    struct Coordinates: Decodable, Sendable {
        let wgs84: WGS84?
    }

    struct WGS84: Decodable, Sendable {
        let latitude: Double?
        let longitude: Double?
    }
}

struct WidgetGMBETAResponse: Decodable, Sendable {
    let data: WidgetGMBETAData?
}

struct WidgetGMBETAData: Decodable, Sendable {
    let enabled: Bool?
    let eta: [WidgetGMBETA]?
    let description: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = container.hkBool(.enabled)
        eta = try? container.decodeIfPresent([WidgetGMBETA].self, forKey: .eta)
        description = container.hkString(.description)
            ?? container.hkString(.descriptionEnglish)
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, eta
        case description = "description_en"
        case descriptionEnglish = "description"
    }
}

struct WidgetGMBETA: Decodable, Sendable {
    let timestamp: String?
    let diff: Int?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = container.hkString(.timestamp)
        diff = container.hkInt(.diff)
    }

    private enum CodingKeys: String, CodingKey { case timestamp, diff }
}

struct WidgetGMBStopResponse: Decodable, Sendable {
    let data: WidgetGMBStop?
}

struct WidgetNLBRouteResponse: Decodable, Sendable {
    let routes: [WidgetNLBRoute]?
}

struct WidgetNLBRoute: Decodable, Hashable, Sendable {
    let id: String?
    let number: String?
    let name: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.hkString(.id)
        number = container.hkString(.number)
        name = container.hkString(.name)
    }

    private enum CodingKeys: String, CodingKey {
        case id = "routeId"
        case number = "routeNo"
        case name = "routeName_e"
    }
}

struct WidgetNLBStopResponse: Decodable, Sendable {
    let stops: [WidgetNLBStop]?
}

struct WidgetNLBStop: Decodable, Hashable, Sendable {
    let id: String?
    let name: String?
    let latitude: Double?
    let longitude: Double?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.hkString(.id)
        name = container.hkString(.name)
        latitude = container.hkDouble(.latitude)
        longitude = container.hkDouble(.longitude)
    }

    private enum CodingKeys: String, CodingKey {
        case id = "stopId"
        case name = "stopName_e"
        case latitude
        case longitude
    }
}

struct WidgetNLBETAResponse: Decodable, Sendable {
    let estimatedArrivals: [WidgetNLBETA]?
}

struct WidgetNLBETA: Decodable, Sendable {
    let arrivalTime: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        arrivalTime = container.hkString(.arrivalTime)
    }

    private enum CodingKeys: String, CodingKey { case arrivalTime = "estimatedArrivalTime" }
}

private struct WidgetNLBRouteCandidate: Sendable {
    let route: WidgetNLBRoute
    let routeID: String
    let origin: String
    let destination: String

    var orientationKey: String {
        "\(WidgetTransitQueryParser.folded(origin))|\(WidgetTransitQueryParser.folded(destination))"
    }
}

private struct WidgetEnvelope<T: Decodable>: Decodable {
    let data: T
}

private extension KeyedDecodingContainer {
    func hkString(_ key: Key) -> String? {
        if let value = try? decode(String.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key) { return String(value) }
        if let value = try? decode(Double.self, forKey: key) { return String(value) }
        return nil
    }

    func hkInt(_ key: Key) -> Int? {
        if let value = try? decode(Int.self, forKey: key) { return value }
        if let value = try? decode(String.self, forKey: key) { return Int(value) }
        return nil
    }

    func hkDouble(_ key: Key) -> Double? {
        if let value = try? decode(Double.self, forKey: key) { return value }
        if let value = try? decode(String.self, forKey: key) { return Double(value) }
        return nil
    }

    func hkBool(_ key: Key) -> Bool? {
        if let value = try? decode(Bool.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key) { return value != 0 }
        if let value = try? decode(String.self, forKey: key) {
            switch value.lowercased() {
            case "true", "1", "yes": return true
            case "false", "0", "no": return false
            default: return nil
            }
        }
        return nil
    }
}

// MARK: - Hong Kong target resolution

struct WidgetHongKongTargetResolver: Sendable {
    let client: WidgetHongKongAPIClient

    init(client: WidgetHongKongAPIClient = WidgetHongKongAPIClient()) {
        self.client = client
    }

    func targets(for input: String) async -> [WidgetTransitTargetRecord] {
        guard let match = WidgetTransitOperatorCatalog.operatorID(matchingPrefix: input),
              let routeAndStop = splitRouteAndStop(match.remainder)
        else { return [] }
        return await targets(
            operatorID: match.id,
            route: routeAndStop.route,
            direction: nil,
            stop: routeAndStop.stop
        )
    }

    func target(
        operatorID: String,
        route: String,
        direction: Int,
        stop: String?
    ) async -> WidgetTransitTargetRecord? {
        await targets(operatorID: operatorID, route: route, direction: direction, stop: stop).first
    }

    private func targets(
        operatorID: String,
        route: String,
        direction: Int?,
        stop: String?
    ) async -> [WidgetTransitTargetRecord] {
        guard let operatorID = WidgetHongKongOperatorID(rawValue: operatorID),
              let route = cleanRoute(route)
        else { return [] }

        do {
            switch operatorID {
            case .kmb:
                return try await kmbTargets(route: route, direction: direction, stop: stop)
            case .ctb:
                return try await citybusTargets(route: route, direction: direction, stop: stop)
            case .gmb:
                return try await gmbTargets(route: route, direction: direction, stop: stop)
            case .nlb:
                return try await nlbTargets(route: route, direction: direction, stop: stop)
            }
        } catch is CancellationError {
            return []
        } catch {
            return []
        }
    }

    func etaDates(for target: WidgetTransitTargetRecord) async -> (dates: [Date], unavailable: Bool) {
        guard let operatorID = target.operatorID,
              let operatorValue = WidgetHongKongOperatorID(rawValue: operatorID)
        else { return ([], true) }

        do {
            let dates: [Date]
            switch operatorValue {
            case .kmb:
                let values = try await client.kmbETAs(
                    stopID: target.stationID,
                    route: target.lineName,
                    serviceType: target.serviceType ?? "1"
                )
                dates = values.compactMap { value in
                    guard value.direction == target.providerDirection,
                          value.sequence == target.stopSequence,
                          let eta = value.eta
                    else { return nil }
                    return WidgetHongKongDateParser.date(eta)
                }
            case .ctb:
                let values = try await client.citybusETAs(
                    stopID: target.stationID,
                    route: target.lineName
                )
                dates = values.compactMap { value in
                    guard value.direction == target.providerDirection,
                          value.sequence == target.stopSequence,
                          let eta = value.eta
                    else { return nil }
                    return WidgetHongKongDateParser.date(eta)
                }
            case .gmb:
                guard let routeSequence = Int(target.providerDirection ?? "") else {
                    return ([], true)
                }
                let value = try await client.gmbETA(
                    routeID: target.lineID,
                    routeSequence: routeSequence,
                    stopSequence: target.stopSequence
                )
                guard value.enabled != false else { return ([], true) }
                dates = (value.eta ?? []).compactMap { eta in
                    if let timestamp = eta.timestamp {
                        return WidgetHongKongDateParser.date(timestamp)
                    }
                    if let diff = eta.diff, diff >= 0 {
                        return Date().addingTimeInterval(TimeInterval(diff * 60))
                    }
                    return nil
                }
            case .nlb:
                let values = try await client.nlbETAs(
                    routeID: target.lineID,
                    stopID: target.stationID
                )
                dates = values.compactMap { value in
                    guard let arrivalTime = value.arrivalTime else { return nil }
                    return WidgetHongKongDateParser.date(arrivalTime)
                }
            }
            return (Array(dates.filter { $0 > Date() }.sorted().prefix(3)), false)
        } catch is CancellationError {
            return ([], true)
        } catch {
            return ([], true)
        }
    }

    private func kmbTargets(
        route: String,
        direction: Int?,
        stop: String?
    ) async throws -> [WidgetTransitTargetRecord] {
        async let routes = client.kmbRoutes()
        async let stops = client.kmbStops()
        let routeValues = try await routes
        let stopValues = try await stops
        let stopMap = Dictionary(uniqueKeysWithValues: stopValues.compactMap { value -> (String, WidgetKMBStop)? in
            guard let id = clean(value.id) else { return nil }
            return (id, value)
        })
        let bounds = direction.map { [$0 == WidgetTransitManualDirection.outbound ? "O" : "I"] }
            ?? ["O", "I"]
        let variants = routeValues.filter { value in
            guard let valueRoute = clean(value.route),
                  WidgetTransitQueryParser.folded(valueRoute) == WidgetTransitQueryParser.folded(route),
                  let bound = clean(value.bound),
                  bounds.contains(bound),
                  clean(value.serviceType) != nil
            else { return false }
            return true
        }.sorted { (Int($0.serviceType ?? "") ?? Int.max) < (Int($1.serviceType ?? "") ?? Int.max) }

        for variant in variants {
            guard let routeValue = clean(variant.route),
                  let bound = clean(variant.bound),
                  let serviceType = clean(variant.serviceType)
            else { continue }
            let routeStops = try? await client.kmbRouteStops(
                route: routeValue,
                direction: bound == "O" ? "outbound" : "inbound",
                serviceType: serviceType
            )
            guard let routeStops else { continue }
            let ordered = routeStops.sorted { ($0.sequence ?? Int.max) < ($1.sequence ?? Int.max) }
            if let record = makeKMBRecord(
                variant: variant,
                orderedStops: ordered,
                stopMap: stopMap,
                requestedStop: stop
            ) {
                return [record]
            }
        }
        return []
    }

    private func makeKMBRecord(
        variant: WidgetKMBRoute,
        orderedStops: [WidgetKMBRouteStop],
        stopMap: [String: WidgetKMBStop],
        requestedStop: String?
    ) -> WidgetTransitTargetRecord? {
        let hint = clean(requestedStop).map(WidgetTransitQueryParser.folded)
        let candidates = orderedStops.compactMap { membership -> (WidgetKMBRouteStop, WidgetKMBStop)? in
            guard let stopID = clean(membership.stopID), let stop = stopMap[stopID],
                  clean(stop.name) != nil,
                  let latitude = stop.latitude, let longitude = stop.longitude,
                  latitude.isFinite, longitude.isFinite
            else { return nil }
            if let hint, !WidgetTransitQueryParser.folded(stop.name ?? "").contains(hint) {
                return nil
            }
            return (membership, stop)
        }
        guard let (membership, stop) = candidates.first,
              let stopID = clean(stop.id),
              let name = clean(stop.name),
              let sequence = membership.sequence, sequence > 0,
              let route = clean(variant.route),
              let bound = clean(variant.bound)
        else { return nil }
        return WidgetTransitTargetRecord(
            cityID: "hk",
            cityName: "香港",
            lineID: route,
            lineName: route,
            direction: bound == "O" ? WidgetTransitManualDirection.outbound : WidgetTransitManualDirection.inbound,
            origin: clean(variant.origin) ?? "",
            destination: clean(variant.destination) ?? "",
            stopID: stopID,
            stopName: name,
            stationID: stopID,
            stopSequence: sequence,
            latitude: stop.latitude ?? 0,
            longitude: stop.longitude ?? 0,
            operatorID: WidgetHongKongOperatorID.kmb.rawValue,
            providerDirection: bound == "O" ? "O" : "I",
            serviceType: clean(variant.serviceType)
        )
    }

    private func citybusTargets(
        route: String,
        direction: Int?,
        stop: String?
    ) async throws -> [WidgetTransitTargetRecord] {
        let routeInfo = try await client.citybusRoute(route: route)
        async let routeStops = client.citybusStops(
            route: route,
            direction: direction == WidgetTransitManualDirection.inbound ? "inbound" : "outbound"
        )
        async let stopValues = client.citybusStopList()
        let memberships = try await routeStops
        let stops = try await stopValues
        let stopMap = Dictionary(uniqueKeysWithValues: stops.compactMap { value -> (String, WidgetCitybusStop)? in
            guard let id = clean(value.id) else { return nil }
            return (id, value)
        })
        let requestedDirection = direction ?? WidgetTransitManualDirection.outbound
        let expectedBound = requestedDirection == WidgetTransitManualDirection.outbound ? "O" : "I"
        let ordered = memberships
            .filter { $0.direction == nil || $0.direction == expectedBound }
            .sorted { ($0.sequence ?? Int.max) < ($1.sequence ?? Int.max) }
        let hint = clean(stop).map(WidgetTransitQueryParser.folded)
        for membership in ordered {
            guard let stopID = clean(membership.stopID), let value = stopMap[stopID],
                  let name = clean(value.name), let sequence = membership.sequence,
                  sequence > 0, let latitude = value.latitude, let longitude = value.longitude,
                  latitude.isFinite, longitude.isFinite
            else { continue }
            if let hint, !WidgetTransitQueryParser.folded(name).contains(hint) { continue }
            return [WidgetTransitTargetRecord(
                cityID: "hk",
                cityName: "香港",
                lineID: clean(routeInfo.route) ?? route,
                lineName: clean(routeInfo.route) ?? route,
                direction: requestedDirection,
                origin: clean(routeInfo.origin) ?? "",
                destination: clean(routeInfo.destination) ?? "",
                stopID: stopID,
                stopName: name,
                stationID: stopID,
                stopSequence: sequence,
                latitude: latitude,
                longitude: longitude,
                operatorID: WidgetHongKongOperatorID.ctb.rawValue,
                providerDirection: expectedBound,
                serviceType: nil
            )]
        }
        return []
    }

    private func gmbTargets(
        route: String,
        direction: Int?,
        stop: String?
    ) async throws -> [WidgetTransitTargetRecord] {
        let parsed = parseGMBRoute(route)
        let routeRegions = try await client.gmbRouteCodes()
        let matchingRegions = routeRegions.compactMap { region, routes in
            routes.contains(where: { WidgetTransitQueryParser.folded($0) == WidgetTransitQueryParser.folded(parsed.routeCode) })
                ? region.uppercased() : nil
        }.sorted()
        let regions: [String]
        if let requestedRegion = parsed.region {
            guard matchingRegions.contains(requestedRegion) else { return [] }
            regions = [requestedRegion]
        } else {
            // GMB route codes are only unique inside HKI/KLN/NT. Refuse an
            // unqualified duplicate instead of silently picking one region.
            guard matchingRegions.count == 1, let only = matchingRegions.first else { return [] }
            regions = [only]
        }

        let desiredDirection = direction ?? WidgetTransitManualDirection.outbound
        let desiredRouteSequence = desiredDirection + 1
        let routeValues = try await client.gmbRoute(region: regions[0], routeCode: parsed.routeCode)
        for routeValue in routeValues {
            guard let routeID = clean(routeValue.routeID),
                  let directionValue = routeValue.directions.first(where: { $0.routeSequence == desiredRouteSequence }),
                  let routeSequence = directionValue.routeSequence
            else { continue }
            let routeStops = try? await client.gmbRouteStops(routeID: routeID, routeSequence: routeSequence)
            guard let routeStops else { continue }
            let ordered = routeStops.sorted { ($0.sequence ?? Int.max) < ($1.sequence ?? Int.max) }
            let hint = clean(stop).map(WidgetTransitQueryParser.folded)
            guard let membership = ordered.first(where: { item in
                guard let name = clean(item.name) else { return false }
                return hint.map { WidgetTransitQueryParser.folded(name).contains($0) } ?? true
            }), let stopID = clean(membership.stopID), let sequence = membership.sequence,
                  sequence > 0
            else { continue }
            let stopValue = try await client.gmbStop(stopID: stopID)
            guard let coordinate = stopValue.coordinates?.wgs84,
                  let latitude = coordinate.latitude, let longitude = coordinate.longitude,
                  latitude.isFinite, longitude.isFinite,
                  let name = clean(membership.name)
            else { continue }
            let routeCode = clean(routeValue.routeCode) ?? parsed.routeCode
            return [WidgetTransitTargetRecord(
                cityID: "hk",
                cityName: "香港",
                lineID: routeID,
                lineName: "\(regions[0]) \(routeCode)",
                direction: desiredDirection,
                origin: clean(directionValue.origin) ?? "",
                destination: clean(directionValue.destination) ?? "",
                stopID: stopID,
                stopName: name,
                stationID: stopID,
                stopSequence: sequence,
                latitude: latitude,
                longitude: longitude,
                operatorID: WidgetHongKongOperatorID.gmb.rawValue,
                providerDirection: String(routeSequence),
                serviceType: nil
            )]
        }
        return []
    }

    private func nlbTargets(
        route: String,
        direction: Int?,
        stop: String?
    ) async throws -> [WidgetTransitTargetRecord] {
        let routeValues = try await client.nlbRoutes().filter {
            guard let number = clean($0.number) else { return false }
            return WidgetTransitQueryParser.folded(number) == WidgetTransitQueryParser.folded(route)
        }
        let candidates = routeValues.compactMap { value -> WidgetNLBRouteCandidate? in
            guard let routeID = clean(value.id),
                  let routeName = clean(value.name),
                  let endpoints = nlbEndpoints(from: routeName)
            else { return nil }
            return WidgetNLBRouteCandidate(
                route: value,
                routeID: routeID,
                origin: endpoints.origin,
                destination: endpoints.destination
            )
        }.sorted {
            let left = [
                WidgetTransitQueryParser.folded($0.origin),
                WidgetTransitQueryParser.folded($0.destination),
                WidgetTransitQueryParser.folded($0.route.name ?? ""),
            ]
            let right = [
                WidgetTransitQueryParser.folded($1.origin),
                WidgetTransitQueryParser.folded($1.destination),
                WidgetTransitQueryParser.folded($1.route.name ?? ""),
            ]
            if left != right { return left.lexicographicallyPrecedes(right) }
            // routeId is only a deterministic tie-breaker. It never defines
            // NLB direction because the v2 route list has no bound field.
            return $0.routeID < $1.routeID
        }
        guard !candidates.isEmpty else { return [] }

        // NLB v2 exposes direction through routeName_e (origin > destination)
        // rather than a stable inbound/outbound value. Pair the two endpoint
        // orientations and assign the canonical sorted pair to 0/1. This
        // avoids the old, incorrect assumption that routeId order is a
        // direction mapping.
        let desiredDirection = direction ?? WidgetTransitManualDirection.outbound
        let orientationKeys = Array(Set(candidates.map { $0.orientationKey })).sorted()
        guard orientationKeys.count <= 2 else { return [] }
        let selectedOrientation = orientationKeys.count == 1
            ? orientationKeys[0]
            : orientationKeys[min(desiredDirection, orientationKeys.count - 1)]

        let hint = clean(stop).map(WidgetTransitQueryParser.folded)
        for selected in candidates where selected.orientationKey == selectedOrientation {
            let stops = try await client.nlbStops(routeID: selected.routeID)
            guard let selectedStop = stops.first(where: { value in
                guard let name = clean(value.name) else { return false }
                return hint.map { WidgetTransitQueryParser.folded(name).contains($0) } ?? true
            }), let stopID = clean(selectedStop.id), let stopName = clean(selectedStop.name),
                  let latitude = selectedStop.latitude, let longitude = selectedStop.longitude,
                  latitude.isFinite, longitude.isFinite
            else { continue }
            let sequence = stops.firstIndex(of: selectedStop).map { $0 + 1 } ?? 1
            return [WidgetTransitTargetRecord(
                cityID: "hk",
                cityName: "香港",
                lineID: selected.routeID,
                lineName: clean(selected.route.number) ?? route,
                direction: desiredDirection,
                origin: selected.origin,
                destination: selected.destination,
                stopID: stopID,
                stopName: stopName,
                stationID: stopID,
                stopSequence: sequence,
                latitude: latitude,
                longitude: longitude,
                operatorID: WidgetHongKongOperatorID.nlb.rawValue,
                providerDirection: nil,
                serviceType: nil
            )]
        }
        return []
    }

    private func nlbEndpoints(from routeName: String) -> (origin: String, destination: String)? {
        let parts = routeName
            .split(separator: ">", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard parts.count >= 2, let origin = parts.first, let destination = parts.last else {
            return nil
        }
        return (origin, destination)
    }

    private func splitRouteAndStop(_ input: String) -> (route: String, stop: String?)? {
        let parts = input.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard let route = parts.first, !route.isEmpty else { return nil }
        let stop = parts.dropFirst().joined(separator: " ")
        return (route, stop.isEmpty ? nil : stop)
    }

    private func parseGMBRoute(_ input: String) -> (region: String?, routeCode: String) {
        let parts = input.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard parts.count > 1 else { return (nil, input) }
        let possibleRegion = parts[0].uppercased()
        guard ["HKI", "KLN", "NT"].contains(possibleRegion) else { return (nil, input) }
        return (possibleRegion, parts.dropFirst().joined(separator: " "))
    }

    private func cleanRoute(_ value: String) -> String? {
        guard let value = clean(value), !value.contains("/") else { return nil }
        return value
    }

    private func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }
}

enum WidgetHongKongDateParser {
    static func date(_ value: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: value) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: value) { return date }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Hong_Kong")
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }
}
