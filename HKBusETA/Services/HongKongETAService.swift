import Foundation

/// Hong Kong ETA clients for the data.gov.hk / operator APIs.
enum HongKongETAService {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        return URLSession(configuration: configuration)
    }()

    /// Fetches upcoming ETAs for one route variant at one stop sequence.
    static func fetchEtas(entry: RouteEntry, seq: Int, db: EtaDB, language: AppLanguage) async -> [Eta] {
        (try? await fetchEtasReportingErrors(entry: entry, seq: seq, db: db, language: language)) ?? []
    }

    static func fetchEtasReportingErrors(entry: RouteEntry, seq: Int, db: EtaDB, language: AppLanguage) async throws -> [Eta] {
        let availableStops = entry.stops

        let tasks: [Task<[Eta], Error>] = entry.co.compactMap { coRaw in
            guard let stopIDs = availableStops[coRaw],
                  seq >= 0, seq < stopIDs.count
            else { return nil }
            let stopId = stopIDs[seq]

            return Task {
                do {
                    switch coRaw {
                    case "kmb":
                        return try await fetchKMB(
                            stopId: stopId,
                            route: entry.route,
                            serviceType: entry.serviceTypeValue,
                            bound: entry.bound["kmb"] ?? entry.boundValue,
                            seq: seq,
                            companyCount: entry.co.count,
                            stops: stopIDs
                        )
                    case "ctb":
                        return try await fetchCTB(
                            stopId: stopId,
                            route: entry.route,
                            bound: entry.bound["ctb"] ?? entry.boundValue,
                            seq: seq
                        )
                    case "nlb":
                        guard let nlbId = entry.nlbId?.value, !nlbId.isEmpty else { return [] }
                        return try await fetchNLB(stopId: stopId, nlbId: nlbId, language: language)
                    case "gmb":
                        guard let gtfsId = entry.gtfsId?.value, !gtfsId.isEmpty else { return [] }
                        return try await fetchGMB(
                            stopId: stopId,
                            gtfsId: gtfsId,
                            bound: entry.bound["gmb"] ?? entry.boundValue,
                            seq: seq
                        )
                    case "lrtfeeder":
                        return try await fetchLRTFeeder(stopId: stopId, route: entry.route, language: language)
                    case "lightRail":
                        return try await fetchLightRail(stopId: stopId, route: entry.route, dest: entry.dest)
                    case "mtr":
                        return try await fetchMTR(
                            stopId: stopId,
                            route: entry.route,
                            bound: entry.bound["mtr"] ?? entry.boundValue,
                            stopList: db.stopList
                        )
                    default:
                        if HongKongProvider().operators.op(coRaw)?.isFerry == true {
                            return ferryEtas(entry: entry, db: db, language: language)
                        }
                        return []
                    }
                }
            }
        }

        var etas: [Eta] = []
        var successes = 0
        var failures: [Error] = []
        for task in tasks {
            do { etas.append(contentsOf: try await task.value); successes += 1 }
            catch { failures.append(error) }
        }
        try Task.checkCancellation()
        if successes == 0, let error = failures.first { throw error }

        if etas.contains(where: { !$0.eta.isEmpty }) {
            etas = etas.filter { !$0.eta.isEmpty }
        }
        etas.sort { lhs, rhs in
            if lhs.eta.isEmpty { return false }
            if rhs.eta.isEmpty { return true }
            return lhs.eta < rhs.eta
        }
        return etas
    }

    // MARK: - Helpers

    private static func getJSON<T: Decodable>(_ url: URL) async throws -> T {
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func postJSON<T: Decodable>(_ url: URL, body: [String: String]) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func scheduleRemark(_ language: AppLanguage) -> Terminal {
        language.isChinese
            ? Terminal(en: "", zh: "預定班次")
            : Terminal(en: "Scheduled", zh: "")
    }

    // MARK: - KMB

    private static func fetchKMB(
        stopId: String,
        route: String,
        serviceType: String,
        bound: String,
        seq: Int,
        companyCount: Int,
        stops: [String]
    ) async throws -> [Eta] {
        let url = URL(string: "https://data.etabus.gov.hk/v1/transport/kmb/eta/\(stopId)/\(route)/\(serviceType)")!
        let response: KMBEtaResponse = try await getJSON(url)

        var items = response.data.filter { $0.dir == bound }
        items.sort { abs($0.seq - seq) < abs($1.seq - seq) }
        if let first = items.first {
            items = items.filter { $0.seq == first.seq }
        }
        if companyCount == 1 {
            items = items.filter { item in
                guard let type = item.service_type else { return true }
                if String(type) != serviceType { return true }
                return item.seq == seq + 1
            }
        }
        if stops.count > 1, stops.first == stops.last, stopId == stops.first {
            items = items.filter { $0.seq == seq + 1 }
        }
        return items.map {
            Eta(
                eta: $0.eta ?? "",
                remark: Terminal(en: $0.rmk_en ?? "", zh: $0.rmk_tc ?? ""),
                dest: Terminal(en: $0.dest_en ?? "", zh: $0.dest_tc ?? ""),
                co: "kmb"
            )
        }
    }

    // MARK: - Citybus

    private static func fetchCTB(stopId: String, route: String, bound: String, seq: Int) async throws -> [Eta] {
        let url = URL(string: "https://rt.data.gov.hk/v2/transport/citybus/eta/CTB/\(stopId)/\(route)")!
        let response: CTBEtaResponse = try await getJSON(url)

        var items = response.data.filter { item in
            guard let dir = item.dir, !dir.isEmpty else { return false }
            return bound.contains(dir)
        }
        items.sort { abs(($0.seq ?? 0) - seq) < abs(($1.seq ?? 0) - seq) }
        if let first = items.first {
            items = items.filter { $0.seq == first.seq }
        }
        return items.map {
            Eta(
                eta: $0.eta ?? "",
                remark: Terminal(en: $0.rmk_en ?? "", zh: $0.rmk_tc ?? ""),
                dest: Terminal(en: $0.dest_en ?? "", zh: $0.dest_tc ?? ""),
                co: "ctb"
            )
        }
    }

    // MARK: - NLB

    private static func fetchNLB(stopId: String, nlbId: String, language: AppLanguage) async throws -> [Eta] {
        let languageCode = language.isChinese ? "zh" : "en"
        let url = URL(string: "https://rt.data.gov.hk/v2/transport/nlb/stop.php?action=estimatedArrivals&routeId=\(nlbId)&stopId=\(stopId)&language=\(languageCode)")!
        let response: NLBEtaResponse = try await getJSON(url)

        let outputs = (response.estimatedArrivals ?? [])
            .filter { !($0.estimatedArrivalTime ?? "").isEmpty }
            .map { item -> Eta in
                let isScheduled = item.departed != "1" || item.noGPS == "1"
                let time = (item.estimatedArrivalTime ?? "").replacingOccurrences(of: " ", with: "T")
                let variant = item.routeVariantName ?? ""
                return Eta(
                    eta: time + ".000+08:00",
                    remark: isScheduled ? scheduleRemark(language) : Terminal(en: "", zh: ""),
                    dest: language.isChinese ? Terminal(en: "", zh: variant) : Terminal(en: variant, zh: ""),
                    co: "nlb"
                )
            }

        if outputs.isEmpty, let message = response.message, !message.isEmpty {
            return [
                Eta(
                    eta: "",
                    remark: language.isChinese ? Terminal(en: "", zh: message) : Terminal(en: message, zh: ""),
                    dest: Terminal(en: "", zh: ""),
                    co: "nlb"
                )
            ]
        }
        return outputs
    }

    // MARK: - Green minibus

    private static func fetchGMB(stopId: String, gtfsId: String, bound: String, seq: Int) async throws -> [Eta] {
        let url = URL(string: "https://data.etagmb.gov.hk/eta/route-stop/\(gtfsId)/\(stopId)")!
        let response: GMBEtaResponse = try await getJSON(url)

        let wantedRouteSeq: Int?
        switch bound {
        case "O": wantedRouteSeq = 1
        case "I": wantedRouteSeq = 2
        default: wantedRouteSeq = nil
        }

        var etas: [Eta] = []
        for item in response.data ?? [] {
            if let wantedRouteSeq, item.route_seq != wantedRouteSeq { continue }
            guard item.stop_seq == seq + 1 else { continue }
            if item.enabled, let list = item.eta, !list.isEmpty {
                for eta in list {
                    etas.append(
                        Eta(
                            eta: eta.timestamp ?? "",
                            remark: Terminal(en: eta.remarks_en ?? "", zh: eta.remarks_tc ?? ""),
                            dest: Terminal(en: "", zh: ""),
                            co: "gmb"
                        )
                    )
                }
            } else {
                etas.append(
                    Eta(
                        eta: "",
                        remark: Terminal(en: item.description_en ?? "", zh: item.description_tc ?? ""),
                        dest: Terminal(en: "", zh: ""),
                        co: "gmb"
                    )
                )
            }
        }
        return etas
    }

    // MARK: - MTR Bus (light rail feeder)

    private static func fetchLRTFeeder(stopId: String, route: String, language: AppLanguage) async throws -> [Eta] {
        let url = URL(string: "https://rt.data.gov.hk/v1/transport/mtr/bus/getSchedule")!
        let response: MTRBusScheduleResponse = try await postJSON(url, body: ["language": language.isChinese ? "zh" : "en", "routeName": route])

        let stops = response.busStop ?? []
        if stops.isEmpty {
            if let title = response.routeStatusRemarkTitle, !title.isEmpty {
                return [
                    Eta(
                        eta: "",
                        remark: language.isChinese ? Terminal(en: "", zh: title) : Terminal(en: title, zh: ""),
                        dest: Terminal(en: "", zh: ""),
                        co: "lrtfeeder"
                    )
                ]
            }
            return []
        }

        var etas: [Eta] = []
        for stop in stops where stop.busStopId == stopId {
            for bus in stop.bus {
                let secondsText = (bus.arrivalTimeInSecond == "108000" ? bus.departureTimeInSecond : bus.arrivalTimeInSecond) ?? "0"
                let seconds = Int(secondsText) ?? 0
                let etaDate = Date().addingTimeInterval(TimeInterval(seconds))

                let remark: Terminal
                if let stopRemark = stop.busStopRemark, !stopRemark.isEmpty {
                    remark = Terminal(en: stopRemark, zh: stopRemark)
                } else if let busRemark = bus.busRemark, !busRemark.isEmpty {
                    remark = Terminal(en: busRemark, zh: busRemark)
                } else if bus.isScheduled == "1" {
                    remark = scheduleRemark(language)
                } else {
                    remark = Terminal(en: "", zh: "")
                }

                etas.append(
                    Eta(
                        eta: RegionClock.isoString(from: etaDate),
                        remark: remark,
                        dest: Terminal(en: "", zh: ""),
                        co: "lrtfeeder"
                    )
                )
            }
        }
        return etas
    }

    // MARK: - Light Rail

    private static func fetchLightRail(stopId: String, route: String, dest: Terminal) async throws -> [Eta] {
        let stationId = String(stopId.dropFirst(2))
        let url = URL(string: "https://rt.data.gov.hk/v1/transport/mtr/lrt/getSchedule?station_id=\(stationId)&with_special=1")!
        let response: LRTScheduleResponse = try await getJSON(url)
        let platforms = response.platform_list ?? []

        if !platforms.isEmpty, platforms.allSatisfy({ ($0.end_service_status ?? 0) != 0 }) {
            return [
                Eta(
                    eta: "",
                    remark: Terminal(en: "This stop's service for today has ended", zh: "此站今日服務已經終止"),
                    dest: Terminal(en: "", zh: ""),
                    co: "lightRail"
                )
            ]
        }

        var etas: [Eta] = []
        for platform in platforms {
            for item in platform.route_list ?? [] {
                let matchesRoute = item.route_no == route || item.additionalInfo1 == route
                let matchesDest = item.dest_ch == dest.zh || (item.dest_en ?? "").contains("Circular")
                guard matchesRoute, matchesDest, item.stop == 0 else { continue }

                let waitMinutes = parseLRTWaitTime(item.time_en ?? "")
                let etaDate = Date().addingTimeInterval(TimeInterval(waitMinutes * 60))

                let cars = String(repeating: "●", count: max(item.train_length ?? 0, 0))
                let platformZh = "\(platform.platform_id)號月台\(cars.isEmpty ? "" : " - " + cars)"
                let platformEn = "Platform \(platform.platform_id)\(cars.isEmpty ? "" : " - " + cars)"
                let remarkZh = (item.routeRemarkChi2?.isEmpty == false) ? "\(platformZh) - \(item.routeRemarkChi2!)" : platformZh
                let remarkEn = (item.routeRemarkEng2?.isEmpty == false) ? "\(platformEn) - \(item.routeRemarkEng2!)" : platformEn

                etas.append(
                    Eta(
                        eta: RegionClock.isoString(from: etaDate),
                        remark: Terminal(en: remarkEn, zh: remarkZh),
                        dest: Terminal(en: "", zh: ""),
                        co: "lightRail"
                    )
                )
            }
        }
        return etas
    }

    private static func parseLRTWaitTime(_ text: String) -> Int {
        switch text.lowercased() {
        case "arriving", "departing", "-", "":
            return 0
        default:
            let digits = text.prefix { $0.isNumber }
            return Int(digits) ?? 0
        }
    }

    // MARK: - MTR

    private static func fetchMTR(stopId: String, route: String, bound: String, stopList: [String: StopEntry]) async throws -> [Eta] {
        let url = URL(string: "https://rt.data.gov.hk/v1/transport/mtr/getSchedule.php?line=\(route)&sta=\(stopId)")!
        let response: MTRScheduleResponse = try await getJSON(url)

        guard response.status == 1 else {
            if let message = response.message, !message.isEmpty {
                let cleaned = message.replacingOccurrences(of: "Please click here for more information.", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                return [
                    Eta(eta: "", remark: Terminal(en: cleaned, zh: cleaned), dest: Terminal(en: "", zh: ""), co: "mtr")
                ]
            }
            return []
        }

        guard let line = response.data?["\(route)-\(stopId)"] else { return [] }
        let direction = bound.hasSuffix("UT") ? "UP" : "DOWN"
        let trains = (direction == "UP" ? line.UP : line.DOWN) ?? []

        return trains.compactMap { train in
            guard let time = train.time, !time.isEmpty else { return nil }
            let destCode = train.dest ?? ""
            let dest = stopList[destCode]?.name ?? Terminal(en: "", zh: "")
            let platform = train.plat ?? ""
            return Eta(
                eta: time.replacingOccurrences(of: " ", with: "T") + "+08:00",
                remark: platform.isEmpty ? Terminal(en: "", zh: "") : Terminal(en: "Platform \(platform)", zh: "\(platform)號月台"),
                dest: dest,
                co: "mtr"
            )
        }
    }
}
