import Foundation

struct DashboardMetrics {
    let observed: Int
    let firstRecorded: Int
    let sightings: Int
    let monthlyAverage: Double
    // The API's month-based new-individual counts cannot establish returning
    // individuals for arbitrary date bounds. Do not manufacture that subset.
    var seenAgain: Int? { observed == 0 && firstRecorded == 0 ? 0 : nil }
}

extension DashboardSnapshot {
    var metrics: DashboardMetrics {
        let count = months.reduce(0) { $0 + $1.sightings }
        return DashboardMetrics(observed: species.reduce(0) { $0 + $1.individuals },
            firstRecorded: months.reduce(0) { $0 + $1.newIndividuals }, sightings: count,
            monthlyAverage: months.isEmpty ? 0 : Double(count) / Double(months.count))
    }
}

struct RecentResighting: Identifiable {
    let latest: Sighting
    let previous: Sighting
    var id: String { latest.turtleID }

    static func rows(from sightings: [Sighting]) -> [RecentResighting] {
        Dictionary(grouping: sightings, by: \.turtleID).values.compactMap { records in
            let sorted = records.sorted { date($0.date) > date($1.date) }
            guard sorted.count > 1 else { return nil }
            return RecentResighting(latest: sorted[0], previous: sorted[1])
        }.sorted { date($0.latest.date) > date($1.latest.date) }
    }

    private static func date(_ value: String) -> Date { APIFormatters.display.date(from: value) ?? .distantPast }
}

extension Sighting {
    var turtleReference: Turtle {
        Turtle(id: turtleID, species: species, location: location, lastSeen: date, sightings: 0,
               condition: condition, firstRecorded: "Not recorded", isFavorite: false, coordinate: coordinate,
               backendID: UUID(uuidString: turtleID), name: displayName)
    }
}

extension TurtleSpecies {
    var shellAsset: String? {
        switch self {
        case .green: "GreenSpecies"
        case .hawksbill: "HawksbillSpecies"
        case .oliveRidley: "RidleySpecies"
        default: nil
        }
    }
}

extension TurtleLogSummary {
    /// A marking kind describes only its own body part, never the turtle's
    /// overall health or a later encounter with no assessment.
    var markingCondition: TurtleCondition? {
        guard isBodyConditionRecord else { return nil }
        switch status.lowercased() {
        case "wound", "injury", "injured": return .injured
        case "scar", "scarred", "tag scar": return .scarred
        default: return nil
        }
    }
}
