import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case dashboard
    case map
    case individuals
    case favorites
    case detail

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .map: "Map"
        case .individuals: "Individuals"
        case .favorites: "Favorites"
        case .detail: "Turtle #001"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: "chart.xyaxis.line"
        case .map: "map"
        case .individuals: "tortoise"
        case .favorites: "heart"
        case .detail: "circle"
        }
    }
}

enum TurtleSpecies: String, CaseIterable, Identifiable {
    case green = "Green turtle"
    case hawksbill = "Hawksbill"
    case oliveRidley = "Olive Ridley"
    case loggerhead = "Loggerhead"
    case leatherback = "Leatherback"

    var id: String { rawValue }
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
    /// Stable backend identifier when the record comes from the API. Demo
    /// records intentionally keep this optional so the app can run offline.
    let backendID: UUID?
    /// Mirrors the mobile app's `Turtle.coordinate` shape so API-backed data
    /// can be adapted here later without changing the map view.
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
    /// Mirrors the mobile app's `TurtleSighting.coordinate` field.
    let coordinate: TurtleCoordinate
}

struct SpeciesSummary: Identifiable {
    let id: String
    let species: TurtleSpecies
    let individuals: Int
    let sightings: Int
}

enum DemoData {
    static let turtles: [Turtle] = [
        Turtle(id: "Turtle #001", species: .hawksbill, location: "Kuta Beach", lastSeen: "17 Aug 2026", sightings: 5, condition: .injured, firstRecorded: "01-03-2026", isFavorite: false, coordinate: TurtleCoordinate(latitude: -8.7180, longitude: 115.1690)),
        Turtle(id: "Turtle #002", species: .green, location: "Nusa Dua reef", lastSeen: "12 Aug 2026", sightings: 8, condition: .healthy, firstRecorded: "12-04-2026", isFavorite: false, coordinate: TurtleCoordinate(latitude: -8.7960, longitude: 115.2280)),
        Turtle(id: "Turtle #003", species: .oliveRidley, location: "Serangan Island", lastSeen: "09 Aug 2026", sightings: 4, condition: .scarred, firstRecorded: "21-04-2026", isFavorite: false, coordinate: TurtleCoordinate(latitude: -8.7240, longitude: 115.2500)),
        Turtle(id: "Turtle #004", species: .green, location: "Sanur flats", lastSeen: "02 Aug 2026", sightings: 3, condition: .scarred, firstRecorded: "07-05-2026", isFavorite: true, coordinate: TurtleCoordinate(latitude: -8.6870, longitude: 115.2620)),
        Turtle(id: "Turtle #005", species: .leatherback, location: "Pantai Timur", lastSeen: "28 Jul 2026", sightings: 2, condition: .healthy, firstRecorded: "16-06-2026", isFavorite: true, coordinate: TurtleCoordinate(latitude: -8.7800, longitude: 115.2500))
    ]

    static let sightings: [Sighting] = [
        Sighting(id: "sighting-1", turtleID: "Turtle #001", species: .hawksbill, location: "Kuta Beach", date: "17 Aug 2026", condition: .injured, coordinate: TurtleCoordinate(latitude: -8.7180, longitude: 115.1690)),
        Sighting(id: "sighting-2", turtleID: "Turtle #002", species: .green, location: "Nusa Dua reef", date: "12 Aug 2026", condition: .healthy, coordinate: TurtleCoordinate(latitude: -8.7960, longitude: 115.2280)),
        Sighting(id: "sighting-3", turtleID: "Turtle #003", species: .oliveRidley, location: "Serangan Island", date: "09 Aug 2026", condition: .scarred, coordinate: TurtleCoordinate(latitude: -8.7240, longitude: 115.2500)),
        Sighting(id: "sighting-4", turtleID: "Turtle #004", species: .green, location: "Sanur flats", date: "02 Aug 2026", condition: .scarred, coordinate: TurtleCoordinate(latitude: -8.6870, longitude: 115.2620)),
        Sighting(id: "sighting-5", turtleID: "Turtle #005", species: .leatherback, location: "Pantai Timur", date: "28 Jul 2026", condition: .healthy, coordinate: TurtleCoordinate(latitude: -8.7800, longitude: 115.2500))
    ]

    static let speciesSummaries: [SpeciesSummary] = [
        SpeciesSummary(id: "olive-ridley", species: .oliveRidley, individuals: 2, sightings: 96),
        SpeciesSummary(id: "green", species: .green, individuals: 2, sightings: 84),
        SpeciesSummary(id: "loggerhead", species: .loggerhead, individuals: 1, sightings: 84),
        SpeciesSummary(id: "hawksbill", species: .hawksbill, individuals: 2, sightings: 42),
        SpeciesSummary(id: "leatherback", species: .leatherback, individuals: 1, sightings: 36)
    ]
}
