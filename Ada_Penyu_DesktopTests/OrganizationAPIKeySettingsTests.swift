import AppKit
import XCTest
@testable import Ada_Penyu_Desktop

@MainActor
final class OrganizationAPIKeySettingsTests: XCTestCase {
    override func tearDown() {
        BackendStub.handler = nil
        BackendStub.responseDelay = nil
        super.tearDown()
    }

    func testIssuedKeyStartsMaskedAndRequiresAcknowledgementBeforeLeaving() async throws {
        let (model, _) = try await makeSettings()
        await model.enter()
        await model.rotate()
        XCTAssertEqual(model.newSecret, "test-only-secret")
        XCTAssertFalse(model.isSecretRevealed)
        XCTAssertFalse(model.requestLeave(to: .map))
        XCTAssertEqual(model.pendingDestination, .map)
        model.cancelNavigation()
        XCTAssertNil(model.pendingDestination)
        model.acknowledgeSaved()
        XCTAssertTrue(model.requestLeave(to: .map))
        model.leave()
        XCTAssertNil(model.newSecret)
        XCTAssertNil(model.metadata)
    }

    func testDiscardClearsSecretAndRevokeClearsMetadata() async throws {
        let (model, _) = try await makeSettings()
        await model.enter()
        await model.rotate()
        await model.revoke()
        XCTAssertNil(model.newSecret)
        XCTAssertEqual(model.metadata, .unconfigured)
        await model.rotate()
        model.leave()
        XCTAssertNil(model.newSecret)
    }

    func testDemoAndRangerCannotMakeManagementRequests() async throws {
        let (model, client) = try await makeSettings()
        var requests = 0
        BackendStub.handler = { _ in requests += 1; throw URLError(.badServerResponse) }
        model.configure(client: client, user: client.account, isDemo: true)
        await model.enter()
        await model.rotate()
        await model.revoke()
        XCTAssertFalse(model.canManage)
        XCTAssertTrue(model.accessMessage?.contains("demo") == true)
        let owner = try XCTUnwrap(client.account)
        let ranger = AppUser(id: owner.id, email: owner.email, displayName: owner.displayName,
            role: .ranger, organisationID: owner.organisationID, organisationName: owner.organisationName)
        model.configure(client: client, user: ranger, isDemo: false)
        await model.enter()
        await model.rotate()
        XCTAssertFalse(model.canManage)
        XCTAssertTrue(model.accessMessage?.contains("owner") == true)
        XCTAssertEqual(requests, 0)
    }

    func testDuplicateRotationAndNavigationAreBlockedWhileChanging() async throws {
        let (model, _) = try await makeSettings()
        await model.enter()
        BackendStub.responseDelay = { $0.httpMethod == "POST" ? 0.1 : 0 }
        var rotations = 0
        BackendStub.handler = { request in
            if request.httpMethod == "POST" { rotations += 1 }
            return keySettingsResponse(request)
        }
        let first = Task { await model.rotate() }
        await Task.yield()
        XCTAssertTrue(model.isChanging)
        XCTAssertFalse(model.requestLeave(to: .individuals))
        XCTAssertNil(model.pendingDestination)
        await model.rotate()
        await first.value
        XCTAssertEqual(rotations, 1)
        XCTAssertNotNil(model.newSecret)
    }

    func testLateIssuanceCannotRestoreSecretAfterLeavingOrRoleChange() async throws {
        let (model, client) = try await makeSettings()
        await model.enter()
        BackendStub.responseDelay = { $0.httpMethod == "POST" ? 0.1 : 0 }
        let issuing = Task { await model.rotate() }
        await Task.yield()
        model.leave()
        await issuing.value
        XCTAssertNil(model.newSecret)
        XCTAssertNil(model.metadata)
        await model.enter()
        await model.rotate()
        XCTAssertNotNil(model.newSecret)
        model.configure(client: client, user: nil, isDemo: false)
        XCTAssertNil(model.newSecret)
        XCTAssertFalse(model.canManage)
    }

    func testAmbiguousFailureRequiresMetadataReloadAndNeverLeaksServerError() async throws {
        let (model, _) = try await makeSettings()
        await model.enter()
        var rotations = 0
        BackendStub.handler = { request in
            if request.httpMethod == "POST" { rotations += 1; throw URLError(.timedOut) }
            return keySettingsResponse(request)
        }
        await model.rotate()
        XCTAssertEqual(rotations, 1)
        XCTAssertNil(model.metadata)
        XCTAssertTrue(model.errorMessage?.contains("may have") == true)
        await model.rotate()
        XCTAssertEqual(rotations, 1)
        await model.load()
        BackendStub.handler = { _ in (500, APIFixtures.data("{\"detail\":\"do-not-display-secret\"}")) }
        await model.rotate()
        XCTAssertFalse(model.errorMessage?.contains("do-not-display-secret") == true)
    }

    func testForbiddenAndUnavailableMetadataHaveActionableStates() async throws {
        let (model, _) = try await makeSettings()
        BackendStub.handler = { _ in (403, APIFixtures.data("{\"detail\":\"Forbidden\"}")) }
        await model.enter()
        XCTAssertFalse(model.canManage)
        XCTAssertTrue(model.accessMessage?.contains("owner") == true)
        model.leave()
        BackendStub.handler = { _ in (404, APIFixtures.data("{\"detail\":\"Not Found\"}")) }
        await model.enter()
        XCTAssertTrue(model.errorMessage?.contains("not available") == true)
    }

    func testClipboardExpirySurvivesLeavingSettings() async throws {
        let pasteboard = NSPasteboard(name: .init("key-tests-\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        let clipboard = ExpiringSecretClipboard(pasteboard: pasteboard, lifetime: .milliseconds(30))
        let (model, _) = try await makeSettings(clipboard: clipboard)
        await model.enter()
        await model.rotate()
        model.copySecret()
        XCTAssertTrue(model.didCopy)
        XCTAssertEqual(pasteboard.string(forType: .string), "test-only-secret")
        model.leave()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertNil(pasteboard.string(forType: .string))
    }

    func testClipboardExpiryPreservesAnythingCopiedAfterward() async throws {
        let pasteboard = NSPasteboard(name: .init("key-tests-\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        let clipboard = ExpiringSecretClipboard(pasteboard: pasteboard, lifetime: .milliseconds(30))
        XCTAssertTrue(clipboard.copy("test-only-secret"))
        pasteboard.clearContents()
        pasteboard.setString("my-new-copy", forType: .string)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(pasteboard.string(forType: .string), "my-new-copy")
    }

    func testAppStoreSignOutAndDemoEntryClearLiveKeyState() async throws {
        let (_, client) = try await makeSettings()
        let store = AppStore(client: client)
        await store.organizationKeySettings.enter()
        await store.organizationKeySettings.rotate()
        XCTAssertNotNil(store.organizationKeySettings.newSecret)
        store.signOut()
        XCTAssertNil(store.organizationKeySettings.newSecret)
        XCTAssertFalse(store.organizationKeySettings.canManage)
        store.enterDemoWorkspace()
        XCTAssertTrue(store.organizationKeySettings.accessMessage?.contains("demo") == true)
    }

    func testContextChangesReloadPageButTokenRefreshKeepsUnsavedSecret() async throws {
        let (model, client) = try await makeSettings()
        await model.enter()
        await model.rotate()
        let originalVersion = model.contextVersion
        model.configure(client: client, user: client.account, isDemo: false)
        XCTAssertEqual(model.contextVersion, originalVersion)
        XCTAssertNotNil(model.newSecret)
        model.configure(client: client, user: nil, isDemo: false)
        XCTAssertNotEqual(model.contextVersion, originalVersion)
        XCTAssertNil(model.newSecret)
    }

    private func makeSettings(clipboard: ExpiringSecretClipboard? = nil) async throws -> (OrganizationAPIKeySettings, APIClient) {
        BackendStub.handler = { request in APIFixtures.auth(request) ?? keySettingsResponse(request) }
        let client = makeKeyTestClient()
        _ = try await client.login(email: "person@example.test", password: "test-only")
        return (OrganizationAPIKeySettings(client: client, clipboard: clipboard ?? ExpiringSecretClipboard()), client)
    }
}

private func keySettingsResponse(_ request: URLRequest) -> (Int, Data) {
    switch request.httpMethod {
    case "POST": return (200, APIFixtures.data("{\"configured\":true,\"prefix\":\"adapenyu_test1234\",\"issued_at\":\"2026-11-17T08:00:00Z\",\"api_key\":\"test-only-secret\"}"))
    case "DELETE": return (204, Data())
    default: return (200, APIFixtures.data("{\"configured\":false,\"prefix\":null,\"issued_at\":null}"))
    }
}
