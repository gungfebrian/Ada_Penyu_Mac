import AppKit
import CryptoKit
import Foundation

struct NotSureReviewPhoto: Codable {
    let data: Data
    let image: NSImage?

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
    let photo: NotSureReviewPhoto?
    let sampleImageName: String?
    let fingerprint: I3SFingerprint?
    let isBundledExample: Bool

    var image: NSImage? { photo?.image }
    var evidenceLabel: String {
        isBundledExample ? "Sample reference" : "Backend score \(confidencePercent)%"
    }
}

enum NotSureReviewDecision: String, Codable, CaseIterable, Identifiable {
    case pending, recommendedMatch, reviewedUnknown
    var id: Self { self }
    var title: String {
        switch self {
        case .pending: "Not Sure"
        case .recommendedMatch: "Match recommended"
        case .reviewedUnknown: "Reviewed as unknown"
        }
    }
}

enum NotSureReviewAction {
    case saveNote(String)
    case rejectCandidate(String)
    case restoreCandidate(String)
    case recommend(String, note: String)
    case resolveUnknown(note: String)
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
        case .noteRequired: "Add a short note explaining your decision."
        case .searchUnavailable: "Gallery search is available for field photographs in a signed-in workspace."
        }
    }
}

struct EscalatedNotSureCase: Codable, Identifiable {
    var id = UUID()
    let title: String
    let side: TurtlePhotoSide
    let photo: NotSureReviewPhoto
    let companion: NotSureReviewPhoto?
    let queryFingerprint: I3SFingerprint?
    let queryROI: [ScalePoint]
    var candidates: [EscalatedNotSureCandidate]
    let submittedBy: String
    let isExample: Bool
    var createdAt = Date()
    private(set) var updatedAt = Date()
    private(set) var decision: NotSureReviewDecision = .pending
    private(set) var recommendedCandidateID: String?
    private(set) var rejectedCandidateIDs: Set<String> = []
    private(set) var note = ""

    var queryImage: NSImage? { photo.image }
    var queryPhotoData: Data { photo.data }
    var companionImage: NSImage? { companion?.image }

    func canRecommend(_ candidate: EscalatedNotSureCandidate) -> Bool {
        decision == .pending && queryImage != nil &&
        candidate.side == side && candidate.sideMatches && candidate.image != nil &&
        candidate.isBundledExample == isExample && !rejectedCandidateIDs.contains(candidate.id)
    }

    mutating func apply(_ action: NotSureReviewAction) throws {
        if case .reopen = action {
            decision = .pending
            recommendedCandidateID = nil
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
        case .resolveUnknown(let text):
            note = try Self.decisionNote(text)
            decision = .reviewedUnknown
            recommendedCandidateID = nil
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
