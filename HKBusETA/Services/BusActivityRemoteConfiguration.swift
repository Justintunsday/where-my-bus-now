import Foundation
import Security

/// Only a public HTTPS endpoint and APNs environment are build configuration.
/// The scoped installation credential is generated on-device and kept in Keychain.
@MainActor enum BusActivityRemoteConfiguration {
    static func registrar(bundle: Bundle = .main) -> (any BusActivityPushRegistering)? {
        guard let raw = bundle.object(forInfoDictionaryKey: "LIVE_ACTIVITY_SERVER_URL") as? String,
              !raw.isEmpty, !raw.contains("$("), let base = URL(string: raw),
              base.scheme == "https", base.host != nil, base.user == nil, base.password == nil,
              base.query == nil, base.fragment == nil,
              let configured = bundle.object(forInfoDictionaryKey: "APNS_ENVIRONMENT") as? String,
              ["development", "production"].contains(configured),
              let credential = try? InstallationCredential.loadOrCreate(scope: base.absoluteString) else { return nil }
        let session = BusInstallationSession(base: base, credential: credential)
        return try? HTTPBusActivityPushRegistrar(endpoint: base.appendingPathComponent("v1/activities"),
            environment: configured == "development" ? .sandbox : .production,
            scopeID: credential.id, authorization: { try await session.authorization() })
    }
}

private struct InstallationCredential: Codable, Sendable {
    let id: String
    let secret: String
    var bearer: String { "\(id).\(secret)" }

    static func loadOrCreate(scope: String) throws -> Self {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "app.hkbus.swiftui.live-activities", kSecAttrAccount as String: scope]
        var result: CFTypeRef?
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data { return try JSONDecoder().decode(Self.self, from: data) }
        guard status == errSecItemNotFound else { throw BusPushRegistrationError.invalidConfiguration }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw BusPushRegistrationError.invalidConfiguration
        }
        let value = Self(id: UUID().uuidString.lowercased(), secret: bytes.map { String(format: "%02x", $0) }.joined())
        var item = query
        item[kSecValueData as String] = try JSONEncoder().encode(value)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw BusPushRegistrationError.invalidConfiguration }
        return value
    }
}

private actor BusInstallationSession {
    let base: URL
    let credential: InstallationCredential
    private var registeredAt: Date?
    init(base: URL, credential: InstallationCredential) { self.base = base; self.credential = credential }

    func authorization() async throws -> String {
        if let registeredAt, Date().timeIntervalSince(registeredAt) < 300 { return credential.bearer }
        var request = URLRequest(url: base.appendingPathComponent("v1/installations").appendingPathComponent(credential.id), timeoutInterval: 15)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(credential.bearer)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(response.statusCode) else { throw BusPushRegistrationError.rejected(response.statusCode) }
        registeredAt = Date()
        return credential.bearer
    }
}
