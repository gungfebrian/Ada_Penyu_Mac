import XCTest
@testable import Ada_Penyu_Desktop

@MainActor
final class AutomaticNotSureQueueTests: XCTestCase {
    func testQueueUsesServerUnknownFilterInsteadOfFilteringOneMixedPage() async throws {
        var requests: [URLRequest] = []
        BackendStub.handler = { request in
            if let auth = APIFixtures.auth(request) { return auth }
            requests.append(request)
            return (200, APIFixtures.page(""))
        }
        defer { BackendStub.handler = nil }
        let client = APIClient(baseURL: URL(string: "https://example.test")!, session: BackendStub.session(), credentialStore: MemoryCredentials())
        _ = try await client.login(email: "person@example.test", password: "test-only")
        _ = try await RemoteTurtleRepository(client: client).listPendingSightings(limit: 50)
        XCTAssertEqual(requests.count, 1)
        let query = URLComponents(url: try XCTUnwrap(requests.first?.url), resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(query?.first(where: { $0.name == "unidentified_only" })?.value, "true")
    }
    static let logID = "20000000-0000-4000-8000-000000000001"
    static let photoID = "20000000-0000-4000-8000-000000000002"
    static let attemptID = "20000000-0000-4000-8000-000000000003"
    static var sighting: String { """
    {"id":"\(logID)","turtle_id":null,"is_draft":false,"observed_at":"2026-11-01T00:00:00Z",
    "location":{"name":"Reef","coordinates":null},"notes":"Keep this note",
    "photos":[{"id":"\(photoID)","url":"/query-image","side":"right","marking_id":null,"body_spot_id":null}],
    "match_result":{"id":"\(attemptID)"}}
    """ }
    static var match: String { """
    {"id":"\(attemptID)","log_id":"\(logID)","created_at":"2026-11-01T00:00:00Z",
    "query_sides":["right"],"match_state":"likely_match","agreed":null,"gallery_size":1,
    "candidates":[{"rank":1,"confidence":0.85,"above_threshold":true,"turtle":\(APIFixtures.profile.replacingOccurrences(of: "\"right\":null", with: "\"right\":{\"url\":\"/candidate-image\",\"uploaded_at\":\"2026-01-01T00:00:00Z\"}"))}]}
    """ }

    static var savedMatch: String { """
    {"id":"\(attemptID)","created_at":"2026-11-01T00:00:00Z",
    "query_sides":["right"],"match_state":"likely_match","agreed":null,"gallery_size":1,
    "candidates":[{"turtle_id":"\(APIFixtures.turtleID)","name":"Amina","profile_code":"000123","rank":1,"confidence":0.85,"above_threshold":true}]}
    """ }

    func testMetadataQueueLoadsWithoutPhotosOrMatchingAndPreservesPagination() async throws {
        var calls: [String] = []
        BackendStub.handler = { request in
            if let auth = APIFixtures.auth(request) { return auth }
            calls.append(request.url!.path)
            return (200, APIFixtures.page(Self.sighting, total: 75))
        }
        defer { BackendStub.handler = nil }
        let client = APIClient(baseURL: URL(string: "https://example.test")!, session: BackendStub.session(), credentialStore: MemoryCredentials())
        _ = try await client.login(email: "person@example.test", password: "test-only")
        let store = AppStore(client: client)
        await store.loadMobileReviewQueue()
        XCTAssertEqual(calls, ["/api/v2/logs"])
        XCTAssertEqual(store.mobileReviewRows.map(\.id), [UUID(uuidString: Self.logID)!])
        XCTAssertTrue(store.escalatedNotSureCases.isEmpty)
        XCTAssertTrue(store.hasMoreMobileReviews)
        XCTAssertEqual(store.mobileReviewRows.first?.headPhotos.first?.side, .right)
    }

    func testSelectedSavedAttemptLoadsQueryOnlyAndConfirmationFailureStaysPending() async throws {
        var calls: [String] = []
        var allowConfirmation = false
        let image = try XCTUnwrap(I3SSampleLibrary.sample(forFilenameOrID: "Amina1_L"))
        let bytes = try XCTUnwrap(I3SSampleLibrary.loadImage(for: image)?.tiffRepresentation)
        BackendStub.handler = { request in
            if let auth = APIFixtures.auth(request) { return auth }
            let path = request.url!.path
            if path.contains("/match-results/") && path.hasSuffix("/photos") { return (404, APIFixtures.data("{}")) }
            calls.append("\(request.httpMethod!) \(path)")
            if path.hasSuffix("/identification") {
                XCTAssertEqual(request.httpMethod, "PUT")
                let body = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: String]
                XCTAssertEqual(body?["attempt_id"]?.lowercased(), Self.attemptID)
                XCTAssertEqual(body?["turtle_id"]?.lowercased(), APIFixtures.turtleID)
                return allowConfirmation ? (200, APIFixtures.data("{}")) : (409, APIFixtures.data("{\"detail\":\"Changed on another device\"}"))
            }
            if path.hasSuffix("/queries") { return (200, APIFixtures.data("[{\"side\":\"right\",\"photo_id\":\"\(Self.photoID)\",\"sha256\":\"abc\",\"url\":\"/retained-query\"}]")) }
            if path.hasSuffix("/match-results") { return (200, APIFixtures.page(Self.savedMatch)) }
            if path == "/retained-query" || path == "/candidate-image" || path.hasSuffix("/photos/right") { return (200, bytes) }
            if path == "/api/v2/logs" { return (200, APIFixtures.page(Self.sighting)) }
            return (200, APIFixtures.data(Self.sighting))
        }
        defer { BackendStub.handler = nil }
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = APIClient(baseURL: URL(string: "https://example.test")!, session: BackendStub.session(), credentialStore: MemoryCredentials())
        _ = try await client.login(email: "person@example.test", password: "test-only")
        let store = AppStore(client: client, reviewJournal: NotSureReviewJournal(directory: directory))
        await store.loadMobileReviewQueue()
        let id = UUID(uuidString: Self.logID)!
        try await store.prepareMobileReview(id)
        let item = try XCTUnwrap(store.escalatedNotSureCases.first)
        XCTAssertEqual(item.side, .right)
        XCTAssertEqual(item.matchAttemptID?.uuidString.lowercased(), Self.attemptID)
        XCTAssertFalse(calls.contains(where: { $0.contains("rematch") || $0.contains("individuals/") }))
        XCTAssertEqual(item.note, "Keep this note")
        try await store.loadNotSureCandidatePhoto(caseID: item.id, candidateID: APIFixtures.turtleID.uppercased())
        do {
            try await store.resolveNotSureCaseAndSyncBackend(item.id, action: .recommend(APIFixtures.turtleID.uppercased(), note: "Same turtle"))
            XCTFail("Conflict must be surfaced")
        } catch {}
        XCTAssertEqual(store.escalatedNotSureCases.first?.decision, .pending)
        XCTAssertTrue(calls.contains("PUT /api/v2/logs/\(Self.logID)/identification"))
        allowConfirmation = true
        try await store.resolveNotSureCaseAndSyncBackend(item.id, action: .recommend(APIFixtures.turtleID.uppercased(), note: "Same turtle"))
        XCTAssertEqual(store.escalatedNotSureCases.first?.decision, .recommendedMatch)
        XCTAssertTrue(store.mobileReviewRows.isEmpty)

    }

    func testAmbiguousSavedPhotoRequiresExplicitChoiceAndCreatesProvenanceForThatChoice() async throws {
        let ambiguous = Self.sighting.replacingOccurrences(of: "\"side\":\"right\"", with: "\"side\":null")
        var matches = 0
        let bytes = try XCTUnwrap(I3SSampleLibrary.loadImage(for: XCTUnwrap(I3SSampleLibrary.sample(forFilenameOrID: "Amina1_L")))?.tiffRepresentation)
        BackendStub.handler = { request in
            if let auth = APIFixtures.auth(request) { return auth }
            let path = request.url!.path
            if path.contains("/match-results/") && path.hasSuffix("/photos") { return (404, APIFixtures.data("{}")) }
            if path.hasSuffix("/rematch") {
                matches += 1
                return (200, APIFixtures.data(Self.match))
            }
            if path.hasSuffix("/queries") { return (200, APIFixtures.data(matches == 0 ? "[]" : "[{\"side\":\"right\",\"photo_id\":\"\(Self.photoID)\",\"url\":\"/retained-query\"}]")) }
            if path.hasSuffix("/match-results") { return (200, APIFixtures.page(Self.savedMatch)) }
            if path == "/retained-query" { return (200, bytes) }
            return (200, APIFixtures.data(ambiguous))
        }
        defer { BackendStub.handler = nil }
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = APIClient(baseURL: URL(string: "https://example.test")!, session: BackendStub.session(), credentialStore: MemoryCredentials())
        _ = try await client.login(email: "person@example.test", password: "test-only")
        let store = AppStore(client: client, reviewJournal: NotSureReviewJournal(directory: directory))
        let id = UUID(uuidString: Self.logID)!
        do { try await store.prepareMobileReview(id); XCTFail("Must ask for side") }
        catch { XCTAssertTrue(error is ReviewInputSelectionRequired) }
        XCTAssertEqual(matches, 0)
        try await store.prepareMobileReview(id, inputs: [ReviewQueryInput(photoID: UUID(uuidString: Self.photoID), side: .right, file: nil)])
        XCTAssertEqual(matches, 1)
        XCTAssertEqual(store.escalatedNotSureCases.first?.side, .right)
    }

    func testFailedSelectedRematchRetriesTheSameManifestWithoutUploadingSourcePhotos() async throws {
        let unsaved = Self.sighting.replacingOccurrences(of: "{\"id\":\"\(Self.attemptID)\"}", with: "null")
        var manifests: [String] = []
        let bytes = try XCTUnwrap(I3SSampleLibrary.loadImage(for: XCTUnwrap(I3SSampleLibrary.sample(forFilenameOrID: "Amina1_L")))?.tiffRepresentation)
        BackendStub.handler = { request in
            if let auth = APIFixtures.auth(request) { return auth }
            let path = request.url!.path
            if path.contains("/match-results/") && path.hasSuffix("/photos") { return (404, APIFixtures.data("{}")) }
            if path.hasSuffix("/rematch") {
                let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
                manifests.append(body.components(separatedBy: "\r\n\r\n").dropFirst().first?.components(separatedBy: "\r\n--").first ?? "")
                XCTAssertFalse(body.contains("filename="))
                if manifests.count == 1 { return (503, APIFixtures.data("{\"detail\":\"Try again\"}")) }
                return (200, APIFixtures.data(Self.match))
            }
            if path.hasSuffix("/queries") { return (200, APIFixtures.data("[{\"side\":\"right\",\"photo_id\":\"\(Self.photoID)\",\"url\":\"/retained-query\"}]")) }
            if path == "/retained-query" { return (200, bytes) }
            return (200, APIFixtures.data(unsaved))
        }
        defer { BackendStub.handler = nil }
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = APIClient(baseURL: URL(string: "https://example.test")!, session: BackendStub.session(), credentialStore: MemoryCredentials())
        _ = try await client.login(email: "person@example.test", password: "test-only")
        let store = AppStore(client: client, reviewJournal: NotSureReviewJournal(directory: directory))
        do { try await store.prepareMobileReview(UUID(uuidString: Self.logID)!); XCTFail("First attempt fails") } catch {}
        XCTAssertTrue(store.escalatedNotSureCases.isEmpty)
        try await store.prepareMobileReview(UUID(uuidString: Self.logID)!)
        XCTAssertEqual(manifests.count, 2)
        XCTAssertFalse(manifests[0].isEmpty)
        let retryPayload = try JSONSerialization.jsonObject(with: Data(manifests[1].utf8)) as? NSDictionary
        let firstPayload = try JSONSerialization.jsonObject(with: Data(manifests[0].utf8)) as? NSDictionary
        XCTAssertEqual(firstPayload, retryPayload)
        let command = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(manifests[0].utf8)) as? [String: Any])
        XCTAssertNotNil(UUID(uuidString: command["attempt_id"] as? String ?? ""))
        let input = try XCTUnwrap((command["inputs"] as? [[String: Any]])?.first)
        XCTAssertEqual((input["photo_id"] as? String)?.lowercased(), Self.photoID)
        XCTAssertEqual(input["side"] as? String, "right")
    }

    func testQueueResponseAfterSignOutCannotRestorePrivateRows() async throws {
        let started = expectation(description: "Queue request started")
        BackendStub.handler = { request in
            if let auth = APIFixtures.auth(request) { return auth }
            started.fulfill()
            return (200, APIFixtures.page(Self.sighting))
        }
        BackendStub.responseDelay = { $0.url!.path == "/api/v2/logs" ? 0.15 : 0 }
        defer { BackendStub.handler = nil; BackendStub.responseDelay = nil }
        let client = APIClient(baseURL: URL(string: "https://example.test")!, session: BackendStub.session(), credentialStore: MemoryCredentials())
        _ = try await client.login(email: "person@example.test", password: "test-only")
        let store = AppStore(client: client)
        let load = Task { await store.loadMobileReviewQueue() }
        await fulfillment(of: [started], timeout: 2)
        store.signOut()
        await load.value
        XCTAssertTrue(store.mobileReviewRows.isEmpty)
        XCTAssertFalse(store.isSyncingMobileQueue)
        XCTAssertNil(store.notSureQueueError)
    }

    func testLoadMoreUsesNextOffsetAndDeduplicatesRowsWithoutPreparingCases() async throws {
        var offsets: [String?] = []
        let second = Self.sighting.replacingOccurrences(of: Self.logID, with: "20000000-0000-4000-8000-000000000004")
        BackendStub.handler = { request in
            if let auth = APIFixtures.auth(request) { return auth }
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
            let offset = query?.first(where: { $0.name == "offset" })?.value
            offsets.append(offset)
            return (200, APIFixtures.page(offset == "0" ? Self.sighting : Self.sighting + "," + second, total: 3, offset: offset == "0" ? 0 : 1))
        }
        defer { BackendStub.handler = nil }
        let client = APIClient(baseURL: URL(string: "https://example.test")!, session: BackendStub.session(), credentialStore: MemoryCredentials())
        _ = try await client.login(email: "person@example.test", password: "test-only")
        let store = AppStore(client: client)
        await store.loadMobileReviewQueue()
        await store.loadMobileReviewQueue(loadMore: true)
        XCTAssertEqual(offsets, ["0", "1"])
        XCTAssertEqual(store.mobileReviewRows.count, 2)
        XCTAssertFalse(store.hasMoreMobileReviews)
        XCTAssertTrue(store.escalatedNotSureCases.isEmpty)
    }

    func testAnnotationsStayForSameEvidenceAndClearWhenQueryChanges() throws {
        let photo = NotSureReviewPhoto(data: Data([1, 2, 3]))
        let candidate = EscalatedNotSureCandidate(id: "candidate", rank: 1, name: "Amina", profileCode: "000123",
            side: .right, sideMatches: true, dateText: "", location: "", confidencePercent: 85,
            photo: nil, sampleImageName: nil, fingerprint: nil, isBundledExample: false)
        var item = EscalatedNotSureCase(title: "Reef", side: .right, photo: photo, companion: nil,
            queryFingerprint: nil, queryROI: [], candidates: [candidate], submittedBy: "Patrol", isExample: false)
        let anchor = ManualAnchorPair(label: "A", queryPoint: ScalePoint(x: 0.2, y: 0.3), candidatePoint: ScalePoint(x: 0.4, y: 0.5))
        try item.apply(.saveManualAnchors(candidateID: "candidate", anchors: [anchor]))
        try item.apply(.saveNote("Keep my notes"))
        item.replaceQueryEvidence(side: .right, photo: photo, companion: nil)
        XCTAssertEqual(item.manualAnchors(for: "candidate").count, 1)
        item.replaceQueryEvidence(side: .right, photo: NotSureReviewPhoto(data: Data([4, 5, 6])), companion: nil)
        XCTAssertTrue(item.manualAnchors(for: "candidate").isEmpty)
        XCTAssertEqual(item.note, "Keep my notes")
    }

    func testChangedQueueRowAdjustsOffsetBeforeLoadingMore() async throws {
        var offsets: [String] = []
        let second = Self.sighting.replacingOccurrences(of: Self.logID, with: "20000000-0000-4000-8000-000000000004")
        BackendStub.handler = { request in
            if let auth = APIFixtures.auth(request) { return auth }
            if request.url!.path == "/api/v2/logs" {
                let offset = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.first(where: { $0.name == "offset" })!.value!
                offsets.append(offset)
                return (200, APIFixtures.page(Self.sighting + "," + second, total: 3))
            }
            return (200, APIFixtures.data(Self.sighting.replacingOccurrences(of: "\"turtle_id\":null", with: "\"turtle_id\":\"\(APIFixtures.turtleID)\"")))
        }
        defer { BackendStub.handler = nil }
        let client = APIClient(baseURL: URL(string: "https://example.test")!, session: BackendStub.session(), credentialStore: MemoryCredentials())
        _ = try await client.login(email: "person@example.test", password: "test-only")
        let store = AppStore(client: client)
        await store.loadMobileReviewQueue()
        do { try await store.prepareMobileReview(UUID(uuidString: Self.logID)!); XCTFail("Changed row must not match") } catch {}
        await store.loadMobileReviewQueue(loadMore: true)
        XCTAssertEqual(offsets, ["0", "1"], "Removing a preceding row shifts the server offset")
    }

    func testNewCropUsesMatchingSideAndFreshAttemptWhileExplicitRetryReusesPayload() async throws {
        let leftID = "20000000-0000-4000-8000-000000000005"
        let paired = Self.sighting.replacingOccurrences(of: "\"photos\":[", with: "\"photos\":[{\"id\":\"\(leftID)\",\"url\":\"/left-query\",\"side\":\"left\"},")
        let bytes = try XCTUnwrap(I3SSampleLibrary.loadImage(for: XCTUnwrap(I3SSampleLibrary.sample(forFilenameOrID: "Amina1_L")))?.tiffRepresentation)
        var commands: [[String: Any]] = []
        BackendStub.handler = { request in
            if let auth = APIFixtures.auth(request) { return auth }
            let path = request.url!.path
            if path.contains("/match-results/") && path.hasSuffix("/photos") { return (404, APIFixtures.data("{}")) }
            if path.hasSuffix("/rematch") {
                let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
                let json = body.components(separatedBy: "\r\n\r\n").dropFirst().first?.components(separatedBy: "\r\n--").first ?? ""
                commands.append((try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] ?? [:])
                return (503, APIFixtures.data("{\"detail\":\"Unavailable\"}"))
            }
            if path.hasSuffix("/match-results") { return (200, APIFixtures.page(Self.savedMatch)) }
            if path.hasSuffix("/queries") { return (200, APIFixtures.data("[]")) }
            if path == "/retained-query" || path == "/query-image" || path == "/left-query" { return (200, bytes) }
            return (200, APIFixtures.data(paired))
        }
        defer { BackendStub.handler = nil }
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = APIClient(baseURL: URL(string: "https://example.test")!, session: BackendStub.session(), credentialStore: MemoryCredentials())
        _ = try await client.login(email: "person@example.test", password: "test-only")
        let store = AppStore(client: client, reviewJournal: NotSureReviewJournal(directory: directory))
        let id = UUID(uuidString: Self.logID)!
        try await store.prepareMobileReview(id)
        XCTAssertEqual(store.escalatedNotSureCases.first?.side, .right, "Legacy snapshots retain their recorded query side")
        do { try await store.findNotSureCandidates(for: id, overridePhotoData: Data([1]), usePairedSide: true) } catch {}
        do { try await store.findNotSureCandidates(for: id, overridePhotoData: Data([2])) } catch {}
        do { try await store.findNotSureCandidates(for: id, retryPreviousAttempt: true) } catch {}
        XCTAssertEqual(commands.count, 3)
        let inputs = try XCTUnwrap(commands[0]["inputs"] as? [[String: Any]])
        let crop = try XCTUnwrap(inputs.first(where: { $0["file"] as? String == "query_1" }))
        XCTAssertEqual(crop["side"] as? String, "right")
        XCTAssertEqual((crop["photo_id"] as? String)?.lowercased(), Self.photoID)
        XCTAssertNotEqual(commands[0]["attempt_id"] as? String, commands[1]["attempt_id"] as? String)
        XCTAssertEqual(commands[1] as NSDictionary, commands[2] as NSDictionary)
    }

}
