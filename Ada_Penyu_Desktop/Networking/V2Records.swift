import Foundation

struct V2Page<Value: Decodable>: Decodable {
    let items: [Value]
    let total: Int
    let limit: Int
    let offset: Int
}

struct IndividualDraft: Encodable {
    var id = UUID()
    let profileCode: String
    let name: String
    let species: String
    let sex: String
    let firstSeenAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, species, sex, profileCode = "profile_code", firstSeenAt = "first_seen_at"
    }

    func validate() throws {
        guard profileCode.count == 6, profileCode.utf8.allSatisfy({ (48...57).contains($0) }),
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              ["unknown", "male", "female"].contains(sex) else {
            throw APIError.validation("Enter a name, a six-digit profile code, sex, and first-seen date.")
        }
    }
}

struct V2Photo: Decodable {
    let url: String
    let capturedAt: Date?
    let uploadedAt: Date
    enum CodingKeys: String, CodingKey { case url, capturedAt = "captured_at", uploadedAt = "uploaded_at" }
}

struct V2Location: Decodable {
    let name: String
    let coordinates: Coordinates?
    struct Coordinates: Decodable { let latitude: Double; let longitude: Double }
    var coordinate: TurtleCoordinate? { coordinates.map { TurtleCoordinate(latitude: $0.latitude, longitude: $0.longitude) } }
}

struct V2Condition: Decodable {
    let status: String?
    let notes: String?
    let markings: [Marking]
    struct Marking: Decodable {
        let id: UUID
        let region: String
        let kind: String
        let severity: String?
        let notes: String?
    }
}

struct V2Sighting: Decodable {
    let id: UUID
    let observedAt: Date
    let event: Event
    let location: V2Location
    let condition: V2Condition?
    let measurements: Measurements?
    let notes: String?
    struct Event: Decodable { let type: String }
    struct Measurements: Decodable {
        let length: Double?
        let width: Double?
        let weight: Double?
        enum CodingKeys: String, CodingKey { case length = "carapace_length_cm", width = "carapace_width_cm", weight = "weight_kg" }
    }
    enum CodingKeys: String, CodingKey {
        case id, event, location, condition, measurements, notes, observedAt = "observed_at"
    }

    var measurement: TurtleMeasurement? {
        guard let value = measurements, value.length != nil || value.width != nil || value.weight != nil else { return nil }
        return TurtleMeasurement(id: id.uuidString, date: APIFormatters.display.string(from: observedAt),
            length: value.length, width: value.width, weight: value.weight)
    }

    var logs: [TurtleLogSummary] {
        let date = APIFormatters.display.string(from: observedAt)
        let encounter = TurtleLogSummary(id: id.uuidString, date: date, location: location.name,
            status: event.type.replacingOccurrences(of: "_", with: " ").capitalized,
            condition: TurtleCondition(apiValue: condition?.status), notes: notes, coordinate: location.coordinate)
        let parts: [String: TurtleBodyPart] = ["head": .head, "carapace": .carapace,
            "front_flipper_left": .flipperLeft, "front_flipper_right": .flipperRight,
            "rear_flipper_left": .footLeft, "rear_flipper_right": .footRight, "tail": .tail]
        // An encounter-wide assessment is not a per-body-part assessment.
        return [encounter] + (condition?.markings ?? []).compactMap { marking in
            guard let part = parts[marking.region] else { return nil }
            return TurtleLogSummary(id: marking.id.uuidString, date: date, location: location.name,
                status: marking.kind.replacingOccurrences(of: "_", with: " ").capitalized,
                condition: nil, notes: marking.notes,
                coordinate: location.coordinate, bodyPart: part, markingSeverity: marking.severity)
        }
    }
}

struct V2Profile: Decodable {
    let id: UUID
    let name: String
    let species: String
    let profileCode: String
    let firstSeenAt: Date
    let identityPhotos: IdentityPhotos
    let summary: Summary
    struct IdentityPhotos: Decodable { let left: V2Photo?; let right: V2Photo? }
    struct Summary: Decodable {
        let totalSightings: Int
        let latestSighting: Preview?
        let lastRecordedCondition: RecordedCondition?
        struct RecordedCondition: Decodable { let status: String }
        struct Preview: Decodable {
            let observedAt: Date
            let location: V2Location
            enum CodingKeys: String, CodingKey { case location, observedAt = "observed_at" }
        }
        enum CodingKeys: String, CodingKey {
            case totalSightings = "total_sightings", latestSighting = "latest_sighting", lastRecordedCondition = "last_recorded_condition"
        }
    }
    enum CodingKeys: String, CodingKey {
        case id, name, species, summary, profileCode = "profile_code", firstSeenAt = "first_seen_at", identityPhotos = "identity_photos"
    }

    func turtle() -> Turtle {
        let latest = summary.latestSighting
        return Turtle(id: id.uuidString, species: TurtleSpecies(apiValue: species),
            location: latest?.location.name ?? "Not recorded",
            lastSeen: latest.map { APIFormatters.display.string(from: $0.observedAt) } ?? "Not recorded",
            sightings: summary.totalSightings,
            condition: TurtleCondition(apiValue: summary.lastRecordedCondition?.status) ?? .unknown,
            firstRecorded: APIFormatters.display.string(from: firstSeenAt), isFavorite: false,
            coordinate: latest?.location.coordinate, backendID: id,
            leftPhotoURL: identityPhotos.left?.url, rightPhotoURL: identityPhotos.right?.url,
            name: name.isEmpty ? profileCode : name)
    }
}
