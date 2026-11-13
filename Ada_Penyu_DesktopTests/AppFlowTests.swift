import XCTest
@testable import Ada_Penyu_Desktop

@MainActor
final class AppFlowTests: XCTestCase {
    func testIndividualsQueryBuildsStableQueryItems() throws {
        let query = IndividualQuery(
            search: "Turtle #001",
            species: [.hawksbill],
            condition: .injured,
            sort: .lastSeenDescending,
            page: PageRequest(limit: 25, offset: 50)
        )

        XCTAssertEqual(query.queryItems.map(\.description), [
            "q=Turtle #001",
            "species=hawksbill",
            "condition=injured",
            "sort=last_seen_desc",
            "limit=25",
            "offset=50",
        ])
    }

    func testStoreFavoriteToggleUpdatesFavorites() async throws {
        let store = AppStore(repository: TestTurtleRepository())
        await store.reloadAll()
        store.toggleFavorite(TestTurtleRepository.turtle)
        for _ in 0..<100 where store.favoriteTurtles.isEmpty { await Task.yield() }
        XCTAssertEqual(store.favoriteTurtles.first?.id, TestTurtleRepository.turtle.id)
        store.toggleFavorite(TestTurtleRepository.turtle)
        for _ in 0..<100 where !store.favoriteTurtles.isEmpty { await Task.yield() }
        XCTAssertTrue(store.favoriteTurtles.isEmpty)
    }

    func testSelectingIndividualKeepsOriginSectionForModalPresentation() {
        let store = AppStore(repository: TestTurtleRepository())
        store.activeSection = .favorites

        store.select(TestTurtleRepository.turtle)

        XCTAssertEqual(store.activeSection, .favorites)
        XCTAssertEqual(store.selectedTurtle?.id, APIFixtures.turtleID)
        XCTAssertEqual(store.detailOrigin, .favorites)
    }

    func testDismissingModalPreventsInFlightDetailFromReappearing() async throws {
        let store = AppStore(repository: TestTurtleRepository())

        store.select(TestTurtleRepository.turtle)
        store.dismissDetail()
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertNil(store.selectedTurtle)
        XCTAssertNil(store.selectedDetail)
        XCTAssertFalse(store.isDetailLoading)
    }

    func testI3SBinaryFgpRoundTripAndCompareEngine() throws {
        var roi = I3SRoi()
        _ = try roi.add(I3SPoint2D(x: 100, y: 100))
        _ = try roi.add(I3SPoint2D(x: 300, y: 100))
        _ = try roi.add(I3SPoint2D(x: 300, y: 300))
        _ = try roi.add(I3SPoint2D(x: 100, y: 300))
        XCTAssertTrue(roi.closePolygonIfPossible())
        XCTAssertTrue(roi.isFinal)
        XCTAssertTrue(roi.contains(I3SPoint2D(x: 200, y: 200)))
        XCTAssertFalse(roi.contains(I3SPoint2D(x: 40, y: 40)))

        let original = I3SFingerprint(
            ref1: I3SPoint2D(x: 110, y: 210),
            ref2: I3SPoint2D(x: 160, y: 130),
            ref3: I3SPoint2D(x: 280, y: 180),
            roi: roi,
            keypoints: [
                I3SKeypoint(center: I3SPoint2D(x: 150, y: 180), size: 18),
                I3SKeypoint(center: I3SPoint2D(x: 195, y: 210), size: 22),
                I3SKeypoint(center: I3SPoint2D(x: 235, y: 175), size: 16),
                I3SKeypoint(center: I3SPoint2D(x: 210, y: 245), size: 20),
                I3SKeypoint(center: I3SPoint2D(x: 165, y: 240), size: 19),
            ],
            comment: "Amina_L test"
        )

        let data = I3SFingerprintFile.write(original)
        let decoded = try I3SFingerprintFile.read(from: data, filename: "test.fgp")
        XCTAssertEqual(decoded.keypoints.count, 5)
        XCTAssertTrue(decoded.roi.isFinal)
        XCTAssertEqual(decoded.comment, "Amina_L test")

        let selfMatch = I3SCompareEngine.compareTwo(unknown: original, candidate: decoded)
        XCTAssertGreaterThanOrEqual(selfMatch.pairCount, 3)
        XCTAssertLessThan(selfMatch.score, 1.0)
    }

    func testI3SSampleLibraryAndSurfExtractor() throws {
        XCTAssertFalse(I3SSampleLibrary.samples.isEmpty)
        let first = try XCTUnwrap(I3SSampleLibrary.samples.first)
        XCTAssertEqual(first.fingerprint.keypoints.count, 35)
        XCTAssertTrue(first.fingerprint.roi.isFinal)

        let image = try XCTUnwrap(I3SSampleLibrary.loadImage(for: first))
        let extracted = I3SSurfExtractor.extractKeypoints(from: image, roi: first.fingerprint.roi)
        XCTAssertFalse(extracted.isEmpty)
        XCTAssertLessThanOrEqual(extracted.count, I3SExpertParameters.default.nrElements)
    }

    func testI3SMatchesOriginalCppReferenceScoresAndPairs() throws {
        struct Reference: Decodable {
            let query: String
            let candidate: String
            let score: Double
            let pairs: Int
        }
        let url = try XCTUnwrap(Bundle(for: AppFlowTests.self)
            .url(forResource: "i3s-v402-reference", withExtension: "json"))
        let references = try JSONDecoder().decode([Reference].self, from: Data(contentsOf: url))
        let samples = Dictionary(uniqueKeysWithValues: I3SSampleLibrary.samples.map { ($0.id, $0) })
        XCTAssertEqual(references.count, 97)
        for reference in references {
            let unknown = try XCTUnwrap(samples[reference.query]).fingerprint
            let candidate = try XCTUnwrap(samples[reference.candidate]).fingerprint
            let result = I3SCompareEngine.compareTwo(unknown: unknown, candidate: candidate)
            let label = "\(reference.query) -> \(reference.candidate)"
            XCTAssertEqual(result.score, reference.score, accuracy: 0.000001, label)
            XCTAssertEqual(result.pairCount, reference.pairs, label)
            XCTAssertEqual(result.matchedPairs.count, reference.pairs, label)
        }
    }

    func testI3SRecognizesOtherEncountersInBundledGallery() throws {
        for query in I3SSampleLibrary.samples {
            let gallery = I3SSampleLibrary.samples.filter { $0.id != query.id && $0.photoSide == query.photoSide }
            let best = try XCTUnwrap(gallery.min {
                I3SCompareEngine.compareTwo(unknown: query.fingerprint, candidate: $0.fingerprint).score
                    < I3SCompareEngine.compareTwo(unknown: query.fingerprint, candidate: $1.fingerprint).score
            })
            // Sample IDs name the individual before the encounter number.
            XCTAssertEqual(best.id.prefix(while: { !$0.isNumber }), query.id.prefix(while: { !$0.isNumber }), query.id)
        }
    }

}
