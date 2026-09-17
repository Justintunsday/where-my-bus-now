import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private struct FixtureTransport: WidgetTransitAPITransport, @unchecked Sendable {
    func data(for request: URLRequest) async throws -> WidgetTransitAPITransportResponse {
        let host = request.url?.host ?? ""
        if host == "primary.example" {
            return WidgetTransitAPITransportResponse(data: Data(), statusCode: 503)
        }

        let path = request.url?.path ?? ""
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let values = Dictionary(uniqueKeysWithValues: query.map { ($0.name, $0.value ?? "") })
        if host == "data.etabus.gov.hk" {
            if path.hasSuffix("/route") {
                return response(#"{"data":[{"route":"1A","bound":"O","service_type":"1","orig_en":"Star Ferry","dest_en":"Sau Mau Ping"},{"route":"1A","bound":"I","service_type":"1","orig_en":"Sau Mau Ping","dest_en":"Star Ferry"}]}"#)
            }
            if path.hasSuffix("/stop") {
                return response(#"{"data":[{"stop":"KMB-1","name_en":"KMB Stop","lat":22.3001,"long":114.1701},{"stop":"KMB-2","name_en":"KMB Stop 2","lat":22.3002,"long":114.1702}]}"#)
            }
            if path.hasSuffix("/route-stop/1A/outbound/1") {
                return response(#"{"data":[{"seq":1,"stop":"KMB-1"},{"seq":2,"stop":"KMB-2"}]}"#)
            }
            if path.hasSuffix("/route-stop/1A/inbound/1") {
                return response(#"{"data":[{"seq":1,"stop":"KMB-2"},{"seq":2,"stop":"KMB-1"}]}"#)
            }
            if path.contains("/eta/") {
                return response(#"{"data":[{"dir":"O","seq":1,"eta":"2099-09-17T19:25:00+08:00"}]}"#)
            }
        }
        if host == "rt.data.gov.hk" && path.contains("/citybus-nwfb/") {
            if path.hasSuffix("/route/CTB/1A") {
                return response(#"{"data":{"co":"CTB","route":"1A","orig_en":"Central","dest_en":"Wan Chai"}}"#)
            }
            if path.hasSuffix("/route-stop/CTB/1A/outbound") {
                return response(#"{"data":[{"dir":"O","seq":1,"stop":"CTB-1"}]}"#)
            }
            if path.hasSuffix("/stop") {
                return response(#"{"data":[{"stop":"CTB-1","name_en":"CTB Stop","lat":22.3003,"long":114.1703}]}"#)
            }
            if path.contains("/eta/CTB/error/1A") {
                return WidgetTransitAPITransportResponse(data: Data(), statusCode: 503)
            }
            if path.contains("/eta/CTB/") {
                return response(#"{"data":[]}"#)
            }
        }
        if host == "data.etagmb.gov.hk" {
            if path == "/route" {
                return response(#"{"data":{"routes":{"HKI":["1"],"KLN":["1"]}}}"#)
            }
            if path == "/route/HKI/1" {
                return response(#"{"data":[{"route_id":"2001","route_code":"1","directions":[{"route_seq":1,"orig_en":"Central","dest_en":"The Peak"},{"route_seq":2,"orig_en":"The Peak","dest_en":"Central"}]}]}"#)
            }
            if path == "/route-stop/2001/1" {
                return response(#"{"data":{"route_stops":[{"stop_seq":1,"stop_id":"GMB-1","name_en":"GMB Stop"}]}}"#)
            }
            if path == "/stop/GMB-1" {
                return response(#"{"data":{"coordinates":{"wgs84":{"latitude":22.3004,"longitude":114.1704}}}}"#)
            }
            if path == "/eta/route-stop/2001/1/1" {
                return response(#"{"data":{"enabled":true,"eta":[{"timestamp":"2099-09-17T19:25:00.000+08:00","diff":10}]}}"#)
            }
        }
        if host == "rt.data.gov.hk" && path.contains("/nlb/") {
            if path.hasSuffix("/route.php") {
                return response(#"{"routes":[{"routeId":"20","routeNo":"1","routeName_e":"Mui Wo > Tai O"},{"routeId":"2","routeNo":"1","routeName_e":"Tai O > Mui Wo"}]}"#)
            }
            if path.hasSuffix("/stop.php") && values["action"] == "list" {
                let routeID = values["routeId"] ?? ""
                let body = routeID == "2"
                    ? #"{"stops":[{"stopId":"NLB-2","stopName_e":"Tai O","latitude":22.3006,"longitude":114.1706}]}"#
                    : #"{"stops":[{"stopId":"NLB-20","stopName_e":"Mui Wo","latitude":22.3005,"longitude":114.1705}]}"#
                return response(body)
            }
            if path.hasSuffix("/stop.php") && values["action"] == "estimatedArrivals" {
                return response(#"{"estimatedArrivals":[{"estimatedArrivalTime":"2099-09-17 19:25:00"}]}"#)
            }
        }
        if path.hasSuffix("/search") {
            let body = values["city_id"] == "019" ? foshanSearchJSON : shanghaiSearchJSON
            return WidgetTransitAPITransportResponse(data: Data(body.utf8), statusCode: 200)
        }
        if path.hasSuffix("/lines/detail") {
            let lineID = values["line_id"] ?? "line-0"
            return WidgetTransitAPITransportResponse(
                data: Data(lineDetailJSON(lineID: lineID).utf8),
                statusCode: 200
            )
        }
        if path.hasSuffix("/lines/realtime") {
            precondition(values["city_id"] == "034", "realtime must stay in the entity city")
            precondition(values["target_order"] == "2")
            precondition(values["station_id"] == "034-2")
            return WidgetTransitAPITransportResponse(
                data: Data(#"{"buses":[{"eta":{"travelTime":120,"arrivalTime":-1}}]}"#.utf8),
                statusCode: 200
            )
        }
        preconditionFailure("Unexpected widget API path: \(path)")
    }

    private func response(_ body: String) -> WidgetTransitAPITransportResponse {
        WidgetTransitAPITransportResponse(data: Data(body.utf8), statusCode: 200)
    }

    private var foshanSearchJSON: String {
        #"{"lines":[{"name":"352","lineNo":"352","directions":[{"direction":0,"lineId":"fs-352-0","startSn":"禅城","endSn":"南海"},{"direction":1,"lineId":"fs-352-1","startSn":"南海","endSn":"禅城"}]}],"stations":[]}"#
    }

    private var shanghaiSearchJSON: String {
        #"{"lines":[{"name":"71","lineNo":"71","directions":[{"direction":0,"lineId":"line-0","startSn":"人民广场","endSn":"外滩"},{"direction":1,"lineId":"line-1","startSn":"外滩","endSn":"人民广场"}]}],"stations":[]}"#
    }

    private func lineDetailJSON(lineID: String) -> String {
        let start = lineID == "line-1" ? "外滩" : lineID.hasPrefix("fs-") && lineID.hasSuffix("-1") ? "南海" : "人民广场"
        let end = lineID == "line-1" ? "人民广场" : lineID.hasPrefix("fs-") && lineID.hasSuffix("-1") ? "禅城" : "外滩"
        let stop = lineID.hasPrefix("fs-") ? "季华园" : "人民广场"
        let prefix = lineID.hasPrefix("fs-") ? "019" : "034"
        let name = lineID.hasPrefix("fs-") ? "352" : "71"
        return "{\"line\":{\"lineId\":\"\(lineID)\",\"name\":\"\(name)\",\"startSn\":\"\(start)\",\"endSn\":\"\(end)\"},\"stations\":[{\"order\":1,\"sId\":\"\(prefix)-1\",\"sn\":\"起点\",\"wgsLat\":31.2200,\"wgsLng\":121.4600,\"physicalStId\":\"\(prefix)-1\"},{\"order\":2,\"sId\":\"\(prefix)-2\",\"sn\":\"\(stop)\",\"wgsLat\":31.2300,\"wgsLng\":121.4700}],\"empty\":false}"
    }
}

@main
struct WidgetTransitTargetSelfTest {
    static func main() async {
        precondition(WidgetTransitQueryParser.parse("佛山 352")?.city.id == "019")
        precondition(WidgetTransitQueryParser.parse("上海 71 人民广场")?.city.id == "034")
        precondition(WidgetTransitQueryParser.parse("71") == nil, "a city is required")

        let record = WidgetTransitTargetRecord(
            cityID: "034",
            cityName: "上海",
            lineID: "line-0",
            lineName: "71",
            direction: 0,
            origin: "人民广场",
            destination: "外滩",
            stopID: "034-2",
            stopName: "人民广场",
            stationID: "034-2",
            stopSequence: 2,
            latitude: 31.23,
            longitude: 121.47
        )
        precondition(record.id.hasPrefix("wmbn-target-v1_"))
        let restored = WidgetTransitTargetRecord(id: record.id)
        precondition(restored == record, "entity ID must rebuild the full target")
        precondition(restored?.cityID == "034" && restored?.stopName == "人民广场")

        let client = WidgetTransitAPIClient(
            baseURLs: [
                URL(string: "https://primary.example/v1")!,
                URL(string: "https://fallback.example/v1")!,
            ],
            transport: FixtureTransport()
        )
        let resolver = WidgetTransitTargetResolver(client: client)
        let foshanTargets = await resolver.targets(for: "佛山 352")
        precondition(!foshanTargets.isEmpty)
        precondition(foshanTargets.allSatisfy { $0.cityID == "019" && $0.cityName == "佛山" })
        precondition(foshanTargets.contains { $0.direction == 1 && $0.destination == "禅城" })

        let foshanOutbound = await resolver.target(
            for: WidgetTransitCityCatalog.all.first { $0.id == "019" }!,
            route: "352",
            direction: WidgetTransitManualDirection.outbound,
            stop: nil
        )
        precondition(
            foshanOutbound?.cityID == "019"
                && foshanOutbound?.direction == WidgetTransitManualDirection.outbound
                && foshanOutbound?.stopName == "起点",
            "an empty stop selects the first stop in the selected direction"
        )

        let foshanInboundStop = await resolver.target(
            for: WidgetTransitCityCatalog.all.first { $0.id == "019" }!,
            route: "352",
            direction: WidgetTransitManualDirection.inbound,
            stop: "季华园"
        )
        precondition(
            foshanInboundStop?.cityID == "019"
                && foshanInboundStop?.direction == WidgetTransitManualDirection.inbound
                && foshanInboundStop?.stopName == "季华园",
            "manual stop selection must stay within the selected direction"
        )

        let shanghaiTargets = await resolver.targets(for: "上海 71 人民广场")
        precondition(!shanghaiTargets.isEmpty)
        precondition(shanghaiTargets.allSatisfy {
            $0.cityID == "034" && $0.cityName == "上海" && $0.lineName == "71" && $0.stopName == "人民广场"
        })
        precondition(shanghaiTargets.allSatisfy { $0.stopID == $0.stationID }, "sId must cover missing physicalStId")
        let shanghaiInbound = await resolver.target(
            for: WidgetTransitCityCatalog.all.first { $0.id == "034" }!,
            route: "71",
            direction: WidgetTransitManualDirection.inbound,
            stop: nil
        )
        precondition(
            shanghaiInbound?.cityID == "034"
                && shanghaiInbound?.direction == WidgetTransitManualDirection.inbound
                && shanghaiInbound?.stopName == "起点",
            "manual resolution must isolate the selected city ID"
        )
        let etaResult = await resolver.etaDates(for: record)
        precondition(etaResult.unavailable == false && etaResult.dates.count == 1)

        let url = try! WidgetTransitAPIClient.makeURL(
            baseURL: WidgetTransitAPIClient.primaryBaseURL,
            path: "lines/realtime",
            parameters: [("city_id", "034"), ("line_id", "line-0")]
        )
        precondition(url.absoluteString.contains("city_id=034"))

        precondition(WidgetTransitOperatorCatalog.hongKongIDs == ["kmb", "ctb", "gmb", "nlb"])
        let hongKong = WidgetTransitCityCatalog.all.first { $0.id == "hk" }!
        let hongKongClient = WidgetHongKongAPIClient(transport: FixtureTransport())
        let hongKongResolver = WidgetTransitTargetResolver(
            client: client,
            hongKongClient: hongKongClient
        )

        let kmb = await hongKongResolver.target(
            for: hongKong,
            operatorID: "kmb",
            route: "1A",
            direction: WidgetTransitManualDirection.outbound,
            stop: nil
        )
        precondition(
            kmb?.cityID == "hk" && kmb?.operatorID == "kmb" && kmb?.stopName == "KMB Stop",
            "KMB must resolve through its own route and stop namespace"
        )
        let kmbETA = await hongKongResolver.etaDates(for: kmb!)
        precondition(kmbETA.unavailable == false && kmbETA.dates.count == 1)

        let citybus = await hongKongResolver.target(
            for: hongKong,
            operatorID: "ctb",
            route: "1A",
            direction: WidgetTransitManualDirection.outbound,
            stop: nil
        )
        precondition(
            citybus?.operatorID == "ctb" && citybus?.stopName == "CTB Stop",
            "the same route number must not mix KMB and Citybus"
        )
        let citybusNoData = await hongKongResolver.etaDates(for: citybus!)
        precondition(citybusNoData.unavailable == false && citybusNoData.dates.isEmpty)

        let errorTarget = WidgetTransitTargetRecord(
            cityID: "hk", cityName: "香港", lineID: "1A", lineName: "1A",
            direction: WidgetTransitManualDirection.outbound,
            origin: "Central", destination: "Wan Chai", stopID: "error", stopName: "Error",
            stationID: "error", stopSequence: 1, latitude: 22.3, longitude: 114.17,
            operatorID: "ctb", providerDirection: "O"
        )
        let citybusError = await hongKongResolver.etaDates(for: errorTarget)
        precondition(citybusError.unavailable == true && citybusError.dates.isEmpty)

        let ambiguousGMB = await hongKongResolver.target(
            for: hongKong,
            operatorID: "gmb",
            route: "1",
            direction: WidgetTransitManualDirection.outbound,
            stop: nil
        )
        precondition(ambiguousGMB == nil, "an unqualified duplicate GMB route must be rejected")
        let gmb = await hongKongResolver.target(
            for: hongKong,
            operatorID: "gmb",
            route: "HKI 1",
            direction: WidgetTransitManualDirection.outbound,
            stop: nil
        )
        precondition(gmb?.operatorID == "gmb" && gmb?.lineID == "2001" && gmb?.providerDirection == "1")
        let gmbETA = await hongKongResolver.etaDates(for: gmb!)
        precondition(gmbETA.unavailable == false && gmbETA.dates.count == 1)

        let nlb = await hongKongResolver.target(
            for: hongKong,
            operatorID: "nlb",
            route: "1",
            direction: WidgetTransitManualDirection.inbound,
            stop: nil
        )
        precondition(
            nlb?.operatorID == "nlb" && nlb?.lineID == "2" && nlb?.origin == "Tai O",
            "NLB direction must come from routeName_e endpoints, not routeId order"
        )

        print("SIDESTORE WIDGET TARGET SELF-TEST OK")
    }
}
