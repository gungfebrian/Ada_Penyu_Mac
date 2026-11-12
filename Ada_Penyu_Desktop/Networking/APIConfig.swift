import Foundation

struct APIConfig {
    static let defaultURL = URL(string: "https://api.donagondev.my.id")!
    static let overrideKey = "ada.debug.apiBaseURL"
    let baseURL: URL

    static func currentURL(defaults: UserDefaults = .standard) -> URL {
        #if DEBUG
        if let raw = defaults.string(forKey: overrideKey), let url = try? validatedURL(raw) { return url }
        #endif
        return defaultURL
    }

    static func validatedURL(_ raw: String) throws -> URL {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              var parts = URLComponents(string: value),
              let scheme = parts.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil,
              parts.port.map({ (1...65535).contains($0) }) ?? true else {
            throw APIError.validation("Enter an HTTP or HTTPS server URL with a host and optional port.")
        }
        parts.scheme = scheme
        parts.host = host.lowercased()
        if parts.path == "/" { parts.path = "" }
        guard let url = parts.url else { throw APIError.invalidResponse }
        return url
    }

    func isTrustedOrigin(_ url: URL) -> Bool { TrustedAPIRedirectDelegate.sameOrigin(baseURL, url) }
}

#if DEBUG
enum BackendEndpointOverride {
    static func save(_ url: URL, defaults: UserDefaults = .standard) { defaults.set(url.absoluteString, forKey: APIConfig.overrideKey) }
    static func reset(defaults: UserDefaults = .standard) { defaults.removeObject(forKey: APIConfig.overrideKey) }
}
#endif
