import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case dashboard
    case map
    case individuals
    case scientistReview
    case identification
    case favorites

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .map: "Map"
        case .individuals: "Individuals"
        case .scientistReview: "Scientist Review"
        case .identification: "I3S Pattern ID"
        case .favorites: "Favorites"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: "chart.xyaxis.line"
        case .map: "map"
        case .individuals: "tortoise"
        case .scientistReview: "rectangle.split.2x1.badge.gearshape"
        case .identification: "viewfinder.circle"
        case .favorites: "heart"
        }
    }
}

enum ChartMode: String, CaseIterable, Identifiable {
    case sightings = "Sightings"
    case newIndividuals = "New individuals"

    var id: String { rawValue }
    var title: String { rawValue }
}

enum TurtleSpecies: String, CaseIterable, Identifiable {
    case unknown = "Unknown species"
    case green = "Green turtle"
    case hawksbill = "Hawksbill"
    case oliveRidley = "Olive Ridley"
    case loggerhead = "Loggerhead"
    case leatherback = "Leatherback"

    var id: String { rawValue }
}

/// The body regions we display on the turtle diagram. Raw values map to
/// image asset names in `Assets.xcassets`, so the enum is the single source
/// of truth for rendering.
enum TurtleBodyPart: String, CaseIterable, Identifiable, Hashable {
    case head
    case flipperLeft
    case flipperRight
    case carapace
    case footLeft
    case footRight
    case tail

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .head: "Head"
        case .flipperLeft: "Left flipper"
        case .flipperRight: "Right flipper"
        case .carapace: "Shell"
        case .footLeft: "Left foot"
        case .footRight: "Right foot"
        case .tail: "Tail"
        }
    }

    /// Matches the image asset names shipped in `Assets.xcassets`.
    var imageName: String {
        switch self {
        case .head: "head"
        case .flipperLeft: "flipper_left"
        case .flipperRight: "flipper_right"
        case .carapace: "carapas"
        case .footLeft: "left_foot"
        case .footRight: "right_foot"
        case .tail: "tail"
        }
    }
}

enum TurtleCondition: String, CaseIterable, Identifiable {
    case unknown = "Unknown"
    case healthy = "Healthy"
    case scarred = "Scarred"
    case injured = "Injured"

    var id: String { rawValue }

    var tint: Color {
        switch self {
        case .unknown: AdaColors.tertiaryInk
        case .healthy: AdaColors.green
        case .scarred: AdaColors.orange
        case .injured: AdaColors.red
        }
    }

    var background: Color {
        switch self {
        case .unknown: AdaColors.tertiaryInk.opacity(0.12)
        case .healthy: AdaColors.green.opacity(0.12)
        case .scarred: AdaColors.orange.opacity(0.15)
        case .injured: AdaColors.red.opacity(0.12)
        }
    }
}

struct Turtle: Identifiable, Hashable {
    let name: String?
    var displayName: String { name ?? id }
    let id: String
    let species: TurtleSpecies
    let location: String
    let lastSeen: String
    let sightings: Int
    let condition: TurtleCondition
    let firstRecorded: String
    let isFavorite: Bool
    let backendID: UUID?
    let coordinate: TurtleCoordinate?
    let leftPhotoURL: String?
    let rightPhotoURL: String?

    init(
        id: String,
        species: TurtleSpecies,
        location: String,
        lastSeen: String,
        sightings: Int,
        condition: TurtleCondition,
        firstRecorded: String,
        isFavorite: Bool,
        coordinate: TurtleCoordinate?,
        backendID: UUID? = nil,
        leftPhotoURL: String? = nil,
        rightPhotoURL: String? = nil,
        name: String? = nil
    ) {
        self.name = name
        self.id = id
        self.species = species
        self.location = location
        self.lastSeen = lastSeen
        self.sightings = sightings
        self.condition = condition
        self.firstRecorded = firstRecorded
        self.isFavorite = isFavorite
        self.coordinate = coordinate
        self.backendID = backendID
        self.leftPhotoURL = leftPhotoURL
        self.rightPhotoURL = rightPhotoURL
    }
}

enum TurtlePhotoSide: String, CaseIterable, Identifiable, Codable, Hashable {
    case left
    case right

    var id: String { rawValue }

    var title: String {
        switch self {
        case .left: "Left Profile"
        case .right: "Right Profile"
        }
    }
}

struct MatchCandidateItem: Identifiable, Hashable {
    let individualID: UUID
    let name: String
    let profileCode: String?
    let species: TurtleSpecies
    let rank: Int
    let fusedScore: Double
    let confidence: Double
    let confidencePercent: Int
    let globalScore: Double
    let localMatch: Int
    let matchedPhotoSide: TurtlePhotoSide
    let photoURL: String?
    let aboveThreshold: Bool
    let lastSeenDate: String?
    let lastSeenLocation: String?
    let condition: TurtleCondition?
    var i3sDistanceScore: Double?
    var i3sPairedCount: Int?

    var id: UUID { individualID }
}

struct MatchSearchOutcome: Hashable {
    let querySide: TurtlePhotoSide
    let gallerySize: Int
    let matchState: String
    let candidates: [MatchCandidateItem]
    let isDualPair: Bool
    let pairAgreed: Bool?
}

struct OverlayMatchPoint: Hashable, Codable {
    let x: Double
    let y: Double
}

struct OverlayAnnotationItem: Identifiable, Hashable, Codable {
    let featureID: String
    let label: String
    let score: Double?
    let query: OverlayMatchPoint
    let candidate: OverlayMatchPoint

    var id: String { featureID }

    enum CodingKeys: String, CodingKey {
        case featureID = "feature_id"
        case label
        case score
        case query
        case candidate
    }
}

struct TurtleCoordinate: Hashable {
    let latitude: Double
    let longitude: Double
}

struct Sighting: Identifiable, Hashable {
    var name: String? = nil
    var displayName: String { name ?? turtleID }
    let id: String
    let turtleID: String
    let species: TurtleSpecies
    let location: String
    let date: String
    let condition: TurtleCondition
    let coordinate: TurtleCoordinate
}

struct SpeciesSummary: Identifiable {
    let id: String
    let species: TurtleSpecies
    let individuals: Int
    let sightings: Int
}
