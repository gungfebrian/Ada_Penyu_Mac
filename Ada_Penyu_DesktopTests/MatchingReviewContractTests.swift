import XCTest
@testable import Ada_Penyu_Desktop

@MainActor
final class MatchingReviewContractTests: XCTestCase {
    private let identity = APIFixtures.turtleID

    func testCurrentSingleResponseAndEmptyNoReliableStateDecode() async throws {
        let client = client()
        BackendStub.handler = { request in
            APIFixtures.auth(request) ?? (200, try! JSONSerialization.data(withJSONObject: self.single(side: "left", candidates: [])))
        }
        _ = try await client.login(email: "person@example.test", password: "test-only", rememberMe: false)
        let result = try await RemoteTurtleRepository(client: client).matchPhoto(imageData: Data([1]), side: .left)
        XCTAssertEqual(result.gallerySize, 83)
        XCTAssertEqual(result.matchState, "no_reliable_match")
        XCTAssertTrue(result.candidates.isEmpty)
    }

    func testPairedIdentityOnBothSidesDoesNotCrashAndKeepsCorrectSideEvidence() async throws {
        let client = client()
        let paired: [String: Any] = ["individual_id": identity, "name": "Turtle", "species": "green", "rank": 1,
            "merge_rank_score": 0.85, "confidence": 0.8, "confidence_percent": 80,
            "left": ["rank": 1, "fused_score": 0.8], "right": ["rank": 1, "fused_score": 0.7],
            "photos": ["left": ["url": "/api/v1/left-photo", "capture_date": "2026-11-12T00:00:00Z"],
                       "right": ["url": "/api/v1/right-photo", "capture_date": "2026-11-12T00:00:00Z"]]]
        let response: [String: Any] = ["match_state": "likely_match", "agreed": true, "candidates": [paired],
            "photo_a": single(side: "left", candidates: [candidate(side: "left", points: 31)]),
            "photo_b": single(side: "right", candidates: [candidate(side: "right", points: 9)])]
        BackendStub.handler = { APIFixtures.auth($0) ?? (200, try! JSONSerialization.data(withJSONObject: response)) }
        _ = try await client.login(email: "person@example.test", password: "test-only", rememberMe: false)
        let result = try await RemoteTurtleRepository(client: client).matchPhotoPair(leftData: Data([1]), rightData: Data([2]))
        XCTAssertEqual(result.candidates.count, 1)
        XCTAssertEqual(result.candidates.first?.localMatch, 31)
        XCTAssertEqual(result.candidates.first?.fusedScore, 0.85)
    }

    private func client() -> APIClient {
        APIClient(baseURL: URL(string: "https://example.test")!, session: BackendStub.session(), credentialStore: MemoryCredentials())
    }

    private func single(side: String, candidates: [[String: Any]]) -> [String: Any] {
        ["query": ["side": side, "flipped": false], "gallery_size": 83, "match_state": "no_reliable_match", "candidates": candidates]
    }

    private func candidate(side: String, points: Int) -> [String: Any] {
        ["individual_id": identity, "name": "Turtle", "species": "green", "rank": 1,
         "fused_score": 0.7, "confidence": 0.8, "confidence_percent": 80, "global_score": 0.9,
         "local_match": points, "matched_photo_side": side, "photo_url": "/api/v1/\(side)-photo", "above_threshold": true]
    }
}
