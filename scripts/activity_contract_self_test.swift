import Foundation

@main enum ActivityContractSelfTest {
    static func main() throws {
        let target = BusTrackingTarget.preview
        precondition(target.timeZone.secondsFromGMT(for: Date(timeIntervalSince1970: 0)) == 28_800,
                     "Legacy boarding records retain their transit time zone")
        var regional = target
        regional.timeZoneIdentifier = "Asia/Shanghai"
        let regionalDecoded = try JSONDecoder().decode(BusTrackingTarget.self, from: JSONEncoder().encode(regional))
        precondition(regionalDecoded.timeZone.identifier == "Asia/Shanghai")
        let url = target.deepLink!
        precondition(BusTrackingTarget.decode(url: url) == target, "Unicode/deep link round trip")
        precondition(BusTrackingTarget.decode(url: URL(string: "https://example.com/eta")!) == nil)
        precondition(BusTrackingTarget.decode(url: URL(string: "busnow://eta?target=invalid")!) == nil)
        precondition(BusTrackingTarget.decode(url: URL(string: "busnow://wrong?target=YWJj")!) == nil)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for (seconds, expected) in [(-120.0, 0), (0, 0), (0.01, 1), (59, 1), (60, 1), (60.01, 2), (360, 6), (86460, 1441)] {
            precondition(BusArrivalState.remainingMinutes(arrival: now.addingTimeInterval(seconds), now: now) == expected)
        }
        precondition(BusArrivalState.remainingMinutes(arrival: Date(timeIntervalSince1970: .infinity), now: now) == nil)
        let iso = ISO8601DateFormatter()
        for (start, end, expected) in [
            ("2026-10-13T07:54:00+08:00", "2026-10-13T08:00:00+08:00", 6),
            ("2026-10-13T07:57:00+08:00", "2026-10-13T08:00:00+08:00", 3),
            ("2026-10-13T07:59:00+08:00", "2026-10-13T08:00:00+08:00", 1),
            ("2026-10-13T23:57:00+08:00", "2026-10-14T00:03:00+08:00", 6),
            ("2026-10-13T23:57:00+08:00", "2026-10-13T16:03:00Z", 6),
            ("2026-11-01T01:57:00-04:00", "2026-11-01T01:03:00-05:00", 6)
        ] {
            precondition(BusArrivalState.remainingMinutes(arrival: iso.date(from: end)!, now: iso.date(from: start)!) == expected)
        }
        let prediction = BusArrivalState.prediction(arrival: now.addingTimeInterval(420), updatedAt: now, scheduled: false)
        precondition(prediction.isFresh(at: now.addingTimeInterval(89)))
        precondition(!prediction.isFresh(at: now.addingTimeInterval(90)), "Never present old data as live")
        precondition(prediction.remainingMinutes(at: now.addingTimeInterval(90)) == nil)
        if #available(macOS 15.0, iOS 18.0, *) {
            let format = BusArrivalMinuteFormatStyle(state: prediction, language: "en")
            precondition(String(format.format(now).characters) == "7 min")
            precondition(format.discreteInput(after: now) == now.addingTimeInterval(60))
            precondition(String(format.format(now.addingTimeInterval(60)).characters) == "6 min")
            precondition(format.discreteInput(after: now.addingTimeInterval(60)) == now.addingTimeInterval(90))
            precondition(String(format.format(now.addingTimeInterval(90)).characters) == "—")
            precondition(format.discreteInput(after: now.addingTimeInterval(90)) == nil)
            let before = format.discreteInput(before: now.addingTimeInterval(60))!
            precondition(before < now.addingTimeInterval(60) && String(format.format(before).characters) == "7 min")
            let expiryBefore = format.discreteInput(before: now.addingTimeInterval(120))!
            precondition(expiryBefore < prediction.staleDate && String(format.format(expiryBefore).characters) == "6 min")
            let encodedFormat = try JSONEncoder().encode(format)
            let decodedFormat = try JSONDecoder().decode(BusArrivalMinuteFormatStyle.self, from: encodedFormat)
            precondition(decodedFormat == format, "System text formatter survives widget serialization")
        }
        let short = BusArrivalState.prediction(arrival: now.addingTimeInterval(20), updatedAt: now, scheduled: false)
        precondition(short.staleDate == now.addingTimeInterval(20), "Stale by predicted arrival")
        let adjusted = BusArrivalState.prediction(arrival: now.addingTimeInterval(600), updatedAt: now.addingTimeInterval(30), scheduled: false)
        precondition(adjusted.arrival! > prediction.arrival!, "Provider adjustments are accepted")
        let cancelled = BusArrivalState.unavailable(at: now, message: "Cancelled", cancelled: true)
        precondition(cancelled.status == .cancelled && cancelled.arrival == nil && !cancelled.isFresh(at: now))
        precondition(cancelled.remainingMinutes(at: now) == nil)
        let unavailable = BusArrivalState.unavailable(at: now)
        precondition(unavailable.arrival == nil && unavailable.status == .unavailable)
        let stateData = try JSONEncoder().encode(prediction)
        let decodedState = try JSONDecoder().decode(BusArrivalState.self, from: stateData)
        precondition(decodedState == prediction)
        let json = try JSONSerialization.jsonObject(with: stateData) as! [String: Any]
        precondition((json["arrivalEpoch"] as? Double) == 1_800_000_420, "APNs uses Unix seconds")
        precondition(stateData.count < 1024, "ActivityKit payload remains small")
        let legacy = Data(#"{"arrivalEpoch":1800000420,"updatedEpoch":1800000000,"validUntilEpoch":1800000090,"status":"live","message":""}"#.utf8)
        let legacyState = try JSONDecoder().decode(BusArrivalState.self, from: legacy)
        precondition(legacyState.secondArrival == nil && legacyState.change == nil, "Decode existing activities")
        let departures = BusArrivalState.snapshot(arrivals: [1_800_000_600, 1_800_000_180, 1_800_000_180, .nan], updatedAt: now)
        precondition(departures.arrivalEpoch == 1_800_000_180 && departures.secondArrivalEpoch == 1_800_000_600)
        let revised = BusArrivalState.snapshot(arrivals: [1_800_000_240, 1_800_000_600], updatedAt: now.addingTimeInterval(30), previous: departures)
        precondition(revised.change == .adjusted)
        let next = BusArrivalState.snapshot(arrivals: [1_800_000_600], updatedAt: now.addingTimeInterval(181), previous: departures)
        precondition(next.change == .nextBus && next.arrivalEpoch == 1_800_000_600)
        precondition(!departures.isFresh(at: now.addingTimeInterval(181)), "Clock passing cannot silently select a second bus")
        let offline = BusArrivalState.failed(previous: departures, at: now.addingTimeInterval(45), network: true, message: "offline")
        precondition(offline.arrivalEpoch == departures.arrivalEpoch && offline.secondArrivalEpoch == departures.secondArrivalEpoch)
        precondition(offline.updatedAt == now && !offline.isFresh(at: now.addingTimeInterval(45)), "Failed request preserves the actual last response timestamp")
        precondition(BusArrivalState.snapshot(arrivals: [], updatedAt: now).status == .noService)
        precondition(BusArrivalState.reportedStatus("Departed from terminal") == nil)
        precondition(BusArrivalState.reportedStatus("已開出") == nil, "Departing the origin is not leaving the boarding stop")
        precondition(BusArrivalState.reportedStatus("Service cancelled") == .cancelled)
        precondition(BusArrivalState.reportedStatus("班次已離站") == .departed)
        precondition(BusArrivalState.failed(previous: departures, at: now, network: false,
            message: String(repeating: "error", count: 1000)).message.count <= 160)
        for status in [BusArrivalStatus.cancelled, .arrived, .departed, .noService, .ended] {
            let terminal = BusArrivalState.snapshot(arrivals: [], updatedAt: now, explicitStatus: status)
            precondition(terminal.isTerminal && !terminal.isFresh(at: now))
        }
        for scenario in BusArrivalPreview.allCases {
            let sample = BusArrivalPreview.state(scenario, at: now)
            let bytes = try JSONEncoder().encode(sample)
            let roundTrip = try JSONDecoder().decode(BusArrivalState.self, from: bytes)
            precondition(roundTrip == sample)
        }
        let original = try JSONEncoder().encode(target)
        for (key, value) in [("regionID", "cl-040"), ("providerID", "another-provider"), ("serviceType", "2"),
                             ("stopID", "opposite-stop"), ("lineID", "another-line"), ("source", "amapBase"), ("mode", "metro")] {
            var fields = try JSONSerialization.jsonObject(with: original) as! [String: Any]
            fields[key] = value
            let different = try JSONDecoder().decode(BusTrackingTarget.self, from: JSONSerialization.data(withJSONObject: fields))
            precondition(different.id != target.id, "Identity includes \(key)")
        }
        var fields = try JSONSerialization.jsonObject(with: original) as! [String: Any]
        fields["directions"] = ["kmb": "I"]
        let reverse = try JSONDecoder().decode(BusTrackingTarget.self, from: JSONSerialization.data(withJSONObject: fields))
        precondition(reverse.id != target.id, "Direction isolation")
        fields["stopSequence"] = -1
        let invalid = try JSONDecoder().decode(BusTrackingTarget.self, from: JSONSerialization.data(withJSONObject: fields))
        precondition(BusTrackingTarget.decode(url: invalid.deepLink!) == nil, "Reject invalid stop sequence")
        print("PASS: whole-minute rounding, hour/day/time-zone/DST boundaries, discrete system text and expiration, state serialization, Live Activity identity, revisions, terminal states, offline retention, deep links and APNs contract")
    }
}
