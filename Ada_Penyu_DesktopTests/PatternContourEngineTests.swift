import AppKit
import XCTest
@testable import Ada_Penyu_Desktop

@MainActor
final class PatternContourEngineTests: XCTestCase {
    func testExtractsMultipleNumberedScaleContoursInsideBundledROIs() throws {
        let samples = I3SSampleLibrary.samples
        XCTAssertFalse(samples.isEmpty, "Bundled sea turtle sample library must not be empty")

        for sample in samples {
            let image = try XCTUnwrap(I3SSampleLibrary.loadImage(for: sample), "Missing image for \(sample.id)")
            let w = Double(max(1, sample.imageWidth))
            let h = Double(max(1, sample.imageHeight))
            let roi = sample.roi.compactMap { pair -> ScalePoint? in
                guard pair.count >= 2 else { return nil }
                return ScalePoint(x: pair[0] / w, y: pair[1] / h)
            }
            let patterns = PatternContourEngine.extractPatterns(from: image, roiPolygon: roi)
            XCTAssertGreaterThanOrEqual(
                patterns.count,
                4,
                "Expected >= 4 real scale patterns inside ROI for \(sample.id), got \(patterns.count)"
            )
            XCTAssertEqual(patterns.map(\.number), Array(1...patterns.count), "Numbers must be 1..N for \(sample.id)")
            for pat in patterns {
                XCTAssertGreaterThanOrEqual(pat.polygon.count, 3)
                XCTAssertGreaterThan(pat.imageArea, 0)
                XCTAssertGreaterThanOrEqual(pat.aspectRatio, 1.0)
            }
        }
    }

    func testAutoDetectFacialPatternROILocalizesCheekScalesWithoutHardcodedBox() throws {
        let samplesToCheck = ["Amina1_L", "Amina3_L", "Aikane2_L", "Zizo1_R"]
        for sid in samplesToCheck {
            let sample = try XCTUnwrap(I3SSampleLibrary.sample(forFilenameOrID: sid))
            let image = try XCTUnwrap(I3SSampleLibrary.loadImage(for: sample))
            let detected = PatternContourEngine.detectFacialPatternROI(from: image, side: sample.photoSide)
            XCTAssertGreaterThanOrEqual(detected.roi.count, 4)

            let patterns = PatternContourEngine.extractPatterns(from: image, roiPolygon: detected.roi)
            XCTAssertGreaterThanOrEqual(patterns.count, 4, "Auto-detected ROI for \(sid) should isolate multiple scale patterns")
        }
    }

    func testManualCalculatorComputesAffineAlignmentAndShapeScoreOnSameIndividual() throws {
        let qSample = try XCTUnwrap(I3SSampleLibrary.sample(forFilenameOrID: "Amina3_L"))
        let cSample = try XCTUnwrap(I3SSampleLibrary.sample(forFilenameOrID: "Amina1_L"))
        let qImg = try XCTUnwrap(I3SSampleLibrary.loadImage(for: qSample))
        let cImg = try XCTUnwrap(I3SSampleLibrary.loadImage(for: cSample))

        let qROI = qSample.roi.compactMap { $0.count >= 2 ? ScalePoint(x: $0[0] / Double(qSample.imageWidth), y: $0[1] / Double(qSample.imageHeight)) : nil }
        let cROI = cSample.roi.compactMap { $0.count >= 2 ? ScalePoint(x: $0[0] / Double(cSample.imageWidth), y: $0[1] / Double(cSample.imageHeight)) : nil }

        let qPatterns = PatternContourEngine.extractPatterns(from: qImg, roiPolygon: qROI)
        let cPatterns = PatternContourEngine.extractPatterns(from: cImg, roiPolygon: cROI)

        let autoPairs = PatternMatchCalculator.autoSuggestPairs(
            query: qPatterns,
            candidate: cPatterns,
            queryFP: qSample.fingerprint,
            candidateFP: cSample.fingerprint,
            queryImageSize: qImg.size,
            candidateImageSize: cImg.size,
            queryROI: qROI,
            candidateROI: cROI
        )
        XCTAssertGreaterThanOrEqual(autoPairs.count, 3, "Expected >= 3 matched pattern pairs between Amina3_L and Amina1_L")

        let calc = PatternMatchCalculator.calculate(
            query: qPatterns,
            candidate: cPatterns,
            pairs: autoPairs,
            queryROI: qROI,
            candidateROI: cROI
        )
        XCTAssertEqual(calc.pairCount, autoPairs.count)
        XCTAssertNotNil(calc.affineResidualPercent)
        XCTAssertEqual(calc.warpedQueryContours.count, qPatterns.count)
        XCTAssertGreaterThan(calc.combinedScorePercent, 45)
    }

    func testExtractsWatertightPolygonalScaleSutureMeshAcrossBundledTurtles() throws {
        let sampleIDs = ["Amina1_L", "Amina3_L", "Ghost1_L", "Zizo1_R"]
        for sid in sampleIDs {
            let sample = try XCTUnwrap(I3SSampleLibrary.sample(forFilenameOrID: sid))
            let image = try XCTUnwrap(I3SSampleLibrary.loadImage(for: sample))
            let w = Double(max(1, sample.imageWidth))
            let h = Double(max(1, sample.imageHeight))
            let roi = sample.roi.compactMap { pair -> ScalePoint? in
                guard pair.count >= 2 else { return nil }
                return ScalePoint(x: pair[0] / w, y: pair[1] / h)
            }
            let mesh = PatternContourEngine.extractScaleSutureMesh(from: image, roiPolygon: roi)
            XCTAssertGreaterThanOrEqual(mesh.cells.count, 4, "Expected >= 4 polygonal suture cells for \(sid)")
            XCTAssertGreaterThanOrEqual(mesh.edges.count, 8, "Expected shared suture edges for \(sid)")
            XCTAssertGreaterThanOrEqual(mesh.vertices.count, 6, "Expected shared junction vertices for \(sid)")

            if let firstV = mesh.vertices.first {
                let shifted = ScalePoint(x: min(0.95, firstV.point.x + 0.02), y: min(0.95, firstV.point.y + 0.02))
                let moved = mesh.movingVertex(id: firstV.id, to: shifted)
                XCTAssertEqual(moved.vertices.first?.point, shifted)
            }
        }
    }
}
