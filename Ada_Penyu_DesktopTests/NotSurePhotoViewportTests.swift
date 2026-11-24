import XCTest
@testable import Ada_Penyu_Desktop

final class NotSurePhotoViewportTests: XCTestCase {
    func testEachPhotoAndOverlayHaveIndependentZoomAndPan() {
        var viewports = NotSureComparisonViewports()
        viewports.sighting = viewports.sighting.magnified(by: 2)
        viewports.sighting.commitPan(CGSize(width: 30, height: -20))

        XCTAssertEqual(viewports.candidate.scale, 1)
        XCTAssertEqual(viewports.candidate.offset, .zero)
        XCTAssertEqual(viewports.overlay.scale, 1)
        XCTAssertEqual(viewports.overlay.offset, .zero)

        viewports.candidate.stepZoom(by: 0.5)

        XCTAssertEqual(viewports.candidate.scale, 1.5)
        XCTAssertEqual(viewports.sighting.scale, 2)
        XCTAssertEqual(viewports.sighting.offset, CGSize(width: 30, height: -20))
    }

    func testPinchScalesFromTheCurrentZoomAndClampsToLimits() {
        var viewport = NotSurePhotoViewport()
        viewport.stepZoom(by: 0.5)

        XCTAssertEqual(viewport.magnified(by: 2).scale, 3)
        XCTAssertEqual(viewport.magnified(by: 4).scale, 4)
        XCTAssertEqual(viewport.magnified(by: 0.5).scale, 1)
        XCTAssertEqual(viewport.scale, 1.5)
    }

    func testReturningToFitClearsCommittedAndInProgressPan() {
        var viewport = NotSurePhotoViewport().magnified(by: 2)
        viewport.commitPan(CGSize(width: 30, height: -20))
        viewport.dragDelta = CGSize(width: 10, height: 5)

        XCTAssertEqual(viewport.offset, CGSize(width: 40, height: -15))

        viewport = viewport.magnified(by: 0.5)
        XCTAssertEqual(viewport.offset, .zero)
        XCTAssertEqual(viewport.magnified(by: 2).offset, .zero)
    }
}
