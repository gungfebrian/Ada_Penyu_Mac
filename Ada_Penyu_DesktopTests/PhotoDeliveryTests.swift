import XCTest
@testable import Ada_Penyu_Desktop

@MainActor
final class PhotoDeliveryTests: XCTestCase {
    private func reference(revision: String = "source-1", signature: String = "one", thumbnail: Bool = true) throws -> PhotoReference {
        let thumb = thumbnail ? """
        {"revision":"jpeg-v1","url":"/thumb","download_url":"https://objects.test/thumb?sig=\(signature)","expires_at":"2099-01-01T00:00:00Z","width":384,"height":256,"content_type":"image/jpeg"}
        """ : "null"
        return try JSONDecoder.api.decode(PhotoReference.self, from: Data("""
        {"id":"10000000-0000-4000-8000-000000000003","revision":"\(revision)","url":"/original","download_url":"https://objects.test/original?sig=\(signature)","uploaded_at":"2026-11-25T00:00:00Z","thumbnail":\(thumb)}
        """.utf8))
    }

    func testCardsFetchThumbnailAndComparisonFetchesOriginal() async throws {
        var requests: [String] = []
        let loader = PhotoDelivery(scope: "account-org-backend") { path in
            requests.append(path)
            return Data(path.utf8)
        }
        let photo = try reference()
        let card = try await loader.data(for: photo, representation: .thumbnail)
        let comparison = try await loader.data(for: photo, representation: .original)
        XCTAssertEqual(card, Data("https://objects.test/thumb?sig=one".utf8))
        XCTAssertEqual(comparison, Data("https://objects.test/original?sig=one".utf8))
        XCTAssertEqual(requests.count, 2)
    }

    func testSignatureRotationReusesBytesButNewRevisionDoesNot() async throws {
        var count = 0
        let loader = PhotoDelivery(scope: "scope") { _ in count += 1; return Data([UInt8(count)]) }
        let first = try await loader.data(for: reference(), representation: .original)
        let rotated = try await loader.data(for: reference(signature: "two"), representation: .original)
        let replaced = try await loader.data(for: reference(revision: "source-2"), representation: .original)
        XCTAssertEqual(first, rotated)
        XCTAssertNotEqual(first, replaced)
        XCTAssertEqual(count, 2)
    }

    func testMissingThumbnailDoesNotDownloadOriginalOnNewServer() async throws {
        var requests = 0
        let loader = PhotoDelivery(scope: "scope") { _ in requests += 1; return Data([1]) }
        let data = try await loader.data(for: reference(thumbnail: false), representation: .thumbnail)
        XCTAssertNil(data)
        XCTAssertEqual(requests, 0)
    }

    func testOldServerKeepsOriginalCompatibility() async throws {
        let photo = try JSONDecoder.api.decode(PhotoReference.self, from: Data("{\"url\":\"/legacy\"}".utf8))
        let loader = PhotoDelivery(scope: "scope") { path in
            XCTAssertEqual(path, "/legacy")
            return Data([1])
        }
        let data = try await loader.data(for: photo, representation: .thumbnail)
        XCTAssertEqual(data, Data([1]))
    }

    func testConcurrentConsumersShareOneDownloadAndClearDiscardsCache() async throws {
        var count = 0
        let loader = PhotoDelivery(scope: "scope") { _ in count += 1; await Task.yield(); return Data([1]) }
        let photo = try reference()
        async let a = loader.data(for: photo, representation: .original)
        async let b = loader.data(for: photo, representation: .original)
        _ = try await (a, b)
        XCTAssertEqual(count, 1)
        loader.clear()
        _ = try await loader.data(for: photo, representation: .original)
        XCTAssertEqual(count, 2)
    }

    func testStorageFailureRenewsOnceAndDoesNotLoop() async throws {
        var attempts = 0
        var renewals = 0
        let loader = PhotoDelivery(scope: "scope") { _ in attempts += 1; throw APIError.http(status: 403, detail: "Expired") }
        let photo = try reference()
        do {
            _ = try await loader.data(for: photo, representation: .original) {
                renewals += 1
                return try self.reference(signature: "two")
            }
            XCTFail("Storage should still fail after bounded retry")
        } catch { XCTAssertEqual((error as? APIError)?.statusCode, 403) }
        XCTAssertEqual(renewals, 1)
        XCTAssertEqual(attempts, 2)
    }
}

extension PhotoDeliveryTests {
    func testReviewDownloadsSignedVariantsAndNeverPersistsSignatures() async throws {
        let logID = AutomaticNotSureQueueTests.logID
        let attemptID = AutomaticNotSureQueueTests.attemptID
        let photoID = AutomaticNotSureQueueTests.photoID
        let turtleID = APIFixtures.turtleID
        let sample = try XCTUnwrap(I3SSampleLibrary.sample(forFilenameOrID: "Amina1_L"))
        let original = try XCTUnwrap(I3SSampleLibrary.loadImage(for: sample)?.tiffRepresentation)
        let metadata = """
        {"attempt_id":"\(attemptID)","queries":[{"side":"right","photo_id":"\(photoID)","photo":{"id":"\(photoID)","revision":"query-v1","url":"/query-proxy","download_url":"https://objects.test/query?sig=private","uploaded_at":"2026-11-25T00:00:00Z"}}],
        "candidates":[{"turtle_id":"\(turtleID)","side":"right","availability":"available","photo":{"id":"\(turtleID)","revision":"source-v1","url":"/original-proxy","download_url":"https://objects.test/original?sig=private","uploaded_at":"2026-11-25T00:00:00Z","thumbnail":{"revision":"jpeg-v1","url":"/thumb-proxy","download_url":"https://objects.test/thumb?sig=private","width":384,"height":256}}}]}
        """
        var imagePaths: [String] = []
        BackendStub.handler = { request in
            if let auth = APIFixtures.auth(request) { return auth }
            let path = request.url!.path
            if request.url?.host == "objects.test" {
                XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
                imagePaths.append(path)
                return (200, original)
            }
            if path.hasSuffix("/photos") { return (200, Data(metadata.utf8)) }
            if path.hasSuffix("/match-results") { return (200, APIFixtures.page(AutomaticNotSureQueueTests.savedMatch)) }
            return (200, Data(AutomaticNotSureQueueTests.sighting.utf8))
        }
        defer { BackendStub.handler = nil }
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = APIClient(baseURL: URL(string: "https://example.test")!, session: BackendStub.session(), credentialStore: MemoryCredentials())
        _ = try await client.login(email: "person@example.test", password: "test-only")
        let store = AppStore(client: client, reviewJournal: NotSureReviewJournal(directory: directory))
        try await store.prepareMobileReview(UUID(uuidString: logID)!)
        let item = try XCTUnwrap(store.escalatedNotSureCases.first)
        let candidate = try XCTUnwrap(item.candidates.first)
        XCTAssertNil(candidate.photo)
        await store.loadNotSureThumbnail(caseID: item.id, candidateID: candidate.id)
        XCTAssertNotNil(store.reviewThumbnails[item.id.uuidString + ":" + candidate.id])
        XCTAssertNil(store.escalatedNotSureCases.first?.candidates.first?.photo)
        try await store.loadNotSureCandidatePhoto(caseID: item.id, candidateID: candidate.id)
        XCTAssertNotNil(store.escalatedNotSureCases.first?.candidates.first?.photo)
        XCTAssertEqual(imagePaths, ["/query", "/thumb", "/original"])
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where file.pathExtension == "json" {
            let journal = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(journal.contains("sig=private"))
            XCTAssertFalse(journal.contains("objects.test"))
        }
    }
}
