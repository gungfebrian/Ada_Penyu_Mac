import XCTest
@testable import Ada_Penyu_Desktop

@MainActor
final class SettingsNavigationTests: XCTestCase {
    override func tearDown() {
        BackendStub.handler = nil
        BackendStub.responseDelay = nil
        super.tearDown()
    }

    func testEnteringSettingsDismissesTurtleDetails() {
        let store = AppStore(repository: TestTurtleRepository())
        store.select(TestTurtleRepository.turtle)
        XCTAssertNotNil(store.selectedTurtle)
        store.requestNavigation(to: .settings)
        XCTAssertEqual(store.activeSection, .settings)
        XCTAssertNil(store.selectedTurtle)
    }

    func testDirectSectionAssignmentCannotDiscardAnUnsavedKey() async throws {
        let store = try await ownerStore()
        store.activeSection = .settings
        await store.organizationKeySettings.enter()
        await store.organizationKeySettings.rotate()
        store.activeSection = .map
        XCTAssertEqual(store.activeSection, .settings)
        XCTAssertEqual(store.organizationKeySettings.pendingDestination, .map)
        store.organizationKeySettings.cancelNavigation()
        XCTAssertEqual(store.activeSection, .settings)
        XCTAssertNotNil(store.organizationKeySettings.newSecret)
        store.activeSection = .individuals
        store.discardKeyAndNavigate()
        XCTAssertEqual(store.activeSection, .individuals)
        XCTAssertNil(store.organizationKeySettings.newSecret)
    }

    func testAcknowledgedKeyIsClearedOnNavigation() async throws {
        let store = try await ownerStore()
        store.activeSection = .settings
        await store.organizationKeySettings.enter()
        await store.organizationKeySettings.rotate()
        store.organizationKeySettings.acknowledgeSaved()
        store.activeSection = .map
        XCTAssertEqual(store.activeSection, .map)
        XCTAssertNil(store.organizationKeySettings.newSecret)
    }

    func testChangingKeyBlocksNavigationButNotSignOut() async throws {
        let store = try await ownerStore()
        store.activeSection = .settings
        await store.organizationKeySettings.enter()
        BackendStub.responseDelay = { $0.url!.path.hasSuffix("/rotate") ? 0.1 : 0 }
        let operation = Task { await store.organizationKeySettings.rotate() }
        await Task.yield()
        XCTAssertTrue(store.organizationKeySettings.isChanging)
        store.activeSection = .map
        XCTAssertEqual(store.activeSection, .settings)
        store.signOut()
        await operation.value
        XCTAssertFalse(store.isAuthenticated)
        XCTAssertNil(store.organizationKeySettings.newSecret)
    }

    private func ownerStore() async throws -> AppStore {
        BackendStub.handler = { request in
            if let auth = APIFixtures.auth(request) { return auth }
            if request.httpMethod == "POST" {
                return (200, APIFixtures.data("{\"configured\":true,\"prefix\":\"adapenyu_test1234\",\"issued_at\":\"2026-11-17T08:00:00Z\",\"api_key\":\"test-only-secret\"}"))
            }
            return (200, APIFixtures.data("{\"configured\":false,\"prefix\":null,\"issued_at\":null}"))
        }
        let client = makeKeyTestClient()
        _ = try await client.login(email: "person@example.test", password: "test-only")
        return AppStore(client: client)
    }
}
