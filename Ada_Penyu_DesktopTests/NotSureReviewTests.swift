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
