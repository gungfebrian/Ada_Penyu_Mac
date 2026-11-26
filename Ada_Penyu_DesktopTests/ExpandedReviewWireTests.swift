import XCTest
@testable import Ada_Penyu_Desktop

/// These fixtures are HTTP responses from the companion backend's real isolated-DB
/// integration tests, not Swift DTO-generated expectations.
@MainActor
final class ExpandedReviewWireTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "expanded-review-" + name, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    func testBackendRematchResponsesDecodeBothCoverageStages() throws {
        let first = try JSONDecoder.api.decode(ReviewMatchResult.self, from: fixture("rematch70-response"))
        let expanded = try JSONDecoder.api.decode(ReviewMatchResult.self, from: fixture("rematch100-response"))
        XCTAssertEqual(first.review?.coveragePercent, 70)
        XCTAssertEqual(expanded.review?.coveragePercent, 100)
        XCTAssertNotNil(expanded.review?.parentAttemptID)
        XCTAssertFalse(first.candidates.isEmpty)
        XCTAssertFalse(expanded.candidates.isEmpty)
    }

    func testBackendPageBeyondFiftyRetainsAllRemainingCandidatesAndPhotoReferences() throws {
        let page = try JSONDecoder.api.decode(ReviewCandidatePage.self, from: fixture("candidate-page-response"))
        XCTAssertEqual(page.offset, 50)
        XCTAssertEqual(page.total, 53)
        XCTAssertEqual(page.items.map(\.rank), [51, 52, 53])
        XCTAssertEqual(page.review.coveragePercent, 100)
        XCTAssertEqual(page.items.last?.confidence, 0.5)
        XCTAssertNotNil(page.items.first?.turtle.identityPhotos?.left)
    }

    func testBackendReviewStateIncludesDurableRejectionsAndEligibility() throws {
        let state = try JSONDecoder.api.decode(DesktopReviewState.self, from: fixture("review-response"))
        XCTAssertEqual(state.coveragePercent, 100)
        XCTAssertEqual(state.rejectedCandidateIDs.count, 1)
        XCTAssertTrue(state.canCreateNew)
    }

    func testBackendCreationReturnsTheIdentifiedOriginalSighting() throws {
        let sighting = try JSONDecoder.api.decode(MobileReviewSighting.self, from: fixture("new-turtle-response"))
        XCTAssertNotNil(sighting.turtleID)
        XCTAssertFalse(sighting.isDraft)
        XCTAssertEqual(Set(sighting.headPhotos.compactMap(\.side)), Set([.left, .right]))
    }
}
