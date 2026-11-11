import XCTest
@testable import Ada_Penyu_Desktop

@MainActor
final class ScientistReviewTests: XCTestCase {
    func testScenarioOneRejectsLookalikeRankOneAndConfirmsRankTwo() {
        let vm = ScientistReviewViewModel()

        // Starting state: Scenario 1, clean original photos (all overlays off)
        XCTAssertEqual(vm.activeScenario, .rankOneJunctionMismatch)
        XCTAssertTrue(vm.isShowingCleanOriginalPhotos)
        XCTAssertEqual(vm.selectedCandidate.rank, 1)
        XCTAssertEqual(vm.selectedCandidate.topologyState, .junctionMismatch)

        // Toggle Scale outlines to inspect numbered junctions
        vm.showScaleOutlines = true
        XCTAssertFalse(vm.isShowingCleanOriginalPhotos)

        // Reject Rank #1 (Surya) -> marks rejected and advances to Rank #2 (Amina)
        vm.rejectSelectedCandidateAndAdvance()
        XCTAssertEqual(vm.candidates[0].status, .rejected)
        XCTAssertEqual(vm.selectedCandidate.rank, 2)
        XCTAssertEqual(vm.selectedCandidate.profileCode, "PEN-CM-007")
        XCTAssertEqual(vm.selectedCandidate.topologyState, .isomorphicMatch)

        // Confirm Same turtle on Rank #2 (with gallery enrollment kept separate by default)
        vm.prepareSameTurtleConfirmation()
        XCTAssertTrue(vm.isConfirmSameTurtlePresented)
        XCTAssertFalse(vm.nominateForGalleryReference)

        vm.confirmSameTurtleIdentity()
        XCTAssertFalse(vm.isConfirmSameTurtlePresented)
        XCTAssertEqual(vm.candidates[1].status, .confirmed)
        XCTAssertEqual(vm.currentOutcome?.resolution, .linkedToExisting)
        XCTAssertEqual(vm.currentOutcome?.linkedCandidateID, "PEN-CM-007")
        XCTAssertEqual(vm.currentOutcome?.nominateForGalleryEnrollment, false)
    }

    func testScenarioTwoGlareOccludesScalesAndSavesUnsureWithEmptyIdentity() {
        let vm = ScientistReviewViewModel()
        vm.switchScenario(.glareOcclusionUnsure)

        XCTAssertEqual(vm.activeScenario, .glareOcclusionUnsure)
        XCTAssertTrue(vm.isShowingCleanOriginalPhotos)
        XCTAssertTrue(vm.sighting.hasSpecularGlare)
        XCTAssertEqual(vm.selectedCandidate.topologyState, .glareOccluded)

        // Scientist opens Unsure sheet and saves with identity empty + requests better photo & second review
        vm.prepareUnsureSheet()
        XCTAssertTrue(vm.isUnsureSheetPresented)
        XCTAssertTrue(vm.requestBetterPhoto)
        XCTAssertTrue(vm.requestSecondReview)

        vm.saveUnsureDecision()
        XCTAssertFalse(vm.isUnsureSheetPresented)
        XCTAssertEqual(vm.currentOutcome?.resolution, .savedUnsure)
        XCTAssertNil(vm.currentOutcome?.linkedCandidateID)
        XCTAssertEqual(vm.currentOutcome?.requestBetterPhoto, true)
        XCTAssertEqual(vm.currentOutcome?.requestSecondReview, true)

        // Reset demo restores initial clean state
        vm.resetDemo()
        XCTAssertEqual(vm.activeScenario, .rankOneJunctionMismatch)
        XCTAssertNil(vm.currentOutcome)
        XCTAssertTrue(vm.isShowingCleanOriginalPhotos)
        XCTAssertEqual(vm.selectedCandidateIndex, 0)
    }

    func testMultiCandidateComparisonAndWiderSearch() {
        let vm = ScientistReviewViewModel()
        XCTAssertEqual(vm.multiComparisonCandidates.count, 3)

        vm.selectAllCandidatesForMultiCompare()
        XCTAssertEqual(vm.layoutMode, .multiCandidateGrid)

        vm.runWiderSearch()
        XCTAssertEqual(vm.multiComparisonCandidates.count, 4)
    }
}
