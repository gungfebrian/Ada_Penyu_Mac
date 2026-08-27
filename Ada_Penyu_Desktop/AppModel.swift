import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case dashboard
    case map
    case individuals
    case favorites

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .map: "Map"
        case .individuals: "Individuals"
        case .favorites: "Favorites"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: "chart.xyaxis.line"
        case .map: "map"
        case .individuals: "tortoise"
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
    case healthy = "Healthy"
    case scarred = "Scarred"
    case injured = "Injured"

    var id: String { rawValue }

    var tint: Color {
        switch self {
        case .healthy: AdaColors.green
        case .scarred: AdaColors.orange
        case .injured: AdaColors.red
        }
    }

    var background: Color {
        switch self {
        case .healthy: AdaColors.green.opacity(0.12)
        case .scarred: AdaColors.orange.opacity(0.15)
        case .injured: AdaColors.red.opacity(0.12)
        }
    }
}

struct Turtle: Identifiable, Hashable {
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
        backendID: UUID? = nil
    ) {
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
    }
}

struct TurtleCoordinate: Hashable {
    let latitude: Double
    let longitude: Double
}

struct Sighting: Identifiable, Hashable {
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
