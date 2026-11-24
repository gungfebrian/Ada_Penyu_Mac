import AppKit
import XCTest
@testable import Ada_Penyu_Desktop

@MainActor
final class NotSureReviewTests: XCTestCase {
    func testDecisionsSurviveReloadAndStayInTheirAccount() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = NotSureReviewJournal(directory: directory)
        var item = try makeCase()
        try item.apply(.rejectCandidate("candidate"))
        XCTAssertThrowsError(try item.apply(.recommend("candidate", note: "Looked at the edge")))
        try item.apply(.restoreCandidate("candidate"))
        try item.apply(.recommend("candidate", note: "Matched the three visible junctions."))
        try journal.save(item, scope: "account A")
        let reopenedJournal = NotSureReviewJournal(directory: directory)
        var restored = try XCTUnwrap(reopenedJournal.load(scope: "account A").first)
        XCTAssertEqual(restored.id, item.id)
        XCTAssertEqual(restored.decision, .recommendedMatch)
        XCTAssertEqual(restored.recommendedCandidateID, "candidate")
        XCTAssertEqual(restored.note, "Matched the three visible junctions.")
        XCTAssertNotNil(restored.queryImage)
        XCTAssertTrue(try reopenedJournal.load(scope: "account B").isEmpty)
        try restored.apply(.reopen)
        try restored.apply(.resolveUnknown(note: "Glare hides the identifying scales."))
        try reopenedJournal.save(restored, scope: "account A")
        XCTAssertEqual(try journal.load(scope: "account A").first?.decision, .reviewedUnknown)
        XCTAssertNil(try journal.load(scope: "account A").first?.recommendedCandidateID)
    }

    func testRejectsRecommendationWithoutComparableEvidence() throws {
        var item = try makeCase(candidateSide: .right)
        XCTAssertThrowsError(try item.apply(.recommend("candidate", note: "Wrong side.")))
        item = try makeCase(bundled: true)
        XCTAssertThrowsError(try item.apply(.recommend("candidate", note: "Sample candidate.")))
        item = try makeCase()
        XCTAssertThrowsError(try item.apply(.recommend("missing", note: "")))
        XCTAssertThrowsError(try item.apply(.resolveUnknown(note: "  ")))
        try item.apply(.saveNote("Need a clearer left photo."))
        XCTAssertEqual(item.decision, .pending)
    }

    func testWaitingPhotoUsesTheBackendDownloadURL() {
        let signed = OrganizationLogPhoto(
            id: UUID(),
            url: "/api/v2/logs/log/photos/face",
            downloadURL: "https://cdn.example/face.jpg",
            side: .left,
            markingID: nil,
            bodySpotID: nil
        )
        let stable = OrganizationLogPhoto(id: UUID(), url: "/api/v2/logs/log/photos/face", side: .left, markingID: nil, bodySpotID: nil)
        XCTAssertEqual(signed.fetchPath, "https://cdn.example/face.jpg")
        XCTAssertEqual(stable.fetchPath, "/api/v2/logs/log/photos/face")
    }

    func testWaitingLogUsesTheIOSFacePhotoRule() {
        let face = OrganizationLogPhoto(id: UUID(), url: "/face", side: .left, markingID: nil, bodySpotID: nil)
        let spot = OrganizationLogPhoto(id: UUID(), url: "/spot", side: nil, markingID: nil, bodySpotID: UUID())
        let waiting = OrganizationLog(id: UUID(), observedAt: Date(), locationName: "Reef", notes: nil, turtleID: nil, photos: [face])
        let named = OrganizationLog(id: UUID(), observedAt: Date(), locationName: "Reef", notes: nil, turtleID: UUID(), photos: [face])
        let spotOnly = OrganizationLog(id: UUID(), observedAt: Date(), locationName: "Reef", notes: nil, turtleID: nil, photos: [spot])
        let marked = OrganizationLog(id: UUID(), observedAt: Date(), locationName: "Reef", notes: nil, turtleID: nil, photos: [])
        XCTAssertTrue(OrganizationLog.isWaiting(waiting))
        XCTAssertFalse(OrganizationLog.isWaiting(named))
        XCTAssertFalse(OrganizationLog.isWaiting(spotOnly))
        XCTAssertTrue(OrganizationLog.isWaiting(marked, markedOnThisMac: [marked.id]))
    }

    func testSyncRefreshesWaitingLogsWithoutCreatingALocalCase() async throws {
        let waitingID = UUID()
        let faceID = UUID()
        let identifiedID = UUID()
        let waiting = waitingLogJSON(id: waitingID, faceID: faceID, turtleID: nil)
        let identified = waitingLogJSON(id: identifiedID, faceID: UUID(), turtleID: UUID())
        BackendStub.handler = { request in
            if let auth = APIFixtures.auth(request) { return auth }
            guard request.url?.path == "/api/v2/logs" else { return (200, APIFixtures.page(APIFixtures.profile)) }
            let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            XCTAssertEqual(items.first { $0.name == "identified_only" }?.value, "false")
            return (200, APIFixtures.page("\(waiting),\(identified)", total: 2))
        }
        defer { BackendStub.handler = nil }
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = APIClient(baseURL: URL(string: "https://example.test")!, session: BackendStub.session(), credentialStore: MemoryCredentials())
        let store = AppStore(client: client, reviewJournal: NotSureReviewJournal(directory: directory))
        try await store.signIn(email: "person@example.test", password: "test-only-password", rememberMe: false)
        XCTAssertEqual(store.waitingLogs.count, 1)
        XCTAssertEqual(store.waitingLogs.map(\.id), [waitingID])
        XCTAssertTrue(store.escalatedNotSureCases.isEmpty)
        let synced = await store.syncMobilePendingSightings()
        XCTAssertEqual(synced, 1)
        XCTAssertTrue(store.escalatedNotSureCases.isEmpty)
        XCTAssertEqual(store.statusMessage, "1 unidentified sighting")
    }

    func testSignInRestoresTheQueueAfterSignOut() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        BackendStub.handler = { APIFixtures.auth($0) ?? (500, Data()) }
        defer { BackendStub.handler = nil }
        let client = APIClient(baseURL: URL(string: "https://example.test")!, session: BackendStub.session(),
            credentialStore: MemoryCredentials())
        _ = try await client.login(email: "person@example.test", password: "test-only")
        let store = AppStore(client: client, reviewJournal: NotSureReviewJournal(directory: directory))
        let item = try makeCase()
        try store.escalateToNotSureReview(item)
        XCTAssertEqual(store.pendingNotSureCases.map(\.id), [item.id])
        store.signOut()
        XCTAssertTrue(store.escalatedNotSureCases.isEmpty)
        try await store.signIn(email: "person@example.test", password: "test-only", rememberMe: false)
        XCTAssertEqual(store.pendingNotSureCases.map(\.id), [item.id])
    }

    private func waitingLogJSON(id: UUID, faceID: UUID, turtleID: UUID?) -> String {
        let turtle = turtleID.map { "\"\($0.uuidString.lowercased())\"" } ?? "null"
        return """
        {"id":"\(id.uuidString.lowercased())","turtle_id":\(turtle),"observed_at":"2026-01-01T00:00:00Z","location":{"name":"Reef","coordinates":null},"notes":null,"photos":[{"id":"\(faceID.uuidString.lowercased())","url":"/face","side":"left","marking_id":null,"body_spot_id":null}]}
        """
    }

    private func makeCase(candidateSide: TurtlePhotoSide = .left, bundled: Bool = false) throws -> EscalatedNotSureCase {
        let pixels = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let data = try XCTUnwrap(pixels.representation(using: .png, properties: [:]))
        let photo = NotSureReviewPhoto(data: data)
        let candidate = EscalatedNotSureCandidate(id: "candidate", rank: 1, name: "Amina", profileCode: "AP-01",
            side: candidateSide, sideMatches: candidateSide == .left, dateText: "Gallery", location: "Bali",
            confidencePercent: 88, photo: photo, sampleImageName: nil, fingerprint: nil, isBundledExample: bundled)
        return EscalatedNotSureCase(title: "Left field photo", side: .left, photo: photo, companion: nil,
            queryFingerprint: nil, queryROI: [], candidates: [candidate], submittedBy: "Ranger", isExample: false)
    }
}
