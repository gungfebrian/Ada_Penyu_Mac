import XCTest
@testable import Ada_Penyu_Desktop

@MainActor
final class OrganisationSettingsTests: XCTestCase {
    private let orgID = APIFixtures.orgID
    private let foreignOrgID = "99999999-0000-4000-8000-000000000099"
    private let ownerID = APIFixtures.userID
    private let rangerOneID = "20000000-0000-4000-8000-000000000011"
    private let rangerTwoID = "20000000-0000-4000-8000-000000000012"

    override func tearDown() {
        BackendStub.handler = nil
        BackendStub.responseDelay = nil
        super.tearDown()
    }

    func testRangerGetsReadOnlyProfileAndNoRangerManagement() async throws {
        var mutationCalls = 0
        BackendStub.handler = { [self] request in
            switch request.url!.path {
            case "/api/v1/auth/login": return (200, APIFixtures.tokens())
            case "/api/v1/auth/logout": return (204, Data())
            case "/api/v1/me":
                return (200, APIFixtures.data("""
                {"id":"\(rangerOneID)","organization_id":"\(orgID)","full_name":"Field Ranger","email":"ranger@example.test","status":"active","role":"ranger","is_self":true}
                """))
            case "/api/v1/organization":
                if request.httpMethod == "PATCH" { mutationCalls += 1 }
                return (200, APIFixtures.data("""
                {"id":"\(orgID)","name":"Bali Reef Patrol","email":"team@reef.test","location":"Bali, Indonesia","owner_user_id":"\(ownerID)","members_count":4}
                """))
            case "/api/v1/rangers":
                mutationCalls += 1
                return (403, APIFixtures.data(#"{"detail":"Owner required"}"#))
            default:
                return (404, Data())
            }
        }

        let client = makeKeyTestClient()
        _ = try await client.login(email: "ranger@example.test", password: "test-only")
        let store = AppStore(client: client)

        XCTAssertTrue(store.organisationSettings.canViewProfile)
        XCTAssertFalse(store.organisationSettings.canEditProfile)
        XCTAssertFalse(store.organisationSettings.canManageRangers)

        await store.organisationSettings.loadProfile()
        XCTAssertEqual(store.organisationSettings.profile?.name, "Bali Reef Patrol")
        XCTAssertEqual(store.organisationSettings.profile?.location, "Bali, Indonesia")

        store.organisationSettings.nameDraft = "Unauthorized Rename"
        let saved = await store.organisationSettings.saveProfile()
        let added = await store.organisationSettings.addRanger(fullName: "New", email: "new@example.test")
        XCTAssertFalse(saved)
        XCTAssertNil(added)
        XCTAssertEqual(mutationCalls, 0)
    }

    func testDemoModeIsCompletelyIsolatedAndSendsZeroRequests() async {
        var calls = 0
        BackendStub.handler = { _ in
            calls += 1
            return (200, Data())
        }
        let store = AppStore(client: makeKeyTestClient())
        store.enterDemoWorkspace()

        XCTAssertFalse(store.organisationSettings.canViewProfile)
        XCTAssertFalse(store.organisationSettings.canEditProfile)
        XCTAssertFalse(store.organisationSettings.canManageRangers)
        XCTAssertNotNil(store.organisationSettings.demoMessage)

        await store.organisationSettings.loadProfile()
        await store.organisationSettings.reloadRangers()
        let saved = await store.organisationSettings.saveProfile()
        XCTAssertFalse(saved)
        XCTAssertEqual(calls, 0)
    }

    func testCrossOrganisationResponsesAreRejected() async throws {
        var returnForeignOrg = false
        BackendStub.handler = { [self] request in
            if request.url!.path == "/api/v1/organization", returnForeignOrg {
                return (200, APIFixtures.data("""
                {"id":"\(foreignOrgID)","name":"Other Org","email":null,"location":null,"owner_user_id":"\(ownerID)","members_count":1}
                """))
            }
            if request.url!.path == "/api/v1/rangers" {
                return (200, APIFixtures.data("""
                {"items":[{"id":"\(rangerOneID)","organization_id":"\(foreignOrgID)","full_name":"Foreign","email":"foreign@example.test","status":"active","role":"ranger","is_self":false,"can_remove":true}],"total":1,"limit":25,"offset":0}
                """))
            }
            if let auth = APIFixtures.auth(request) { return auth }
            return (404, Data())
        }

        let store = try await ownerStore()
        returnForeignOrg = true
        await store.organisationSettings.loadProfile()
        XCTAssertNil(store.organisationSettings.profile)
        XCTAssertNotNil(store.organisationSettings.profileError)

        await store.organisationSettings.reloadRangers()
        XCTAssertTrue(store.organisationSettings.rangers.isEmpty)
        XCTAssertNotNil(store.organisationSettings.rangersError)
    }

    func testOrganisationPatchSendsChangedKeysExplicitNullsSkipsNoOpAndUpdatesHeaderName() async throws {
        var patchPayloads: [[String: Any]] = []
        var serverOrgName = "Bali Sea Turtle Society"
        var serverOrgEmail: String? = "seaturtle@example.test"
        var serverOrgLocation: String? = "Bali, Indonesia"

        BackendStub.handler = { [self] request in
            if request.url!.path == "/api/v1/organization" {
                if request.httpMethod == "PATCH", let body = request.rawBody,
                   let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                    patchPayloads.append(json)
                    if let name = json["name"] as? String { serverOrgName = name }
                    if json.keys.contains("email") { serverOrgEmail = json["email"] as? String }
                    if json.keys.contains("location") { serverOrgLocation = json["location"] as? String }
                }
                let emailJSON = serverOrgEmail.map { "\"\($0)\"" } ?? "null"
                let locationJSON = serverOrgLocation.map { "\"\($0)\"" } ?? "null"
                return (200, APIFixtures.data("""
                {"id":"\(orgID)","name":"\(serverOrgName)","email":\(emailJSON),"location":\(locationJSON),"owner_user_id":"\(ownerID)","members_count":3}
                """))
            }
            if let auth = APIFixtures.auth(request) { return auth }
            return (404, Data())
        }

        let store = try await ownerStore()
        await store.organisationSettings.loadProfile()
        XCTAssertEqual(store.organisationSettings.memberCountSummary, "3 members")

        // No-op save sends 0 PATCH requests
        let noopResult = await store.organisationSettings.saveProfile()
        XCTAssertTrue(noopResult)
        XCTAssertEqual(patchPayloads.count, 0)

        // Rename + clear email (explicit null), leave location untouched
        store.organisationSettings.nameDraft = "Coral Triangle Reserve"
        store.organisationSettings.emailDraft = "   "
        let saved = await store.organisationSettings.saveProfile()
        XCTAssertTrue(saved)
        XCTAssertEqual(patchPayloads.count, 1)
        XCTAssertEqual(patchPayloads[0]["name"] as? String, "Coral Triangle Reserve")
        XCTAssertTrue(patchPayloads[0]["email"] is NSNull)
        XCTAssertNil(patchPayloads[0]["location"])
        XCTAssertEqual(store.accountOrganization, "Coral Triangle Reserve")
        XCTAssertNil(store.organisationSettings.profile?.email)
    }

    func testRangerSearchPagingStaleResponsesAndMutations() async throws {
        var capturedQueries: [String] = []
        var capturedAddPayload: [String: String]?
        var capturedPatchPayload: [String: String]?
        var resendCalls = 0
        var deleteCalls = 0

        let ranger1JSON = """
        {"id":"\(rangerOneID)","organization_id":"\(orgID)","full_name":"Nadia Patrol","email":"nadia@example.test","status":"invited","role":"ranger","is_self":false,"can_remove":true}
        """
        let ranger2JSON = """
        {"id":"\(rangerTwoID)","organization_id":"\(orgID)","full_name":"Budi Reef","email":"budi@example.test","status":"active","role":"ranger","is_self":false,"can_remove":true}
        """

        BackendStub.handler = { [self] request in
            if let auth = APIFixtures.auth(request) { return auth }
            let path = request.url!.path
            if path == "/api/v1/rangers" {
                if request.httpMethod == "GET" {
                    let comps = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
                    let q = comps?.queryItems?.first { $0.name == "q" }?.value ?? ""
                    let offset = Int(comps?.queryItems?.first { $0.name == "offset" }?.value ?? "0") ?? 0
                    capturedQueries.append("\(q)@\(offset)")
                    if q == "slow" {
                        return (200, APIFixtures.data("{\"items\":[\(ranger1JSON)],\"total\":1,\"limit\":1,\"offset\":0}"))
                    }
                    if q == "fast" {
                        return (200, APIFixtures.data("{\"items\":[\(ranger2JSON)],\"total\":1,\"limit\":1,\"offset\":0}"))
                    }
                    if offset == 0 {
                        return (200, APIFixtures.data("{\"items\":[\(ranger1JSON)],\"total\":2,\"limit\":1,\"offset\":0}"))
                    }
                    return (200, APIFixtures.data("{\"items\":[\(ranger2JSON)],\"total\":2,\"limit\":1,\"offset\":1}"))
                }
                if request.httpMethod == "POST", let body = request.rawBody {
                    capturedAddPayload = try? JSONDecoder().decode([String: String].self, from: body)
                    return (201, APIFixtures.data(ranger1JSON))
                }
            }
            if path == "/api/v1/rangers/\(rangerOneID)" {
                if request.httpMethod == "GET" {
                    return (200, APIFixtures.data(ranger1JSON))
                }
                if request.httpMethod == "PATCH", let body = request.rawBody {
                    capturedPatchPayload = try? JSONDecoder().decode([String: String].self, from: body)
                    return (200, APIFixtures.data("""
                    {"id":"\(rangerOneID)","organization_id":"\(orgID)","full_name":"Nadia Updated","email":"nadia@example.test","status":"invited","role":"ranger","is_self":false,"can_remove":true}
                    """))
                }
                if request.httpMethod == "DELETE" {
                    deleteCalls += 1
                    return (204, Data())
                }
            }
            if path == "/api/v1/rangers/\(rangerOneID)/resend-invitation" && request.httpMethod == "POST" {
                resendCalls += 1
                return (204, Data())
            }
            return (404, Data())
        }

        let client = makeKeyTestClient()
        _ = try await client.login(email: "person@example.test", password: "test-only")
        let model = OrganisationSettingsModel(client: client, pageSize: 1)

        // Paging
        await model.reloadRangers()
        XCTAssertEqual(model.rangers.count, 1)
        XCTAssertEqual(model.rangerTotal, 2)
        XCTAssertTrue(model.canLoadMoreRangers)
        await model.loadMoreRangers()
        XCTAssertEqual(model.rangers.count, 2)
        XCTAssertFalse(model.canLoadMoreRangers)

        // Stale search guard: slow query resolves after fast query
        BackendStub.responseDelay = { req in
            (req.url?.query?.contains("q=slow") == true) ? 0.14 : 0.01
        }
        let slowTask = Task { await model.reloadRangers(query: "slow") }
        try? await Task.sleep(for: .milliseconds(20))
        await model.reloadRangers(query: "fast")
        await slowTask.value
        XCTAssertEqual(model.rangers.map(\.fullName), ["Budi Reef"])
        BackendStub.responseDelay = nil

        // Add ranger
        let added = await model.addRanger(fullName: "Nadia Patrol", email: "nadia@example.test")
        XCTAssertEqual(added?.id.uuidString.lowercased(), rangerOneID)
        XCTAssertEqual(capturedAddPayload?["full_name"], "Nadia Patrol")
        XCTAssertEqual(capturedAddPayload?["email"], "nadia@example.test")

        // Edit ranger sends only changed key; no-op sends nothing
        let id = UUID(uuidString: rangerOneID)!
        let updated = await model.updateRanger(id: id, fullName: "Nadia Updated", email: "nadia@example.test")
        XCTAssertTrue(updated)
        XCTAssertEqual(capturedPatchPayload?["full_name"], "Nadia Updated")
        XCTAssertNil(capturedPatchPayload?["email"])

        // Resend invitation (invited ranger)
        let resent = await model.resendInvitation(id: id)
        XCTAssertTrue(resent)
        XCTAssertEqual(resendCalls, 1)

        // Remove ranger access
        let removed = await model.removeRangerAccess(id: id)
        XCTAssertTrue(removed)
        XCTAssertEqual(deleteCalls, 1)
        XCTAssertNil(model.member(for: id))
        XCTAssertTrue(capturedQueries.contains("@0"))
        XCTAssertTrue(capturedQueries.contains("@1"))
    }

    func testForbiddenPreservesSessionAndSignOutClearsCachedOrgData() async throws {
        BackendStub.handler = { request in
            if request.url!.path == "/api/v1/organization" && request.httpMethod == "PATCH" {
                return (403, APIFixtures.data(#"{"detail":"Owner permission revoked"}"#))
            }
            if let auth = APIFixtures.auth(request) { return auth }
            return (404, Data())
        }
        let store = try await ownerStore()
        await store.organisationSettings.loadProfile()
        XCTAssertNotNil(store.organisationSettings.profile)

        store.organisationSettings.nameDraft = "New Name"
        let saved = await store.organisationSettings.saveProfile()
        XCTAssertFalse(saved)
        XCTAssertTrue(store.isAuthenticated)
        XCTAssertFalse(store.organisationSettings.canEditProfile)
        XCTAssertEqual(store.organisationSettings.accessDeniedMessage, "Owner permission revoked")

        store.signOut()
        XCTAssertNil(store.organisationSettings.profile)
        XCTAssertTrue(store.organisationSettings.rangers.isEmpty)
        XCTAssertEqual(store.organisationSettings.nameDraft, "")
    }

    private func ownerStore() async throws -> AppStore {
        let client = makeKeyTestClient()
        _ = try await client.login(email: "person@example.test", password: "test-only")
        return AppStore(client: client)
    }
}

private extension URLRequest {
    var rawBody: Data? {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read > 0 { data.append(buffer, count: read) } else { break }
        }
        return data
    }
}
