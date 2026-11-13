import XCTest
@testable import Ada_Penyu_Desktop

@MainActor
final class FilterRaceTests: XCTestCase {
    override func tearDown() { BackendStub.responseDelay = nil; super.tearDown() }

    func testSlowMapResponseCannotOverwriteNewerFilter() async throws {
        let started = expectation(description: "Old map started")
        BackendStub.handler = { request in
            if let auth = APIFixtures.auth(request) { return auth }
            let old = request.url!.query!.contains("green")
            if old { started.fulfill() }
            return (200, APIFixtures.data("""
            {"items":[{"log_id":"\(APIFixtures.turtleID)","name":"\(old ? "old" : "new")","species":"green","timestamp":"2026-11-12T00:00:00Z","place_name":"Test","latitude":0,"longitude":0}]}
            """))
        }
        BackendStub.responseDelay = { $0.url!.query?.contains("green") == true ? 0.2 : 0 }
        let client = APIClient(baseURL: URL(string: "https://example.test")!, session: BackendStub.session(), credentialStore: MemoryCredentials())
        _ = try await client.login(email: "person@example.test", password: "test-only", rememberMe: false)
        let store = AppStore(client: client)
        store.mapSpecies = .green
        let old = Task { await store.reloadMap() }
        await fulfillment(of: [started], timeout: 2)
        store.mapSpecies = .hawksbill
        await store.reloadMap()
        await old.value
        XCTAssertEqual(store.sightings.first?.name, "new")
    }

    func testChangedMapFilterRejectsResponseEvenBeforeNextLoadStarts() async throws {
        let started = expectation(description: "Map started")
        BackendStub.handler = { request in
            if let auth = APIFixtures.auth(request) { return auth }
            started.fulfill()
            return (500, APIFixtures.data("{\"detail\":\"Old filter failed\"}"))
        }
        BackendStub.responseDelay = { $0.url!.path.contains("/map/") ? 0.2 : 0 }
        let client = APIClient(baseURL: URL(string: "https://example.test")!, session: BackendStub.session(), credentialStore: MemoryCredentials())
        _ = try await client.login(email: "person@example.test", password: "test-only", rememberMe: false)
        let store = AppStore(client: client)
        let old = Task { await store.reloadMap() }
        await fulfillment(of: [started], timeout: 2)
        store.mapCondition = .injured
        await old.value
        XCTAssertNil(store.lastError, "An old filter error must not appear under the current filter")
    }
}
