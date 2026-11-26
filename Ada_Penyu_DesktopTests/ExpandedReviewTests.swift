import XCTest
@testable import Ada_Penyu_Desktop

@MainActor
final class ExpandedReviewTests: XCTestCase {
    private let logID = UUID(uuidString: AutomaticNotSureQueueTests.logID)!
    private let firstID = UUID(uuidString: "30000000-0000-4000-8000-000000000001")!
    private let fullID = UUID(uuidString: "30000000-0000-4000-8000-000000000002")!
    private var turtleID: UUID { UUID(uuidString: APIFixtures.turtleID)! }

    private func state(_ percent: Int = 70, rejected: Bool = false, total: Int = 1) -> String {
        """
        {"coverage_percent":\(percent),"candidate_total":\(total),"eligible_count":\(total),"compared_count":\(total),
        "excluded_count":0,"parent_attempt_id":null,"rejected_candidate_ids":[\(rejected ? "\"\(turtleID.uuidString)\"" : "")],"can_create_new":\(percent == 100 && rejected)}
        """
    }
    private func result(_ id: UUID, coverage: Int = 70) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: APIFixtures.data(AutomaticNotSureQueueTests.match)) as? [String: Any])
        object["id"] = id.uuidString
        object["review"] = try JSONSerialization.jsonObject(with: APIFixtures.data(state(coverage)))
        object["queries"] = [["side":"right", "photo_id":AutomaticNotSureQueueTests.photoID, "url":"/retained-query"]]
        return try JSONSerialization.data(withJSONObject: object)
    }
    private func image() throws -> Data {
        try XCTUnwrap(I3SSampleLibrary.loadImage(for: XCTUnwrap(I3SSampleLibrary.sample(forFilenameOrID: "Amina1_L")))?.tiffRepresentation)
    }
    private func store() async throws -> AppStore {
        let client = APIClient(baseURL: URL(string: "https://example.test")!, session: BackendStub.session(), credentialStore: MemoryCredentials())
        _ = try await client.login(email: "person@example.test", password: "test-only")
        return AppStore(client: client, reviewJournal: NotSureReviewJournal(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)))
    }
    private func fallback(_ request: URLRequest, bytes: Data, reviewState: String) -> (Int, Data) {
        if let auth = APIFixtures.auth(request) { return auth }
        let path = request.url!.path
        if path.hasSuffix("/photos") { return (404, APIFixtures.data("{}")) }
        if path.hasSuffix("/review") { return (200, APIFixtures.data(reviewState)) }
        if path.hasSuffix("/queries") { return (200, APIFixtures.data("[{\"side\":\"right\",\"photo_id\":\"\(AutomaticNotSureQueueTests.photoID)\",\"url\":\"/retained-query\"}]")) }
        if path == "/api/v2/logs" { return (200, APIFixtures.page(AutomaticNotSureQueueTests.sighting)) }
        if path.hasSuffix("/match-results") { return (200, APIFixtures.page(AutomaticNotSureQueueTests.savedMatch)) }
        if path == "/retained-query" || path.hasSuffix("/photos/right") || path == "/candidate-image" { return (200, bytes) }
        return (200, APIFixtures.data(AutomaticNotSureQueueTests.sighting))
    }

    func testDesktopCoverageIsIndependentOfFirstPageLimitAndParentIsEncoded() throws {
        let command = ReviewRematchCommand(attemptID: firstID,
            inputs: [ReviewQueryInput(photoID: UUID(uuidString: AutomaticNotSureQueueTests.photoID), side: .right, file: nil)],
            reviewCoverage: 100, parentAttemptID: fullID)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(command)) as? [String: Any])
        XCTAssertEqual(json["review_coverage"] as? Int, 100)
        XCTAssertEqual(json["limit"] as? Int, 8)
        XCTAssertEqual(json["parent_attempt_id"] as? String, fullID.uuidString)
    }

    func testLegacyMobileSnapshotStartsASeventyPercentDesktopAttempt() async throws {
        let bytes = try image(); var manifests: [String] = []
        BackendStub.handler = { request in
            if request.url!.path.hasSuffix("/rematch") {
                manifests.append(String(data: request.httpBody ?? Data(), encoding: .utf8) ?? "")
                return (200, try self.result(self.firstID))
            }
            return self.fallback(request, bytes: bytes, reviewState: self.state())
        }
        defer { BackendStub.handler = nil }
        let store = try await store()
        try await store.prepareMobileReview(logID)
        try await store.startDesktopReviewIfNeeded(try XCTUnwrap(store.escalatedNotSureCases.first?.id))
        XCTAssertEqual(manifests.count, 1)
        XCTAssertTrue(manifests[0].contains("\"review_coverage\":70"))
        XCTAssertEqual(store.escalatedNotSureCases.first?.desktopReview?.coveragePercent, 70)
        XCTAssertEqual(store.escalatedNotSureCases.first?.matchAttemptID, firstID)
    }

    func testCameraMatchWithoutPhotoIDUsesTheSightingHeadPhoto() async throws {
        let bytes = try image()
        var manifests: [String] = []
        BackendStub.handler = { request in
            if request.url!.path.hasSuffix("/rematch") {
                manifests.append(String(data: request.httpBody ?? Data(), encoding: .utf8) ?? "")
                return (200, try self.result(self.firstID))
            }
            if request.url!.path.hasSuffix("/queries") {
                return (200, APIFixtures.data("[{\"side\":\"right\",\"photo_id\":null,\"url\":\"/retained-query\"}]"))
            }
            return self.fallback(request, bytes: bytes, reviewState: self.state())
        }
        defer { BackendStub.handler = nil }
        let store = try await store()
        try await store.prepareMobileReview(logID)
        try await store.startDesktopReviewIfNeeded(try XCTUnwrap(store.escalatedNotSureCases.first?.id))
        let manifest = try XCTUnwrap(manifests.first)
        XCTAssertTrue(manifest.contains("\"review_coverage\":70"))
        XCTAssertTrue(manifest.lowercased().contains(AutomaticNotSureQueueTests.photoID))
    }

    func testExplicitExpansionUsesParentAndAdoptsServerRejections() async throws {
        let bytes = try image(); var manifests: [String] = []; var expanded = false
        BackendStub.handler = { request in
            if request.url!.path.hasSuffix("/rematch") {
                let manifest = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
                manifests.append(manifest)
                expanded = manifest.contains("\"review_coverage\":100")
                return (200, try self.result(expanded ? self.fullID : self.firstID, coverage: expanded ? 100 : 70))
            }
            return self.fallback(request, bytes: bytes, reviewState: self.state(expanded ? 100 : 70, rejected: expanded))
        }
        defer { BackendStub.handler = nil }
        let store = try await store()
        try await store.prepareMobileReview(logID)
        try await store.startDesktopReviewIfNeeded(try XCTUnwrap(store.escalatedNotSureCases.first?.id))
        let caseID = try XCTUnwrap(store.escalatedNotSureCases.first?.id)
        try await store.expandNotSureReview(caseID)
        XCTAssertEqual(manifests.count, 2)
        XCTAssertTrue(manifests[1].contains(self.firstID.uuidString))
        XCTAssertEqual(store.escalatedNotSureCases.first?.desktopReview?.coveragePercent, 100)
        XCTAssertTrue(store.escalatedNotSureCases.first?.rejectedCandidateIDs.contains(turtleID.uuidString) == true)
    }

    func testFailedRejectDoesNotChangeLocalStateAndRetryReusesDecisionID() async throws {
        let bytes = try image(); var rejectBodies: [Data] = []; var rejected = false
        BackendStub.handler = { request in
            if request.url!.path.hasSuffix("/rematch") { return (200, try self.result(self.firstID)) }
            if request.url!.path.hasSuffix("/review"), request.httpMethod == "PUT" {
                rejectBodies.append(request.httpBody ?? Data())
                if rejectBodies.count == 1 { return (503, APIFixtures.data("{\"detail\":\"Try again\"}")) }
                rejected = true
                return (200, APIFixtures.data(self.state(rejected: true)))
            }
            return self.fallback(request, bytes: bytes, reviewState: self.state(rejected: rejected))
        }
        defer { BackendStub.handler = nil }
        let store = try await store(); try await store.prepareMobileReview(logID)
        try await store.startDesktopReviewIfNeeded(try XCTUnwrap(store.escalatedNotSureCases.first?.id))
        let caseID = try XCTUnwrap(store.escalatedNotSureCases.first?.id)
        do { try await store.setNotSureCandidateRejected(caseID: caseID, candidateID: turtleID.uuidString, rejected: true); XCTFail("Must surface save failure") } catch {}
        XCTAssertTrue(try XCTUnwrap(store.escalatedNotSureCases.first).rejectedCandidateIDs.isEmpty)
        try await store.setNotSureCandidateRejected(caseID: caseID, candidateID: turtleID.uuidString, rejected: true)
        XCTAssertEqual(rejectBodies.count, 2)
        let first = try JSONSerialization.jsonObject(with: rejectBodies[0]) as? NSDictionary
        let retry = try JSONSerialization.jsonObject(with: rejectBodies[1]) as? NSDictionary
        XCTAssertEqual(first, retry)
        XCTAssertTrue(store.escalatedNotSureCases.first?.rejectedCandidateIDs.contains(turtleID.uuidString) == true)
    }
    func testLoadMoreUsesSavedAttemptAndIncludesLowScoreCandidateWithoutOriginalDownload() async throws {
        let bytes = try image(); var offsets: [String?] = []; var photoDownloads = 0
        let secondID = "30000000-0000-4000-8000-000000000099"
        BackendStub.handler = { request in
            let path = request.url!.path
            if path.hasSuffix("/rematch") { return (200, try self.result(self.firstID)) }
            if path.hasSuffix("/candidates") {
                offsets.append(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "offset" }?.value)
                var candidate = try XCTUnwrap((JSONSerialization.jsonObject(with: self.result(self.firstID)) as? [String: Any])?["candidates"] as? [[String:Any]]).first!
                var turtle = candidate["turtle"] as! [String:Any]
                turtle["id"] = secondID; candidate["turtle"] = turtle; candidate["rank"] = 2; candidate["confidence"] = 0.01
                let page: [String:Any] = ["items":[candidate],"total":2,"limit":50,"offset":1,
                    "review":try JSONSerialization.jsonObject(with: APIFixtures.data(self.state(total:2)))]
                return (200, try JSONSerialization.data(withJSONObject:page))
            }
            if path.contains("/individuals/") || path == "/candidate-image" { photoDownloads += 1 }
            return self.fallback(request, bytes:bytes, reviewState:self.state(total:2))
        }
        defer { BackendStub.handler = nil }
        let store = try await store(); try await store.prepareMobileReview(logID)
        let id = try XCTUnwrap(store.escalatedNotSureCases.first?.id)
        try await store.startDesktopReviewIfNeeded(id)
        XCTAssertTrue(store.hasMoreNotSureCandidates(id))
        try await store.loadMoreNotSureCandidates(id)
        XCTAssertEqual(offsets,["1"])
        XCTAssertEqual(store.escalatedNotSureCases.first?.candidates.count,2)
        XCTAssertEqual(store.escalatedNotSureCases.first?.candidates.last?.confidencePercent,1)
        XCTAssertFalse(store.hasMoreNotSureCandidates(id))
        XCTAssertEqual(photoDownloads,0)
    }

    func testNewTurtleFailureStaysPendingAndRetryReusesCreationIdentity() async throws {
        let bytes = try image(); var expanded = false; var bodies: [Data] = []
        BackendStub.handler = { request in
            let path = request.url!.path
            if path.hasSuffix("/rematch") {
                expanded = String(data:request.httpBody ?? Data(),encoding:.utf8)?.contains("\"review_coverage\":100") == true
                return (200,try self.result(expanded ? self.fullID : self.firstID,coverage:expanded ? 100 : 70))
            }
            if path.hasSuffix("/new-turtle") {
                bodies.append(request.httpBody ?? Data())
                return bodies.count == 1 ? (503,APIFixtures.data("{\"detail\":\"Try again\"}")) : (200,APIFixtures.data("{}"))
            }
            return self.fallback(request,bytes:bytes,reviewState:self.state(expanded ? 100 : 70,rejected:expanded))
        }
        defer { BackendStub.handler = nil }
        let store = try await store(); await store.loadMobileReviewQueue(); try await store.prepareMobileReview(logID)
        let id = try XCTUnwrap(store.escalatedNotSureCases.first?.id)
        try await store.startDesktopReviewIfNeeded(id); try await store.expandNotSureReview(id)
        let draft = IndividualDraft(profileCode:"123456",name:"New turtle",species:"green",sex:"unknown",firstSeenAt:Date(timeIntervalSince1970:0))
        do { try await store.createNotSureTurtle(caseID:id,draft:draft,photosAdequate:true,note:"Every reference rejected"); XCTFail("Must surface creation failure") } catch {}
        XCTAssertEqual(store.escalatedNotSureCases.first?.decision,.pending)
        XCTAssertFalse(store.mobileReviewRows.isEmpty)
        try await store.createNotSureTurtle(caseID:id,draft:draft,photosAdequate:true,note:"Every reference rejected")
        XCTAssertEqual(bodies.count,2)
        XCTAssertEqual(try JSONSerialization.jsonObject(with:bodies[0]) as? NSDictionary,try JSONSerialization.jsonObject(with:bodies[1]) as? NSDictionary)
        XCTAssertEqual(store.escalatedNotSureCases.first?.decision,.reviewedUnknown)
        XCTAssertTrue(store.mobileReviewRows.isEmpty)
    }

    func testRejectThenRestoreUsesNewDecisionAndAdoptsServerState() async throws {
        let bytes = try image(); var commands: [[String:Any]] = []; var rejected = false
        BackendStub.handler = { request in
            if request.url!.path.hasSuffix("/rematch") { return (200,try self.result(self.firstID)) }
            if request.url!.path.hasSuffix("/review"), request.httpMethod == "PUT" {
                let command = try XCTUnwrap(JSONSerialization.jsonObject(with:request.httpBody!) as? [String:Any])
                commands.append(command); rejected = command["rejected"] as? Bool == true
                return (200,APIFixtures.data(self.state(rejected:rejected)))
            }
            return self.fallback(request,bytes:bytes,reviewState:self.state(rejected:rejected))
        }
        defer { BackendStub.handler = nil }
        let store = try await store(); try await store.prepareMobileReview(logID)
        let id = try XCTUnwrap(store.escalatedNotSureCases.first?.id)
        try await store.startDesktopReviewIfNeeded(id)
        try await store.setNotSureCandidateRejected(caseID:id,candidateID:turtleID.uuidString,rejected:true)
        try await store.setNotSureCandidateRejected(caseID:id,candidateID:turtleID.uuidString,rejected:false)
        XCTAssertTrue(try XCTUnwrap(store.escalatedNotSureCases.first).rejectedCandidateIDs.isEmpty)
        XCTAssertEqual(commands.count,2)
        XCTAssertNotEqual(commands[0]["decision_id"] as? String,commands[1]["decision_id"] as? String)
        XCTAssertEqual(commands.last?["rejected"] as? Bool,false)
    }

    func testLateRejectResponseAfterSignOutCannotRestoreReviewState() async throws {
        let bytes = try image(); let started = expectation(description:"Reject request started")
        BackendStub.handler = { request in
            if request.url!.path.hasSuffix("/rematch") { return (200,try self.result(self.firstID)) }
            if request.url!.path.hasSuffix("/review"), request.httpMethod == "PUT" {
                started.fulfill(); return (200,APIFixtures.data(self.state(rejected:true)))
            }
            return self.fallback(request,bytes:bytes,reviewState:self.state())
        }
        BackendStub.responseDelay = { $0.httpMethod == "PUT" && $0.url!.path.hasSuffix("/review") ? 0.15 : 0 }
        defer { BackendStub.handler = nil; BackendStub.responseDelay = nil }
        let store = try await store(); try await store.prepareMobileReview(logID)
        let id = try XCTUnwrap(store.escalatedNotSureCases.first?.id)
        try await store.startDesktopReviewIfNeeded(id)
        let task = Task { try await store.setNotSureCandidateRejected(caseID:id,candidateID:turtleID.uuidString,rejected:true) }
        await fulfillment(of:[started],timeout:2)
        store.signOut()
        do { try await task.value; XCTFail("Late private response must be rejected") } catch {}
        XCTAssertTrue(store.escalatedNotSureCases.isEmpty)
    }

    func testUnsupportedBackendDoesNotClaimDesktopCoverageOrChangeLegacySnapshot() async throws {
        let bytes = try image()
        BackendStub.handler = { request in
            if request.url!.path.hasSuffix("/rematch") { return (200,APIFixtures.data(AutomaticNotSureQueueTests.match)) }
            return self.fallback(request,bytes:bytes,reviewState:self.state())
        }
        defer { BackendStub.handler = nil }
        let store = try await store(); try await store.prepareMobileReview(logID)
        let id = try XCTUnwrap(store.escalatedNotSureCases.first?.id)
        do { try await store.startDesktopReviewIfNeeded(id); XCTFail("Old backend must not masquerade as desktop review") }
        catch { XCTAssertTrue(error.localizedDescription.contains("desktop review")) }
        XCTAssertNil(store.escalatedNotSureCases.first?.desktopReview)
        XCTAssertEqual(store.escalatedNotSureCases.first?.matchAttemptID?.uuidString.lowercased(),AutomaticNotSureQueueTests.attemptID)
    }

    func testLegacyServerReviewCannotPretendLocalRejectWasSavedToServer() async throws {
        let bytes = try image()
        BackendStub.handler = { self.fallback($0,bytes:bytes,reviewState:self.state()) }
        defer { BackendStub.handler = nil }
        let store = try await store(); try await store.prepareMobileReview(logID)
        let id = try XCTUnwrap(store.escalatedNotSureCases.first?.id)
        do {
            try await store.setNotSureCandidateRejected(caseID:id,candidateID:turtleID.uuidString,rejected:true)
            XCTFail("Server-backed legacy case needs a desktop attempt before rejection")
        } catch { XCTAssertTrue(error.localizedDescription.contains("desktop review")) }
        XCTAssertTrue(try XCTUnwrap(store.escalatedNotSureCases.first).rejectedCandidateIDs.isEmpty)
    }

    func testPairedExpansionKeepsBothParentSources() async throws {
        let bytes = try image(); var manifests: [[String:Any]] = []; var expanded = false
        let leftID = "30000000-0000-4000-8000-000000000098"
        var sighting = try XCTUnwrap(JSONSerialization.jsonObject(with:APIFixtures.data(AutomaticNotSureQueueTests.sighting)) as? [String:Any])
        var photos = sighting["photos"] as! [[String:Any]]
        photos.append(["id":leftID,"url":"/retained-query","side":"left","marking_id":NSNull(),"body_spot_id":NSNull()]); sighting["photos"] = photos
        let source = try JSONSerialization.data(withJSONObject:sighting)
        BackendStub.handler = { request in
            let path = request.url!.path
            if path == "/api/v2/logs/\(self.logID.uuidString.lowercased())" { return (200,source) }
            if path.hasSuffix("/rematch") {
                let body = String(data:request.httpBody ?? Data(),encoding:.utf8) ?? ""
                let manifest = body.components(separatedBy:"\r\n\r\n").dropFirst().first?.components(separatedBy:"\r\n--").first ?? ""
                let json = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(manifest.utf8)) as? [String:Any]); manifests.append(json)
                expanded = json["review_coverage"] as? Int == 100
                var result = try XCTUnwrap(JSONSerialization.jsonObject(with:self.result(expanded ? self.fullID : self.firstID,coverage:expanded ? 100 : 70)) as? [String:Any])
                result["query_sides"] = ["left","right"]
                result["queries"] = [["side":"left","photo_id":leftID,"url":"/retained-query"],["side":"right","photo_id":AutomaticNotSureQueueTests.photoID,"url":"/retained-query"]]
                return (200,try JSONSerialization.data(withJSONObject:result))
            }
            return self.fallback(request,bytes:bytes,reviewState:self.state(expanded ? 100 : 70))
        }
        defer { BackendStub.handler = nil }
        let store = try await store(); try await store.prepareMobileReview(logID)
        let id = try XCTUnwrap(store.escalatedNotSureCases.first?.id)
        try await store.findNotSureCandidates(for:id,usePairedSide:true)
        try await store.expandNotSureReview(id)
        let inputs = try XCTUnwrap(manifests.last?["inputs"] as? [[String:Any]])
        XCTAssertEqual(Set(inputs.compactMap { $0["side"] as? String }),Set(["left","right"]))
        XCTAssertEqual(inputs.count,2)
        XCTAssertNotNil(store.escalatedNotSureCases.first?.companion)
    }

    func testSeventyPercentRetrySearchesBothHeadPhotos() async throws {
        let bytes = try image()
        let leftID = "30000000-0000-4000-8000-000000000098"
        var sighting = try XCTUnwrap(JSONSerialization.jsonObject(with: APIFixtures.data(AutomaticNotSureQueueTests.sighting)) as? [String: Any])
        var photos = sighting["photos"] as! [[String: Any]]
        photos.append(["id": leftID, "url": "/retained-query", "side": "left", "marking_id": NSNull(), "body_spot_id": NSNull()])
        sighting["photos"] = photos
        let source = try JSONSerialization.data(withJSONObject: sighting)
        var manifest: [String: Any] = [:]
        BackendStub.handler = { request in
            let path = request.url!.path
            if path == "/api/v2/logs/\(self.logID.uuidString.lowercased())" { return (200, source) }
            if path.hasSuffix("/rematch") {
                let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
                let jsonText = body.components(separatedBy: "\r\n\r\n").dropFirst().first?.components(separatedBy: "\r\n--").first ?? ""
                manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(jsonText.utf8)) as? [String: Any])
                var result = try XCTUnwrap(JSONSerialization.jsonObject(with: self.result(self.firstID)) as? [String: Any])
                result["query_sides"] = ["left", "right"]
                result["queries"] = [
                    ["side": "left", "photo_id": leftID, "url": "/retained-query"],
                    ["side": "right", "photo_id": AutomaticNotSureQueueTests.photoID, "url": "/retained-query"]
                ]
                return (200, try JSONSerialization.data(withJSONObject: result))
            }
            return self.fallback(request, bytes: bytes, reviewState: self.state())
        }
        defer { BackendStub.handler = nil }
        let store = try await store()
        try await store.prepareMobileReview(logID)
        let id = try XCTUnwrap(store.escalatedNotSureCases.first?.id)
        try await store.findNotSureCandidates(for: id, reviewCoverage: 70)
        let inputs = try XCTUnwrap(manifest["inputs"] as? [[String: Any]])
        XCTAssertEqual(manifest["review_coverage"] as? Int, 70)
        XCTAssertEqual(Set(inputs.compactMap { $0["side"] as? String }), Set(["left", "right"]))
        XCTAssertEqual(Set(inputs.compactMap { ($0["photo_id"] as? String)?.lowercased() }), Set([leftID, AutomaticNotSureQueueTests.photoID]))
    }

    func testChoosingTheOtherSideLoadsThatCandidatePhoto() async throws {
        let bytes = try image()
        let metadata = """
        {"attempt_id":"\(firstID.uuidString)","queries":[{"side":"right","photo_id":"\(AutomaticNotSureQueueTests.photoID)","photo":{"url":"/retained-query"}}],
        "candidates":[
        {"turtle_id":"\(turtleID.uuidString)","side":"right","availability":"available","photo":{"url":"/candidate-image"}},
        {"turtle_id":"\(turtleID.uuidString)","side":"left","availability":"available","photo":{"url":"/left-candidate"}}]}
        """
        var requested: [String] = []
        BackendStub.handler = { request in
            let path = request.url!.path
            if path.hasSuffix("/left-candidate") {
                requested.append(path)
                return (200, bytes)
            }
            if path.hasSuffix("/photos") { return (200, APIFixtures.data(metadata)) }
            if path.hasSuffix("/rematch") { return (200, try self.result(self.firstID)) }
            return self.fallback(request, bytes: bytes, reviewState: self.state())
        }
        defer { BackendStub.handler = nil }
        let store = try await store()
        try await store.prepareMobileReview(logID)
        let id = try XCTUnwrap(store.escalatedNotSureCases.first?.id)
        try await store.startDesktopReviewIfNeeded(id)
        XCTAssertEqual(store.escalatedNotSureCases.first?.candidates.first?.side, .right)
        try await store.alignNotSureCandidatePhotos(caseID: id, side: .left)
        XCTAssertEqual(store.escalatedNotSureCases.first?.candidates.first?.side, .left)
        XCTAssertEqual(store.escalatedNotSureCases.first?.candidates.first?.photoPath, "/left-candidate")
        XCTAssertEqual(requested, ["/left-candidate"])
    }

    func testNewDesktopPreparationRejectsLegacyRematchResponse() async throws {
        let bytes = try image()
        let unsaved = AutomaticNotSureQueueTests.sighting.replacingOccurrences(of:"{\"id\":\"\(AutomaticNotSureQueueTests.attemptID)\"}",with:"null")
        BackendStub.handler = { request in
            if request.url!.path == "/api/v2/logs/\(self.logID.uuidString.lowercased())" { return (200,APIFixtures.data(unsaved)) }
            if request.url!.path.hasSuffix("/rematch") { return (200,APIFixtures.data(AutomaticNotSureQueueTests.match)) }
            return self.fallback(request,bytes:bytes,reviewState:self.state())
        }
        defer { BackendStub.handler = nil }
        let store = try await store()
        do { try await store.prepareMobileReview(logID); XCTFail("New desktop request must require matching coverage") }
        catch { XCTAssertTrue(error.localizedDescription.contains("desktop review")) }
        XCTAssertTrue(store.escalatedNotSureCases.isEmpty)
    }

    func testSavedDesktopLookupUsesDesktopFilterBeforeNewestMobileAttempt() async throws {
        var filters: [String?] = []
        BackendStub.handler = { request in
            if let auth = APIFixtures.auth(request) { return auth }
            let filter = URLComponents(url:request.url!,resolvingAgainstBaseURL:false)?.queryItems?.first { $0.name == "review_only" }?.value
            filters.append(filter)
            return (200,APIFixtures.page(filter == "true" ? AutomaticNotSureQueueTests.savedDesktopMatch : AutomaticNotSureQueueTests.savedMatch))
        }
        defer { BackendStub.handler = nil }
        let client = APIClient(baseURL:URL(string:"https://example.test")!,session:BackendStub.session(),credentialStore:MemoryCredentials())
        _ = try await client.login(email:"person@example.test",password:"test-only")
        let results = try await RemoteTurtleRepository(client:client).reviewMatchResults(logID:logID)
        XCTAssertEqual(filters,["true"])
        XCTAssertEqual(results.first?.review?.coveragePercent,70)
    }

    func testAuditedSameRetryRetainsDecisionAndReason() async throws {
        let bytes = try image(); var bodies: [Data] = []
        BackendStub.handler = { request in
            if request.url!.path.hasSuffix("/rematch") { return (200,try self.result(self.firstID)) }
            if request.url!.path.hasSuffix("/identification") {
                bodies.append(request.httpBody ?? Data())
                return bodies.count == 1 ? (503,APIFixtures.data("{\"detail\":\"Try again\"}")) : (200,APIFixtures.data("{}"))
            }
            return self.fallback(request,bytes:bytes,reviewState:self.state())
        }
        defer { BackendStub.handler = nil }
        let store = try await store(); await store.loadMobileReviewQueue(); try await store.prepareMobileReview(logID)
        let id = try XCTUnwrap(store.escalatedNotSureCases.first?.id)
        try await store.startDesktopReviewIfNeeded(id)
        try await store.loadNotSureCandidatePhoto(caseID:id,candidateID:turtleID.uuidString)
        let action = NotSureReviewAction.recommend(turtleID.uuidString,note:"Same cheek scales")
        do { try await store.resolveNotSureCaseAndSyncBackend(id,action:action); XCTFail("Must surface audit failure") } catch {}
        XCTAssertEqual(store.escalatedNotSureCases.first?.decision,.pending)
        try await store.resolveNotSureCaseAndSyncBackend(id,action:action)
        XCTAssertEqual(bodies.count,2)
        let command = try XCTUnwrap(JSONSerialization.jsonObject(with:bodies[0]) as? NSDictionary)
        XCTAssertEqual(command,try JSONSerialization.jsonObject(with:bodies[1]) as? NSDictionary)
        XCTAssertNotNil(UUID(uuidString:command["decision_id"] as? String ?? ""))
        XCTAssertEqual(command["note"] as? String,"Same cheek scales")
        XCTAssertTrue(store.mobileReviewRows.isEmpty)
        do { try store.updateNotSureCase(id,action:.reopen); XCTFail("Durable identity must not reopen locally") } catch {}
        XCTAssertEqual(store.escalatedNotSureCases.first?.decision,.recommendedMatch)
    }

    func testCancelledSearchResumesTheSamePendingCommand() async throws {
        let bytes = try image(); var bodies: [Data] = []; let started = expectation(description:"Search started")
        BackendStub.handler = { request in
            if request.url!.path.hasSuffix("/rematch") {
                bodies.append(request.httpBody ?? Data()); if bodies.count == 1 { started.fulfill() }
                return (200,try self.result(self.firstID))
            }
            return self.fallback(request,bytes:bytes,reviewState:self.state())
        }
        BackendStub.responseDelay = { $0.url!.path.hasSuffix("/rematch") && bodies.count == 1 ? 0.15 : 0 }
        defer { BackendStub.handler = nil; BackendStub.responseDelay = nil }
        let store = try await store(); try await store.prepareMobileReview(logID)
        let id = try XCTUnwrap(store.escalatedNotSureCases.first?.id)
        let search = Task { try await store.startDesktopReviewIfNeeded(id) }
        await fulfillment(of:[started],timeout:2); search.cancel()
        do { try await search.value; XCTFail("Stopped wait must cancel local publication") } catch {}
        try await store.startDesktopReviewIfNeeded(id)
        XCTAssertEqual(bodies.count,2)
        func manifest(_ body:Data) throws -> NSDictionary {
            let text = String(data:body,encoding:.utf8) ?? ""
            let value = text.components(separatedBy:"\r\n\r\n").dropFirst().first?.components(separatedBy:"\r\n--").first ?? ""
            return try XCTUnwrap(JSONSerialization.jsonObject(with:Data(value.utf8)) as? NSDictionary)
        }
        XCTAssertEqual(try manifest(bodies[0]),try manifest(bodies[1]))
    }

    func testPageHydrationCannotUndoANewerServerRejection() async throws {
        let bytes = try image(); let suspended = expectation(description:"Page state is in flight")
        var pageStateInFlight = false; var rejected = false
        BackendStub.handler = { request in
            let path = request.url!.path
            if path.hasSuffix("/rematch") { return (200,try self.result(self.firstID)) }
            if path.hasSuffix("/candidates") {
                pageStateInFlight = true
                let object = try XCTUnwrap(JSONSerialization.jsonObject(with:self.result(self.firstID)) as? [String:Any])
                return (200,try JSONSerialization.data(withJSONObject:["items":object["candidates"]!,"total":2,"limit":50,"offset":1,
                    "review":try JSONSerialization.jsonObject(with:APIFixtures.data(self.state(total:2)))]))
            }
            if path.hasSuffix("/review"), request.httpMethod == "PUT" {
                rejected = true; return (200,APIFixtures.data(self.state(rejected:true,total:2)))
            }
            if path.hasSuffix("/review"), pageStateInFlight {
                suspended.fulfill(); return (200,APIFixtures.data(self.state(total:2)))
            }
            return self.fallback(request,bytes:bytes,reviewState:self.state(rejected:rejected,total:2))
        }
        BackendStub.responseDelay = { $0.httpMethod == "GET" && $0.url!.path.hasSuffix("/review") && pageStateInFlight ? 0.15 : 0 }
        defer { BackendStub.handler = nil; BackendStub.responseDelay = nil }
        let store = try await store(); try await store.prepareMobileReview(logID)
        let id = try XCTUnwrap(store.escalatedNotSureCases.first?.id)
        try await store.startDesktopReviewIfNeeded(id)
        let page = Task { try await store.loadMoreNotSureCandidates(id) }
        await fulfillment(of:[suspended],timeout:2)
        try await store.setNotSureCandidateRejected(caseID:id,candidateID:turtleID.uuidString,rejected:true)
        do { try await page.value; XCTFail("Stale hydration must be discarded") } catch {}
        XCTAssertTrue(store.escalatedNotSureCases.first?.rejectedCandidateIDs.contains(turtleID.uuidString) == true)
    }

    func testIneligibleOrInadequateNewTurtleDoesNotIssueCreationRequest() async throws {
        let bytes = try image(); var writes = 0; var expanded = false
        BackendStub.handler = { request in
            if request.url!.path.hasSuffix("/rematch") {
                expanded = String(data:request.httpBody ?? Data(),encoding:.utf8)?.contains("\"review_coverage\":100") == true
                return (200,try self.result(expanded ? self.fullID : self.firstID,coverage:expanded ? 100 : 70))
            }
            if request.url!.path.hasSuffix("/new-turtle") { writes += 1; return (200,APIFixtures.data("{}")) }
            return self.fallback(request,bytes:bytes,reviewState:self.state(expanded ? 100 : 70,rejected:expanded))
        }
        defer { BackendStub.handler = nil }
        let store = try await store(); try await store.prepareMobileReview(logID)
        let id = try XCTUnwrap(store.escalatedNotSureCases.first?.id)
        try await store.startDesktopReviewIfNeeded(id)
        let draft = IndividualDraft(profileCode:"123456",name:"Turtle",species:"green",sex:"unknown",firstSeenAt:Date())
        do { try await store.createNotSureTurtle(caseID:id,draft:draft,photosAdequate:true,note:"Checked"); XCTFail("70% is incomplete") } catch {}
        try await store.expandNotSureReview(id)
        do { try await store.createNotSureTurtle(caseID:id,draft:draft,photosAdequate:false,note:"Checked"); XCTFail("Must acknowledge adequate photos") } catch {}
        XCTAssertEqual(writes,0)
        XCTAssertEqual(store.escalatedNotSureCases.first?.decision,.pending)
    }

    func testStrictOldBackendValidationErrorExplainsDesktopRequirement() async throws {
        let bytes = try image()
        BackendStub.handler = { request in
            if request.url!.path.hasSuffix("/rematch") { return (422,APIFixtures.data("{\"detail\":\"Invalid rematch manifest\"}")) }
            return self.fallback(request,bytes:bytes,reviewState:self.state())
        }
        defer { BackendStub.handler = nil }
        let store = try await store(); try await store.prepareMobileReview(logID)
        let id = try XCTUnwrap(store.escalatedNotSureCases.first?.id)
        do { try await store.startDesktopReviewIfNeeded(id); XCTFail("Must surface old backend contract") }
        catch { XCTAssertTrue(error.localizedDescription.lowercased().contains("desktop review")) }
        XCTAssertNil(store.escalatedNotSureCases.first?.desktopReview)
    }

}
