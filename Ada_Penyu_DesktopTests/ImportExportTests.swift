import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Ada_Penyu_Desktop

@MainActor
final class ImportExportTests: XCTestCase {
    // MARK: - HEIC / PNG / JPEG Normalization & EXIF Extraction

    func testNormalizesHEICPNGAndJPEGWithEXIFDateAndGPS() throws {
        let baseCG = try makeSolidCGImage(width: 160, height: 120)
        let exifProps: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2026:11:19 09:42:15",
            ],
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 8.7142,
                kCGImagePropertyGPSLatitudeRef: "S",
                kCGImagePropertyGPSLongitude: 115.4581,
                kCGImagePropertyGPSLongitudeRef: "E",
            ],
        ]

        // 1. JPEG with EXIF date + GPS
        let jpegBytes = try encodeImage(baseCG, type: .jpeg, properties: exifProps)
        let normJPEG = try PhotoImportNormalizer.normalize(data: jpegBytes, filename: "CrystalBay_01_L.jpeg")
        XCTAssertEqual(normJPEG.originalFormat, "JPG")
        XCTAssertEqual(normJPEG.side, .left)
        XCTAssertTrue(normJPEG.sideWasInferred)
        XCTAssertEqual(normJPEG.pairStem, "CrystalBay_01")
        XCTAssertNotNil(normJPEG.capturedAt)
        let coord = try XCTUnwrap(normJPEG.coordinate)
        XCTAssertEqual(coord.latitude, -8.7142, accuracy: 0.001)
        XCTAssertEqual(coord.longitude, 115.4581, accuracy: 0.001)

        // 2. PNG
        let pngBytes = try encodeImage(baseCG, type: .png, properties: nil)
        let normPNG = try PhotoImportNormalizer.normalize(data: pngBytes, filename: "Reef_Right.png")
        XCTAssertEqual(normPNG.originalFormat, "PNG")
        XCTAssertEqual(normPNG.side, .right)
        XCTAssertTrue(normPNG.sideWasInferred)
        XCTAssertNotNil(NSImage(data: normPNG.jpegData))

        // 3. HEIC (native macOS ImageIO encode & decode)
        let heicBytes = try encodeImage(baseCG, type: .heic, properties: exifProps)
        let normHEIC = try PhotoImportNormalizer.normalize(data: heicBytes, filename: "IMG_4021_R.HEIC")
        XCTAssertEqual(normHEIC.originalFormat, "HEIC")
        XCTAssertEqual(normHEIC.side, .right)
        XCTAssertTrue(normHEIC.sideWasInferred)
        XCTAssertEqual(normHEIC.pairStem, "IMG_4021")
        XCTAssertEqual(try XCTUnwrap(normHEIC.coordinate).latitude, -8.7142, accuracy: 0.001)
        XCTAssertNotNil(NSImage(data: normHEIC.jpegData))
    }

    func testSideInferenceAvoidsFalsePositivesOnOrdinaryWords() {
        XCTAssertEqual(PhotoImportNormalizer.inferSideAndStem(from: "Amina1_L.heic").side, .left)
        XCTAssertEqual(PhotoImportNormalizer.inferSideAndStem(from: "Amina1_L.heic").stem, "Amina1")
        XCTAssertEqual(PhotoImportNormalizer.inferSideAndStem(from: "IMG-04-right.JPG").side, .right)
        XCTAssertEqual(PhotoImportNormalizer.inferSideAndStem(from: "left_patrol_02.png").side, .left)
        // Words ending in 'l' or 'r' (coral, water, turtle) must NOT false-trigger!
        XCTAssertNil(PhotoImportNormalizer.inferSideAndStem(from: "coral.jpg").side)
        XCTAssertNil(PhotoImportNormalizer.inferSideAndStem(from: "turtle_water.heic").side)
    }

    func testBatchScannerRecursesFoldersAndAutoPairsLeftRight() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "AdaPenyu-BatchScan-\(UUID().uuidString)", directoryHint: .isDirectory)
        let sub = dir.appending(path: "PatrolMorning", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let cg = try makeSolidCGImage(width: 96, height: 72)
        try encodeImage(cg, type: .heic, properties: nil).write(to: sub.appending(path: "Amina_L.heic"))
        try encodeImage(cg, type: .png, properties: nil).write(to: sub.appending(path: "Amina_R.png"))
        try encodeImage(cg, type: .jpeg, properties: nil).write(to: sub.appending(path: "Solo_Photo.jpg"))
        try Data("not an image".utf8).write(to: sub.appending(path: "notes.txt"))

        let scan = PhotoBatchGrouper.scan(urls: [dir])
        XCTAssertEqual(scan.photos.count, 3)
        XCTAssertEqual(scan.skippedFiles.count, 1)
        XCTAssertEqual(scan.skippedFiles.first?.filename, "notes.txt")

        let grouped = PhotoBatchGrouper.group(scan.photos)
        XCTAssertEqual(grouped.count, 2)
        let paired = try XCTUnwrap(grouped.first { $0.isPaired })
        XCTAssertEqual(paired.title, "Amina")
        XCTAssertEqual(paired.leftPhoto?.originalFormat, "HEIC")
        XCTAssertEqual(paired.rightPhoto?.originalFormat, "PNG")
    }

    // MARK: - CSV & XLSX Round-Trip Catalog Import

    func testCSVAndXLSXRoundTripCatalogImportAndValidation() async throws {
        // 1. Export real XLSX via ExportFileBuilder, then re-import with CatalogImportParser!
        let repo = DemoTurtleRepository(dataset: .baliBaseline)
        let exported = try await repo.export(ExportRequest(
            scope: .all,
            range: .all,
            fields: [.profile, .coordinates],
            format: .xlsx,
            query: IndividualQuery()
        ))

        let parsedXLSX = try CatalogImportParser.parseXLSX(data: exported.data)
        XCTAssertEqual(parsedXLSX.count, DemoFixtures.turtles.count)
        XCTAssertTrue(parsedXLSX.allSatisfy(\.isValid))

        // 2. CSV with quoted commas + validation checks (duplicate & missing name)
        let csv = """
        Profile Code,Name,Species,Sex,First Recorded,Location,Latitude,Longitude
        009901,"Amina, Bali",Green turtle,female,2026-10-12,"Crystal Bay, Nusa Penida",-8.7142,115.4581
        009901,Duplicate Code Turtle,Hawksbill,male,2026-10-13,Toyapakeh,-8.68,115.47
        009902,,Olive Ridley,unknown,2026-10-14,Sanur,-8.70,115.26
        009903,Wayan,Leatherback,male,2026-10-15,Gili,-8.35,116.04
        """
        let rows = try CatalogImportParser.parseCSV(data: Data(csv.utf8))
        XCTAssertEqual(rows.count, 4)
        XCTAssertTrue(rows[0].isValid)
        XCTAssertEqual(rows[0].name, "Amina, Bali")
        XCTAssertEqual(rows[0].species, .green)
        XCTAssertEqual(rows[0].sex, "female")
        XCTAssertFalse(rows[1].isValid) // duplicate code
        XCTAssertFalse(rows[2].isValid) // missing name
        XCTAssertTrue(rows[3].isValid)
        XCTAssertEqual(rows[3].species, .leatherback)
    }

    // MARK: - End-to-End Store Batch Photo, Catalog & Not Sure Bundle Flows

    func testStoreImportsBatchPhotosToNotSureAndEnrollsNewTurtlesInDemoMode() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "AdaPenyu-StoreImport-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = AppStore(reviewJournal: NotSureReviewJournal(directory: dir))
        store.enterDemoWorkspace(persona: .demoResearcher)

        let cg = try makeSolidCGImage(width: 120, height: 90)
        let leftData = try encodeImage(cg, type: .jpeg, properties: nil)
        let rightData = try encodeImage(cg, type: .jpeg, properties: nil)
        let encounter = StagedPhotoEncounter(
            title: "Imported_Pair_01",
            primary: StagedImportPhoto(
                filename: "Imported_Pair_01_L.heic", originalFormat: "HEIC",
                jpegData: leftData, pixelWidth: 120, pixelHeight: 90,
                side: .left, sideWasInferred: true, pairStem: "Imported_Pair_01"
            ),
            companion: StagedImportPhoto(
                filename: "Imported_Pair_01_R.heic", originalFormat: "HEIC",
                jpegData: rightData, pixelWidth: 120, pixelHeight: 90,
                side: .right, sideWasInferred: true, pairStem: "Imported_Pair_01"
            )
        )

        // 1. Offline send to Not Sure Queue
        let queueSummary = await store.importPhotoEncounters([encounter], destination: .notSureQueue)
        XCTAssertEqual(queueSummary.importedCount, 1)
        XCTAssertEqual(queueSummary.escalatedToNotSureCount, 1)
        XCTAssertEqual(store.escalatedNotSureCases.count, 1)
        XCTAssertNotNil(store.escalatedNotSureCases.first?.companionImage)

        // 2. Not Sure Bundle JSON export/import round-trip
        let bundleData = try NotSureReviewBundle.encode(store.escalatedNotSureCases, account: "Demo")
        let decodedBundle = try NotSureReviewBundle.decode(bundleData)
        XCTAssertEqual(decodedBundle.count, 1)
        XCTAssertEqual(decodedBundle.first?.title, "Imported_Pair_01")

        // 3. Enroll New Turtle + upload L/R photos
        let enrollSummary = await store.importPhotoEncounters([encounter], destination: .enrollNew)
        XCTAssertEqual(enrollSummary.importedCount, 1)
        XCTAssertEqual(enrollSummary.failedCount, 0)
        XCTAssertTrue(store.allKnownTurtles.contains { $0.displayName == "Imported_Pair_01" })
    }

    // MARK: - Helpers

    private func makeSolidCGImage(width: Int, height: Int) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw NSError(domain: "ImportExportTests", code: 1)
        }
        ctx.setFillColor(CGColor(red: 0.1, green: 0.45, blue: 0.52, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(ctx.makeImage())
    }

    private func encodeImage(_ image: CGImage, type: UTType, properties: [CFString: Any]?) throws -> Data {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, type.identifier as CFString, 1, nil) else {
            throw NSError(domain: "ImportExportTests", code: 2)
        }
        CGImageDestinationAddImage(dest, image, properties as CFDictionary?)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return out as Data
    }
}
