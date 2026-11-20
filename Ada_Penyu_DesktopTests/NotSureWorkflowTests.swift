import AppKit
import XCTest
@testable import Ada_Penyu_Desktop

@MainActor
final class NotSureWorkflowTests: XCTestCase {
    func testOpenSetVerdictsPersistAndClearOnReopen() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "AdaPenyu-NotSureFlow-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let journal = NotSureReviewJournal(directory: dir)

        var item = try makeCase()
        try item.apply(.resolveAsNewTurtle(note: "Different pattern"))
        XCTAssertEqual(item.decision, .reviewedUnknown)
        XCTAssertEqual(item.unknownOutcome, .newIndividual)
        XCTAssertEqual(item.decisionSummaryTitle, "New turtle")

        try journal.save(item, scope: "scope-open-set")
        var restored = try XCTUnwrap(journal.load(scope: "scope-open-set").first)
        XCTAssertEqual(restored.unknownOutcome, .newIndividual)

        try restored.apply(.reopen)
        XCTAssertEqual(restored.decision, .pending)
        XCTAssertNil(restored.unknownOutcome)
        XCTAssertEqual(restored.decisionSummaryTitle, "Pending")

        try restored.apply(.requestBetterPhoto(note: "Glare / blur"))
        XCTAssertEqual(restored.decision, .reviewedUnknown)
        XCTAssertEqual(restored.unknownOutcome, .needsBetterPhoto)
        XCTAssertEqual(restored.decisionSummaryTitle, "Needs photo")
    }

    func testSavedVerifiedPairsDeduplicateAndPersist() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "AdaPenyu-Pairs-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let journal = NotSureReviewJournal(directory: dir)

        var item = try makeCase()
        let rawPairs = [
            PatternPairLink(queryNumber: 5, candidateNumber: 6),
            PatternPairLink(queryNumber: 2, candidateNumber: 3),
            PatternPairLink(queryNumber: 2, candidateNumber: 8), // duplicate query should be dropped
            PatternPairLink(queryNumber: 7, candidateNumber: 9),
        ]
        try item.apply(.saveVerifiedPairs(candidateID: "cand-1", pairs: rawPairs))
        try journal.save(item, scope: "scope-pairs")

        let loaded = try XCTUnwrap(journal.load(scope: "scope-pairs").first)
        XCTAssertEqual(loaded.verifiedPairs(for: "cand-1").map(\.queryNumber), [2, 5, 7])
        XCTAssertEqual(loaded.verifiedPairs(for: "cand-1").map(\.candidateNumber), [3, 6, 9])

        var mutable = loaded
        try mutable.apply(.saveVerifiedPairs(candidateID: "cand-1", pairs: []))
        XCTAssertTrue(mutable.verifiedPairs(for: "cand-1").isEmpty)
    }

    func testBackwardCompatibleDecodingOfLegacyNotSureJSON() throws {
        let item = try makeCase()
        let encoded = try JSONEncoder().encode(item)
        var json = try XCTUnwrap(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        json.removeValue(forKey: "unknownOutcome")
        json.removeValue(forKey: "verifiedPairsByCandidateID")
        let legacyData = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(EscalatedNotSureCase.self, from: legacyData)
        XCTAssertEqual(decoded.id, item.id)
        XCTAssertNil(decoded.unknownOutcome)
        XCTAssertTrue(decoded.verifiedPairs(for: "cand-1").isEmpty)
    }

    func testAlignmentEvaluatorRequiresThreePairsAndFlagsFlippedOrStretchedAnchors() {
        func makePat(_ num: Int, _ x: Double, _ y: Double) -> DetectedScalePattern {
            DetectedScalePattern(
                number: num,
                polygon: [
                    ScalePoint(x: x - 0.03, y: y - 0.03),
                    ScalePoint(x: x + 0.03, y: y - 0.03),
                    ScalePoint(x: x + 0.03, y: y + 0.03),
                    ScalePoint(x: x - 0.03, y: y + 0.03),
                ],
                centroid: ScalePoint(x: x, y: y),
                roiAreaFraction: 0.05,
                imageArea: 0.0036,
                vertexCount: 4,
                circularity: 0.78,
                aspectRatio: 1.1,
                orientationDeg: 0
            )
        }

        let query = [makePat(1, 0.25, 0.30), makePat(2, 0.55, 0.32), makePat(3, 0.38, 0.62)]
        let candNormal = [makePat(1, 0.27, 0.31), makePat(2, 0.57, 0.33), makePat(3, 0.40, 0.63)]
        let candFlipped = [makePat(1, 0.57, 0.31), makePat(2, 0.27, 0.33), makePat(3, 0.40, 0.63)]
        let roi = [ScalePoint(x: 0.1, y: 0.1), ScalePoint(x: 0.8, y: 0.1), ScalePoint(x: 0.8, y: 0.8), ScalePoint(x: 0.1, y: 0.8)]

        // Fewer than 3 pairs -> needsAnchors
        let twoPairs = [PatternPairLink(queryNumber: 1, candidateNumber: 1), PatternPairLink(queryNumber: 2, candidateNumber: 2)]
        let partial = NotSureAlignmentEvaluator.evaluate(query: query, candidate: candNormal, pairs: twoPairs, queryROI: roi, candidateROI: roi)
        XCTAssertEqual(partial.status, .needsAnchors(remaining: 1))
        XCTAssertFalse(partial.isReadyForOverlay)

        // 3 orientation-preserving pairs -> aligned & ready for overlay
        let threePairs = [
            PatternPairLink(queryNumber: 1, candidateNumber: 1),
            PatternPairLink(queryNumber: 2, candidateNumber: 2),
            PatternPairLink(queryNumber: 3, candidateNumber: 3),
        ]
        let ok = NotSureAlignmentEvaluator.evaluate(query: query, candidate: candNormal, pairs: threePairs, queryROI: roi, candidateROI: roi)
        XCTAssertEqual(ok.status, .aligned)
        XCTAssertTrue(ok.isReadyForOverlay)
        XCTAssertEqual(ok.warpedContours.count, 3)
        XCTAssertFalse(ok.isWarning)

        // Reflected anchors -> flags orientationFlipped
        let flipped = NotSureAlignmentEvaluator.evaluate(query: query, candidate: candFlipped, pairs: threePairs, queryROI: roi, candidateROI: roi)
        XCTAssertEqual(flipped.status, .orientationFlipped)
        XCTAssertTrue(flipped.isWarning)
    }

    func testHeadCropperProducesValidCroppedJPEG() throws {
        let sample = try XCTUnwrap(I3SSampleLibrary.sample(forFilenameOrID: "Amina1_L"))
        let image = try XCTUnwrap(I3SSampleLibrary.loadImage(for: sample))
        let jpeg = try XCTUnwrap(NotSureHeadCropper.croppedJPEGData(from: image, normalizedRect: CGRect(x: 0.2, y: 0.2, width: 0.5, height: 0.5)))
        XCTAssertGreaterThan(jpeg.count, 1000)
        let decoded = try XCTUnwrap(NSImage(data: jpeg))
        XCTAssertGreaterThan(decoded.size.width, 32)
        XCTAssertGreaterThan(decoded.size.height, 32)
    }

    private func makeCase() throws -> EscalatedNotSureCase {
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let photo = NotSureReviewPhoto(data: data)
        let candidate = EscalatedNotSureCandidate(
            id: "cand-1", rank: 1, name: "Amina", profileCode: "PEN-007",
            side: .left, sideMatches: true, dateText: "2026-10-01", location: "Crystal Bay",
            confidencePercent: 84, photo: photo, sampleImageName: nil, fingerprint: nil, isBundledExample: false
        )
        return EscalatedNotSureCase(
            title: "Crystal Bay · Left", side: .left, photo: photo, companion: nil,
            queryFingerprint: nil, queryROI: [], candidates: [candidate], submittedBy: "Ranger Wayan", isExample: false
        )
    }
}
