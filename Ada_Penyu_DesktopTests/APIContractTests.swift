import XCTest
@testable import Ada_Penyu_Desktop

@MainActor
final class MemoryCredentials: CredentialStoring {
    var value: StoredCredentials?
    var failSave = false
    func load() throws -> StoredCredentials? { value }
    func save(_ credentials: StoredCredentials) throws {
        if failSave { throw AuthError.custom("Storage unavailable") }
        value = credentials
    }
    func remove() throws { value = nil }
}

enum APIFixtures {
    static let userID = "10000000-0000-4000-8000-000000000001"
    static let orgID = "10000000-0000-4000-8000-000000000002"
    static let turtleID = "10000000-0000-4000-8000-000000000003"
    static func data(_ value: String) -> Data { Data(value.utf8) }
    static func tokens(_ access: String = "access", refresh: String = "refresh") -> Data {
        data("""
        {"access_token":"\(access)","refresh_token":"\(refresh)","token_type":"bearer","expires_in":900,"refresh_expires_at":"2099-12-31T00:00:00Z"}
        """)
    }
    static let profile = """
    {"id":"\(turtleID)","profile_code":"000123","name":"Amina","species":"unknown","first_seen_at":"2026-01-01T00:00:00Z",
    "identity_photos":{"left":{"url":"/api/v2/individuals/\(turtleID)/photos/left","uploaded_at":"2026-01-01T00:00:00Z","captured_at":null},"right":null},
    "summary":{"total_sightings":12,"latest_sighting":null,"last_recorded_condition":null,"latest_measurements":null}}
    """
    static func page(_ items: String, total: Int = 1, offset: Int = 0) -> Data {
        data("{\"items\":[\(items)],\"total\":\(total),\"limit\":200,\"offset\":\(offset)}")
    }
    static func auth(_ request: URLRequest) -> (Int, Data)? {
        switch request.url!.path {
        case "/api/v1/auth/login": return (200, tokens())
        case "/api/v1/auth/refresh": return (200, tokens("renewed", refresh: "rotated"))
        case "/api/v1/auth/logout": return (204, Data())
        case "/api/v1/me": return (200, data("{\"id\":\"\(userID)\",\"organization_id\":\"\(orgID)\",\"full_name\":\"Researcher\",\"email\":\"person@example.test\",\"status\":\"active\",\"role\":\"owner\",\"is_self\":true}"))
        case "/api/v1/organization": return (200, data("{\"id\":\"\(orgID)\",\"name\":\"Conservation\",\"owner_user_id\":\"\(userID)\"}"))
        default: return nil
        }
    }
}

@MainActor
final class APIContractTests: XCTestCase {
    override func tearDown() {
        BackendStub.responseDelay = nil
        super.tearDown()
    }
    private func client(store: MemoryCredentials? = nil) -> APIClient {
        APIClient(baseURL: URL(string: "https://example.test")!, session: BackendStub.session(), credentialStore: store ?? MemoryCredentials())
    }
    private func signIn(_ client: APIClient, remember: Bool = false) async throws {
        _ = try await client.login(email: "person@example.test", password: "test-only-password", rememberMe: remember)
    }

    func testLoginLoadsRealIdentityAndOnlyRememberedRefreshCredentialsAreSaved() async throws {
        BackendStub.handler = { APIFixtures.auth($0)! }
        let store = MemoryCredentials()
        let client = client(store: store)
        try await signIn(client)
        XCTAssertEqual(client.account?.displayName, "Researcher")
        XCTAssertEqual(client.account?.organisationName, "Conservation")
        XCTAssertNil(store.value)
        try await signIn(client, remember: true)
        XCTAssertEqual(store.value?.refreshToken, "refresh")
        XCTAssertEqual(store.value?.userID.uuidString.lowercased(), APIFixtures.userID)
        client.logout()
        XCTAssertNil(client.account)
        XCTAssertNil(store.value)
    }

    func testRememberedSessionRestoresByRotatingRefreshToken() async throws {
        BackendStub.handler = { APIFixtures.auth($0)! }
        let store = MemoryCredentials()
        let first = client(store: store)
        try await signIn(first, remember: true)
        let restored = client(store: store)
        try await restored.restoreSession()
        XCTAssertEqual(restored.account?.email, "person@example.test")
        XCTAssertEqual(store.value?.refreshToken, "rotated")
        XCTAssertEqual(store.value?.rotationInFlight, false)
    }

    func testFailedRememberedCredentialWriteCannotReportLoginSuccess() async {
        BackendStub.handler = { APIFixtures.auth($0)! }
        let store = MemoryCredentials()
        store.failSave = true
        let client = client(store: store)
        do { try await signIn(client, remember: true); XCTFail("Login should fail") }
        catch { XCTAssertNil(client.account) }
    }

    func testInterruptedRotationIsNotReplayedOnRestore() async throws {
        var requests = 0
        BackendStub.handler = { _ in requests += 1; return (200, APIFixtures.tokens()) }
        let store = MemoryCredentials()
        store.value = StoredCredentials(refreshToken: "possibly-consumed", refreshExpiresAt: Date().addingTimeInterval(3600),
            userID: UUID(), organizationID: UUID(), rotationInFlight: true)
        let client = client(store: store)
        do { try await client.restoreSession(); XCTFail("Interrupted rotation must require sign-in") }
        catch { XCTAssertNil(client.account) }
        XCTAssertNil(store.value)
        XCTAssertEqual(requests, 0)
    }

    func testLateLoginAfterLogoutCannotPersistOrRestoreCredentials() async throws {
        let started = expectation(description: "Login started")
        BackendStub.handler = { request in
            if request.url!.path == "/api/v1/auth/login" { started.fulfill() }
            return APIFixtures.auth(request)!
        }
        BackendStub.responseDelay = { $0.url!.path == "/api/v1/auth/login" ? 0.15 : 0 }
        let store = MemoryCredentials()
        let client = client(store: store)
        let login = Task { try await signIn(client, remember: true) }
        await fulfillment(of: [started], timeout: 2)
        client.logout()
        do { try await login.value; XCTFail("An old login must be rejected") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertNil(store.value)
        XCTAssertNil(client.account)
    }

    func testLogoutDuringRefreshCannotRestoreSession() async throws {
        let started = expectation(description: "Refresh started")
        BackendStub.handler = { request in
            if request.url!.path == "/api/v1/auth/refresh" { started.fulfill() }
            return APIFixtures.auth(request) ?? (401, APIFixtures.data("{}"))
        }
        BackendStub.responseDelay = { $0.url!.path == "/api/v1/auth/refresh" ? 0.15 : 0 }
        let credentials = MemoryCredentials()
        let client = client(store: credentials)
        try await signIn(client, remember: true)
        let request = Task { try await client.getData("api/v2/individuals") }
        await fulfillment(of: [started], timeout: 2)
        client.logout()
        do { _ = try await request.value; XCTFail("An old request must be rejected") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertNil(client.account)
        XCTAssertNil(credentials.value)
    }

    func testForeignOrganizationContextCannotCreateSession() async {
        BackendStub.handler = { request in
            if request.url!.path == "/api/v1/organization" {
                return (200, APIFixtures.data("{\"id\":\"10000000-0000-4000-8000-000000000099\",\"name\":\"Foreign\",\"owner_user_id\":\"\(APIFixtures.userID)\"}"))
            }
            return APIFixtures.auth(request)!
        }
        let client = client()
        do { try await signIn(client); XCTFail("Foreign organization should be rejected") }
        catch { XCTAssertNil(client.account) }
    }

    #if DEBUG
    func testBackendChangeClearsPrivateStateAndInvalidURLDoesNotChangeBackend() async throws {
        let original = UserDefaults.standard.string(forKey: APIConfig.overrideKey)
        defer { UserDefaults.standard.set(original, forKey: APIConfig.overrideKey) }
        let store = AppStore(repository: TestTurtleRepository(), client: client())
        await store.reloadAll()
        XCTAssertFalse(store.turtles.isEmpty)
        let generation = store.sessionGeneration
        XCTAssertThrowsError(try store.changeBackend("file:///tmp/data"))
        XCTAssertEqual(store.sessionGeneration, generation)
        try store.changeBackend("http://127.0.0.1:8010")
        XCTAssertFalse(store.isAuthenticated)
        XCTAssertTrue(store.turtles.isEmpty)
        XCTAssertTrue(store.sightings.isEmpty)
        XCTAssertNotEqual(store.sessionGeneration, generation)
        XCTAssertEqual(store.apiBaseURLString, "http://127.0.0.1:8010")
        try store.changeBackend(nil)
        XCTAssertEqual(store.apiBaseURLString, APIConfig.defaultURL.absoluteString)
    }
    #endif

    func testUnauthorizedRequestsShareOneRefreshAndRetryMultipartBytes() async throws {
        let lock = NSLock()
        var refreshCount = 0
        var bodies: [Data] = []
        BackendStub.handler = { request in
            lock.lock(); defer { lock.unlock() }
            if request.url!.path == "/api/v1/auth/refresh" { refreshCount += 1 }
            if let auth = APIFixtures.auth(request) { return auth }
            bodies.append(request.httpBody ?? Data())
            return request.value(forHTTPHeaderField: "Authorization") == "Bearer renewed"
                ? (200, APIFixtures.data("{}")) : (401, APIFixtures.data("{}"))
        }
        let client = client()
        try await signIn(client)
        async let first = client.requestData(path: "/api/v2/test", method: "POST", body: Data([0, 255, 1]), contentType: "multipart/form-data; boundary=stable")
        async let second = client.requestData(path: "/api/v2/test", method: "POST", body: Data([0, 255, 1]), contentType: "multipart/form-data; boundary=stable")
        _ = try await (first, second)
        XCTAssertEqual(refreshCount, 1)
        XCTAssertTrue(bodies.allSatisfy { $0 == Data([0, 255, 1]) })
    }

    func testSecondUnauthorizedEndsSessionAndDoesNotLoginAgain() async throws {
        var loginCount = 0
        BackendStub.handler = { request in
            if request.url!.path == "/api/v1/auth/login" { loginCount += 1 }
            return APIFixtures.auth(request) ?? (401, APIFixtures.data("{}"))
        }
        let client = client()
        try await signIn(client)
        do { _ = try await client.getData("api/v2/individuals"); XCTFail("Expected 401") }
        catch { XCTAssertEqual((error as? APIError)?.statusCode, 401) }
        XCTAssertNil(client.account)
        XCTAssertEqual(loginCount, 1)
    }

    func testPublicHealthAndExternalPhotoNeverReceiveBearerOrCookies() async throws {
        BackendStub.handler = { request in
            if let auth = APIFixtures.auth(request) { return auth }
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertFalse(request.httpShouldHandleCookies)
            return (200, APIFixtures.data("{\"status\":\"ok\"}"))
        }
        let client = client()
        try await signIn(client)
        try await client.testConnection()
        _ = try await client.requestData(path: "https://storage.test/photo?signature=unchanged", method: "GET", accept: "image/*")
    }

    func testProfilesUseV2AndKeepUnknownsAndStableUUIDs() async throws {
        BackendStub.handler = { request in
            if let auth = APIFixtures.auth(request) { return auth }
            XCTAssertEqual(request.url?.path, "/api/v2/individuals")
            return (200, APIFixtures.page(APIFixtures.profile))
        }
        let client = client()
        try await signIn(client)
        let page = try await RemoteTurtleRepository(client: client).listIndividuals(query: .default)
        let turtle = try XCTUnwrap(page.items.first)
        XCTAssertEqual(turtle.displayName, "Amina")
        XCTAssertEqual(turtle.id.lowercased(), APIFixtures.turtleID)
        XCTAssertEqual(turtle.species, .unknown)
        XCTAssertEqual(turtle.condition, .unknown)
        XCTAssertEqual(turtle.lastSeen, "Not recorded")
        XCTAssertEqual(turtle.sightings, 12)
    }

    func testV2DetailPaginatesAndUsesEncounterMeasurementsAndMarkings() async throws {
        let log = """
        {"id":"10000000-0000-4000-8000-000000000004","observed_at":"2026-02-01T00:00:00Z","event":{"type":"sighting"},
        "location":{"name":"Reef","coordinates":null},"notes":null,"measurements":{"carapace_length_cm":70,"carapace_width_cm":null,"weight_kg":null},
        "condition":{"status":"injured","notes":null,"markings":[{"id":"10000000-0000-4000-8000-000000000005","region":"head","kind":"wound","notes":"Observed wound"}]}}
        """
        var offsets: [String] = []
        BackendStub.handler = { request in
            if let auth = APIFixtures.auth(request) { return auth }
            if request.url!.path.hasSuffix("/logs") {
                let offset = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "offset" }!.value!
                offsets.append(offset)
                return (200, APIFixtures.page(log, total: 2, offset: Int(offset)!))
            }
            return (200, APIFixtures.data(APIFixtures.profile))
        }
        let client = client()
        try await signIn(client)
        let turtle = try JSONDecoder.api.decode(V2Profile.self, from: APIFixtures.data(APIFixtures.profile)).turtle()
        let detail = try await RemoteTurtleRepository(client: client).detail(for: turtle)
        XCTAssertEqual(offsets, ["0", "1"])
        XCTAssertEqual(detail.measurements.count, 2)
        XCTAssertEqual(detail.measurements.first?.length, 70)
        XCTAssertEqual(detail.logs.first?.location, "Reef")
        XCTAssertEqual(detail.logs.filter { $0.bodyPart == .head }.count, 2)
    }

    func testEnrollmentSendsOnlyV2IdentityFieldsAndPhotoUploadUsesV2() async throws {
        BackendStub.handler = { request in
            if let auth = APIFixtures.auth(request) { return auth }
            XCTAssertTrue(request.url!.path.hasPrefix("/api/v2/individuals"))
            if request.httpMethod == "POST" {
                let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
                XCTAssertEqual(Set(body.keys), ["id", "profile_code", "name", "species", "sex", "first_seen_at"])
                XCTAssertEqual(body["profile_code"] as? String, "000123")
                return (201, APIFixtures.data(APIFixtures.profile))
            }
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")!.hasPrefix("multipart/form-data"))
            return (200, APIFixtures.data("{\"url\":\"/api/v2/photo\",\"uploaded_at\":\"2026-01-01T00:00:00Z\",\"captured_at\":null}"))
        }
        let client = client()
        try await signIn(client)
        let repo = RemoteTurtleRepository(client: client)
        let draft = IndividualDraft(profileCode: "000123", name: "Amina", species: "green", sex: "unknown", firstSeenAt: Date())
        _ = try await repo.createIndividual(draft)
        _ = try await repo.uploadIndividualPhoto(individualID: UUID(uuidString: APIFixtures.turtleID)!, side: .left, imageData: Data([0, 255, 1]))
    }

    func testPhotoNamedLikeBundledSampleDoesNotUseBundledImage() async throws {
        BackendStub.handler = { APIFixtures.auth($0) ?? (404, APIFixtures.data("{}")) }
        let store = AppStore(client: client())
        try await store.signIn(email: "person@example.test", password: "test-only", rememberMe: false)
        let image = await store.loadPhoto(for: "Amina1_L.jpg")
        XCTAssertNil(image)
    }

    func testMissingV2ShowsErrorWithoutRecords() async throws {
        BackendStub.handler = { request in
            if let auth = APIFixtures.auth(request) { return auth }
            return (404, APIFixtures.data("{\"detail\":\"Not Found\"}"))
        }
        let store = AppStore(client: client())
        try await store.signIn(email: "person@example.test", password: "test-only", rememberMe: false)
        XCTAssertTrue(store.turtles.isEmpty)
        XCTAssertNotNil(store.lastError)
        XCTAssertTrue(store.isAuthenticated)
    }

    func testSignedOutBootstrapDoesNotFetchPrivateRecords() async {
        var privateRequests = 0
        BackendStub.handler = { _ in privateRequests += 1; return (200, APIFixtures.data("{}")) }
        let store = AppStore(client: client())
        await store.bootstrap()
        XCTAssertEqual(privateRequests, 0)
        XCTAssertTrue(store.turtles.isEmpty)
        store.signOut()
        XCTAssertTrue(store.turtles.isEmpty)
        XCTAssertTrue(store.sightings.isEmpty)
        XCTAssertFalse(store.isAuthenticated)
    }

    func testURLValidationAndCompleteOriginChecks() throws {
        for raw in ["", "file:///tmp/data", "https://user:password@host.test", "https://host.test?q=x", "https://host.test/#x", "http://host.test:99999"] {
            XCTAssertThrowsError(try APIConfig.validatedURL(raw))
        }
        let config = APIConfig(baseURL: try APIConfig.validatedURL("  https://EXAMPLE.test/  "))
        XCTAssertTrue(config.isTrustedOrigin(URL(string: "https://example.test:443/photo")!))
        XCTAssertFalse(config.isTrustedOrigin(URL(string: "http://example.test/photo")!))
        XCTAssertFalse(config.isTrustedOrigin(URL(string: "https://example.test:444/photo")!))
    }

    func testLegacyCredentialsAreRemovedAndOverridesAreDebugOnly() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        for key in ["ada.authPassword", "ada.accessToken", "ada.refreshToken"] { defaults.set("legacy-secret", forKey: key) }
        defaults.set("http://127.0.0.1:8010", forKey: APIConfig.overrideKey)
        _ = APIClient(credentialStore: MemoryCredentials(), defaults: defaults)
        XCTAssertNil(defaults.object(forKey: "ada.authPassword"))
        XCTAssertNil(defaults.object(forKey: "ada.accessToken"))
        XCTAssertNil(defaults.object(forKey: "ada.refreshToken"))
        #if DEBUG
        XCTAssertEqual(APIConfig.currentURL(defaults: defaults).port, 8010)
        #else
        XCTAssertEqual(APIConfig.currentURL(defaults: defaults), APIConfig.defaultURL)
        #endif
    }
}
