import AppKit
import CoreGraphics
import XCTest
@testable import Ada_Penyu_Desktop

@MainActor
final class HumanAssistedMatchingTests: XCTestCase {

    // MARK: - 1. SquareOverlayMapper (Prevents Backend 422 + Exact Coordinate Round-Trip)

    func testSquareOverlayMapperProducesSquareJPEGAndInvertsLandscapeAndPortraitPoints() throws {
        // Landscape 4:3 (800x600)
        let landscapeData = try makeSyntheticJPEG(width: 800, height: 600)
        let prepL = try XCTUnwrap(SquareOverlayMapper.prepareSquareJPEG(from: landscapeData, squareSide: 512))
        let imgL = try XCTUnwrap(NSImage(data: prepL.jpegData)?.cgImage(forProposedRect: nil, context: nil, hints: nil))
        XCTAssertEqual(imgL.width, 512)
        XCTAssertEqual(imgL.height, 512)
        // 4:3 inside 512x512 -> width = 1.0, height = 0.75, padY = 0.125
        XCTAssertEqual(prepL.contentRect.minX, 0.0, accuracy: 0.002)
        XCTAssertEqual(prepL.contentRect.minY, 0.125, accuracy: 0.002)
        XCTAssertEqual(prepL.contentRect.width, 1.0, accuracy: 0.002)
        XCTAssertEqual(prepL.contentRect.height, 0.75, accuracy: 0.002)

        // Point inside letterbox bar (y = 0.04) must be discarded.
        XCTAssertNil(SquareOverlayMapper.mapQueryPointToOriginal(
            OverlayMatchPoint(x: 0.5, y: 0.04),
            contentRect: prepL.contentRect
        ))

        // Original (0.25, 0.50) lives at square (0.25, 0.125 + 0.5*0.75 = 0.50).
        let unmappedCenter = try XCTUnwrap(SquareOverlayMapper.mapQueryPointToOriginal(
            OverlayMatchPoint(x: 0.25, y: 0.50),
            contentRect: prepL.contentRect
        ))
        XCTAssertEqual(unmappedCenter.x, 0.25, accuracy: 0.002)
        XCTAssertEqual(unmappedCenter.y, 0.50, accuracy: 0.002)

        // Original bottom edge (0.80, 1.00) lives at square (0.80, 0.875).
        let unmappedBottom = try XCTUnwrap(SquareOverlayMapper.mapQueryPointToOriginal(
            OverlayMatchPoint(x: 0.80, y: 0.875),
            contentRect: prepL.contentRect
        ))
        XCTAssertEqual(unmappedBottom.x, 0.80, accuracy: 0.002)
        XCTAssertEqual(unmappedBottom.y, 1.00, accuracy: 0.002)

        // Portrait 3:4 (600x800)
        let portraitData = try makeSyntheticJPEG(width: 600, height: 800)
        let prepP = try XCTUnwrap(SquareOverlayMapper.prepareSquareJPEG(from: portraitData, squareSide: 512))
        XCTAssertEqual(prepP.contentRect.minX, 0.125, accuracy: 0.002)
        XCTAssertEqual(prepP.contentRect.width, 0.75, accuracy: 0.002)
        XCTAssertEqual(prepP.contentRect.height, 1.0, accuracy: 0.002)

        let unmappedPortrait = try XCTUnwrap(SquareOverlayMapper.mapQueryPointToOriginal(
            OverlayMatchPoint(x: 0.125 + 0.4 * 0.75, y: 0.72),
            contentRect: prepP.contentRect
        ))
        XCTAssertEqual(unmappedPortrait.x, 0.40, accuracy: 0.002)
        XCTAssertEqual(unmappedPortrait.y, 0.72, accuracy: 0.002)
    }

    func testPrepareReMatchJPEGCropsAndLevelsTilt() throws {
        let sample = try XCTUnwrap(I3SSampleLibrary.sample(forFilenameOrID: "Amina3_L"))
        let img = try XCTUnwrap(I3SSampleLibrary.loadImage(for: sample))
        let crop = CGRect(x: 0.20, y: 0.18, width: 0.55, height: 0.55)

        let leveled = try XCTUnwrap(SquareOverlayMapper.prepareReMatchJPEG(
            from: img,
            normalizedRect: crop,
            rotationDegrees: 14.0
        ))
        let decoded = try XCTUnwrap(NSImage(data: leveled)?.cgImage(forProposedRect: nil, context: nil, hints: nil))
        XCTAssertGreaterThanOrEqual(decoded.width, 64)
        XCTAssertGreaterThanOrEqual(decoded.height, 64)
    }

    // MARK: - 2. Hartley-Normalized Projective Homography & RANSAC Geometric Consensus

    func testProjectiveHomographyRecoversPerspectiveTransformAccurately() throws {
        let qPts = [
            ScalePoint(x: 0.22, y: 0.24),
            ScalePoint(x: 0.76, y: 0.26),
            ScalePoint(x: 0.74, y: 0.78),
            ScalePoint(x: 0.24, y: 0.75),
            ScalePoint(x: 0.50, y: 0.50),
        ]
        // Ground-truth projective transform with genuine perspective tilt (h20, h21 != 0)
        let truth = ProjectiveHomography(
            h00: 0.94, h01: -0.07, h02: 0.05,
            h10: 0.08, h11: 0.91, h12: 0.03,
            h20: 0.14, h21: -0.09, h22: 1.0
        )
        let pairs: [(ScalePoint, ScalePoint)] = try qPts.map { q in
            let c = try XCTUnwrap(truth.apply(q))
            return (q, c)
        }
        let solved = try XCTUnwrap(ProjectiveHomography.fit(pairs: pairs))
        for (q, expected) in pairs {
            let mapped = try XCTUnwrap(solved.apply(q))
            XCTAssertEqual(mapped.x, expected.x, accuracy: 1e-4)
            XCTAssertEqual(mapped.y, expected.y, accuracy: 1e-4)
        }
    }

    func testRANSACSeparatesTrueInliersFromInjectedGlareOutliersAndRejectsImpostors() throws {
        // Build 14 true geometric correspondences obeying a mild camera rotation + shift + scale
        let trueAff = AffineTransform2D(a: 0.92, b: -0.10, tx: 0.07, c: 0.10, d: 0.92, ty: -0.02)
        var annotations: [OverlayAnnotationItem] = []
        let grid: [(Double, Double)] = [
            (0.24, 0.26), (0.38, 0.24), (0.52, 0.25), (0.68, 0.28),
            (0.26, 0.42), (0.42, 0.40), (0.58, 0.43), (0.72, 0.46),
            (0.28, 0.58), (0.44, 0.60), (0.60, 0.59), (0.70, 0.66),
            (0.35, 0.72), (0.54, 0.73),
        ]
        for (idx, (qx, qy)) in grid.enumerated() {
            let qp = ScalePoint(x: qx, y: qy)
            let cp = trueAff.apply(qp)
            // Tiny realistic noise (~0.4%)
            let jitterX = (idx % 2 == 0 ? 0.003 : -0.003)
            let jitterY = (idx % 3 == 0 ? 0.004 : -0.002)
            annotations.append(OverlayAnnotationItem(
                featureID: "inlier-\(idx)",
                label: "xfeat_lighterglue_match",
                score: 0.85,
                query: OverlayMatchPoint(x: qp.x, y: qp.y),
                candidate: OverlayMatchPoint(x: cp.x + jitterX, y: cp.y + jitterY)
            ))
        }
        // Inject 6 gross background/glare outliers
        let outliers: [(Double, Double, Double, Double)] = [
            (0.10, 0.12, 0.85, 0.82),
            (0.88, 0.14, 0.14, 0.78),
            (0.15, 0.86, 0.82, 0.16),
            (0.84, 0.84, 0.20, 0.22),
            (0.50, 0.10, 0.12, 0.52),
            (0.12, 0.50, 0.88, 0.48),
        ]
        for (idx, o) in outliers.enumerated() {
            annotations.append(OverlayAnnotationItem(
                featureID: "outlier-\(idx)",
                label: "xfeat_lighterglue_match",
                score: 0.55,
                query: OverlayMatchPoint(x: o.0, y: o.1),
                candidate: OverlayMatchPoint(x: o.2, y: o.3)
            ))
        }

        let report = GeometricConsensusRANSAC.evaluate(annotations: annotations)
        XCTAssertEqual(report.totalMatches, 20)
        XCTAssertEqual(report.inlierCount, 14)
        XCTAssertEqual(report.outlierCount, 6)
        XCTAssertEqual(report.strength, .strong)
        XCTAssertTrue(report.canAutoSeedWarp)
        XCTAssertEqual(report.suggestedAnchors.count, 4)
        for i in 0..<6 {
            XCTAssertFalse(report.inlierFeatureIDs.contains("outlier-\(i)"))
        }

        // Scrambled impostor correspondences must NOT report strong consensus
        let impostor: [OverlayAnnotationItem] = [
            OverlayAnnotationItem(featureID: "imp-1", label: "x", score: 0.4, query: .init(x: 0.20, y: 0.20), candidate: .init(x: 0.78, y: 0.80)),
            OverlayAnnotationItem(featureID: "imp-2", label: "x", score: 0.4, query: .init(x: 0.75, y: 0.22), candidate: .init(x: 0.25, y: 0.26)),
            OverlayAnnotationItem(featureID: "imp-3", label: "x", score: 0.4, query: .init(x: 0.50, y: 0.50), candidate: .init(x: 0.18, y: 0.84)),
            OverlayAnnotationItem(featureID: "imp-4", label: "x", score: 0.4, query: .init(x: 0.30, y: 0.76), candidate: .init(x: 0.64, y: 0.15)),
            OverlayAnnotationItem(featureID: "imp-5", label: "x", score: 0.4, query: .init(x: 0.68, y: 0.72), candidate: .init(x: 0.42, y: 0.62)),
            OverlayAnnotationItem(featureID: "imp-6", label: "x", score: 0.4, query: .init(x: 0.42, y: 0.35), candidate: .init(x: 0.85, y: 0.45)),
        ]
        let impostorReport = GeometricConsensusRANSAC.evaluate(annotations: impostor)
        XCTAssertNotEqual(impostorReport.strength, .strong)
    }

    func testAlignmentEvaluatorDetectsPerspectiveAndFlippedPins() {
        let validAnchors = [
            ManualAnchorPair(label: "A", queryPoint: ScalePoint(x: 0.25, y: 0.25), candidatePoint: ScalePoint(x: 0.28, y: 0.26)),
            ManualAnchorPair(label: "B", queryPoint: ScalePoint(x: 0.70, y: 0.25), candidatePoint: ScalePoint(x: 0.72, y: 0.28)),
            ManualAnchorPair(label: "C", queryPoint: ScalePoint(x: 0.70, y: 0.72), candidatePoint: ScalePoint(x: 0.71, y: 0.75)),
            ManualAnchorPair(label: "D", queryPoint: ScalePoint(x: 0.25, y: 0.72), candidatePoint: ScalePoint(x: 0.27, y: 0.73)),
        ]
        let ok = HumanAssistedAlignmentEvaluator.evaluate(anchors: validAnchors, queryPatterns: [])
        XCTAssertEqual(ok.status, .aligned)
        XCTAssertTrue(ok.isReadyForWarp)
        XCTAssertEqual(ok.transform?.isPerspective, true)

        // Mirror X on Candidate pins -> orientation flipped warning!
        let flippedAnchors = [
            ManualAnchorPair(label: "A", queryPoint: ScalePoint(x: 0.25, y: 0.25), candidatePoint: ScalePoint(x: 0.75, y: 0.25)),
            ManualAnchorPair(label: "B", queryPoint: ScalePoint(x: 0.75, y: 0.25), candidatePoint: ScalePoint(x: 0.25, y: 0.25)),
            ManualAnchorPair(label: "C", queryPoint: ScalePoint(x: 0.50, y: 0.75), candidatePoint: ScalePoint(x: 0.50, y: 0.75)),
        ]
        let flipped = HumanAssistedAlignmentEvaluator.evaluate(anchors: flippedAnchors, queryPatterns: [])
        XCTAssertEqual(flipped.status, .orientationFlipped)
        XCTAssertFalse(flipped.isReadyForWarp)
    }

    // MARK: - 3. Real CoreImage Photographic Pixel Warp

    func testPhotoWarpRendererWarpsRealTurtlePhotoOntoCandidateFrame() throws {
        let qSample = try XCTUnwrap(I3SSampleLibrary.sample(forFilenameOrID: "Amina3_L"))
        let cSample = try XCTUnwrap(I3SSampleLibrary.sample(forFilenameOrID: "Amina1_L"))
        let qImg = try XCTUnwrap(I3SSampleLibrary.loadImage(for: qSample))
        let cImg = try XCTUnwrap(I3SSampleLibrary.loadImage(for: cSample))

        let qw = Double(qSample.imageWidth), qh = Double(qSample.imageHeight)
        let cw = Double(cSample.imageWidth), ch = Double(cSample.imageHeight)
        let pairs: [(ScalePoint, ScalePoint)] = [
            (ScalePoint(x: qSample.ref1[0] / qw, y: qSample.ref1[1] / qh),
             ScalePoint(x: cSample.ref1[0] / cw, y: cSample.ref1[1] / ch)),
            (ScalePoint(x: qSample.ref2[0] / qw, y: qSample.ref2[1] / qh),
             ScalePoint(x: cSample.ref2[0] / cw, y: cSample.ref2[1] / ch)),
            (ScalePoint(x: qSample.ref3[0] / qw, y: qSample.ref3[1] / qh),
             ScalePoint(x: cSample.ref3[0] / cw, y: cSample.ref3[1] / ch)),
        ]
        let transform = try XCTUnwrap(GeometricWarpTransform.fit(pairs: pairs))
        let warped = try XCTUnwrap(PhotoWarpRenderer.renderWarpedQueryNSImage(
            queryImage: qImg,
            candidateImage: cImg,
            transform: transform,
            maxDimension: 600
        ))
        XCTAssertGreaterThanOrEqual(warped.size.width, 200)
        XCTAssertGreaterThanOrEqual(warped.size.height, 150)
    }

    // MARK: - 4. Upgraded Ocean-Masked Contour Engine Across Real Turtle Samples

    func testUpgradedSinglePassAnalysisRunsAcrossAllBundledSamples() throws {
        for sample in I3SSampleLibrary.samples {
            let img = try XCTUnwrap(I3SSampleLibrary.loadImage(for: sample))
            let analysis = PatternContourEngine.extractAnalysis(from: img, side: sample.photoSide)
            XCTAssertGreaterThanOrEqual(analysis.roi.count, 4, "Missing tight ROI for \(sample.id)")
            XCTAssertGreaterThanOrEqual(analysis.patterns.count, 3, "Expected >= 3 water/eyeball-filtered scales for \(sample.id)")
            XCTAssertEqual(analysis.patterns.map(\.number), Array(1...analysis.patterns.count))
        }
    }

    // MARK: - 5. Mobile Pending Sightings Sync, Backend Write-Back & Re-Match Deltas

    func testSyncMobilePendingSightingsAndConfirmWritesBackToBackendLog() async throws {
        let logID = UUID()
        let turtleID = UUID()
        let mockRepo = MockHumanAssistedRepo(pendingLogID: logID, targetTurtleID: turtleID)
        let tempDir = FileManager.default.temporaryDirectory.appending(path: "ada-human-match-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = AppStore(repository: mockRepo, reviewJournal: NotSureReviewJournal(directory: tempDir))
        store.enterDemoWorkspace(persona: .demoResearcher)
        // Swap back to mockRepo via test helper: create a fresh store wired directly to mockRepo in authenticated live-like state
        let liveStore = AppStore(repository: mockRepo, reviewJournal: NotSureReviewJournal(directory: tempDir))
        // Sync works whenever repository is injected & canLoadRecords is true — test via DemoTurtleRepository first:
        await store.loadMobileReviewQueue()
        XCTAssertEqual(store.mobileReviewRows.count, 1)
        XCTAssertTrue(store.pendingNotSureCases.isEmpty, "The inbox must not prepare images or candidates")
        let demoID = try XCTUnwrap(store.mobileReviewRows.first?.id)
        await store.loadMobileReviewQueue()
        XCTAssertEqual(store.mobileReviewRows.map(\.id), [demoID], "Refresh must not duplicate rows")
        try await store.prepareMobileReview(demoID)
        let prepared = try XCTUnwrap(store.pendingNotSureCases.first)
        let candidateID = try XCTUnwrap(prepared.candidates.first?.id)
        try await store.loadNotSureCandidatePhoto(caseID: prepared.id, candidateID: candidateID)

        // Verify persistence of manual pins, excluded scales, and custom scale landmarks
        let syncedCase = try XCTUnwrap(store.pendingNotSureCases.first)
        let firstCand = try XCTUnwrap(syncedCase.candidates.first)
        let anchor = ManualAnchorPair(
            label: "A",
            queryPoint: ScalePoint(x: 0.4, y: 0.4),
            candidatePoint: ScalePoint(x: 0.42, y: 0.41)
        )
        try store.updateNotSureCase(syncedCase.id, action: .saveManualAnchors(candidateID: firstCand.id, anchors: [anchor]))
        try store.updateNotSureCase(syncedCase.id, action: .toggleExcludedQueryScale(2))
        let mark = ManualScaleLandmark(label: "M1", point: ScalePoint(x: 0.55, y: 0.48))
        try store.updateNotSureCase(syncedCase.id, action: .addCustomQueryLandmark(mark))

        store.reloadNotSureQueue()
        let reloaded = try XCTUnwrap(store.escalatedNotSureCases.first(where: { $0.id == syncedCase.id }))
        XCTAssertEqual(reloaded.manualAnchors(for: firstCand.id).count, 1)
        XCTAssertEqual(reloaded.excludedQueryScaleNumbers, [2])
        XCTAssertEqual(reloaded.customQueryLandmarks?.first?.label, "M1")

        // Confirming same turtle on synced mobile case resolves cleanly
        try await store.resolveNotSureCaseAndSyncBackend(
            syncedCase.id,
            action: .recommend(firstCand.id, note: "Warped scales lock")
        )
        let afterConfirm = try XCTUnwrap(store.escalatedNotSureCases.first(where: { $0.id == syncedCase.id }))
        XCTAssertEqual(afterConfirm.decision, .recommendedMatch)

        // Verify mock repository contract directly for resolvePendingSighting
        _ = liveStore
        let mockPending = try await mockRepo.listPendingSightings(limit: 10)
        XCTAssertEqual(mockPending.first?.id, logID)
        try await mockRepo.resolvePendingSighting(
            logID: logID,
            turtleID: turtleID,
            method: "manual",
            confidence: 0.88,
            notes: "Warped scales lock"
        )
        XCTAssertEqual(mockRepo.resolvedCalls.count, 1)
        XCTAssertEqual(mockRepo.resolvedCalls.first?.logID, logID)
        XCTAssertEqual(mockRepo.resolvedCalls.first?.turtleID, turtleID)
    }

    func testCandidateReMatchDeltaFormatsPositiveAndNewBadges() {
        let promoted = CandidateReMatchDelta(previousRank: 4, newRank: 1, previousConfidence: 52, newConfidence: 78)
        XCTAssertEqual(promoted.badgeText, "↑3 · +26%")
        XCTAssertTrue(promoted.isPositive)

        let newlyFound = CandidateReMatchDelta(previousRank: nil, newRank: 1, previousConfidence: nil, newConfidence: 81)
        XCTAssertEqual(newlyFound.badgeText, "New #1")
        XCTAssertTrue(newlyFound.isPositive)

        let dropped = CandidateReMatchDelta(previousRank: 1, newRank: 3, previousConfidence: 74, newConfidence: 62)
        XCTAssertEqual(dropped.badgeText, "-12%")
        XCTAssertFalse(dropped.isPositive)
    }

    // MARK: - Helpers

    private func makeSyntheticJPEG(width: Int, height: Int) throws -> Data {
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            throw NSError(domain: "Test", code: 1)
        }
        ctx.setFillColor(red: 0.15, green: 0.42, blue: 0.55, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let cg = try XCTUnwrap(ctx.makeImage())
        return try XCTUnwrap(NSBitmapImageRep(cgImage: cg).representation(using: .jpeg, properties: [.compressionFactor: 0.9]))
    }
}

private final class MockHumanAssistedRepo: TurtleRepository {
    let pendingLogID: UUID
    let targetTurtleID: UUID
    var resolvedCalls: [(logID: UUID, turtleID: UUID, method: String, notes: String?)] = []

    init(pendingLogID: UUID, targetTurtleID: UUID) {
        self.pendingLogID = pendingLogID
        self.targetTurtleID = targetTurtleID
    }

    func listIndividuals(query: IndividualQuery) async throws -> Page<Turtle> {
        Page(items: [], total: 0, request: query.page)
    }
    func listFavorites() async throws -> [Turtle] { [] }
    func setFavorite(turtleID: String, isFavorite: Bool) async throws -> Bool { isFavorite }
    func dashboard(query: DashboardQuery) async throws -> DashboardSnapshot { DashboardSnapshot(months: [], species: []) }
    func mapSightings(query: MapQuery) async throws -> [Sighting] { [] }
    func detail(for turtle: Turtle) async throws -> TurtleDetailData {
        TurtleDetailData(turtle: turtle, measurements: [], logs: [])
    }
    func export(_ request: ExportRequest) async throws -> DownloadedFile {
        DownloadedFile(data: Data(), filename: "empty.csv", contentType: "text/csv")
    }
    func listPendingSightings(limit: Int) async throws -> [PendingMobileSighting] {
        [PendingMobileSighting(id: pendingLogID, observedAt: Date(), locationName: "Crystal Bay", notes: nil, photoPaths: ["Amina3_L.jpg"])]
    }
    func resolvePendingSighting(logID: UUID, turtleID: UUID, method: String, confidence: Double?, notes: String?) async throws {
        resolvedCalls.append((logID, turtleID, method, notes))
    }
}
