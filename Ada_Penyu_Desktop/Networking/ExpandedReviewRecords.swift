import Foundation

/// Server-owned coverage and review state; loaded pages are not review completion.
struct DesktopReviewState: Codable, Equatable {
    let coveragePercent: Int
    let candidateTotal: Int
    let eligibleCount: Int
    let comparedCount: Int
    let excludedCount: Int
    let parentAttemptID: UUID?
    let rejectedCandidateIDs: [UUID]
    let canCreateNew: Bool

    enum CodingKeys: String, CodingKey {
        case coveragePercent = "coverage_percent", candidateTotal = "candidate_total"
        case eligibleCount = "eligible_count", comparedCount = "compared_count", excludedCount = "excluded_count"
        case parentAttemptID = "parent_attempt_id", rejectedCandidateIDs = "rejected_candidate_ids"
        case canCreateNew = "can_create_new"
    }
}

struct ReviewCandidatePage: Decodable {
    let items: [ReviewMatchResult.Candidate]
    let total: Int
    let limit: Int
    let offset: Int
    let review: DesktopReviewState
}

struct ReviewRejectionCommand: Encodable {
    var decisionID = UUID()
    let candidateID: UUID
    let rejected: Bool
    enum CodingKeys: String, CodingKey { case decisionID = "decision_id", candidateID = "candidate_id", rejected }
}

struct ReviewIdentityCommand: Encodable {
    let attemptID: UUID
    var decisionID = UUID()
    let turtleID: UUID
    let note: String
    enum CodingKeys: String, CodingKey { case attemptID = "attempt_id", decisionID = "decision_id", turtleID = "turtle_id", note }
}

struct ReviewNewTurtleCommand: Encodable {
    var decisionID = UUID()
    let note: String
    let photosAdequate: Bool
    let turtle: IndividualDraft
    enum CodingKeys: String, CodingKey { case decisionID = "decision_id", photosAdequate = "photos_adequate", note, turtle }
}

extension RemoteTurtleRepository {
    private func reviewPath(_ logID: UUID, _ attemptID: UUID) -> String {
        "api/v2/logs/\(logID.uuidString.lowercased())/match-results/\(attemptID.uuidString.lowercased())"
    }

    func reviewCandidatePage(logID: UUID, attemptID: UUID, limit: Int, offset: Int) async throws -> ReviewCandidatePage {
        try await client.get(reviewPath(logID, attemptID) + "/candidates", queryItems: [
            URLQueryItem(name: "limit", value: String(limit)), URLQueryItem(name: "offset", value: String(offset))])
    }

    func reviewState(logID: UUID, attemptID: UUID) async throws -> DesktopReviewState {
        try await client.get(reviewPath(logID, attemptID) + "/review")
    }

    func saveReviewRejection(logID: UUID, attemptID: UUID, command: ReviewRejectionCommand) async throws -> DesktopReviewState {
        try await client.request(path: reviewPath(logID, attemptID) + "/review", method: "PUT", body: JSONEncoder.api.encode(command))
    }

    func confirmDesktopReview(logID: UUID, command: ReviewIdentityCommand) async throws {
        _ = try await client.requestData(path: "api/v2/logs/\(logID.uuidString.lowercased())/identification", method: "PUT", body: JSONEncoder.api.encode(command))
    }

    func createReviewTurtle(logID: UUID, attemptID: UUID, command: ReviewNewTurtleCommand) async throws {
        _ = try await client.requestData(path: reviewPath(logID, attemptID) + "/new-turtle", method: "POST", body: JSONEncoder.api.encode(command))
    }
}
