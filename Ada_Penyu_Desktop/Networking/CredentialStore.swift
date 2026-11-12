import Foundation
import Security

struct StoredCredentials: Codable {
    let refreshToken: String
    let refreshExpiresAt: Date
    let userID: UUID
    let organizationID: UUID
    var rotationInFlight: Bool
}

@MainActor
protocol CredentialStoring: AnyObject {
    func load() throws -> StoredCredentials?
    func save(_ credentials: StoredCredentials) throws
    func remove() throws
}

/// One active account per backend. No password or access token is persisted.
@MainActor
final class KeychainCredentialStore: CredentialStoring {
    private let service = "org.adapenyu.desktop.refresh-session"
    private let backend: String
    private let defaults: UserDefaults
    private var signOutKey: String { "ADARestorationDisabled.\(backend)" }

    init(baseURL: URL, defaults: UserDefaults = .standard) {
        var canonical = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        canonical?.scheme = baseURL.scheme?.lowercased()
        canonical?.host = baseURL.host?.lowercased()
        if (canonical?.scheme == "https" && canonical?.port == 443) || (canonical?.scheme == "http" && canonical?.port == 80) {
            canonical?.port = nil
        }
        let path = (canonical?.percentEncodedPath ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        canonical?.percentEncodedPath = path.isEmpty ? "" : "/" + path
        backend = canonical?.url?.absoluteString ?? baseURL.absoluteString
        self.defaults = defaults
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: backend,
         kSecAttrSynchronizable as String: false, kSecUseDataProtectionKeychain as String: true]
    }

    func load() throws -> StoredCredentials? {
        guard !defaults.bool(forKey: signOutKey) else { return nil }
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw storageError(status) }
        do { return try JSONDecoder().decode(StoredCredentials.self, from: data) }
        catch { try remove(); return nil }
    }

    func save(_ credentials: StoredCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, value in value } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw storageError(status) }
        defaults.removeObject(forKey: signOutKey)
    }

    func remove() throws {
        // A non-secret tombstone prevents restoration even if Keychain is locked
        // when the user signs out. A later successful save removes it.
        defaults.set(true, forKey: signOutKey)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw storageError(status) }
    }

    private func storageError(_ status: OSStatus) -> AuthError {
        if status == errSecInteractionNotAllowed {
            return .custom("Saved sign-in could not be accessed securely. Unlock your device and try again.")
        }
        return .custom("Secure sign-in storage is unavailable (Keychain \(status)). Please retry or sign in without Remember me.")
    }
}
