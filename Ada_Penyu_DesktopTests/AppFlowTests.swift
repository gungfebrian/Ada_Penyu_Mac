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

    func testDemoRepositoryPreservesFavoriteToggleAsynchronousFlow() async throws {
        let repository = DemoTurtleRepository()
        let turtles = try await repository.listIndividuals(query: .default)
        XCTAssertEqual(turtles.items.count, 8)

        let favorite = try await repository.setFavorite(turtleID: turtles.items[0].id, isFavorite: true)
        XCTAssertTrue(favorite)
        let favorites = try await repository.listFavorites()
        XCTAssertTrue(favorites.contains(where: { $0.id == turtles.items[0].id }))
    }

    func testStoreStartsInLiveMode() {
        let store = AppStore(repository: DemoTurtleRepository())

        XCTAssertEqual(store.mode, .live)
    }

    func testSelectingIndividualKeepsOriginSectionForModalPresentation() {
        let store = AppStore(repository: DemoTurtleRepository())
        store.activeSection = .favorites

        store.select(DemoFixtures.turtles[3])

        XCTAssertEqual(store.activeSection, .favorites)
        XCTAssertEqual(store.selectedTurtle?.id, "Turtle #004")
        XCTAssertEqual(store.detailOrigin, .favorites)
    }

    func testDismissingModalPreventsInFlightDetailFromReappearing() async throws {
        let store = AppStore(repository: DemoTurtleRepository())

        store.select(DemoFixtures.turtles[3])
        store.dismissDetail()
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertNil(store.selectedTurtle)
        XCTAssertNil(store.selectedDetail)
        XCTAssertFalse(store.isDetailLoading)
    }

    func testDemoDashboardAggregatesFixtureRecordsInsteadOfFabricatingValues() async throws {
        let repository = DemoTurtleRepository()

        let snapshot = try await repository.dashboard(query: .lastTwelveMonths)

        XCTAssertEqual(snapshot.months.reduce(0) { $0 + $1.sightings }, DemoFixtures.sightings.count)
        XCTAssertEqual(snapshot.months.reduce(0) { $0 + $1.newIndividuals }, DemoFixtures.turtles.count)
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

    func testDemoVisualComparisonResolvesBundledGalleryPhotosAndOverlays() async throws {
        let repo = DemoTurtleRepository()
        let store = AppStore(mode: .demo, repository: repo)
        let sampleData = try XCTUnwrap(I3SSampleLibrary.loadImageData(named: "Amina3_L.jpg"))
        let outcome = try await store.matchPhoto(imageData: sampleData, side: .left, limit: 4)
        XCTAssertEqual(outcome.candidates.count, 4)

        for cand in outcome.candidates {
            XCTAssertNotNil(cand.photoURL)
            let loadedImage = await store.loadPhoto(for: cand.photoURL)
            XCTAssertNotNil(loadedImage, "Expected Compare Visually photo to load for \(cand.name)")
        }

        let topCandidate = try XCTUnwrap(outcome.candidates.first)
        let overlay = try await store.fetchOverlayAnnotations(
            imageData: sampleData,
            side: .left,
            candidateID: topCandidate.individualID,
            candidateSide: topCandidate.matchedPhotoSide
        )
        XCTAssertFalse(overlay.isEmpty)
        XCTAssertTrue(overlay.allSatisfy { (0...1).contains($0.query.x) && (0...1).contains($0.candidate.x) })
    }
}
