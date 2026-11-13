import Foundation

enum RequestAuthentication { case required, none }

struct APIRequest {
    var method: String
    var path: String
    var query: [String: String?] = [:]
    var body: Data? = nil
    var contentType: String? = nil
    var acceptedStatuses: Set<Int> = [200, 201]
    var timeoutInterval: TimeInterval? = nil
    var cachePolicy: URLRequest.CachePolicy? = nil
    var authentication: RequestAuthentication = .required
    var accept: String = "application/json"
    var queryItems: [URLQueryItem] = []
}

struct APIResponse<Value> {
    let value: Value
    let http: HTTPURLResponse
    var statusCode: Int { http.statusCode }
    func header(_ name: String) -> String? { http.value(forHTTPHeaderField: name) }
}

/// Stateless transport when no coordinator is supplied (public auth, health,
/// isolated tests). API-mode business services always receive a coordinator.
@MainActor
final class APIClient {
    static let shared = APIClient()
    var baseURL: URL { config.baseURL }
    var account: AppUser? { authorization?.currentSession?.user }
    var authEmail: String { account?.email ?? "" }
    let config: APIConfig
    let session: URLSession
    let authorization: SessionCoordinator?
    let bearerTokenProvider: (@Sendable () -> String?)?
    private var rateLimits: [String: (Date, APIError)] = [:]

    func clearSessionState() { rateLimits.removeAll() }

    private init(
        config: APIConfig,
        session: URLSession = .shared,
        authorization: SessionCoordinator? = nil,
        bearerTokenProvider: (@Sendable () -> String?)? = nil
    ) {
        self.config = config
        self.session = session
        self.authorization = authorization
        self.bearerTokenProvider = bearerTokenProvider
    }

    convenience init(baseURL: URL? = nil, session: URLSession? = nil,
                     credentialStore: CredentialStoring? = nil, defaults: UserDefaults = .standard) {
        let baseURL = baseURL ?? APIConfig.currentURL()
        for key in ["ada.authEmail", "ada.authPassword", "ada.accessToken", "ada.refreshToken", "ada.userID"] {
            defaults.removeObject(forKey: key)
        }
        let config = APIConfig(baseURL: baseURL)
        let session = session ?? Self.privateSession(baseURL: baseURL)
        let transport = APIClient(config: config, session: session)
        let coordinator = SessionCoordinator(transport: transport,
            store: credentialStore ?? KeychainCredentialStore(baseURL: baseURL, defaults: defaults))
        self.init(config: config, session: session, authorization: coordinator)
    }

    func login(email: String, password: String, rememberMe: Bool = false) async throws -> AuthSession {
        guard let authorization else { throw AuthError.invalidCredentials }
        return try await authorization.signIn(email: email, password: password, rememberMe: rememberMe)
    }

    func restoreSession() async throws { _ = try await authorization?.restoreSession() }
    func logout() { authorization?.endSession(revoke: true); clearSessionState() }

    static func publicClient(baseURL: URL) -> APIClient {
        APIClient(config: APIConfig(baseURL: baseURL), session: privateSession(baseURL: baseURL))
    }

    func testConnection() async throws {
        struct Health: Decodable { let status: String }
        let health: Health = try await send(APIRequest(method: "GET", path: "/health",
            timeoutInterval: 5, authentication: .none))
        guard health.status.lowercased() == "ok" else { throw APIError.invalidResponse }
    }

    func send<T: Decodable>(_ request: APIRequest, as type: T.Type = T.self) async throws -> T {
        try await sendResponse(request, as: type).value
    }

    func sendResponse<T: Decodable>(_ request: APIRequest, as type: T.Type = T.self) async throws -> APIResponse<T> {
        let generation = request.authentication == .required ? authorization?.generation : nil
        let response = try await sendHTTP(request)
        if let generation { try authorization?.check(generation) }
        try requireMedia(response.http, accept: "application/json")
        do {
            return APIResponse(value: try APIJSON.decoder.decode(T.self, from: response.value), http: response.http)
        } catch {
            throw APIError.decoding("Unexpected JSON response.")
        }
    }

    func sendVoid(_ request: APIRequest) async throws { _ = try await sendHTTP(request) }

    func sendData(_ request: APIRequest) async throws -> Data {
        let response = try await sendHTTP(request)
        try requireMedia(response.http, accept: request.accept)
        return response.value
    }

    func sendRaw(_ request: APIRequest) async throws -> Data { try await sendHTTP(request).value }

    func sendHTTP(_ spec: APIRequest, url: URL? = nil) async throws -> APIResponse<Data> {
        try checkRateLimit(spec)
        var url = try url ?? makeURL(path: spec.path, query: spec.query)
        if !spec.queryItems.isEmpty, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.queryItems = (components.queryItems ?? []) + spec.queryItems
            guard let resolved = components.url else { throw APIError.invalidResponse }
            url = resolved
        }
        var request = makeRequest(spec, url: url)
        if spec.authentication == .required, let authorization {
            guard authorization.isConfigured(for: config), config.isTrustedOrigin(url) else { throw APIError.invalidURL("Untrusted API origin.") }
            let captured = authorization.generation
            let token = try await authorization.accessToken()
            try authorization.check(captured)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            var result = try await perform(request)
            try authorization.check(captured)
            if result.statusCode == 401 {
                try await authorization.recoverUnauthorized(rejectedToken: token, generation: captured)
                try authorization.check(captured)
                request.setValue("Bearer \(try await authorization.accessToken())", forHTTPHeaderField: "Authorization")
                result = try await perform(request)
                try authorization.check(captured)
                if result.statusCode == 401 { authorization.rejectRetriedRequest(generation: captured) }
            }
            return try accepted(result, spec: spec)
        }
        return try accepted(await perform(request), spec: spec)
    }

    /// Only the coordinator uses this path; context loading must not recursively
    /// await the refresh task which is currently loading that same context.
    func sendAuthenticatedContext<T: Decodable>(path: String, token: String) async throws -> T {
        let spec = APIRequest(method: "GET", path: path, authentication: .none)
        try checkRateLimit(spec)
        var request = makeRequest(spec, url: try makeURL(path: path))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let result = try accepted(await perform(request), spec: spec)
        try requireMedia(result.http, accept: "application/json")
        do { return try APIJSON.decoder.decode(T.self, from: result.value) }
        catch { throw APIError.decoding("Unexpected account response.") }
    }

    private func makeRequest(_ spec: APIRequest, url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = spec.method
        request.httpBody = spec.body
        request.cachePolicy = spec.cachePolicy ?? (authorization == nil ? .useProtocolCachePolicy : .reloadIgnoringLocalCacheData)
        if let timeout = spec.timeoutInterval { request.timeoutInterval = timeout }
        if spec.authentication == .none {
            request.setValue(nil, forHTTPHeaderField: "Authorization")
            request.httpShouldHandleCookies = false
        } else if authorization == nil, let token = bearerTokenProvider?(), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let contentType = spec.contentType ?? (spec.body == nil ? nil : "application/json") {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        request.setValue(spec.accept, forHTTPHeaderField: "Accept")
        return request
    }

    private func perform(_ request: URLRequest) async throws -> APIResponse<Data> {
        // Paths only: URL queries and transport errors may contain credentials.
        let result: (Data, URLResponse)
        do { result = try await session.data(for: request) }
        catch is CancellationError { throw CancellationError() }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch { throw APIError.transport("Check your connection and try again.") }
        try Task.checkCancellation()
        guard let response = result.1 as? HTTPURLResponse else { throw APIError.transport("Response was not HTTP.") }
        return APIResponse(value: result.0, http: response)
    }

    private func accepted(_ response: APIResponse<Data>, spec: APIRequest) throws -> APIResponse<Data> {
        guard spec.acceptedStatuses.contains(response.statusCode) else {
            let error = APIError.from(response: response.http, body: response.value)
            if response.statusCode == 429 {
                rateLimits[spec.method + spec.path] = (Date().addingTimeInterval(error.retryAfter ?? 60), error)
            }
            throw error
        }
        return response
    }

    private func checkRateLimit(_ spec: APIRequest) throws {
        if let (date, error) = rateLimits[spec.method + spec.path], date > Date() { throw error }
    }

    private func requireMedia(_ response: HTTPURLResponse, accept: String) throws {
        let mime = response.mimeType?.lowercased() ?? ""
        let accepted = accept.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard accepted.contains(where: { $0 == "*/*" || $0 == mime || ($0 == "image/*" && ["image/jpeg", "image/png", "image/webp"].contains(mime)) || ($0 == "application/json" && mime.hasSuffix("+json")) }) else {
            throw APIError.decoding("Unexpected response content type.")
        }
    }

    static func redactedURLString(for url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems, !items.isEmpty else {
            return url.absoluteString
        }
        let sensitiveKeys: Set<String> = ["token", "access_token", "refresh_token", "password", "code"]
        components.queryItems = items.map { item in
            if sensitiveKeys.contains(item.name.lowercased()) {
                return URLQueryItem(name: item.name, value: "<redacted>")
            }
            return item
        }
        return (components.string ?? url.path)
            .replacingOccurrences(of: "%3Credacted%3E", with: "<redacted>")
    }

    func makeURL(path: String, query: [String: String?] = [:]) throws -> URL {
        guard var components = URLComponents(url: config.baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL("Invalid backend URL.")
        }
        let basePath = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path = basePath + (path.hasPrefix("/") ? path : "/\(path)")
        let items = query.compactMap { key, value in value.map { URLQueryItem(name: key, value: $0) } }
        components.queryItems = items.isEmpty ? nil : items
        guard let url = components.url else { throw APIError.invalidURL("Invalid request path.") }
        return url
    }

    static func privateSession(baseURL: URL) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.urlCredentialStorage = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        return URLSession(configuration: config, delegate: TrustedAPIRedirectDelegate(baseURL: baseURL), delegateQueue: nil)
    }
}

/// Check the complete origin (including scheme and effective port), and refuse
/// redirects for credential-bearing POSTs as well as Authorization headers.
final class TrustedAPIRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let baseURL: URL
    nonisolated init(baseURL: URL) { self.baseURL = baseURL }
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        guard let url = request.url, Self.sameOrigin(baseURL, url) else { completionHandler(nil); return }
        completionHandler(request)
    }
    nonisolated static func sameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        func port(_ url: URL) -> Int? { url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 80) }
        return lhs.scheme?.lowercased() == rhs.scheme?.lowercased()
            && lhs.host?.lowercased() == rhs.host?.lowercased() && port(lhs) == port(rhs)
            && rhs.user == nil && rhs.password == nil
    }
}
