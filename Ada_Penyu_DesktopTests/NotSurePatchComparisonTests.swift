import AppKit
import XCTest
@testable import Ada_Penyu_Desktop

@MainActor
final class NotSurePatchComparisonTests: XCTestCase {
    func testReverseDragClampsToPhotoAndRejectsLetterboxStart() throws {
        let photo = CGRect(x: 20, y: 40, width: 200, height: 100)
        let patch = try XCTUnwrap(NotSurePatchGeometry.selection(
            from: CGPoint(x: 120, y: 90), to: CGPoint(x: 0, y: 150), in: photo
        ))
        XCTAssertEqual(patch, CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5))
        XCTAssertNil(NotSurePatchGeometry.selection(
            from: CGPoint(x: 120, y: 10), to: CGPoint(x: 150, y: 90), in: photo
        ))
    }

    func testPreviewUsesOneScaleForPhotoAndOutline() {
        let patch = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        let viewport = CGSize(width: 200, height: 200)
        let landscape = NotSurePatchGeometry.preview(
            patch: patch, photoSize: CGSize(width: 400, height: 200), in: viewport
        )
        XCTAssertEqual(landscape.clip, CGRect(x: 0, y: 50, width: 200, height: 100))
        XCTAssertEqual(landscape.photo, CGRect(x: -100, y: 0, width: 400, height: 200))
        let outline = [
            ScalePoint(x: 0.25, y: 0.25), ScalePoint(x: 0.75, y: 0.25),
            ScalePoint(x: 0.75, y: 0.75), ScalePoint(x: 0.25, y: 0.75)
        ]
        XCTAssertEqual(NotSurePhotoGeometry.polygonPath(outline, in: landscape.photo).boundingRect, landscape.clip)
        let portrait = NotSurePatchGeometry.preview(
            patch: patch, photoSize: CGSize(width: 200, height: 400), in: viewport
        )
        XCTAssertEqual(portrait.clip, CGRect(x: 50, y: 0, width: 100, height: 200))
        XCTAssertEqual(portrait.photo, CGRect(x: 0, y: -100, width: 200, height: 400))
        XCTAssertEqual(NotSurePhotoGeometry.polygonPath(outline, in: portrait.photo).boundingRect, portrait.clip)
    }

    func testChangingCandidateOrReplacingItsPhotoClearsOnlyCandidatePatch() {
        let photo = NSImage(size: CGSize(width: 100, height: 100))
        let replacement = NSImage(size: photo.size)
        let sighting = NotSurePatchSource(photo: photo, side: .left)
        let candidate = NotSurePatchSource(photo: photo, side: .left, candidateID: "first")
        let next = NotSurePatchSource(photo: photo, side: .left, candidateID: "next")
        let updated = NotSurePatchSource(photo: replacement, side: .left, candidateID: "next")
        let rect = CGRect(x: 0.1, y: 0.2, width: 0.4, height: 0.5)
        var session = NotSurePatchSession()
        session.updateSources(sighting: sighting, candidate: candidate)
        session.sighting = rect
        session.candidate = rect

        session.updateSources(sighting: sighting, candidate: next)
        XCTAssertEqual(session.sighting, rect)
        XCTAssertNil(session.candidate)

        session.candidate = rect
        session.updateSources(sighting: sighting, candidate: updated)
        XCTAssertEqual(session.sighting, rect)
        XCTAssertNil(session.candidate)

        let reopened = NotSurePatchSession()
        XCTAssertNil(reopened.sighting)
        XCTAssertNil(reopened.candidate)
    }

    func testChangingSightingSideClearsOnlySightingPatch() {
        let photo = NSImage(size: CGSize(width: 100, height: 100))
        let candidate = NotSurePatchSource(photo: photo, side: .left, candidateID: "first")
        let rect = CGRect(x: 0.1, y: 0.2, width: 0.4, height: 0.5)
        var session = NotSurePatchSession()
        session.updateSources(sighting: NotSurePatchSource(photo: photo, side: .left), candidate: candidate)
        session.sighting = rect
        session.candidate = rect

        session.updateSources(sighting: NotSurePatchSource(photo: photo, side: .right), candidate: candidate)

        XCTAssertNil(session.sighting)
        XCTAssertEqual(session.candidate, rect)
    }

    func testRefreshUsesAnOlderPhotoOnlyOnTheSameSide() {
        let older = NotSureReviewPhoto(data: Data([1]))
        let fresh = NotSureReviewPhoto(data: Data([2]))
        XCTAssertNil(NotSureReviewPhoto.refreshed(nil, side: .right, previous: older, previousSide: .left))
        XCTAssertEqual(NotSureReviewPhoto.refreshed(nil, side: .left, previous: older, previousSide: .left)?.data, older.data)
        XCTAssertEqual(NotSureReviewPhoto.refreshed(fresh, side: .right, previous: older, previousSide: .left)?.data, fresh.data)
    }
}
