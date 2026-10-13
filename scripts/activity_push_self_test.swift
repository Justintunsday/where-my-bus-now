import Foundation

@MainActor private final class FakeRegistrar: BusActivityPushRegistering {
    let scopeID = "test-installation"
    var tokens: [String] = []
    var removed: [String] = []
    var failsRevocation = false
    func register(activityID: String, token: String, tokenVersion: Int, target: BusTrackingTarget, startedAt: Date) async throws {
        tokens.append(token)
    }
    func revoke(activityID: String) async throws {
        if failsRevocation { throw URLError(.notConnectedToInternet) }
        removed.append(activityID)
    }
}

@main enum ActivityPushSelfTest {
    @MainActor static func main() async throws {
        let name = "busnow.push-test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let registrar = FakeRegistrar()
        let coordinator = BusActivityPushCoordinator(registrar: registrar, defaults: defaults)
        coordinator.receive(token: Data([0x01, 0xaf]), activityID: "trip", target: .preview, startedAt: .now)
        coordinator.receive(token: Data([0x02, 0xbe]), activityID: "trip", target: .preview, startedAt: .now)
        for _ in 0..<20 { await Task.yield() }
        precondition(registrar.tokens == ["02be"], "Rotation cancels registration of the obsolete token")
        precondition(!defaults.dictionaryRepresentation().values.contains { String(describing: $0).contains("02be") }, "Tokens aren't persisted in preferences")
        registrar.failsRevocation = true
        coordinator.end(activityID: "trip")
        for _ in 0..<20 { await Task.yield() }
        precondition(defaults.stringArray(forKey: "busnow.activityPush.test-installation.revoked") == ["trip"])
        registrar.failsRevocation = false
        let relaunched = BusActivityPushCoordinator(registrar: registrar, defaults: defaults)
        relaunched.reconcile(activeIDs: [])
        for _ in 0..<20 { await Task.yield() }
        precondition(registrar.removed == ["trip"], "Revocation survives relaunch after a network failure")
        precondition(defaults.stringArray(forKey: "busnow.activityPush.test-installation.revoked")?.isEmpty == true)
        do {
            _ = try HTTPBusActivityPushRegistrar(endpoint: URL(string: "http://example.com/trips")!, environment: .sandbox,
                scopeID: "installation", authorization: { "session" })
            preconditionFailure("Unencrypted registration must be rejected")
        } catch BusPushRegistrationError.invalidConfiguration { }
        print("PASS: per-activity token rotation, no preference token storage, durable revocation and HTTPS configuration")
    }
}
