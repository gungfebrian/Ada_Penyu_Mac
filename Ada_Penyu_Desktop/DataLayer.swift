import Foundation

struct PageRequest: Hashable, Sendable {
    let limit: Int
    let offset: Int

    init(limit: Int = 50, offset: Int = 0) {
        self.limit = max(1, limit)
        self.offset = max(0, offset)
    }
}

struct Page<Value> {
    let items: [Value]
    let total: Int
    let request: PageRequest

    var hasMore: Bool { request.offset + items.count < total }
}

enum IndividualSort: String, CaseIterable, Identifiable {
    case name
    case lastSeenDescending = "last_seen_desc"

    var id: String { rawValue }
    var title: String { self == .name ? "Name" : "Last seen" }
}

struct IndividualQuery: Hashable, Sendable {
    var search: String?
    var species: [TurtleSpecies]
    /// Optional single-select body-condition filter. `nil` means "no filter".
    var condition: TurtleCondition?
    var sort: IndividualSort
    var page: PageRequest

    static let `default` = IndividualQuery(search: nil, species: [], condition: nil, sort: .lastSeenDescending, page: PageRequest())

    init(
        search: String? = nil,
        species: [TurtleSpecies] = [],
        condition: TurtleCondition? = nil,
        sort: IndividualSort = .lastSeenDescending,
        page: PageRequest = PageRequest()
    ) {
        self.search = search?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true ? nil : search
        self.species = species
        self.condition = condition
        self.sort = sort
        self.page = page
    }

    var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        if let search { items.append(URLQueryItem(name: "q", value: search)) }
        items.append(contentsOf: species.map { URLQueryItem(name: "species", value: $0.apiValue) })
        if let condition { items.append(URLQueryItem(name: "condition", value: condition.apiValue)) }
        items.append(URLQueryItem(name: "sort", value: sort.rawValue))
        items.append(URLQueryItem(name: "limit", value: String(page.limit)))
        items.append(URLQueryItem(name: "offset", value: String(page.offset)))
        return items
    }
}

struct DashboardQuery: Hashable, Sendable {
    var since: Date?
    var until: Date?
    var species: TurtleSpecies?

    static var lastTwelveMonths: DashboardQuery {
        let now = Date()
        return DashboardQuery(since: Calendar.current.date(byAdding: .month, value: -11, to: now), until: now)
    }

    var queryItems: [URLQueryItem] {
        var result: [URLQueryItem] = []
        if let since { result.append(URLQueryItem(name: "since", value: APIFormatters.iso8601.string(from: since))) }
        if let until { result.append(URLQueryItem(name: "until", value: APIFormatters.iso8601.string(from: until))) }
        if let species { result.append(URLQueryItem(name: "species", value: species.apiValue)) }
        return result
    }
}

struct MapQuery: Hashable, Sendable {
    var period: MapPeriod
    var species: TurtleSpecies?
    var condition: TurtleCondition?
    var page: PageRequest

    static let `default` = MapQuery(period: .thirtyDays, species: nil, condition: nil, page: PageRequest(limit: 200))

    var queryItems: [URLQueryItem] {
        var result: [URLQueryItem] = [
            URLQueryItem(name: "since", value: APIFormatters.iso8601.string(from: period.since)),
            URLQueryItem(name: "until", value: APIFormatters.iso8601.string(from: Date())),
            URLQueryItem(name: "limit", value: String(page.limit)),
            URLQueryItem(name: "offset", value: String(page.offset)),
        ]
        if let species { result.append(URLQueryItem(name: "species", value: species.apiValue)) }
        if let condition { result.append(URLQueryItem(name: "condition", value: condition.apiValue)) }
        return result
    }
}

enum MapPeriod: String, CaseIterable, Identifiable {
    case sevenDays = "7 days"
    case thirtyDays = "30 days"
    case thisYear = "This year"
    case allTime = "All time"

    var id: String { rawValue }

    var since: Date {
        let calendar = Calendar.current
        switch self {
        case .sevenDays: return calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        case .thirtyDays: return calendar.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        case .thisYear: return calendar.date(from: calendar.dateComponents([.year], from: Date())) ?? Date()
        case .allTime: return Date(timeIntervalSince1970: 0)
        }
    }
}

enum ExportScope: String, CaseIterable, Identifiable {
    case currentView = "current_view"
    case all

    var id: String { rawValue }
    var title: String { self == .currentView ? "Current view" : "All individuals" }
}

enum ExportRange: String, CaseIterable, Identifiable {
    case sevenDays = "7d"
    case thirtyDays = "30d"
    case thisYear = "this_year"
    case all

    var id: String { rawValue }
    var title: String {
        switch self {
        case .sevenDays: "7 days"
        case .thirtyDays: "30 days"
        case .thisYear: "This year"
        case .all: "All time"
        }
    }
}

enum ExportField: String, CaseIterable, Identifiable {
    case profile
    case measurements
    case sightingLog = "sighting_log"
    case conditionHistory = "condition_history"
    case coordinates
    case photo

    var id: String { rawValue }
    var title: String {
        switch self {
        case .profile: "Profile"
        case .measurements: "Measurements"
        case .sightingLog: "Sighting log"
        case .conditionHistory: "Condition history"
        case .coordinates: "Coordinates"
        case .photo: "Photo"
        }
    }
}

enum ExportFormat: String, CaseIterable, Identifiable {
    case csv
    case xlsx
    case pdf

    var id: String { rawValue }
    var title: String { rawValue.uppercased() == "XLSX" ? "XLSX" : rawValue.uppercased() }
    var fileExtension: String { rawValue }
}

struct ExportRequest: Hashable, Sendable {
    var scope: ExportScope
    var range: ExportRange
    var fields: Set<ExportField>
    var format: ExportFormat
    var query: IndividualQuery

    static let `default` = ExportRequest(scope: .currentView, range: .all, fields: [.profile], format: .csv, query: .default)
}

struct DownloadedFile {
    let data: Data
    let filename: String
    let contentType: String
}

struct DashboardSnapshot {
    struct Month: Identifiable {
        let month: String
        let sightings: Int
        let newIndividuals: Int
        var id: String { month }
    }

    let months: [Month]
    let species: [SpeciesSummary]
}

struct TurtleMeasurement: Identifiable, Hashable {
    let id: String
    let date: String
    let length: Double?
    let width: Double?
    let weight: Double?
}

struct TurtleLogSummary: Identifiable, Hashable {
    let id: String
    let date: String
    let location: String
    let status: String
    let condition: TurtleCondition?
    let notes: String?
    let coordinate: TurtleCoordinate?
    /// Only populated for body-condition records. `nil` for regular sighting
    /// entries. The Body Condition tab filters on this.
    let bodyPart: TurtleBodyPart?
    let markingSeverity: String?
    var isBodyConditionRecord: Bool { bodyPart != nil }

    init(
        id: String,
        date: String,
        location: String,
        status: String,
        condition: TurtleCondition?,
        notes: String?,
        coordinate: TurtleCoordinate?,
        bodyPart: TurtleBodyPart? = nil,
        markingSeverity: String? = nil
    ) {
        self.id = id
        self.date = date
        self.location = location
        self.status = status
        self.condition = condition
        self.notes = notes
        self.coordinate = coordinate
        self.bodyPart = bodyPart
        self.markingSeverity = markingSeverity
    }
}

struct TurtleDetailData {
    let turtle: Turtle
    let measurements: [TurtleMeasurement]
    let logs: [TurtleLogSummary]
    var sightingLogs: [TurtleLogSummary] { logs.filter { !$0.isBodyConditionRecord } }
}

protocol TurtleRepository: AnyObject {
    func listIndividuals(query: IndividualQuery) async throws -> Page<Turtle>
    func listFavorites() async throws -> [Turtle]
    func setFavorite(turtleID: String, isFavorite: Bool) async throws -> Bool
    func dashboard(query: DashboardQuery) async throws -> DashboardSnapshot
    func mapSightings(query: MapQuery) async throws -> [Sighting]
    func detail(for turtle: Turtle) async throws -> TurtleDetailData
    func export(_ request: ExportRequest) async throws -> DownloadedFile
    func matchPhoto(imageData: Data, side: TurtlePhotoSide, limit: Int) async throws -> MatchSearchOutcome
    func matchPhotoPair(leftData: Data, rightData: Data, limit: Int) async throws -> MatchSearchOutcome
    func fetchOverlayAnnotations(imageData: Data, side: TurtlePhotoSide, candidateID: UUID, candidateSide: TurtlePhotoSide, maxThreads: Int) async throws -> [OverlayAnnotationItem]
    func fetchOverlayPNG(imageData: Data, side: TurtlePhotoSide, candidateID: UUID, candidateSide: TurtlePhotoSide, maxThreads: Int) async throws -> Data
    func uploadIndividualPhoto(individualID: UUID, side: TurtlePhotoSide, imageData: Data) async throws -> String
    func createIndividual(_ draft: IndividualDraft) async throws -> Turtle
    func fetchPhotoData(pathOrURL: String) async throws -> Data
}

extension TurtleRepository {
    func matchPhoto(imageData: Data, side: TurtlePhotoSide, limit: Int = 10) async throws -> MatchSearchOutcome {
        MatchSearchOutcome(querySide: side, gallerySize: 0, matchState: "no_match", candidates: [], isDualPair: false, pairAgreed: nil)
    }

    func matchPhotoPair(leftData: Data, rightData: Data, limit: Int = 10) async throws -> MatchSearchOutcome {
        MatchSearchOutcome(querySide: .left, gallerySize: 0, matchState: "no_match", candidates: [], isDualPair: true, pairAgreed: nil)
    }

    func fetchOverlayAnnotations(imageData: Data, side: TurtlePhotoSide, candidateID: UUID, candidateSide: TurtlePhotoSide, maxThreads: Int = 35) async throws -> [OverlayAnnotationItem] {
        []
    }

    func fetchOverlayPNG(imageData: Data, side: TurtlePhotoSide, candidateID: UUID, candidateSide: TurtlePhotoSide, maxThreads: Int = 35) async throws -> Data {
        Data()
    }

    func uploadIndividualPhoto(individualID: UUID, side: TurtlePhotoSide, imageData: Data) async throws -> String {
        "/api/v1/individuals/\(individualID.uuidString)/photos/\(side.rawValue)"
    }

    func createIndividual(_ draft: IndividualDraft) async throws -> Turtle {
        try draft.validate()
        return Turtle(id: draft.id.uuidString, species: TurtleSpecies(apiValue: draft.species), location: "Not recorded",
            lastSeen: "Not recorded", sightings: 0, condition: .unknown,
            firstRecorded: APIFormatters.display.string(from: draft.firstSeenAt), isFavorite: false,
            coordinate: nil, backendID: draft.id, name: draft.name)
    }

    func fetchPhotoData(pathOrURL: String) async throws -> Data {
        throw APIError.invalidResponse
    }
}

enum APIFormatters {
    static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let display: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd MMM yyyy"
        return formatter
    }()
}

extension TurtleSpecies {
    var apiValue: String {
        switch self {
        case .unknown: "unknown"
        case .green: "green"
        case .hawksbill: "hawksbill"
        case .oliveRidley: "olive_ridley"
        case .loggerhead: "loggerhead"
        case .leatherback: "leatherback"
        }
    }

    init(apiValue: String) {
        switch apiValue.lowercased() {
        case "green": self = .green
        case "hawksbill": self = .hawksbill
        case "olive_ridley", "olive ridley": self = .oliveRidley
        case "loggerhead": self = .loggerhead
        case "leatherback": self = .leatherback
        default: self = .unknown
        }
    }
}

extension TurtleCondition {
    var apiValue: String {
        switch self {
        case .unknown: "unknown"
        case .healthy: "healthy"
        case .scarred: "scarred"
        case .injured: "injured"
        }
    }

    init?(apiValue: String?) {
        guard let value = apiValue?.lowercased() else { return nil }
        switch value {
        case "healthy": self = .healthy
        case "scarred": self = .scarred
        case "injured": self = .injured
        default: return nil
        }
    }
}

struct MultipartPart {
    let name: String
    let filename: String?
    let contentType: String?
    let data: Data
}

extension JSONDecoder {
    static let api: JSONDecoder = {
        let decoder = JSONDecoder()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = fractional.date(from: string) ?? plain.date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date: \(string)")
        }
        return decoder
    }()
}

extension JSONEncoder {
    static let api: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

private struct IndividualPageDTO: Decodable {
    let items: [IndividualDTO]
    let total: Int
    let limit: Int
    let offset: Int
}

private struct IndividualDTO: Decodable {
    let id: UUID
    let name: String
    let species: String
    let sex: String
    let profileCode: String
    let currentHealthStatus: String
    let firstSeenDate: Date
    let lastSeenDate: Date?
    let lastSeenLocation: String?
    let totalSightings: Int
    let latestMeasurements: MeasurementsDTO?
    let photos: [String: PhotoDTO?]

    enum CodingKeys: String, CodingKey {
        case id, name, species, sex
        case profileCode = "profile_code"
        case currentHealthStatus = "current_health_status"
        case firstSeenDate = "first_seen_date"
        case lastSeenDate = "last_seen_date"
        case lastSeenLocation = "last_seen_location"
        case totalSightings = "total_sightings"
        case latestMeasurements = "latest_measurements"
        case photos
    }
}

private struct MeasurementsDTO: Decodable {
    let curvedCarapaceLength: Double?
    let curvedCarapaceWidth: Double?
    let weight: Double?
    let logID: UUID
    let timestamp: Date

    enum CodingKeys: String, CodingKey {
        case curvedCarapaceLength = "curved_carapace_length"
        case curvedCarapaceWidth = "curved_carapace_width"
        case weight
        case logID = "log_id"
        case timestamp
    }
}

private struct PhotoDTO: Decodable {
    let url: String
    let captureDate: Date

    enum CodingKeys: String, CodingKey {
        case url
        case captureDate = "capture_date"
    }
}

private struct DashboardDTO: Decodable {
    let months: [MonthDTO]
    let species: [SpeciesDTO]
}

private struct MonthDTO: Decodable {
    let month: String
    let sightings: Int
    let newIndividuals: Int

    enum CodingKeys: String, CodingKey {
        case month, sightings
        case newIndividuals = "new_individuals"
    }
}

private struct SpeciesDTO: Decodable {
    let species: String
    let individuals: Int
    let sightings: Int
}

private struct MapPageDTO: Decodable {
    let items: [MapSightingDTO]
}

private struct MapSightingDTO: Decodable {
    let logID: UUID
    let turtleID: UUID?
    let name: String?
    let species: String?
    let condition: String?
    let timestamp: Date
    let placeName: String
    let latitude: Double
    let longitude: Double

    enum CodingKeys: String, CodingKey {
        case logID = "log_id"
        case turtleID = "turtle_id"
        case name, species, condition, timestamp
        case placeName = "place_name"
        case latitude, longitude
    }
}

private struct MatchCandidateDTO: Decodable {
    let individualID: UUID
    let name: String
    let profileCode: String?
    let species: String
    let rank: Int
    let fusedScore: Double
    let confidence: Double
    let confidencePercent: Int
    let globalScore: Double
    let localMatch: Int
    let matchedPhotoSide: String
    let photoURL: String?
    let aboveThreshold: Bool
    let lastSeenDate: Date?
    let lastSeenLocation: String?
    let currentHealthStatus: String?

    enum CodingKeys: String, CodingKey {
        case individualID = "individual_id"
        case name
        case profileCode = "profile_code"
        case species
        case rank
        case fusedScore = "fused_score"
        case confidence
        case confidencePercent = "confidence_percent"
        case globalScore = "global_score"
        case localMatch = "local_match"
        case matchedPhotoSide = "matched_photo_side"
        case photoURL = "photo_url"
        case aboveThreshold = "above_threshold"
        case lastSeenDate = "last_seen_date"
        case lastSeenLocation = "last_seen_location"
        case currentHealthStatus = "current_health_status"
    }

    func toItem() -> MatchCandidateItem {
        MatchCandidateItem(
            individualID: individualID,
            name: name,
            profileCode: profileCode,
            species: TurtleSpecies(apiValue: species),
            rank: rank,
            fusedScore: fusedScore,
            confidence: confidence,
            confidencePercent: confidencePercent,
            globalScore: globalScore,
            localMatch: localMatch,
            matchedPhotoSide: TurtlePhotoSide(rawValue: matchedPhotoSide) ?? .left,
            photoURL: photoURL,
            aboveThreshold: aboveThreshold,
            lastSeenDate: lastSeenDate.map(APIFormatters.display.string(from:)),
            lastSeenLocation: lastSeenLocation,
            condition: TurtleCondition(apiValue: currentHealthStatus)
        )
    }
}

private struct MatchQueryInfoDTO: Decodable {
    let side: String
    let gallerySize: Int

    enum CodingKeys: String, CodingKey {
        case side
        case gallerySize = "gallery_size"
    }
}

private struct MatchResultDTO: Decodable {
    let query: MatchQueryInfoDTO
    let state: String
    let candidates: [MatchCandidateDTO]
}

private struct PairedSideEvidenceDTO: Decodable {
    let rank: Int?
    let fusedScore: Double?
    let confidence: Double?
    let confidencePercent: Int?

    enum CodingKeys: String, CodingKey {
        case rank
        case fusedScore = "fused_score"
        case confidence
        case confidencePercent = "confidence_percent"
    }
}

private struct PairedCandidateDTO: Decodable {
    let individualID: UUID
    let name: String
    let profileCode: String?
    let species: String
    let rank: Int
    let combinedScore: Double
    let confidence: Double
    let confidencePercent: Int
    let left: PairedSideEvidenceDTO
    let right: PairedSideEvidenceDTO
    let photos: [String: PhotoDTO?]
    let lastSeenDate: Date?
    let lastSeenLocation: String?
    let currentHealthStatus: String?

    enum CodingKeys: String, CodingKey {
        case individualID = "individual_id"
        case name
        case profileCode = "profile_code"
        case species
        case rank
        case combinedScore = "combined_score"
        case confidence
        case confidencePercent = "confidence_percent"
        case left
        case right
        case photos
        case lastSeenDate = "last_seen_date"
        case lastSeenLocation = "last_seen_location"
        case currentHealthStatus = "current_health_status"
    }

    func toItem() -> MatchCandidateItem {
        let leftURL = photos["left"]??.url
        let rightURL = photos["right"]??.url
        let side: TurtlePhotoSide = leftURL != nil ? .left : .right
        return MatchCandidateItem(
            individualID: individualID,
            name: name,
            profileCode: profileCode,
            species: TurtleSpecies(apiValue: species),
            rank: rank,
            fusedScore: combinedScore,
            confidence: confidence,
            confidencePercent: confidencePercent,
            globalScore: left.fusedScore ?? right.fusedScore ?? combinedScore,
            localMatch: 0,
            matchedPhotoSide: side,
            photoURL: leftURL ?? rightURL,
            aboveThreshold: true,
            lastSeenDate: lastSeenDate.map(APIFormatters.display.string(from:)),
            lastSeenLocation: lastSeenLocation,
            condition: TurtleCondition(apiValue: currentHealthStatus)
        )
    }
}

private struct DualMatchResultDTO: Decodable {
    let state: String
    let agreed: Bool
    let candidates: [PairedCandidateDTO]
    let photoA: MatchResultDTO
    let photoB: MatchResultDTO

    enum CodingKeys: String, CodingKey {
        case state
        case agreed
        case candidates
        case photoA = "photo_a"
        case photoB = "photo_b"
    }
}

private struct OverlayAnnotationsDTO: Decodable {
    let annotations: [OverlayAnnotationItem]
}

private extension IndividualDTO {
    func turtle() -> Turtle {
        let leftURL = photos["left"]??.url
        let rightURL = photos["right"]??.url
        return Turtle(
            id: id.uuidString,
            species: TurtleSpecies(apiValue: species),
            location: lastSeenLocation ?? "Location not recorded",
            lastSeen: lastSeenDate.map(APIFormatters.display.string(from:)) ?? "Not recorded",
            sightings: totalSightings,
            condition: TurtleCondition(apiValue: currentHealthStatus) ?? .unknown,
            firstRecorded: APIFormatters.display.string(from: firstSeenDate),
            isFavorite: false,
            coordinate: nil,
            backendID: id,
            leftPhotoURL: leftURL,
            rightPhotoURL: rightURL,
            name: name.isEmpty ? profileCode : name
        )
    }
}

final class RemoteTurtleRepository: TurtleRepository {
    let client: APIClient
    private var cache: [String: Turtle] = [:]

    init(client: APIClient? = nil) { self.client = client ?? .shared }

    func listIndividuals(query: IndividualQuery) async throws -> Page<Turtle> {
        let dto: V2Page<V2Profile> = try await client.get("api/v2/individuals", queryItems: query.queryItems)
        let items = dto.items.map { $0.turtle() }
        items.forEach { cache[$0.id] = $0 }
        return Page(items: items, total: dto.total, request: PageRequest(limit: dto.limit, offset: dto.offset))
    }

    func listFavorites() async throws -> [Turtle] {
        let dto: IndividualPageDTO = try await client.get("api/v1/favorites", queryItems: [URLQueryItem(name: "limit", value: "200")])
        let items = dto.items.map { $0.turtle() }
        items.forEach { cache[$0.id] = $0 }
        return items
    }

    func setFavorite(turtleID: String, isFavorite: Bool) async throws -> Bool {
        guard let backendID = UUID(uuidString: turtleID) ?? cache[turtleID]?.backendID else { throw APIError.invalidResponse }
        let path = "api/v1/favorites/\(backendID.uuidString)"
        if isFavorite { _ = try await client.requestData(path: path, method: "PUT") }
        else { _ = try await client.requestData(path: path, method: "DELETE") }
        return isFavorite
    }

    func dashboard(query: DashboardQuery) async throws -> DashboardSnapshot {
        let dto: DashboardDTO = try await client.get("api/v1/dashboard/summary", queryItems: query.queryItems)
        let species = dto.species.map {
            SpeciesSummary(id: $0.species, species: TurtleSpecies(apiValue: $0.species), individuals: $0.individuals, sightings: $0.sightings)
        }
        return DashboardSnapshot(months: dto.months.map { .init(month: $0.month, sightings: $0.sightings, newIndividuals: $0.newIndividuals) }, species: species).fillingMissingMonths()
    }

    func mapSightings(query: MapQuery) async throws -> [Sighting] {
        let dto: MapPageDTO = try await client.get("api/v1/dashboard/map/sightings", queryItems: query.queryItems)
        return dto.items.compactMap { item in
            guard let species = item.species else { return nil }
            let condition = TurtleCondition(apiValue: item.condition) ?? .unknown
            let turtleID = item.name ?? "Unidentified turtle"
            return Sighting(name: turtleID, id: item.logID.uuidString, turtleID: item.turtleID?.uuidString ?? item.logID.uuidString, species: TurtleSpecies(apiValue: species), location: item.placeName, date: APIFormatters.display.string(from: item.timestamp), condition: condition, coordinate: TurtleCoordinate(latitude: item.latitude, longitude: item.longitude))
        }
    }

    func detail(for turtle: Turtle) async throws -> TurtleDetailData {
        guard let backendID = turtle.backendID else { throw APIError.invalidResponse }
        let profile: V2Profile = try await client.get("api/v2/individuals/\(backendID.uuidString)")
        var logs: [V2Sighting] = []
        var offset = 0
        while true {
            let page: V2Page<V2Sighting> = try await client.get("api/v2/individuals/\(backendID.uuidString)/logs",
                queryItems: [URLQueryItem(name: "limit", value: "200"), URLQueryItem(name: "offset", value: String(offset))])
            logs.append(contentsOf: page.items)
            offset += page.items.count
            if offset >= page.total || page.items.isEmpty { break }
        }
        return TurtleDetailData(turtle: profile.turtle(), measurements: logs.compactMap(\.measurement), logs: logs.flatMap(\.logs))
    }

    func export(_ request: ExportRequest) async throws -> DownloadedFile {
        var items = request.query.queryItems
        items.append(URLQueryItem(name: "format", value: request.format.rawValue))
        items.append(URLQueryItem(name: "scope", value: request.scope.rawValue))
        items.append(URLQueryItem(name: "range", value: request.range.rawValue))
        items.append(contentsOf: request.fields.map { URLQueryItem(name: "fields", value: $0.rawValue) })
        let (data, response) = try await client.getData("api/v1/exports/individuals", queryItems: items)
        let filename = response.value(forHTTPHeaderField: "Content-Disposition")?.split(separator: "filename=").last.map(String.init)?.trimmingCharacters(in: CharacterSet(charactersIn: "\" ")) ?? "individuals.\(request.format.fileExtension)"
        return DownloadedFile(data: data, filename: filename, contentType: response.mimeType ?? "application/octet-stream")
    }

    func matchPhoto(imageData: Data, side: TurtlePhotoSide, limit: Int = 10) async throws -> MatchSearchOutcome {
        let queryItems = [
            URLQueryItem(name: "side", value: side.rawValue),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "empty_on_no_reliable", value: "false"),
        ]
        let part = MultipartPart(name: "file", filename: "query.jpg", contentType: "image/jpeg", data: imageData)
        let dto: MatchResultDTO = try await client.requestMultipart(
            path: "api/v1/match",
            method: "POST",
            queryItems: queryItems,
            parts: [part]
        )
        return MatchSearchOutcome(
            querySide: TurtlePhotoSide(rawValue: dto.query.side) ?? side,
            gallerySize: dto.query.gallerySize,
            matchState: dto.state,
            candidates: dto.candidates.map { $0.toItem() },
            isDualPair: false,
            pairAgreed: nil
        )
    }

    func matchPhotoPair(leftData: Data, rightData: Data, limit: Int = 10) async throws -> MatchSearchOutcome {
        let queryItems = [
            URLQueryItem(name: "side_a", value: "left"),
            URLQueryItem(name: "side_b", value: "right"),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "empty_on_no_reliable", value: "false"),
        ]
        let parts = [
            MultipartPart(name: "file_a", filename: "left.jpg", contentType: "image/jpeg", data: leftData),
            MultipartPart(name: "file_b", filename: "right.jpg", contentType: "image/jpeg", data: rightData),
        ]
        let dto: DualMatchResultDTO = try await client.requestMultipart(
            path: "api/v1/match/pair",
            method: "POST",
            queryItems: queryItems,
            parts: parts
        )
        let sideLookup = Dictionary(uniqueKeysWithValues: (dto.photoA.candidates + dto.photoB.candidates).map { ($0.individualID, $0) })
        let items = dto.candidates.map { paired -> MatchCandidateItem in
            var item = paired.toItem()
            if let sideMatch = sideLookup[paired.individualID] {
                item = MatchCandidateItem(
                    individualID: item.individualID,
                    name: item.name,
                    profileCode: item.profileCode,
                    species: item.species,
                    rank: item.rank,
                    fusedScore: item.fusedScore,
                    confidence: item.confidence,
                    confidencePercent: item.confidencePercent,
                    globalScore: sideMatch.globalScore,
                    localMatch: sideMatch.localMatch,
                    matchedPhotoSide: item.matchedPhotoSide,
                    photoURL: item.photoURL,
                    aboveThreshold: item.aboveThreshold,
                    lastSeenDate: item.lastSeenDate,
                    lastSeenLocation: item.lastSeenLocation,
                    condition: item.condition
                )
            }
            return item
        }
        return MatchSearchOutcome(
            querySide: .left,
            gallerySize: dto.photoA.query.gallerySize + dto.photoB.query.gallerySize,
            matchState: dto.state,
            candidates: items,
            isDualPair: true,
            pairAgreed: dto.agreed
        )
    }

    func fetchOverlayAnnotations(
        imageData: Data,
        side: TurtlePhotoSide,
        candidateID: UUID,
        candidateSide: TurtlePhotoSide,
        maxThreads: Int = 35
    ) async throws -> [OverlayAnnotationItem] {
        let queryItems = [
            URLQueryItem(name: "side", value: side.rawValue),
            URLQueryItem(name: "candidate_individual_id", value: candidateID.uuidString),
            URLQueryItem(name: "candidate_side", value: candidateSide.rawValue),
            URLQueryItem(name: "max_threads", value: String(maxThreads)),
        ]
        let part = MultipartPart(name: "file", filename: "query.jpg", contentType: "image/jpeg", data: imageData)
        let dto: OverlayAnnotationsDTO = try await client.requestMultipart(
            path: "api/v1/match/overlay/annotations",
            method: "POST",
            queryItems: queryItems,
            parts: [part]
        )
        return dto.annotations
    }

    func fetchOverlayPNG(
        imageData: Data,
        side: TurtlePhotoSide,
        candidateID: UUID,
        candidateSide: TurtlePhotoSide,
        maxThreads: Int = 35
    ) async throws -> Data {
        let queryItems = [
            URLQueryItem(name: "side", value: side.rawValue),
            URLQueryItem(name: "candidate_individual_id", value: candidateID.uuidString),
            URLQueryItem(name: "candidate_side", value: candidateSide.rawValue),
            URLQueryItem(name: "max_threads", value: String(maxThreads)),
        ]
        let part = MultipartPart(name: "file", filename: "query.jpg", contentType: "image/jpeg", data: imageData)
        let (data, _) = try await client.requestMultipartData(
            path: "api/v1/match/overlay",
            method: "POST",
            queryItems: queryItems,
            parts: [part],
            accept: "image/png"
        )
        return data
    }

    func uploadIndividualPhoto(individualID: UUID, side: TurtlePhotoSide, imageData: Data) async throws -> String {
        let part = MultipartPart(name: "file", filename: "\(side.rawValue).jpg", contentType: "image/jpeg", data: imageData)
        let dto: V2Photo = try await client.requestMultipart(
            path: "api/v2/individuals/\(individualID.uuidString)/photos/\(side.rawValue)",
            method: "PUT",
            parts: [part]
        )
        return dto.url
    }

    func createIndividual(_ draft: IndividualDraft) async throws -> Turtle {
        try draft.validate()
        let dto: V2Profile = try await client.request(path: "api/v2/individuals", method: "POST", body: JSONEncoder.api.encode(draft))
        let created = dto.turtle()
        cache[created.id] = created
        return created
    }

    func fetchPhotoData(pathOrURL: String) async throws -> Data {
        let (data, _) = try await client.requestData(
            path: pathOrURL,
            method: "GET",
            accept: "image/*"
        )
        return data
    }
}

private extension DashboardSnapshot {
    func fillingMissingMonths(now: Date = Date()) -> DashboardSnapshot {
        let calendar = Calendar.current
        let byMonth = Dictionary(uniqueKeysWithValues: months.map { ($0.month, $0) })
        let normalized = (0..<12).compactMap { index -> Month? in
            guard let date = calendar.date(byAdding: .month, value: -11 + index, to: now) else { return nil }
            let key = String(format: "%04d-%02d", calendar.component(.year, from: date), calendar.component(.month, from: date))
            return byMonth[key] ?? Month(month: key, sightings: 0, newIndividuals: 0)
        }
        return DashboardSnapshot(months: normalized, species: species)
    }
}
