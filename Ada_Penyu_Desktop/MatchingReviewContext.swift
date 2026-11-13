import Foundation

/// Captures which side the operator assigned to each input, independently of layout.
struct MatchPhotoInputs {
    let primary: Data?
    let primarySide: TurtlePhotoSide
    let secondary: Data?
    let secondarySide: TurtlePhotoSide
    let paired: Bool

    var hasValidPair: Bool { primary != nil && secondary != nil && primarySide == .left && secondarySide == .right }
    func referenceData(for side: TurtlePhotoSide) -> Data? {
        if paired {
            guard hasValidPair else { return nil }
            return side == .right ? secondary : primary
        }
        return primarySide == side ? primary : nil
    }
}

/// Requests and explicit gallery-source changes share one generation.
struct MatchReviewContext {
    private(set) var revision = 0
    mutating func invalidate() { revision += 1 }
    mutating func beginExamples() { invalidate() }
    func accepts(_ requestRevision: Int) -> Bool { requestRevision == revision }
}
