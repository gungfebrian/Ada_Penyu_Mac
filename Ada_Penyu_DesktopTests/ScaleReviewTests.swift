import XCTest
@testable import Ada_Penyu_Desktop

@MainActor
final class ScaleReviewTests: XCTestCase {
    private let square = [ScalePoint(x: 0.2, y: 0.2), ScalePoint(x: 0.4, y: 0.2), ScalePoint(x: 0.4, y: 0.4), ScalePoint(x: 0.2, y: 0.4)]
    private let roi = ScaleRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)

    func testPendingProposalIsNotACountedScaleAndConfirmationIsReversible() throws {
        var doc = ScalePhotoReview(photoHash: "query", pixelWidth: 100, pixelHeight: 100)
        doc.setHeadROI(roi)
        let id = try XCTUnwrap(doc.add(polygon: square, source: .proposal))
        XCTAssertEqual(doc.confirmedCount, 0)
        doc.setStatus(id, .confirmed)
        XCTAssertEqual(doc.confirmedCount, 1)
        doc.setStatus(id, .rejected)
        XCTAssertEqual(doc.confirmedCount, 0)
    }

    func testRegenerationPreservesReviewedAndManualScalesAndStableNumbers() throws {
        var doc = ScalePhotoReview(photoHash: "query", pixelWidth: 100, pixelHeight: 100)
        doc.setHeadROI(roi)
        let accepted = try XCTUnwrap(doc.add(polygon: square, source: .proposal))
        doc.setStatus(accepted, .confirmed)
        let manual = try XCTUnwrap(doc.add(polygon: square.map { ScalePoint(x: $0.x + 0.3, y: $0.y) }, source: .manual))
        doc.replaceProposals([square])
        XCTAssertEqual(doc.scales.count, 2)
        XCTAssertEqual(doc.scales.first(where: { $0.id == accepted })?.number, 1)
        XCTAssertNotNil(doc.scales.first(where: { $0.id == manual }))
        XCTAssertEqual(doc.confirmedCount, 1)
    }

    func testRedrawingRevokesConfirmationAndRejectsInvalidGeometry() throws {
        var doc = ScalePhotoReview(photoHash: "query", pixelWidth: 100, pixelHeight: 100)
        doc.setHeadROI(roi)
        let id = try XCTUnwrap(doc.add(polygon: square, source: .manual))
        doc.setStatus(id, .confirmed)
        XCTAssertFalse(doc.redraw(id, polygon: [ScalePoint(x: 0, y: 0)]))
        XCTAssertEqual(doc.confirmedCount, 1)
        XCTAssertTrue(doc.redraw(id, polygon: square.map { ScalePoint(x: $0.x + 0.1, y: $0.y) }))
        XCTAssertEqual(doc.confirmedCount, 0)
        XCTAssertEqual(doc.scales.first?.number, 1)
        let crossed = [square[0], square[2], square[1], square[3]]
        XCTAssertNil(doc.add(polygon: crossed, source: .manual))
    }

    func testHeadRegionChangeClearsOldAnnotationsAndExportRetainsProvenance() throws {
        var doc = ScalePhotoReview(photoHash: "sha256-photo", pixelWidth: 400, pixelHeight: 300)
        doc.setHeadROI(roi)
        _ = doc.add(polygon: square, source: .manual)
        let bytes = try JSONEncoder().encode(doc)
        let read = try JSONDecoder().decode(ScalePhotoReview.self, from: bytes)
        XCTAssertEqual(read.photoHash, "sha256-photo")
        XCTAssertEqual(read.scales.first?.source, .manual)
        XCTAssertEqual(read.confirmedCount, 0)
        doc.setHeadROI(ScaleRect(x: 0.5, y: 0.5, width: 0.3, height: 0.3))
        XCTAssertTrue(doc.scales.isEmpty)
    }

    func testPhotoReviewsCannotLeakAcrossImages() {
        let store = ScaleReviewStore()
        store.ensurePhoto(hash: "A", width: 10, height: 10)
        store.update("A") { $0.setHeadROI(self.roi); _ = $0.add(polygon: self.square, source: .manual) }
        store.ensurePhoto(hash: "B", width: 10, height: 10)
        XCTAssertEqual(store.documents["A"]?.scales.count, 1)
        XCTAssertEqual(store.documents["B"]?.scales.count, 0)
    }

    func testClosedRegionsAreLimitedToROIAndBorderRegionsAreRejected() throws {
        let width = 60, height = 40
        var edges = [UInt8](repeating: 0, count: width * height)
        for y in 8...20 { for x in 8...20 where x == 8 || x == 20 || y == 8 || y == 20 { edges[y * width + x] = 255 } }
        for y in 8...20 { for x in 40...52 where x == 40 || x == 52 || y == 8 || y == 20 { edges[y * width + x] = 255 } }
        let polygons = ScaleRegionProposalEngine.closedRegions(edges: edges, width: width, height: height,
            roi: ScaleRect(x: 0, y: 0, width: 0.5, height: 1))
        XCTAssertEqual(polygons.count, 1)
        XCTAssertTrue(try XCTUnwrap(polygons.first).allSatisfy { $0.x < 0.5 })
        XCTAssertEqual(ScaleRegionProposalEngine.closedRegions(edges: [0], width: width, height: height, roi: roi).count, 0)
    }

    func testRegenerationFromOtherPanePreservesEveryActiveRedrawLease() throws {
        let store = ScaleReviewStore()
        store.ensurePhoto(hash: "same-photo", width: 100, height: 100)
        var scaleID: UUID?
        store.update("same-photo") { $0.setHeadROI(self.roi); scaleID = $0.add(polygon: self.square, source: .proposal) }
        let id = try XCTUnwrap(scaleID)
        let firstPane = try XCTUnwrap(store.beginRedraw("same-photo", scaleID: id))
        let otherPane = try XCTUnwrap(store.beginRedraw("same-photo", scaleID: id))
        store.endRedraw("same-photo", lease: firstPane)
        store.replaceProposals("same-photo", polygons: [])
        XCTAssertEqual(store.documents["same-photo"]?.scales.first?.id, id)
        store.endRedraw("same-photo", lease: otherPane)
        store.replaceProposals("same-photo", polygons: [])
        XCTAssertTrue(try XCTUnwrap(store.documents["same-photo"]).scales.isEmpty)
    }

    func testHeadResetInvalidatesProposalGenerationAndMissingScalesCannotBeLeased() throws {
        let store = ScaleReviewStore()
        store.ensurePhoto(hash: "photo", width: 100, height: 100)
        store.update("photo") { $0.setHeadROI(self.roi) }
        let firstRevision = try XCTUnwrap(store.documents["photo"]).headRevision
        store.update("photo") { $0.setHeadROI(self.roi) }
        XCTAssertNotEqual(store.documents["photo"]?.headRevision, firstRevision)
        XCTAssertNil(store.beginRedraw("photo", scaleID: UUID()))
        XCTAssertNil(store.beginRedraw("missing", scaleID: UUID()))
    }

    func testBlankAndOpenEdgesDoNotInventScales() {
        let width = 40, height = 40
        let empty = [UInt8](repeating: 0, count: width * height)
        XCTAssertTrue(ScaleRegionProposalEngine.closedRegions(edges: empty, width: width, height: height, roi: roi).isEmpty)
    }
}
