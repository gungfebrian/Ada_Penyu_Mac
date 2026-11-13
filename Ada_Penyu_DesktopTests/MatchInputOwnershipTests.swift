import XCTest
@testable import Ada_Penyu_Desktop

@MainActor
final class MatchInputOwnershipTests: XCTestCase {
    func testRightPrimaryCannotBeUsedAsLeftAfterSwitchingToPair() {
        let right = Data([1]), secondary = Data([2])
        let pair = MatchPhotoInputs(primary: right, primarySide: .right,
            secondary: secondary, secondarySide: .right, paired: true)
        XCTAssertFalse(pair.hasValidPair)
        XCTAssertNil(pair.referenceData(for: .left))
    }

    func testOppositeSideSecondaryFixtureCannotReplaceRightReference() {
        let pair = MatchPhotoInputs(primary: Data([1]), primarySide: .left,
            secondary: Data([2]), secondarySide: .left, paired: true)
        XCTAssertFalse(pair.hasValidPair)
        XCTAssertNil(pair.referenceData(for: .right))
    }

    func testValidPairReturnsTheExactCorrespondingPhoto() {
        let pair = MatchPhotoInputs(primary: Data([1]), primarySide: .left,
            secondary: Data([2]), secondarySide: .right, paired: true)
        XCTAssertTrue(pair.hasValidPair)
        XCTAssertEqual(pair.referenceData(for: .right), Data([2]))
        XCTAssertEqual(pair.referenceData(for: .left), Data([1]))
    }

    func testChoosingExamplesRejectsThePendingBackendResult() {
        var context = MatchReviewContext()
        context.invalidate()
        let backendRequest = context.revision
        XCTAssertTrue(context.accepts(backendRequest))
        context.beginExamples()
        XCTAssertFalse(context.accepts(backendRequest))
        XCTAssertTrue(context.accepts(context.revision))
    }
}
