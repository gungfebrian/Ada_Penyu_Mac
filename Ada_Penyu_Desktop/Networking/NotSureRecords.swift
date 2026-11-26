import Foundation

/// Queue metadata is deliberately independent of decoded images and the local review journal.
struct MobileReviewSighting: Decodable, Identifiable {
    let id: UUID
    let turtleID: UUID?
    let isDraft: Bool
    let observedAt: Date
    let location: V2Location
    let notes: String?
    let photos: [MobileReviewPhoto]
    let matchResult: SavedAttempt?
    struct SavedAttempt: Decodable { let id: UUID }
    enum CodingKeys: String, CodingKey {
        case id, location, notes, photos, turtleID = "turtle_id", isDraft = "is_draft"
        case observedAt = "observed_at", matchResult = "match_result"
    }
    var headPhotos: [MobileReviewPhoto] { photos.filter { $0.markingID == nil && $0.bodySpotID == nil } }
    var defaultInputs: [ReviewQueryInput]? {
        let photos = headPhotos
        guard !photos.isEmpty, photos.count <= 2, photos.allSatisfy({ $0.side != nil }),
              Set(photos.compactMap(\.side)).count == photos.count else { return nil }
        return photos.map { ReviewQueryInput(photoID: $0.id, side: $0.side!, file: nil) }
    }
}

struct MobileReviewPhoto: Decodable, Identifiable {
    let id: UUID
    let url: String
    let downloadURL: String?
    let side: TurtlePhotoSide?
    let markingID: UUID?
    let bodySpotID: UUID?
    var revision: String? = nil
    var thumbnail: PhotoThumbnail? = nil
    var expiresAt: Date? = nil
    enum CodingKeys: String, CodingKey {
        case id, url, side, revision, thumbnail, expiresAt = "expires_at", downloadURL = "download_url", markingID = "marking_id", bodySpotID = "body_spot_id"
    }
    var fetchPath: String { downloadURL.flatMap { $0.isEmpty ? nil : $0 } ?? url }
    var reference: PhotoReference {
        PhotoReference(url: url, id: id, revision: revision, downloadURL: downloadURL, expiresAt: expiresAt, thumbnail: thumbnail)
    }
}

struct ReviewQueryInput: Codable, Equatable {
    let photoID: UUID?
    let side: TurtlePhotoSide
    let file: String?
    enum CodingKeys: String, CodingKey { case side, file, photoID = "photo_id" }
}

struct ReviewRematchCommand: Encodable {
    let attemptID: UUID
    let inputs: [ReviewQueryInput]
    var limit = 8
    var reviewCoverage: Int? = nil
    var parentAttemptID: UUID? = nil
    enum CodingKeys: String, CodingKey {
        case inputs, limit, attemptID = "attempt_id", reviewCoverage = "review_coverage", parentAttemptID = "parent_attempt_id"
    }
}

struct ReviewQueryEvidence: Decodable {
    let side: TurtlePhotoSide
    let photoID: UUID?
    let url: String
    enum CodingKeys: String, CodingKey { case side, url, photoID = "photo_id" }
}

struct ReviewMatchResult: Decodable {
    let id: UUID
    let querySides: [TurtlePhotoSide]
    let candidates: [Candidate]
    var queries: [ReviewQueryEvidence]?
    var review: DesktopReviewState? = nil
    struct Candidate: Decodable {
        let rank: Int
        let confidence: Double
        let turtle: Card
        enum CodingKeys: String, CodingKey {
            case rank, confidence, turtle, name, turtleID = "turtle_id", profileCode = "profile_code"
        }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            rank = try values.decode(Int.self, forKey: .rank)
            confidence = try values.decode(Double.self, forKey: .confidence)
            if let expanded = try values.decodeIfPresent(Card.self, forKey: .turtle) { turtle = expanded }
            else {
                // History snapshots contain frozen candidate labels rather than live turtle cards.
                turtle = Card(id: try values.decode(UUID.self, forKey: .turtleID), name: try values.decode(String.self, forKey: .name),
                    profileCode: try values.decode(String.self, forKey: .profileCode), identityPhotos: nil)
            }
        }
    }
    struct Card: Decodable {
        let id: UUID
        let name: String
        let profileCode: String
        let identityPhotos: Photos?
        struct Photos: Decodable { let left: V2Photo?; let right: V2Photo? }
        enum CodingKeys: String, CodingKey { case id, name, profileCode = "profile_code", identityPhotos = "identity_photos" }
    }
    enum CodingKeys: String, CodingKey { case id, candidates, queries, review, querySides = "query_sides" }
}

struct ReviewInputSelectionRequired: LocalizedError {
    let sighting: MobileReviewSighting
    var errorDescription: String? { "Reopen this case to choose a head photo and side before matching." }
}
