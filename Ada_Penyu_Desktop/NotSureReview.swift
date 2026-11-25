import AppKit
import CryptoKit
import Foundation

struct NotSureReviewPhoto: Codable {
    let data: Data
    let image: NSImage?

    static func refreshed(
        _ fresh: Self?,
        side: TurtlePhotoSide,
        previous: Self?,
        previousSide: TurtlePhotoSide?
    ) -> Self? {
        fresh ?? (side == previousSide ? previous : nil)
    }

    init(data: Data) {
        self.data = data
        self.image = NSImage(data: data)
    }

    init?(snapshot image: NSImage?) {
        guard let image,
              let raster = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let data = NSBitmapImageRep(cgImage: raster).representation(using: .jpeg,
                  properties: [.compressionFactor: 0.94]) else { return nil }
        self.init(data: data)
    }

    init(from decoder: Decoder) throws {
        try self.init(data: decoder.singleValueContainer().decode(Data.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(data)
    }
}

struct EscalatedNotSureCandidate: Codable, Identifiable {
    let id: String
    let rank: Int
    let name: String
    let profileCode: String
    let side: TurtlePhotoSide
    let sideMatches: Bool
    let dateText: String
    let location: String
    let confidencePercent: Int
    var photo: NotSureReviewPhoto?
    var photoPath: String? = nil
    var photoRevision: String? = nil
    var photoAvailability: String? = nil
    let sampleImageName: String?
    let fingerprint: I3SFingerprint?
    let isBundledExample: Bool

    var image: NSImage? { photo?.image }
    var evidenceLabel: String {
        isBundledExample ? "Sample" : "\(confidencePercent)%"
    }
}

/// Distinguishes open-set non-matches ("New turtle" — absent from gallery) from
/// quality-blocked encounters ("Needs photo" — glare, blur, or oblique angle).
enum NotSureUnknownOutcome: String, Codable, CaseIterable, Identifiable, Sendable {
    case newIndividual
    case needsBetterPhoto

    var id: Self { self }

    var title: String {
        switch self {
        case .newIndividual: "New turtle"
        case .needsBetterPhoto: "Needs photo"
        }
    }
}

enum NotSureReviewDecision: String, Codable, CaseIterable, Identifiable {
    case pending, recommendedMatch, reviewedUnknown
    var id: Self { self }
    var title: String {
        switch self {
        case .pending: "Not Sure"
        case .recommendedMatch: "Match"
        case .reviewedUnknown: "Unknown"
        }
    }
}

enum NotSureReviewAction {
    case saveNote(String)
    case rejectCandidate(String)
    case restoreCandidate(String)
    case recommend(String, note: String)
    case resolveUnknown(note: String)
    case resolveAsNewTurtle(note: String)
    case requestBetterPhoto(note: String)
    case saveVerifiedPairs(candidateID: String, pairs: [PatternPairLink])
    case saveManualAnchors(candidateID: String, anchors: [ManualAnchorPair])
    case toggleExcludedQueryScale(Int)
    case addCustomQueryLandmark(ManualScaleLandmark)
    case removeCustomQueryLandmark(UUID)
    case clearManualScaleEdits
    case reopen
}

enum NotSureReviewError: LocalizedError {
    case accountUnavailable, caseUnavailable, invalidPhoto, alreadyReviewed, invalidCandidate, noteRequired, searchUnavailable
    var errorDescription: String? {
        switch self {
        case .accountUnavailable: "Open an account workspace to save a review."
        case .caseUnavailable: "This review is no longer available."
        case .invalidPhoto: "Choose a readable query photograph before saving this case."
        case .alreadyReviewed: "Reopen this case before changing the decision."
        case .invalidCandidate: "Choose an available same-side reference to recommend a match."
        case .noteRequired: "Pick a reason or add a short note."
        case .searchUnavailable: "Gallery search is available for field photographs in a signed-in workspace."
        }
    }
}

struct EscalatedNotSureCase: Codable, Identifiable {
    var id = UUID()
    let title: String
    var side: TurtlePhotoSide
    var photo: NotSureReviewPhoto
    var companion: NotSureReviewPhoto?
    let queryFingerprint: I3SFingerprint?
    let queryROI: [ScalePoint]
    var candidates: [EscalatedNotSureCandidate]
    let submittedBy: String
    let isExample: Bool
    var matchAttemptID: UUID? = nil
    var reviewInputs: [ReviewQueryInput]? = nil
    var sourceLogID: UUID? = nil
    var createdAt = Date()
    private(set) var updatedAt = Date()
    private(set) var decision: NotSureReviewDecision = .pending
    private(set) var recommendedCandidateID: String?
    private(set) var rejectedCandidateIDs: Set<String> = []
    private(set) var note = ""
    private(set) var unknownOutcome: NotSureUnknownOutcome? = nil
    private(set) var verifiedPairsByCandidateID: [String: [PatternPairLink]]? = nil
    private(set) var manualAnchorsByCandidateID: [String: [ManualAnchorPair]]? = nil
    private(set) var excludedQueryScaleNumbers: Set<Int>? = nil
    private(set) var customQueryLandmarks: [ManualScaleLandmark]? = nil
    var reMatchDeltasByCandidateID: [String: CandidateReMatchDelta]? = nil

    var queryImage: NSImage? { photo.image }
    var queryPhotoData: Data { photo.data }
    var companionImage: NSImage? { companion?.image }
    var isFromMobileQueue: Bool { sourceLogID != nil }

    var decisionSummaryTitle: String {
        switch decision {
        case .pending: "Pending"
        case .recommendedMatch: "Match"
        case .reviewedUnknown: unknownOutcome?.title ?? "Unknown"
        }
    }

    mutating func replaceQueryEvidence(side: TurtlePhotoSide, photo: NotSureReviewPhoto, companion: NotSureReviewPhoto?) {
        if self.side != side || self.photo.data != photo.data || self.companion?.data != companion?.data {
            verifiedPairsByCandidateID = nil
            manualAnchorsByCandidateID = nil
            excludedQueryScaleNumbers = nil
            customQueryLandmarks = nil
        }
        self.side = side
        if self.photo.data != photo.data { self.photo = photo }
        if self.companion?.data != companion?.data { self.companion = companion }
    }

    func verifiedPairs(for candidateID: String) -> [PatternPairLink] {
        verifiedPairsByCandidateID?[candidateID] ?? []
    }

    func manualAnchors(for candidateID: String) -> [ManualAnchorPair] {
        manualAnchorsByCandidateID?[candidateID] ?? []
    }

    var savedAnchorMaxCount: Int {
        let pairMax = verifiedPairsByCandidateID?.values.map(\.count).max() ?? 0
        let anchorMax = manualAnchorsByCandidateID?.values.map(\.count).max() ?? 0
        return max(pairMax, anchorMax)
    }

    func canRecommend(_ candidate: EscalatedNotSureCandidate) -> Bool {
        decision == .pending && queryImage != nil &&
        candidate.side == side && candidate.sideMatches && candidate.image != nil &&
        candidate.isBundledExample == isExample && !rejectedCandidateIDs.contains(candidate.id)
    }

    mutating func apply(_ action: NotSureReviewAction) throws {
        if case .reopen = action {
            decision = .pending
            recommendedCandidateID = nil
            unknownOutcome = nil
            updatedAt = Date()
            return
        }

        guard decision == .pending else { throw NotSureReviewError.alreadyReviewed }
        switch action {
        case .saveNote(let text):
            note = text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .rejectCandidate(let id):
            guard candidates.contains(where: { $0.id == id }) else { throw NotSureReviewError.invalidCandidate }
            rejectedCandidateIDs.insert(id)
        case .restoreCandidate(let id):
            rejectedCandidateIDs.remove(id)
        case .recommend(let id, let text):
            guard let candidate = candidates.first(where: { $0.id == id }), canRecommend(candidate) else {
                throw NotSureReviewError.invalidCandidate
            }
            note = try Self.decisionNote(text)
            decision = .recommendedMatch
            recommendedCandidateID = id
            unknownOutcome = nil
        case .resolveUnknown(let text):
            note = try Self.decisionNote(text)
            decision = .reviewedUnknown
            recommendedCandidateID = nil
            unknownOutcome = nil
        case .resolveAsNewTurtle(let text):
            note = try Self.decisionNote(text)
            decision = .reviewedUnknown
            recommendedCandidateID = nil
            unknownOutcome = .newIndividual
        case .requestBetterPhoto(let text):
            note = try Self.decisionNote(text)
            decision = .reviewedUnknown
            recommendedCandidateID = nil
            unknownOutcome = .needsBetterPhoto
        case .saveVerifiedPairs(let candidateID, let pairs):
            guard candidates.contains(where: { $0.id == candidateID }) else {
                throw NotSureReviewError.invalidCandidate
            }
            var seenQ = Set<Int>()
            var seenC = Set<Int>()
            let normalized = pairs
                .filter { seenQ.insert($0.queryNumber).inserted && seenC.insert($0.candidateNumber).inserted }
                .sorted { $0.queryNumber < $1.queryNumber }
            var map = verifiedPairsByCandidateID ?? [:]
            if normalized.isEmpty {
                map.removeValue(forKey: candidateID)
            } else {
                map[candidateID] = normalized
            }
            verifiedPairsByCandidateID = map.isEmpty ? nil : map
        case .saveManualAnchors(let candidateID, let anchors):
            guard candidates.contains(where: { $0.id == candidateID }) else {
                throw NotSureReviewError.invalidCandidate
            }
            var map = manualAnchorsByCandidateID ?? [:]
            if anchors.isEmpty {
                map.removeValue(forKey: candidateID)
            } else {
                map[candidateID] = anchors
            }
            manualAnchorsByCandidateID = map.isEmpty ? nil : map
        case .toggleExcludedQueryScale(let scaleNumber):
            var set = excludedQueryScaleNumbers ?? []
            if set.contains(scaleNumber) {
                set.remove(scaleNumber)
            } else {
                set.insert(scaleNumber)
            }
            excludedQueryScaleNumbers = set.isEmpty ? nil : set
        case .addCustomQueryLandmark(let landmark):
            var list = customQueryLandmarks ?? []
            list.append(landmark)
            customQueryLandmarks = list
        case .removeCustomQueryLandmark(let landmarkID):
            var list = customQueryLandmarks ?? []
            list.removeAll { $0.id == landmarkID }
            customQueryLandmarks = list.isEmpty ? nil : list
        case .clearManualScaleEdits:
            excludedQueryScaleNumbers = nil
            customQueryLandmarks = nil
        case .reopen:
            break
        }
        updatedAt = Date()
    }

    private static func decisionNote(_ text: String) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw NotSureReviewError.noteRequired }
        return trimmed
    }
}

// MARK: - Honest Human-Assisted Geometric Warp Alignment (No Fake Centroid Verdict)

/// Result of aligning Query's extracted scale contours onto Candidate's photo via 3+ user-tapped anchor pairs.
/// Intentionally avoids emitting an automated "Strong fit" verdict — empirical open-set benchmarks showed
/// dense cheek mosaics produce low centroid residuals even on impostors, so the warped overlay is strictly
/// a visual inspection aid paired with geometric sanity guards (reflection & extreme stretch).
nonisolated struct NotSureAlignmentCheck: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case needsAnchors(remaining: Int)
        case aligned
        case orientationFlipped
        case extremeStretch(ratio: Double)
    }

    let status: Status
    let pairCount: Int
    let warpedContours: [WarpedPatternContour]
    let orientationPreserved: Bool
    let anisotropyRatio: Double?

    var isReadyForOverlay: Bool { !warpedContours.isEmpty }

    var pillText: String {
        switch status {
        case .needsAnchors(let remaining):
            return pairCount == 0 ? "Tap 3 matching scales" : "Tap \(remaining) more"
        case .aligned:
            return "\(pairCount) anchored · Check overlay"
        case .orientationFlipped:
            return "Flipped anchors"
        case .extremeStretch(let ratio):
            return String(format: "Distorted (%.1f×)", ratio)
        }
    }

    var isWarning: Bool {
        switch status {
        case .orientationFlipped, .extremeStretch: true
        case .needsAnchors, .aligned: false
        }
    }
}

nonisolated enum NotSureAlignmentEvaluator {
    static func evaluate(
        query: [DetectedScalePattern],
        candidate: [DetectedScalePattern],
        pairs: [PatternPairLink],
        queryROI: [ScalePoint],
        candidateROI: [ScalePoint]
    ) -> NotSureAlignmentCheck {
        let calc = PatternMatchCalculator.calculate(
            query: query,
            candidate: candidate,
            pairs: pairs,
            queryROI: queryROI,
            candidateROI: candidateROI
        )

        guard calc.pairCount >= 3, !calc.warpedQueryContours.isEmpty else {
            return NotSureAlignmentCheck(
                status: .needsAnchors(remaining: max(1, 3 - calc.pairCount)),
                pairCount: calc.pairCount,
                warpedContours: [],
                orientationPreserved: true,
                anisotropyRatio: nil
            )
        }

        let queryByNum = Dictionary(uniqueKeysWithValues: query.map { ($0.number, $0) })
        let warpedByNum = Dictionary(uniqueKeysWithValues: calc.warpedQueryContours.map { ($0.number, $0) })
        let linear = estimateLinearPart(queryByNum: queryByNum, warpedByNum: warpedByNum, pairs: pairs)
        let orientationPreserved = (linear?.determinant ?? 1.0) > 1e-6
        let anisotropy = linear?.anisotropyRatio

        let status: NotSureAlignmentCheck.Status
        if !orientationPreserved {
            status = .orientationFlipped
        } else if let ratio = anisotropy, ratio > 3.2 {
            status = .extremeStretch(ratio: ratio)
        } else {
            status = .aligned
        }

        return NotSureAlignmentCheck(
            status: status,
            pairCount: calc.pairCount,
            warpedContours: calc.warpedQueryContours,
            orientationPreserved: orientationPreserved,
            anisotropyRatio: anisotropy
        )
    }

    private struct LinearPart {
        let determinant: Double
        let anisotropyRatio: Double
    }

    private static func estimateLinearPart(
        queryByNum: [Int: DetectedScalePattern],
        warpedByNum: [Int: WarpedPatternContour],
        pairs: [PatternPairLink]
    ) -> LinearPart? {
        let pts: [(ScalePoint, ScalePoint)] = pairs.compactMap { link in
            guard let q = queryByNum[link.queryNumber], let w = warpedByNum[link.queryNumber] else { return nil }
            return (q.centroid, w.centroid)
        }
        guard pts.count >= 3 else { return nil }

        var bestArea = 0.0
        var bestTri: ((ScalePoint, ScalePoint), (ScalePoint, ScalePoint), (ScalePoint, ScalePoint))?
        for i in 0..<(pts.count - 2) {
            for j in (i + 1)..<(pts.count - 1) {
                for k in (j + 1)..<pts.count {
                    let q0 = pts[i].0, q1 = pts[j].0, q2 = pts[k].0
                    let area = abs((q1.x - q0.x) * (q2.y - q0.y) - (q1.y - q0.y) * (q2.x - q0.x))
                    if area > bestArea {
                        bestArea = area
                        bestTri = (pts[i], pts[j], pts[k])
                    }
                }
            }
        }
        guard bestArea > 1e-6, let (p0, p1, p2) = bestTri else { return nil }

        let dx1 = p1.0.x - p0.0.x, dy1 = p1.0.y - p0.0.y
        let dx2 = p2.0.x - p0.0.x, dy2 = p2.0.y - p0.0.y
        let du1 = p1.1.x - p0.1.x, dv1 = p1.1.y - p0.1.y
        let du2 = p2.1.x - p0.1.x, dv2 = p2.1.y - p0.1.y
        let qDet = dx1 * dy2 - dx2 * dy1
        guard abs(qDet) > 1e-8 else { return nil }

        let a = (du1 * dy2 - du2 * dy1) / qDet
        let b = (dx1 * du2 - dx2 * du1) / qDet
        let c = (dv1 * dy2 - dv2 * dy1) / qDet
        let d = (dx1 * dv2 - dx2 * dv1) / qDet

        let det = a * d - b * c
        let traceSq = a * a + b * b + c * c + d * d
        let disc = sqrt(max(0.0, traceSq * traceSq - 4.0 * det * det))
        let s1 = sqrt(max(0.0, (traceSq + disc) * 0.5))
        let s2 = sqrt(max(0.0, (traceSq - disc) * 0.5))
        return LinearPart(determinant: det, anisotropyRatio: s1 / max(1e-4, s2))
    }
}

enum NotSureHeadCropper {
    /// Crops a normalized top-left `[0, 1]` rect from `image` and encodes it as JPEG for live open-set re-search.
    static func croppedJPEGData(from image: NSImage, normalizedRect: CGRect, quality: Double = 0.92) -> Data? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let imgW = Double(cg.width)
        let imgH = Double(cg.height)
        guard imgW >= 16, imgH >= 16 else { return nil }

        let x = min(max(normalizedRect.minX, 0.0), 0.92)
        let y = min(max(normalizedRect.minY, 0.0), 0.92)
        let w = min(max(normalizedRect.width, 0.08), 1.0 - x)
        let h = min(max(normalizedRect.height, 0.08), 1.0 - y)

        let pixelRect = CGRect(
            x: floor(x * imgW),
            y: floor(y * imgH),
            width: max(16, floor(w * imgW)),
            height: max(16, floor(h * imgH))
        ).intersection(CGRect(x: 0, y: 0, width: imgW, height: imgH))

        guard pixelRect.width >= 16, pixelRect.height >= 16, let cropped = cg.cropping(to: pixelRect) else {
            return nil
        }
        return NSBitmapImageRep(cgImage: cropped).representation(
            using: .jpeg,
            properties: [.compressionFactor: quality]
        )
    }
}

/// App-container storage, keyed by service, organization and account (or demo persona).
/// Writes replace a single case atomically before the visible queue changes.
struct NotSureReviewJournal {
    let directory: URL

    init(directory: URL = URL.applicationSupportDirectory
        .appending(path: "AdaPenyu Desktop/Not Sure Reviews", directoryHint: .isDirectory)) {
        self.directory = directory
    }

    func load(scope: String) throws -> [EscalatedNotSureCase] {
        let folder = folder(for: scope)
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(at: folder,
                includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return []
        }
        let decoder = JSONDecoder()
        return try urls.filter { $0.pathExtension == "json" }.map { url in
            try decoder.decode(EscalatedNotSureCase.self, from: Data(contentsOf: url))
        }.sorted { $0.createdAt > $1.createdAt }
    }

    func save(_ item: EscalatedNotSureCase, scope: String) throws {
        let folder = folder(for: scope)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let file = folder.appending(path: item.id.uuidString).appendingPathExtension("json")
        try JSONEncoder().encode(item).write(to: file, options: .atomic)
    }

    private func folder(for scope: String) -> URL {
        let key = SHA256.hash(data: Data(scope.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: key, directoryHint: .isDirectory)
    }
}
