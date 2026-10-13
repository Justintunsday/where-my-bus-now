import Foundation
import Observation

/// Separate additive storage. Does not migrate or rewrite the user's bookmarks.
@MainActor @Observable
final class BoardingStore {
    private(set) var targets: [BusTrackingTarget]
    @ObservationIgnored private let defaults: UserDefaults
    private let key = "busnow.boardingTargets.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        targets = defaults.data(forKey: key)
            .flatMap { try? JSONDecoder().decode([BusTrackingTarget].self, from: $0) } ?? []
    }

    func save(_ target: BusTrackingTarget) {
        targets.removeAll { $0.id == target.id }
        targets.insert(target, at: 0)
        persist()
    }

    func remove(_ target: BusTrackingTarget) {
        targets.removeAll { $0.id == target.id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(targets) { defaults.set(data, forKey: key) }
    }
}
