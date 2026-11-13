import Foundation

/// All credential and refresh commits run on the main actor, matching the app's
/// service isolation. Network suspension never releases an uncommitted token pair.
@MainActor
final class SessionCoordinator {
    private let transport: APIClient
    private let store: CredentialStoring
    private var tokens: TokenPair?
    private var accessExpiresAt = Date.distantPast
    private var persisted: StoredCredentials?
    private var rememberMe = false
    private var context: AuthSession?
    var currentSession: AuthSession? { context }
    private var refreshTask: Task<Void, Error>?
    private(set) var revocationTask: Task<Void, Never>?
    private var retryNotBefore = Date.distantPast
    private(set) var generation = UUID()

    var onContextChanged: ((AuthSession) -> Void)?
    var onSessionEnded: ((String?) -> Void)?
    var onContextFailure: ((Error) -> Void)?

    init(transport: APIClient, store: CredentialStoring) {
        self.transport = transport
        self.store = store
    }

    func signIn(email: String, password: String, rememberMe: Bool) async throws -> AuthSession {
        endSession(revoke: true, notify: false)
        let captured = generation
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !password.isEmpty else {
            throw AuthError.invalidCredentials
        }
        let body = try JSONEncoder().encode(["email": email.trimmingCharacters(in: .whitespacesAndNewlines), "password": password])
        let pair: TokenPair = try await transport.send(APIRequest(method: "POST", path: "/api/v1/auth/login", body: body, authentication: .none))
        do {
            try check(captured)
            try validate(pair)
        } catch {
            revoke(pair.refreshToken)
            throw error
        }
        do {
            let session = try await fetchContext(token: pair.accessToken)
            try check(captured)
            let record = try credentials(pair: pair, session: session)
            if rememberMe { try store.save(record) }
            self.rememberMe = rememberMe
            persisted = record
            tokens = pair
            accessExpiresAt = Date().addingTimeInterval(TimeInterval(pair.expiresIn))
            context = session
            return session
        } catch {
            if generation == captured { endSession(revoke: false) }
            revoke(pair.refreshToken)
            throw error
        }
    }

    func restoreSession() async throws -> AuthSession? {
        if tokens != nil {
            _ = try await accessToken()
            return context
        }
        let captured = generation
        guard let record = try store.load() else { return nil }
        guard record.refreshExpiresAt > Date() else { try store.remove(); return nil }
        guard !record.rotationInFlight else {
            try store.remove()
            throw AuthError.custom("The previous session renewal was interrupted. Please sign in again.")
        }
        try check(captured)
        persisted = record
        rememberMe = true
        tokens = TokenPair(accessToken: "", refreshToken: record.refreshToken, tokenType: "bearer",
                           expiresIn: 0, refreshExpiresAt: record.refreshExpiresAt)
        try await refresh()
        return context
    }

    func reloadContext() async throws -> AuthSession {
        let captured = generation
        let token = try await accessToken()
        let loaded: AuthSession
        do {
            loaded = try await fetchContext(token: token)
        } catch let error as APIError where error.statusCode == 401 {
            try await recoverUnauthorized(rejectedToken: token, generation: captured)
            guard let context else { throw AuthError.custom("Please sign in again.") }
            return context
        }
        try check(captured)
        try validateIdentity(loaded)
        context = loaded
        return loaded
    }

    func accessToken() async throws -> String {
        guard tokens != nil else { throw AuthError.custom("Please sign in to continue.") }
        if refreshTask != nil || accessExpiresAt <= Date().addingTimeInterval(30) {
            try await refresh()
        } else if context == nil, let token = tokens?.accessToken {
            let captured = generation
            let loaded = try await fetchContext(token: token)
            try check(captured)
            try validateIdentity(loaded)
            context = loaded
            onContextChanged?(loaded)
        }
        guard let token = tokens?.accessToken, context != nil else { throw AuthError.custom("Please sign in again.") }
        return token
    }

    func recoverUnauthorized(rejectedToken: String, generation captured: UUID) async throws {
        try check(captured)
        if let token = tokens?.accessToken, token != rejectedToken {
            _ = try await accessToken()
            return
        }
        try await refresh()
    }

    func rejectRetriedRequest(generation captured: UUID) {
        guard generation == captured else { return }
        endSession(revoke: false, message: "Your session has ended. Please sign in again.")
    }

    private func refresh() async throws {
        if let refreshTask { return try await refreshTask.value }
        guard Date() >= retryNotBefore else {
            throw APIError.http(status: 429, detail: "Please wait before trying to renew your session again.")
        }
        let captured = generation
        let task = Task { try await self.performRefresh(generation: captured) }
        refreshTask = task
        defer { if generation == captured { refreshTask = nil } }
        try await task.value
    }

    private func performRefresh(generation captured: UUID) async throws {
        guard let old = tokens, var record = persisted else { throw AuthError.custom("Please sign in again.") }
        guard old.refreshExpiresAt > Date() else {
            endSession(revoke: false, message: "Your session has expired. Please sign in again.")
            throw AuthError.custom("Your session has expired. Please sign in again.")
        }
        record.rotationInFlight = true
        if rememberMe { try store.save(record) }
        let pair: TokenPair
        do {
            let body = try JSONEncoder().encode(["refresh_token": old.refreshToken])
            pair = try await transport.send(APIRequest(method: "POST", path: "/api/v1/auth/refresh", body: body, authentication: .none))
            try check(captured)
            try validate(pair)
        } catch {
            try check(captured)
            if let error = error as? APIError, error.statusCode == 429 {
                record.rotationInFlight = false
                if rememberMe { try store.save(record) }
                retryNotBefore = Date().addingTimeInterval(error.retryAfter ?? 60)
                throw error
            }
            let message = (error as? APIError)?.statusCode == 401
                ? "Your session has ended. Please sign in again."
                : "Session renewal could not be completed. Please sign in again when connected."
            endSession(revoke: false, message: message)
            throw AuthError.custom(message)
        }
        // Save the replacement before publishing it. An I/O failure must not
        // leave the consumed refresh token eligible for another attempt.
        let replacement = StoredCredentials(refreshToken: pair.refreshToken, refreshExpiresAt: pair.refreshExpiresAt,
                                            userID: record.userID, organizationID: record.organizationID, rotationInFlight: false)
        do {
            if rememberMe { try store.save(replacement) }
        } catch {
            endSession(revoke: false, message: "The renewed session could not be saved securely. Please sign in again.")
            throw error
        }
        tokens = pair
        persisted = replacement
        accessExpiresAt = Date().addingTimeInterval(TimeInterval(pair.expiresIn))
        context = nil
        do {
            let loaded = try await fetchContext(token: pair.accessToken)
            try check(captured)
            try validateIdentity(loaded)
            context = loaded
            onContextChanged?(loaded)
        } catch {
            try check(captured)
            if (error as? APIError)?.statusCode == 401 {
                endSession(revoke: false, message: "Your session has ended. Please sign in again.")
            } else {
                onContextFailure?(error)
            }
            throw error
        }
    }

    private func fetchContext(token: String) async throws -> AuthSession {
        let account: AccountDTO = try await transport.sendAuthenticatedContext(path: "/api/v1/me", token: token)
        let organization: OrganizationDTO = try await transport.sendAuthenticatedContext(path: "/api/v1/organization", token: token)
        return try CurrentAccountPolicy.session(account: account, organization: organization)
    }

    private func validateIdentity(_ session: AuthSession) throws {
        if let persisted {
            guard session.user.id == persisted.userID, session.user.organisationID == persisted.organizationID else {
                endSession(revoke: false, message: "The session account changed. Please sign in again.")
                throw AuthError.custom("The session account changed. Please sign in again.")
            }
        }
    }

    private func credentials(pair: TokenPair, session: AuthSession) throws -> StoredCredentials {
        guard let organizationID = session.user.organisationID else { throw AuthError.custom("Missing organisation.") }
        return StoredCredentials(refreshToken: pair.refreshToken, refreshExpiresAt: pair.refreshExpiresAt,
                                 userID: session.user.id, organizationID: organizationID, rotationInFlight: false)
    }

    private func validate(_ pair: TokenPair) throws {
        guard pair.tokenType == "bearer", !pair.accessToken.isEmpty, !pair.refreshToken.isEmpty,
              pair.expiresIn > 0, pair.refreshExpiresAt > Date() else {
            throw APIError.decoding("Invalid session credentials.")
        }
    }

    func isConfigured(for config: APIConfig) -> Bool { transport.config.baseURL == config.baseURL }

    func requireUser(_ user: AppUser) throws {
        guard let persisted, let active = context?.user, user.id == persisted.userID,
              user.organisationID == persisted.organizationID, user.role == active.role else {
            throw AuthError.custom("This operation belongs to another session.")
        }
    }

    func check(_ captured: UUID) throws {
        try Task.checkCancellation()
        guard captured == generation else { throw CancellationError() }
    }

    func endSession(revoke shouldRevoke: Bool, message: String? = nil, notify: Bool = true) {
        let outgoing = tokens?.refreshToken ?? persisted?.refreshToken
        generation = UUID()
        refreshTask?.cancel()
        refreshTask = nil
        tokens = nil
        persisted = nil
        context = nil
        accessExpiresAt = .distantPast
        retryNotBefore = .distantPast
        rememberMe = false
        try? store.remove() // Keychain store also leaves a durable sign-out tombstone.
        if notify { onSessionEnded?(message) }
        if shouldRevoke, let outgoing { revoke(outgoing) }
    }

    private func revoke(_ refreshToken: String) {
        let transport = transport
        guard let body = try? JSONEncoder().encode(["refresh_token": refreshToken]) else { return }
        revocationTask = Task {
            try? await transport.sendVoid(APIRequest(method: "POST", path: "/api/v1/auth/logout", body: body,
                                                     acceptedStatuses: [204], authentication: .none))
        }
    }
}

