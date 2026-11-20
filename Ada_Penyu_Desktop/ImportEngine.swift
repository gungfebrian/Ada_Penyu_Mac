import AppKit
import Compression
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Supported Import Types

enum ImportFileKind: Equatable, Sendable {
    case image
    case spreadsheet
    case notSureBundle
    case unsupported
}

enum PhotoBatchDestination: String, CaseIterable, Identifiable, Sendable {
    case matchAndTriage = "Match & Triage"
    case notSureQueue = "Not Sure Queue"
    case enrollNew = "Enroll New"

    var id: Self { self }

    var icon: String {
        switch self {
        case .matchAndTriage: "sparkles"
        case .notSureQueue: "tray.and.arrow.down"
        case .enrollNew: "plus.circle"
        }
    }

    var shortHint: String {
        switch self {
        case .matchAndTriage: "Run open-set matcher · send uncertain matches to Not Sure"
        case .notSureQueue: "Save directly into Not Sure Queue (works offline)"
        case .enrollNew: "Create individual profiles and upload Left/Right photos"
        }
    }
}

// MARK: - Staged Photo Models

struct StagedImportPhoto: Identifiable, Sendable {
    let id: UUID
    let sourceURL: URL?
    let filename: String
    let originalFormat: String
    let jpegData: Data
    let pixelWidth: Int
    let pixelHeight: Int
    let capturedAt: Date?
    let coordinate: TurtleCoordinate?
    var side: TurtlePhotoSide
    let sideWasInferred: Bool
    let pairStem: String

    init(
        id: UUID = UUID(),
        sourceURL: URL? = nil,
        filename: String,
        originalFormat: String,
        jpegData: Data,
        pixelWidth: Int,
        pixelHeight: Int,
        capturedAt: Date? = nil,
        coordinate: TurtleCoordinate? = nil,
        side: TurtlePhotoSide,
        sideWasInferred: Bool,
        pairStem: String
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.filename = filename
        self.originalFormat = originalFormat
        self.jpegData = jpegData
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.capturedAt = capturedAt
        self.coordinate = coordinate
        self.side = side
        self.sideWasInferred = sideWasInferred
        self.pairStem = pairStem
    }

    var previewImage: NSImage? { NSImage(data: jpegData) }
}

struct StagedPhotoEncounter: Identifiable, Sendable {
    let id: UUID
    var title: String
    var primary: StagedImportPhoto
    var companion: StagedImportPhoto?

    init(id: UUID = UUID(), title: String, primary: StagedImportPhoto, companion: StagedImportPhoto? = nil) {
        self.id = id
        self.title = title
        self.primary = primary
        self.companion = companion
    }

    var isPaired: Bool { companion != nil }
    var capturedAt: Date? { primary.capturedAt ?? companion?.capturedAt }
    var coordinate: TurtleCoordinate? { primary.coordinate ?? companion?.coordinate }

    var leftPhoto: StagedImportPhoto? {
        if primary.side == .left { return primary }
        if companion?.side == .left { return companion }
        return nil
    }

    var rightPhoto: StagedImportPhoto? {
        if primary.side == .right { return primary }
        if companion?.side == .right { return companion }
        return nil
    }
}

// MARK: - Staged Catalog Spreadsheet Models

struct StagedCatalogRow: Identifiable, Sendable {
    let id: UUID
    let rowNumber: Int
    let profileCode: String
    let name: String
    let species: TurtleSpecies
    let sex: String
    let firstSeenAt: Date
    let location: String
    let coordinate: TurtleCoordinate?
    let condition: TurtleCondition
    let leftPhotoFilename: String?
    let rightPhotoFilename: String?
    let validationError: String?

    var isValid: Bool { validationError == nil }

    var draft: IndividualDraft? {
        guard isValid else { return nil }
        return IndividualDraft(
            profileCode: profileCode,
            name: name,
            species: species.apiValue,
            sex: sex,
            firstSeenAt: firstSeenAt
        )
    }
}

struct ImportScanResult: Sendable {
    var photos: [StagedImportPhoto] = []
    var catalogRows: [StagedCatalogRow] = []
    var notSureCases: [EscalatedNotSureCase] = []
    var skippedFiles: [(filename: String, reason: String)] = []
    var sourceLabel: String = ""
}

// MARK: - Not Sure Bundle Handoff Codec

struct NotSureReviewBundle: Codable {
    let schemaVersion: Int
    let exportedAt: Date
    let sourceAccount: String
    let cases: [EscalatedNotSureCase]

    static func encode(_ cases: [EscalatedNotSureCase], account: String) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let bundle = NotSureReviewBundle(
            schemaVersion: 1,
            exportedAt: Date(),
            sourceAccount: account,
            cases: cases
        )
        return try encoder.encode(bundle)
    }

    static func decode(_ data: Data) throws -> [EscalatedNotSureCase] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let bundle = try? decoder.decode(NotSureReviewBundle.self, from: data) {
            return bundle.cases
        }
        if let direct = try? JSONDecoder().decode([EscalatedNotSureCase].self, from: data) {
            return direct
        }
        throw ImportError.unreadableBundle
    }
}

enum ImportError: LocalizedError {
    case unreadableImage(String)
    case unreadableSpreadsheet(String)
    case unreadableBundle
    case noValidItems

    var errorDescription: String? {
        switch self {
        case .unreadableImage(let name): "Could not decode image \(name)."
        case .unreadableSpreadsheet(let reason): "Could not read spreadsheet: \(reason)"
        case .unreadableBundle: "File is not a valid Ada Penyu review bundle."
        case .noValidItems: "No valid items to import."
        }
    }
}

// MARK: - Photo Import Normalizer (HEIC / HEIF / JPEG / PNG / WebP / TIFF + EXIF)

nonisolated enum PhotoImportNormalizer {
    static let imageExtensions: Set<String> = [
        "heic", "heif", "jpg", "jpeg", "png", "webp", "tif", "tiff"
    ]
    static let spreadsheetExtensions: Set<String> = ["csv", "tsv", "xlsx"]

    static var panelAllowedContentTypes: [UTType] {
        var types: [UTType] = [.heic, .heif, .jpeg, .png, .webP, .tiff, .commaSeparatedText, .tabSeparatedText, .json, .folder]
        if let xlsx = UTType(filenameExtension: "xlsx") {
            types.append(xlsx)
        }
        return types
    }

    static func classify(url: URL) -> ImportFileKind {
        let ext = url.pathExtension.lowercased()
        if imageExtensions.contains(ext) { return .image }
        if spreadsheetExtensions.contains(ext) { return .spreadsheet }
        if ext == "json" { return .notSureBundle }
        return .unsupported
    }

    /// Decodes HEIC/HEIF/JPEG/PNG/WebP/TIFF via ImageIO, applies EXIF orientation,
    /// caps longest edge to `maxPixelDimension`, extracts EXIF timestamp & GPS, and encodes clean JPEG.
    static func normalize(
        url: URL,
        maxPixelDimension: Int = 2048,
        jpegQuality: Double = 0.90
    ) throws -> StagedImportPhoto {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let rawData = try Data(contentsOf: url)
        return try normalize(
            data: rawData,
            filename: url.lastPathComponent,
            sourceURL: url,
            maxPixelDimension: maxPixelDimension,
            jpegQuality: jpegQuality
        )
    }

    static func normalize(
        data: Data,
        filename: String,
        sourceURL: URL? = nil,
        maxPixelDimension: Int = 2048,
        jpegQuality: Double = 0.90
    ) throws -> StagedImportPhoto {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw ImportError.unreadableImage(filename)
        }

        let properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
        let capturedAt = extractCaptureDate(from: properties)
        let coordinate = extractCoordinate(from: properties)

        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelDimension,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary)
                ?? CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ImportError.unreadableImage(filename)
        }

        let jpegOut = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(jpegOut, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ImportError.unreadableImage(filename)
        }
        let encodeOptions: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: jpegQuality,
        ]
        CGImageDestinationAddImage(dest, cgImage, encodeOptions as CFDictionary)
        guard CGImageDestinationFinalize(dest), jpegOut.length > 0 else {
            throw ImportError.unreadableImage(filename)
        }

        let inferred = inferSideAndStem(from: filename)
        let ext = (filename as NSString).pathExtension.uppercased()
        let formatLabel = ext.isEmpty ? "IMG" : (ext == "JPEG" ? "JPG" : ext)

        return StagedImportPhoto(
            sourceURL: sourceURL,
            filename: filename,
            originalFormat: formatLabel,
            jpegData: jpegOut as Data,
            pixelWidth: cgImage.width,
            pixelHeight: cgImage.height,
            capturedAt: capturedAt,
            coordinate: coordinate,
            side: inferred.side ?? .left,
            sideWasInferred: inferred.side != nil,
            pairStem: inferred.stem
        )
    }

    /// Infers `Left` vs `Right` strictly from side tokens (`_L`, `_R`, `-left`, `-right`, `(L)`, `(R)`)
    /// without false-matching letters inside ordinary words like `"turtle"` or `"coral"`.
    static func inferSideAndStem(from filename: String) -> (side: TurtlePhotoSide?, stem: String) {
        let base = (filename as NSString).deletingPathExtension
        let patterns: [(regex: String, side: TurtlePhotoSide)] = [
            ("(?i)([_\\-\\s\\.\\(])(left|l)(\\))?$", .left),
            ("(?i)([_\\-\\s\\.\\(])(right|r)(\\))?$", .right),
            ("(?i)^(left|l)([_\\-\\s\\.])", .left),
            ("(?i)^(right|r)([_\\-\\s\\.])", .right),
        ]

        for entry in patterns {
            if let range = base.range(of: entry.regex, options: .regularExpression) {
                var stem = base
                stem.removeSubrange(range)
                let cleaned = stem.trimmingCharacters(in: CharacterSet(charactersIn: " _-.()"))
                return (entry.side, cleaned.isEmpty ? base : cleaned)
            }
        }
        return (nil, base)
    }

    private static func extractCaptureDate(from properties: [CFString: Any]) -> Date? {
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let raw = (exif?[kCGImagePropertyExifDateTimeOriginal] as? String)
            ?? (exif?[kCGImagePropertyExifDateTimeDigitized] as? String)
            ?? (tiff?[kCGImagePropertyTIFFDateTime] as? String)
        guard let raw, !raw.isEmpty else { return nil }

        let exifFormatter = DateFormatter()
        exifFormatter.locale = Locale(identifier: "en_US_POSIX")
        exifFormatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        if let parsed = exifFormatter.date(from: raw) { return parsed }
        return ISO8601DateFormatter().date(from: raw)
    }

    private static func extractCoordinate(from properties: [CFString: Any]) -> TurtleCoordinate? {
        guard let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
              let latRaw = gps[kCGImagePropertyGPSLatitude] as? Double,
              let lonRaw = gps[kCGImagePropertyGPSLongitude] as? Double else {
            return nil
        }
        let latRef = (gps[kCGImagePropertyGPSLatitudeRef] as? String)?.uppercased() ?? "N"
        let lonRef = (gps[kCGImagePropertyGPSLongitudeRef] as? String)?.uppercased() ?? "E"
        let lat = latRef == "S" ? -abs(latRaw) : abs(latRaw)
        let lon = lonRef == "W" ? -abs(lonRaw) : abs(lonRaw)
        guard (-90...90).contains(lat), (-180...180).contains(lon), !(lat == 0 && lon == 0) else {
            return nil
        }
        return TurtleCoordinate(latitude: lat, longitude: lon)
    }
}

// MARK: - Batch Scanner & Auto Left/Right Pairing

nonisolated enum PhotoBatchGrouper {
    /// Expands files and folders recursively, normalizing supported photos, parsing spreadsheets,
    /// and collecting any skipped items cleanly.
    static func scan(urls: [URL], existingProfileCodes: Set<String> = []) -> ImportScanResult {
        var result = ImportScanResult()
        var flatFiles: [URL] = []

        for url in urls {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }

            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
                result.skippedFiles.append((url.lastPathComponent, "File not found"))
                continue
            }

            if isDir.boolValue {
                if let enumerator = FileManager.default.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) {
                    for case let child as URL in enumerator {
                        if child.path.contains("__MACOSX") { continue }
                        let values = try? child.resourceValues(forKeys: [.isRegularFileKey])
                        if values?.isRegularFile == true {
                            flatFiles.append(child)
                        }
                    }
                }
            } else {
                flatFiles.append(url)
            }
        }

        flatFiles.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        result.sourceLabel = urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) items"

        for fileURL in flatFiles {
            switch PhotoImportNormalizer.classify(url: fileURL) {
            case .image:
                do {
                    let photo = try PhotoImportNormalizer.normalize(url: fileURL)
                    result.photos.append(photo)
                } catch {
                    result.skippedFiles.append((fileURL.lastPathComponent, error.localizedDescription))
                }
            case .spreadsheet:
                do {
                    let rows = try CatalogImportParser.parse(url: fileURL, existingCodes: existingProfileCodes)
                    result.catalogRows.append(contentsOf: rows)
                } catch {
                    result.skippedFiles.append((fileURL.lastPathComponent, error.localizedDescription))
                }
            case .notSureBundle:
                do {
                    let accessed = fileURL.startAccessingSecurityScopedResource()
                    defer { if accessed { fileURL.stopAccessingSecurityScopedResource() } }
                    let data = try Data(contentsOf: fileURL)
                    let decoded = try NotSureReviewBundle.decode(data)
                    result.notSureCases.append(contentsOf: decoded)
                } catch {
                    result.skippedFiles.append((fileURL.lastPathComponent, error.localizedDescription))
                }
            case .unsupported:
                result.skippedFiles.append((fileURL.lastPathComponent, "Unsupported format"))
            }
        }

        return result
    }

    /// Pairs matching Left + Right photos into single encounters by matching filename stem
    /// (`Amina_L.heic` + `Amina_R.heic`) or opposite-side EXIF timestamps within `timeWindowSeconds`.
    static func group(_ photos: [StagedImportPhoto], timeWindowSeconds: TimeInterval = 300) -> [StagedPhotoEncounter] {
        var used = Set<UUID>()
        var encounters: [StagedPhotoEncounter] = []

        // Pass 1: Pair exact stem matches (e.g., Amina1_L.jpg + Amina1_R.jpg)
        for i in photos.indices {
            let a = photos[i]
            guard !used.contains(a.id) else { continue }
            guard a.sideWasInferred else { continue }
            if let j = photos.indices.first(where: { idx in
                idx > i &&
                !used.contains(photos[idx].id) &&
                photos[idx].sideWasInferred &&
                photos[idx].side != a.side &&
                photos[idx].pairStem.caseInsensitiveCompare(a.pairStem) == .orderedSame
            }) {
                let b = photos[j]
                used.insert(a.id)
                used.insert(b.id)
                let (primary, companion) = a.side == .left ? (a, b) : (b, a)
                encounters.append(StagedPhotoEncounter(
                    title: primary.pairStem,
                    primary: primary,
                    companion: companion
                ))
            }
        }

        // Pass 2: Pair opposite-side photos captured within ±5 minutes (EXIF timestamp)
        let remaining = photos.filter { !used.contains($0.id) }
        for i in remaining.indices {
            let a = remaining[i]
            guard !used.contains(a.id), let dateA = a.capturedAt, a.sideWasInferred else { continue }
            if let match = remaining[(i + 1)...].first(where: { b in
                !used.contains(b.id) &&
                b.sideWasInferred &&
                b.side != a.side &&
                b.capturedAt.map { abs($0.timeIntervalSince(dateA)) <= timeWindowSeconds } == true
            }) {
                used.insert(a.id)
                used.insert(match.id)
                let (primary, companion) = a.side == .left ? (a, match) : (match, a)
                encounters.append(StagedPhotoEncounter(
                    title: primary.pairStem,
                    primary: primary,
                    companion: companion
                ))
            }
        }

        // Pass 3: Remaining standalone photos
        for photo in photos where !used.contains(photo.id) {
            encounters.append(StagedPhotoEncounter(
                title: photo.pairStem,
                primary: photo,
                companion: nil
            ))
        }

        return encounters
    }
}

// MARK: - Catalog Spreadsheet Parser (RFC-4180 CSV/TSV + Pure-Swift XLSX)

nonisolated enum CatalogImportParser {
    static func parse(url: URL, existingCodes: Set<String> = []) throws -> [StagedCatalogRow] {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let ext = url.pathExtension.lowercased()
        if ext == "xlsx" {
            let table = try parseXLSXTable(data: data)
            return buildRows(from: table, existingCodes: existingCodes)
        }
        let delimiter: Character = (ext == "tsv") ? "\t" : ","
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw ImportError.unreadableSpreadsheet("Unsupported text encoding.")
        }
        let table = parseDelimitedTable(text: text, delimiter: delimiter)
        return buildRows(from: table, existingCodes: existingCodes)
    }

    static func parseCSV(data: Data, existingCodes: Set<String> = []) throws -> [StagedCatalogRow] {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw ImportError.unreadableSpreadsheet("Unsupported text encoding.")
        }
        return buildRows(from: parseDelimitedTable(text: text, delimiter: ","), existingCodes: existingCodes)
    }

    static func parseXLSX(data: Data, existingCodes: Set<String> = []) throws -> [StagedCatalogRow] {
        let table = try parseXLSXTable(data: data)
        return buildRows(from: table, existingCodes: existingCodes)
    }

    // MARK: Row Mapping & Validation

    private static func buildRows(from table: [[String]], existingCodes: Set<String>) -> [StagedCatalogRow] {
        guard let rawHeaders = table.first, !rawHeaders.isEmpty else { return [] }
        let headers = rawHeaders.map { normalizeHeader($0) }

        func col(_ candidates: [String]) -> Int? {
            for candidate in candidates {
                if let idx = headers.firstIndex(of: candidate) { return idx }
            }
            return nil
        }

        let codeIdx = col(["profile_code", "profilecode", "code", "id"])
        let nameIdx = col(["name", "display_name", "displayname", "turtle_name", "turtle"])
        let speciesIdx = col(["species", "turtle_species"])
        let sexIdx = col(["sex", "gender"])
        let firstSeenIdx = col(["first_recorded", "firstrecorded", "first_seen", "first_seen_at", "date", "last_seen"])
        let locationIdx = col(["location", "site", "beach", "place"])
        let latIdx = col(["latitude", "lat"])
        let lonIdx = col(["longitude", "lon", "lng"])
        let conditionIdx = col(["condition", "health", "health_status", "status"])
        let leftPhotoIdx = col(["left_photo", "leftphoto", "left_photo_url"])
        let rightPhotoIdx = col(["right_photo", "rightphoto", "right_photo_url"])

        var seenCodes = existingCodes
        var autoSeed = 100_001
        var rows: [StagedCatalogRow] = []

        for (offset, cells) in table.dropFirst().enumerated() {
            let trimmedCells = cells.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if trimmedCells.allSatisfy(\.isEmpty) { continue }

            func cell(_ idx: Int?) -> String {
                guard let idx, trimmedCells.indices.contains(idx) else { return "" }
                return trimmedCells[idx]
            }

            let rawName = cell(nameIdx)
            let rawCode = cell(codeIdx)
            let normalizedCode: String
            if rawCode.isEmpty {
                while seenCodes.contains(String(format: "%06d", autoSeed)) { autoSeed += 1 }
                normalizedCode = String(format: "%06d", autoSeed)
                autoSeed += 1
            } else {
                let digits = rawCode.filter(\.isNumber)
                if digits.count == 6 {
                    normalizedCode = digits
                } else if !digits.isEmpty && digits.count < 6 {
                    normalizedCode = String(repeating: "0", count: 6 - digits.count) + digits
                } else {
                    normalizedCode = rawCode
                }
            }

            let species = parseSpecies(cell(speciesIdx))
            let sex = parseSex(cell(sexIdx))
            let firstSeenAt = parseDate(cell(firstSeenIdx)) ?? Date()
            let location = cell(locationIdx).isEmpty ? "Not recorded" : cell(locationIdx)
            let condition = TurtleCondition(apiValue: cell(conditionIdx)) ?? .unknown

            let coordinate: TurtleCoordinate?
            if let lat = Double(cell(latIdx)), let lon = Double(cell(lonIdx)),
               (-90...90).contains(lat), (-180...180).contains(lon) {
                coordinate = TurtleCoordinate(latitude: lat, longitude: lon)
            } else {
                coordinate = nil
            }

            var error: String?
            if rawName.isEmpty {
                error = "Missing name"
            } else if normalizedCode.count != 6 || !normalizedCode.allSatisfy(\.isNumber) {
                error = "Code must be 6 digits"
            } else if seenCodes.contains(normalizedCode) {
                error = "Duplicate code \(normalizedCode)"
            }

            if error == nil {
                seenCodes.insert(normalizedCode)
            }

            rows.append(StagedCatalogRow(
                id: UUID(),
                rowNumber: offset + 2,
                profileCode: normalizedCode,
                name: rawName.isEmpty ? "Unnamed Row \(offset + 2)" : rawName,
                species: species,
                sex: sex,
                firstSeenAt: firstSeenAt,
                location: location,
                coordinate: coordinate,
                condition: condition,
                leftPhotoFilename: cell(leftPhotoIdx).isEmpty ? nil : cell(leftPhotoIdx),
                rightPhotoFilename: cell(rightPhotoIdx).isEmpty ? nil : cell(rightPhotoIdx),
                validationError: error
            ))
        }

        return rows
    }

    private static func normalizeHeader(_ raw: String) -> String {
        raw.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}")))
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
    }

    private static func parseSpecies(_ raw: String) -> TurtleSpecies {
        let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.contains("green") || lower.contains("mydas") { return .green }
        if lower.contains("hawksbill") || lower.contains("imbricata") { return .hawksbill }
        if lower.contains("olive") || lower.contains("ridley") { return .oliveRidley }
        if lower.contains("loggerhead") || lower.contains("caretta") { return .loggerhead }
        if lower.contains("leatherback") || lower.contains("coriacea") { return .leatherback }
        return TurtleSpecies(apiValue: raw)
    }

    private static func parseSex(_ raw: String) -> String {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "male", "m": "male"
        case "female", "f": "female"
        default: "unknown"
        }
    }

    private static func parseDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.lowercased() != "not recorded" else { return nil }
        if let d = APIFormatters.display.date(from: trimmed) { return d }
        if let d = ISO8601DateFormatter().date(from: trimmed) { return d }
        let formats = ["yyyy-MM-dd", "dd MMM yyyy", "dd/MM/yyyy", "MM/dd/yyyy", "yyyy/MM/dd"]
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for fmt in formats {
            f.dateFormat = fmt
            if let d = f.date(from: trimmed) { return d }
        }
        return nil
    }

    // MARK: RFC-4180 Delimited Parser

    static func parseDelimitedTable(text: String, delimiter: Character) -> [[String]] {
        let clean = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentCell = ""
        var inQuotes = false
        var idx = clean.startIndex

        while idx < clean.endIndex {
            let ch = clean[idx]
            let nextIdx = clean.index(after: idx)

            if inQuotes {
                if ch == "\"" {
                    if nextIdx < clean.endIndex && clean[nextIdx] == "\"" {
                        currentCell.append("\"")
                        idx = clean.index(after: nextIdx)
                        continue
                    } else {
                        inQuotes = false
                    }
                } else {
                    currentCell.append(ch)
                }
            } else {
                if ch == "\"" && currentCell.isEmpty {
                    inQuotes = true
                } else if ch == delimiter {
                    currentRow.append(currentCell)
                    currentCell = ""
                } else if ch == "\r" || ch == "\n" {
                    currentRow.append(currentCell)
                    rows.append(currentRow)
                    currentRow = []
                    currentCell = ""
                    if ch == "\r" && nextIdx < clean.endIndex && clean[nextIdx] == "\n" {
                        idx = clean.index(after: nextIdx)
                        continue
                    }
                } else {
                    currentCell.append(ch)
                }
            }
            idx = nextIdx
        }

        if !currentCell.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentCell)
            rows.append(currentRow)
        }
        return rows
    }

    // MARK: Pure-Swift XLSX Reader (STORE + DEFLATE ZIP + XMLParser)

    private static func parseXLSXTable(data: Data) throws -> [[String]] {
        let entries = try unzipEntries(data: data)
        var sharedStrings: [String] = []
        if let ssData = entries["xl/sharedStrings.xml"] {
            sharedStrings = XLSXSharedStringsParser.parse(data: ssData)
        }
        guard let sheetData = entries["xl/worksheets/sheet1.xml"]
                ?? entries.first(where: { $0.key.hasPrefix("xl/worksheets/sheet") && $0.key.hasSuffix(".xml") })?.value else {
            throw ImportError.unreadableSpreadsheet("No worksheet found inside .xlsx archive.")
        }
        return XLSXWorksheetParser.parse(data: sheetData, sharedStrings: sharedStrings)
    }

    private static func unzipEntries(data: Data) throws -> [String: Data] {
        let bytes = [UInt8](data)
        let count = bytes.count
        guard count >= 22 else { throw ImportError.unreadableSpreadsheet("Archive too small.") }

        func u16(_ offset: Int) -> UInt16 {
            UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
        }
        func u32(_ offset: Int) -> UInt32 {
            UInt32(bytes[offset])
                | (UInt32(bytes[offset + 1]) << 8)
                | (UInt32(bytes[offset + 2]) << 16)
                | (UInt32(bytes[offset + 3]) << 24)
        }

        // Locate End of Central Directory record (0x06054b50)
        let searchMin = max(0, count - 65_557)
        var eocdOffset: Int?
        var pos = count - 22
        while pos >= searchMin {
            if u32(pos) == 0x0605_4b50 {
                eocdOffset = pos
                break
            }
            pos -= 1
        }
        guard let eocd = eocdOffset else {
            throw ImportError.unreadableSpreadsheet("Not a valid ZIP / .xlsx file.")
        }

        let cdCount = Int(u16(eocd + 10))
        let cdOffset = Int(u32(eocd + 16))
        var cursor = cdOffset
        var entries: [String: Data] = [:]

        for _ in 0..<cdCount {
            guard cursor + 46 <= count, u32(cursor) == 0x0201_4b50 else { break }
            let method = u16(cursor + 10)
            let compSize = Int(u32(cursor + 20))
            let uncompSize = Int(u32(cursor + 24))
            let nameLen = Int(u16(cursor + 28))
            let extraLen = Int(u16(cursor + 30))
            let commentLen = Int(u16(cursor + 32))
            let localOffset = Int(u32(cursor + 42))

            guard cursor + 46 + nameLen <= count else { break }
            let name = String(decoding: bytes[(cursor + 46)..<(cursor + 46 + nameLen)], as: UTF8.self)
            cursor += 46 + nameLen + extraLen + commentLen

            guard localOffset + 30 <= count, u32(localOffset) == 0x0403_4b50 else { continue }
            let localNameLen = Int(u16(localOffset + 26))
            let localExtraLen = Int(u16(localOffset + 28))
            let dataStart = localOffset + 30 + localNameLen + localExtraLen
            guard dataStart + compSize <= count else { continue }
            let payload = Data(bytes[dataStart..<(dataStart + compSize)])

            if method == 0 {
                entries[name] = payload
            } else if method == 8 {
                if let inflated = inflateRawDeflate(payload, expectedSize: max(uncompSize, 1024)) {
                    entries[name] = inflated
                }
            }
        }

        return entries
    }

    private static func inflateRawDeflate(_ compressed: Data, expectedSize: Int) -> Data? {
        guard !compressed.isEmpty else { return Data() }
        var bufferSize = max(expectedSize, compressed.count * 4, 4096)
        for _ in 0..<4 {
            var output = [UInt8](repeating: 0, count: bufferSize)
            let decodedCount: Int = compressed.withUnsafeBytes { rawBuf in
                guard let srcPtr = rawBuf.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(&output, bufferSize, srcPtr, compressed.count, nil, COMPRESSION_ZLIB)
            }
            if decodedCount > 0 && decodedCount < bufferSize {
                return Data(output[0..<decodedCount])
            }
            if decodedCount == bufferSize {
                bufferSize *= 4
            } else {
                return nil
            }
        }
        return nil
    }
}

private final class XLSXSharedStringsParser: NSObject, XMLParserDelegate {
    private var strings: [String] = []
    private var insideSI = false
    private var insideT = false
    private var current = ""

    static func parse(data: Data) -> [String] {
        let handler = XLSXSharedStringsParser()
        let parser = XMLParser(data: data)
        parser.delegate = handler
        parser.parse()
        return handler.strings
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "si" { insideSI = true; current = "" }
        else if elementName == "t", insideSI { insideT = true }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if insideT { current += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "t" { insideT = false }
        else if elementName == "si" {
            strings.append(current)
            insideSI = false
        }
    }
}

private final class XLSXWorksheetParser: NSObject, XMLParserDelegate {
    private let sharedStrings: [String]
    private var rows: [[String]] = []
    private var currentRow: [Int: String] = [:]
    private var maxColInRow = -1
    private var currentCellCol = 0
    private var currentCellType = ""
    private var captureValue = false
    private var currentText = ""

    init(sharedStrings: [String]) {
        self.sharedStrings = sharedStrings
    }

    static func parse(data: Data, sharedStrings: [String]) -> [[String]] {
        let handler = XLSXWorksheetParser(sharedStrings: sharedStrings)
        let parser = XMLParser(data: data)
        parser.delegate = handler
        parser.parse()
        return handler.rows
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "row":
            currentRow = [:]
            maxColInRow = -1
        case "c":
            currentCellType = attributeDict["t"] ?? ""
            if let ref = attributeDict["r"], let col = Self.columnIndex(from: ref) {
                currentCellCol = col
            } else {
                currentCellCol = maxColInRow + 1
            }
            maxColInRow = max(maxColInRow, currentCellCol)
            currentText = ""
        case "v", "t":
            captureValue = true
            currentText = ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if captureValue { currentText += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "v":
            captureValue = false
            if currentCellType == "s", let idx = Int(currentText), sharedStrings.indices.contains(idx) {
                currentRow[currentCellCol] = sharedStrings[idx]
            } else {
                currentRow[currentCellCol] = currentText
            }
        case "t":
            captureValue = false
            currentRow[currentCellCol] = (currentRow[currentCellCol] ?? "") + currentText
        case "row":
            if maxColInRow >= 0 {
                let rowArray = (0...maxColInRow).map { currentRow[$0] ?? "" }
                rows.append(rowArray)
            }
        default:
            break
        }
    }

    private static func columnIndex(from cellRef: String) -> Int? {
        var col = 0
        var sawLetter = false
        for scalar in cellRef.uppercased().unicodeScalars {
            if scalar.value >= 65 && scalar.value <= 90 {
                col = col * 26 + Int(scalar.value - 64)
                sawLetter = true
            } else {
                break
            }
        }
        return sawLetter ? col - 1 : nil
    }
}
