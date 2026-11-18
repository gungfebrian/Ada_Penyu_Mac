import XCTest
@testable import Ada_Penyu_Desktop

@MainActor
final class PasswordSecurityTests: XCTestCase {
    override func tearDown() {
        BackendStub.handler = nil
        BackendStub.responseDelay = nil
        super.tearDown()
    }

    func testInvalidInputsSendNoRequest() async throws {
        var changeCalls = 0
        BackendStub.handler = { request in
            if let auth = APIFixtures.auth(request) { return auth }
            if request.url!.path == "/api/v1/auth/change-password" { changeCalls += 1 }
            return (204, Data())
        }
        let store = try await signedInStore()

        // Empty current password
        store.passwordSecurity.currentPassword = ""
        store.passwordSecurity.newPassword = "Valid1!Password"
        store.passwordSecurity.confirmNewPassword = "Valid1!Password"
        var signedOut = false
        let emptyResult = await store.passwordSecurity.submit { signedOut = true }
        XCTAssertFalse(emptyResult)
        XCTAssertEqual(changeCalls, 0)
        XCTAssertNotNil(store.passwordSecurity.errorMessage)

        // Weak password
        store.passwordSecurity.currentPassword = "Old1!Password"
        store.passwordSecurity.newPassword = "weakpass"
        store.passwordSecurity.confirmNewPassword = "weakpass"
        let weakResult = await store.passwordSecurity.submit { signedOut = true }
        XCTAssertFalse(weakResult)
        XCTAssertEqual(changeCalls, 0)
        XCTAssertTrue(store.passwordSecurity.errorMessage?.contains("8 characters") == true)

        // Mismatched confirmation
        store.passwordSecurity.newPassword = "Strong1!Password"
        store.passwordSecurity.confirmNewPassword = "Strong2!Password"
        let mismatchResult = await store.passwordSecurity.submit { signedOut = true }
        XCTAssertFalse(mismatchResult)
        XCTAssertEqual(changeCalls, 0)
        XCTAssertTrue(store.passwordSecurity.errorMessage?.contains("do not match") == true)
        XCTAssertFalse(signedOut)
        XCTAssertTrue(store.isAuthenticated)
    }

    func testDemoAndSignedOutAccountsSendNoRequest() async {
        var changeCalls = 0
        BackendStub.handler = { request in
            if request.url!.path == "/api/v1/auth/change-password" { changeCalls += 1 }
            return (204, Data())
        }
        let store = AppStore(client: makeKeyTestClient())
        XCTAssertFalse(store.passwordSecurity.canChangePassword)
        store.passwordSecurity.currentPassword = "Old1!Password"
        store.passwordSecurity.newPassword = "New1!Password"
        store.passwordSecurity.confirmNewPassword = "New1!Password"
        let signedOutAttempt = await store.passwordSecurity.submit {}
        XCTAssertFalse(signedOutAttempt)
        XCTAssertEqual(changeCalls, 0)

        store.enterDemoWorkspace()
        XCTAssertFalse(store.passwordSecurity.canChangePassword)
        XCTAssertTrue(store.passwordSecurity.accessMessage?.contains("demo") == true)
        store.passwordSecurity.currentPassword = "Old1!Password"
        store.passwordSecurity.newPassword = "New1!Password"
        store.passwordSecurity.confirmNewPassword = "New1!Password"
        let demoAttempt = await store.passwordSecurity.submit {}
        XCTAssertFalse(demoAttempt)
        XCTAssertEqual(changeCalls, 0)
    }

    func testWrongCurrentPasswordReportsInlineAndStaysSignedIn() async throws {
        BackendStub.handler = { request in
            if let auth = APIFixtures.auth(request) { return auth }
            if request.url!.path == "/api/v1/auth/change-password" {
                return (422, APIFixtures.data(#"{"detail":"Wrong current password","code":"CURRENT_PASSWORD_INVALID"}"#))
            }
            return (404, Data())
        }
        let store = try await signedInStore()
        store.passwordSecurity.currentPassword = "Wrong1!Password"
        store.passwordSecurity.newPassword = "New1!Password"
        store.passwordSecurity.confirmNewPassword = "New1!Password"

        let result = await store.passwordSecurity.submit { store.completePasswordChangeSignOut() }
        XCTAssertFalse(result)
        XCTAssertEqual(store.passwordSecurity.currentPasswordError, "Wrong current password")
        XCTAssertTrue(store.isAuthenticated)
        XCTAssertNil(store.sessionNotice)
    }

    func testForbiddenReturnsAccessDeniedWithoutEndingSession() async throws {
        BackendStub.handler = { request in
            if let auth = APIFixtures.auth(request) { return auth }
            if request.url!.path == "/api/v1/auth/change-password" {
                return (403, APIFixtures.data(#"{"detail":"Not permitted"}"#))
            }
            return (404, Data())
        }
        let store = try await signedInStore()
        store.passwordSecurity.currentPassword = "Old1!Password"
        store.passwordSecurity.newPassword = "New1!Password"
        store.passwordSecurity.confirmNewPassword = "New1!Password"

        let result = await store.passwordSecurity.submit { store.completePasswordChangeSignOut() }
        XCTAssertFalse(result)
        XCTAssertEqual(store.passwordSecurity.accessDeniedMessage, "Not permitted")
        XCTAssertTrue(store.isAuthenticated)
    }

    func testSuccessfulPasswordChangeClearsFormSignsOutAndShowsNotice() async throws {
        var capturedPayload: [String: String]?
        BackendStub.handler = { request in
            if let auth = APIFixtures.auth(request) { return auth }
            if request.url!.path == "/api/v1/auth/change-password" {
                XCTAssertEqual(request.httpMethod, "POST")
                if let body = request.bodyData {
                    capturedPayload = try? JSONDecoder().decode([String: String].self, from: body)
                }
                return (204, Data())
            }
            return (404, Data())
        }
        let store = try await signedInStore()
        store.passwordSecurity.currentPassword = "Old1!Password"
        store.passwordSecurity.newPassword = "New1!Password"
        store.passwordSecurity.confirmNewPassword = "New1!Password"
        store.passwordSecurity.isCurrentPasswordVisible = true

        let ok = await store.passwordSecurity.submit { store.completePasswordChangeSignOut() }
        XCTAssertTrue(ok)
        XCTAssertEqual(capturedPayload?["current_password"], "Old1!Password")
        XCTAssertEqual(capturedPayload?["new_password"], "New1!Password")
        XCTAssertEqual(capturedPayload?["confirm_password"], "New1!Password")
        XCTAssertEqual(store.passwordSecurity.currentPassword, "")
        XCTAssertEqual(store.passwordSecurity.newPassword, "")
        XCTAssertEqual(store.passwordSecurity.confirmNewPassword, "")
        XCTAssertFalse(store.passwordSecurity.isCurrentPasswordVisible)
        XCTAssertFalse(store.isAuthenticated)
        XCTAssertEqual(store.sessionNotice, "Password updated. Please sign in with your new password.")
    }

    func testDuplicateSubmitIsSuppressedWhilePending() async throws {
        var calls = 0
        BackendStub.handler = { request in
            if let auth = APIFixtures.auth(request) { return auth }
            if request.url!.path == "/api/v1/auth/change-password" {
                calls += 1
                return (204, Data())
            }
            return (404, Data())
        }
        BackendStub.responseDelay = { $0.url!.path.hasSuffix("/change-password") ? 0.12 : 0 }
        let store = try await signedInStore()
        store.passwordSecurity.currentPassword = "Old1!Password"
        store.passwordSecurity.newPassword = "New1!Password"
        store.passwordSecurity.confirmNewPassword = "New1!Password"

        let first = Task { await store.passwordSecurity.submit { store.completePasswordChangeSignOut() } }
        await Task.yield()
        let second = await store.passwordSecurity.submit { store.completePasswordChangeSignOut() }
        XCTAssertFalse(second)
        let firstResult = await first.value
        XCTAssertTrue(firstResult)
        XCTAssertEqual(calls, 1)
    }

    func testSessionChangeDuringInFlightPasswordChangeNeverSignsOutNewAccount() async throws {
        var currentUserID = APIFixtures.userID
        BackendStub.handler = { request in
            if request.url!.path == "/api/v1/me" {
                return (200, APIFixtures.data("{\"id\":\"\(currentUserID)\",\"organization_id\":\"\(APIFixtures.orgID)\",\"full_name\":\"User\",\"email\":\"user@example.test\",\"status\":\"active\",\"role\":\"owner\",\"is_self\":true}"))
            }
            if request.url!.path == "/api/v1/organization" {
                return (200, APIFixtures.data("{\"id\":\"\(APIFixtures.orgID)\",\"name\":\"Conservation\",\"owner_user_id\":\"\(currentUserID)\"}"))
            }
            if let auth = APIFixtures.auth(request) { return auth }
            if request.url!.path == "/api/v1/auth/change-password" {
                return (204, Data())
            }
            return (404, Data())
        }
        BackendStub.responseDelay = { $0.url!.path.hasSuffix("/change-password") ? 0.15 : 0 }
        let store = try await signedInStore()
        store.passwordSecurity.currentPassword = "Old1!Password"
        store.passwordSecurity.newPassword = "New1!Password"
        store.passwordSecurity.confirmNewPassword = "New1!Password"

        let inFlight = Task { await store.passwordSecurity.submit { store.completePasswordChangeSignOut() } }
        await Task.yield()

        // Switch session to a different account before the first request completes
        currentUserID = "10000000-0000-4000-8000-000000000099"
        store.enterDemoWorkspace()
        let result = await inFlight.value

        XCTAssertFalse(result)
        XCTAssertTrue(store.isAuthenticated)
        XCTAssertTrue(store.isDemoBypassActive)
        XCTAssertNil(store.sessionNotice)
    }

    private func signedInStore() async throws -> AppStore {
        let client = makeKeyTestClient()
        _ = try await client.login(email: "person@example.test", password: "test-only")
        return AppStore(client: client)
    }
}

private extension URLRequest {
    var bodyData: Data? {
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
