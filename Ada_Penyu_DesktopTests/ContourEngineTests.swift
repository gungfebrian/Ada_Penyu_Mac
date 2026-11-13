import AppKit
import XCTest
@testable import Ada_Penyu_Desktop

final class ContourEngineTests: XCTestCase {
    func testFlatPhotographDoesNotCreateEdgesAtZeroCutoff() throws {
        let field = try XCTUnwrap(ContourEngine.detect(luminance: [Float](repeating: 0.4, count: 144),
            width: 12, height: 12, smooth: true))
        XCTAssertEqual(field.mask(threshold: 0).filter { $0 > 0 }.count, 0)
    }

    func testNonmaximumSuppressionThinsABroadGradientToOneBoundary() throws {
        let pixels: [Float] = (0..<144).map { $0 % 12 < 6 ? 0 : 1 }
        let field = try XCTUnwrap(ContourEngine.detect(luminance: pixels, width: 12, height: 12, smooth: false))
        let mask = field.mask(threshold: 0.5)
        XCTAssertEqual(mask.filter { $0 > 0 }.count, 10)
    }

    func testHysteresisKeepsConnectedWeakDetailAndRejectsIsolatedNoise() {
        var strengths = [Float](repeating: 0, count: 81)
        strengths[4 * 9 + 2] = 0.9
        strengths[4 * 9 + 3] = 0.25
        strengths[4 * 9 + 4] = 0.25
        strengths[1 * 9 + 7] = 0.25
        let field = ContourField(width: 9, height: 9, strengths: strengths)
        let mask = field.mask(threshold: 0.5)
        XCTAssertEqual(mask[4 * 9 + 4], 255)
        XCTAssertEqual(mask[1 * 9 + 7], 0)
    }

    func testHigherCutoffKeepsASubsetAndUsesAbsoluteContrastAcrossPhotos() throws {
        let strong: [Float] = (0..<144).map { $0 % 12 < 6 ? 0 : 1 }
        let weak = strong.map { $0 * 0.15 }
        let a = try XCTUnwrap(ContourEngine.detect(luminance: strong, width: 12, height: 12, smooth: false))
        let b = try XCTUnwrap(ContourEngine.detect(luminance: weak, width: 12, height: 12, smooth: false))
        XCTAssertGreaterThan(a.mask(threshold: 0.3).filter { $0 > 0 }.count, 0)
        XCTAssertEqual(b.mask(threshold: 0.3).filter { $0 > 0 }.count, 0)
        XCTAssertTrue(zip(a.mask(threshold: 0.1), a.mask(threshold: 0.8)).allSatisfy { $1 == 0 || $0 > 0 })
    }

    func testLineWeightMakesExistingEdgesMoreVisibleWithoutDetectingNewOnes() {
        var strengths = [Float](repeating: 0, count: 81)
        strengths[40] = 1
        let field = ContourField(width: 9, height: 9, strengths: strengths)
        XCTAssertEqual(field.mask(threshold: 0.5, lineWeight: 1).filter { $0 > 0 }.count, 1)
        XCTAssertEqual(field.mask(threshold: 0.5, lineWeight: 2).filter { $0 > 0 }.count, 9)
    }

    func testMalformedRasterIsRejected() {
        XCTAssertNil(ContourEngine.detect(luminance: [0], width: 10, height: 10, smooth: false))
        XCTAssertNil(ContourEngine.detect(luminance: [], width: 0, height: 0, smooth: false))
    }

    @MainActor
    func testRasterAndOverlayKeepAsymmetricPhotoOrientation() throws {
        let width = 12, height = 18
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let value: UInt8 = x < 4 && y < 6 ? 255 : 0
                rgba[i] = value; rgba[i + 1] = value; rgba[i + 2] = value; rgba[i + 3] = 255
            }
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(rgba) as CFData))
        let cg = try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let raster = try XCTUnwrap(ContourRasterizer.luminance(from: NSImage(cgImage: cg,
            size: NSSize(width: width, height: height))))
        XCTAssertGreaterThan(raster.pixels[width + 1], 0.99)
        let field = try XCTUnwrap(ContourEngine.detect(luminance: raster.pixels, width: width, height: height, smooth: false))
        let overlay = try XCTUnwrap(ContourRasterizer.overlay(field: field, mask: field.mask(threshold: 0.1)))
        let output = try XCTUnwrap(overlay.cgImage(forProposedRect: nil, context: nil, hints: nil)?.dataProvider?.data) as Data
        XCTAssertTrue((0..<(width * 7)).contains { output[$0 * 4 + 3] > 0 })
        XCTAssertTrue(((height - 6) * width..<(height * width)).allSatisfy { output[$0 * 4 + 3] == 0 })
    }
}
