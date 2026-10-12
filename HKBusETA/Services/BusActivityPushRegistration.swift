import Foundation

/// Per-activity ActivityKit tokens, never ordinary APNs or push-to-start tokens.
@MainActor protocol BusActivityPushRegistering: AnyObject {
    var scopeID: String { get }
    func register(activityID: String, token: String, target: BusTrackingTarget, startedAt: Date) async throws
    func revoke(activityID: String) async throws
}

enum BusPushRegistrationError: Error { case invalidConfiguration, rejected(Int) }

/// Deployment seam: requires an authenticated installation session supplied by the host.
/// No server URL, bearer token or APNs credential is bundled into the shipping app.
@MainActor final class HTTPBusActivityPushRegistrar: BusActivityPushRegistering {
    enum Environment: String, Codable { case sandbox, production }
    let scopeID: String
    private let endpoint: URL
    private let environment: Environment
    private let authorization: @Sendable () async throws -> String

    init(endpoint: URL, environment: Environment, scopeID: String,
         authorization: @escaping @Sendable () async throws -> String) throws {
        guard endpoint.scheme == "https", endpoint.host != nil, endpoint.user == nil,
              endpoint.password == nil, endpoint.query == nil, endpoint.fragment == nil, !scopeID.isEmpty else {
            throw BusPushRegistrationError.invalidConfiguration
        }
        self.endpoint = endpoint
        self.environment = environment
        self.scopeID = scopeID
        self.authorization = authorization
    }

    func register(activityID: String, token: String, target: BusTrackingTarget, startedAt: Date) async throws {
        struct Registration: Encodable {
            let token: String
            let environment: Environment
            let target: BusTrackingTarget
            let createdAtEpoch: Double
            let expiresAtEpoch: Double
        }
        let payload = Registration(token: token, environment: environment, target: target,
                                   createdAtEpoch: startedAt.timeIntervalSince1970,
                                   expiresAtEpoch: startedAt.addingTimeInterval(3600).timeIntervalSince1970)
        try await send(activityID: activityID, method: "PUT", body: JSONEncoder().encode(payload))
    }

    func revoke(activityID: String) async throws { try await send(activityID: activityID, method: "DELETE", body: nil) }

    private func send(activityID: String, method: String, body: Data?) async throws {
        let bearer = try await authorization()
        guard !bearer.isEmpty, !bearer.contains("\n"), !bearer.contains("\r"),
              !activityID.isEmpty, !activityID.contains("/"), !activityID.contains("..") else {
            throw BusPushRegistrationError.invalidConfiguration
        }
        var request = URLRequest(url: endpoint.appendingPathComponent(activityID), timeoutInterval: 15)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if method == "DELETE", [404, 410].contains(response.statusCode) { return }
        guard (200..<300).contains(response.statusCode) else { throw BusPushRegistrationError.rejected(response.statusCode) }
    }
}

/// Rotation cancels obsolete registration work. Only activity IDs are persisted;
/// tokens stay in memory and come from ActivityKit again after relaunch.
@MainActor final class BusActivityPushCoordinator {
    private struct Pending {
        let token: String
        let target: BusTrackingTarget
        let startedAt: Date
    }
    private let registrar: any BusActivityPushRegistering
    private let defaults: UserDefaults
    private let key: String
    private var pending: [String: Pending] = [:]
    private var registrations: [String: Task<Void, Never>] = [:]
    private var revocations: [String: Task<Void, Never>] = [:]
    private var known: Set<String>
    private var revoked: Set<String>

    init(registrar: any BusActivityPushRegistering, defaults: UserDefaults = .standard) {
        self.registrar = registrar
        self.defaults = defaults
        key = "busnow.activityPush.\(registrar.scopeID)"
        known = Set(defaults.stringArray(forKey: key + ".known") ?? [])
        revoked = Set(defaults.stringArray(forKey: key + ".revoked") ?? [])
    }

    func receive(token: Data, activityID: String, target: BusTrackingTarget, startedAt: Date) {
        guard !token.isEmpty else { return }
        registrations.removeValue(forKey: activityID)?.cancel()
        known.insert(activityID)
        pending[activityID] = Pending(token: token.map { String(format: "%02x", $0) }.joined(), target: target, startedAt: startedAt)
        persist()
        submit(activityID)
    }

    func reconcile(activeIDs: Set<String>) {
        for id in known.subtracting(activeIDs) { end(activityID: id) }
        retryPending()
    }

    func end(activityID: String) {
        registrations.removeValue(forKey: activityID)?.cancel()
        pending.removeValue(forKey: activityID)
        known.remove(activityID)
        revoked.insert(activityID)
        persist()
        revoke(activityID)
    }

    func retryPending() {
        for id in pending.keys where registrations[id] == nil { submit(id) }
        for id in revoked where revocations[id] == nil { revoke(id) }
    }

    private func submit(_ id: String) {
        guard let snapshot = pending[id] else { return }
        registrations[id] = Task { [weak self] in
            guard let self else { return }
            for delay in [0, 1, 2, 4, 8, 16] {
                do {
                    if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
                    try Task.checkCancellation()
                    try await registrar.register(activityID: id, token: snapshot.token, target: snapshot.target, startedAt: snapshot.startedAt)
                    try Task.checkCancellation()
                    pending.removeValue(forKey: id)
                    registrations.removeValue(forKey: id)
                    return
                } catch is CancellationError { return }
                catch {
                    if Task.isCancelled { return }
                    if case BusPushRegistrationError.rejected(let status) = error, (400..<500).contains(status), status != 429 { break }
                }
            }
            registrations.removeValue(forKey: id) // Retry on the next foreground reconciliation.
        }
    }

    private func revoke(_ id: String) {
        revocations[id] = Task { [weak self] in
            guard let self else { return }
            defer { revocations.removeValue(forKey: id) }
            do {
                try await registrar.revoke(activityID: id)
                revoked.remove(id)
                persist()
            } catch { /* Keep the durable ID; next foreground retries. Server TTL is the final safety net. */ }
        }
    }

    private func persist() {
        defaults.set(Array(known), forKey: key + ".known")
        defaults.set(Array(revoked), forKey: key + ".revoked")
    }
}
