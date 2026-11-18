import XCTest
@testable import Ada_Penyu_Desktop

@MainActor
final class OrganizationAPIKeyTests: XCTestCase {
    override func tearDown() {
        BackendStub.handler = nil
        BackendStub.responseDelay = nil
        super.tearDown()
    }

    func testOwnerReadsMetadataIssuesOnceAndRevokesEmptyResponse() async throws {
        var calls: [String] = []
        BackendStub.handler = { request in
            if let auth = APIFixtures.auth(request) { return auth }
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access")
            XCTAssertNil(request.value(forHTTPHeaderField: "X-API-Key"))
            XCTAssertNil(request.httpBody)
            XCTAssertEqual(request.timeoutInterval, 30)
            calls.append("\(request.httpMethod!) \(request.url!.path)")
            switch request.httpMethod {
            case "POST":
                return (200, APIFixtures.data("""
                    {"configured":true,"prefix":"adapenyu_test1234","issued_at":"2026-11-17T08:00:00Z","api_key":"test-only-secret"}
                    """))
            case "DELETE": return (204, Data())
            default: return (200, APIFixtures.data("{\"configured\":false,\"prefix\":null,\"issued_at\":null}"))
            }
        }
        let client = makeKeyTestClient()
        _ = try await client.login(email: "person@example.test", password: "test-only")
        let service = OrganizationAPIKeyService(client: client)
        let metadata = try await service.fetchMetadata()
        XCTAssertFalse(metadata.configured)
        XCTAssertNil(metadata.prefix)
        XCTAssertNil(metadata.issuedAt)
        let issued = try await service.rotate()
        XCTAssertEqual(issued.apiKey, "test-only-secret")
        XCTAssertTrue(issued.metadata.configured)
        XCTAssertEqual(issued.metadata.prefix, "adapenyu_test1234")
        XCTAssertNotNil(issued.metadata.issuedAt)
        try await service.revoke()
        XCTAssertEqual(calls, ["GET /api/v1/organization/api-key", "POST /api/v1/organization/api-key/rotate", "DELETE /api/v1/organization/api-key"])
    }

    func testAmbiguousRotationIsNotReplayed() async throws {
        var rotations = 0
        BackendStub.handler = { request in
            if let auth = APIFixtures.auth(request) { return auth }
            rotations += 1
            throw URLError(.timedOut)
        }
        let client = makeKeyTestClient()
        _ = try await client.login(email: "person@example.test", password: "test-only")
        do { _ = try await OrganizationAPIKeyService(client: client).rotate(); XCTFail("Expected timeout") }
        catch { XCTAssertEqual(rotations, 1) }
    }

    func testExplicitUnauthorizedResponseRefreshesBeforeRetrying() async throws {
        var rotations = 0
        BackendStub.handler = { request in
            if let auth = APIFixtures.auth(request) { return auth }
            rotations += 1
            if request.value(forHTTPHeaderField: "Authorization") == "Bearer access" {
                return (401, APIFixtures.data("{\"detail\":\"Expired\"}"))
            }
            return (200, APIFixtures.data("{\"configured\":true,\"prefix\":\"adapenyu_test1234\",\"issued_at\":\"2026-11-17T08:00:00Z\",\"api_key\":\"test-only-secret\"}"))
        }
        let client = makeKeyTestClient()
        _ = try await client.login(email: "person@example.test", password: "test-only")
        let issued = try await OrganizationAPIKeyService(client: client).rotate()
        XCTAssertEqual(issued.apiKey, "test-only-secret")
        XCTAssertEqual(rotations, 2)
    }
}

@MainActor
func makeKeyTestClient() -> APIClient {
    APIClient(baseURL: URL(string: "https://example.test")!, session: BackendStub.session(), credentialStore: MemoryCredentials())
}
