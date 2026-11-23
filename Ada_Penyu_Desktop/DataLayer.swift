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
        lastMonths(12)
    }

    static func lastMonths(_ count: Int, species: TurtleSpecies? = nil, now: Date = Date()) -> DashboardQuery {
        let clamped = max(1, min(60, count))
        let start = Calendar.current.date(byAdding: .month, value: -(clamped - 1), to: now)
        return DashboardQuery(since: start, until: now, species: species)
    }

    /// Number of calendar months spanned by `[since, until]`, defaulting to 12.
    var resolvedMonthCount: Int {
        let end = until ?? Date()
        guard let since else { return 12 }
        let cal = Calendar.current
        let startComps = cal.dateComponents([.year, .month], from: since)
        let endComps = cal.dateComponents([.year, .month], from: end)
        guard let sy = startComps.year, let sm = startComps.month,
              let ey = endComps.year, let em = endComps.month else { return 12 }
        let diff = (ey - sy) * 12 + (em - sm) + 1
        return max(1, min(60, diff))
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
    case twelveMonths = "Last 12 months"
    case allTime = "All time"

    var id: String { rawValue }

    var since: Date {
        let calendar = Calendar.current
        switch self {
        case .sevenDays: return calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        case .thirtyDays: return calendar.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        case .thisYear: return calendar.date(from: calendar.dateComponents([.year], from: Date())) ?? Date()
        case .twelveMonths: return calendar.date(byAdding: .month, value: -11, to: Date()) ?? Date()
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

    var acceptHeader: String {
        switch self {
        case .csv: "text/csv, */*"
        case .xlsx: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet, */*"
        case .pdf: "application/pdf, */*"
        }
    }
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
    let sourceSightingID: String?
    /// Authenticated photo URLs for this row. Empty for sightings that have
    /// no evidence attached, and for markings that neither own nor inherit any.
    let photoPaths: [String]
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
        markingSeverity: String? = nil,
        sourceSightingID: String? = nil,
        photoPaths: [String] = []
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
        self.sourceSightingID = sourceSightingID
        self.photoPaths = photoPaths
    }
}

struct TurtleDetailData {
    let turtle: Turtle
    let measurements: [TurtleMeasurement]
    let logs: [TurtleLogSummary]
    var sightingLogs: [TurtleLogSummary] { logs.filter { !$0.isBodyConditionRecord } }
}

/// Unidentified field sighting saved via Mobile "Match later / Waiting to Match" (`turtle_id == nil`).
nonisolated struct PendingMobileSighting: Identifiable, Hashable, Sendable {
    let id: UUID
    let observedAt: Date
    let locationName: String
    let notes: String?
    let photoPaths: [String]
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
    func listPendingSightings(limit: Int) async throws -> [PendingMobileSighting]
    func resolvePendingSighting(logID: UUID, turtleID: UUID, method: String, confidence: Double?, notes: String?) async throws
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

    func listPendingSightings(limit: Int = 50) async throws -> [PendingMobileSighting] {
        []
    }

    func resolvePendingSighting(logID: UUID, turtleID: UUID, method: String = "manual", confidence: Double? = nil, notes: String? = nil) async throws {}

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

    /// Per-marking kind, not the encounter-wide status. A healthy encounter can
    /// still carry a wounded head; copying the encounter status onto every part
    /// would hide that.
    init?(markingKind: String) {
        switch markingKind.lowercased() {
        case "wound", "missing_limb", "fibropapilloma":
            self = .injured
        case "scratch", "deformity", "barnacles", "barnacle", "tag_scar", "other":
            self = .scarred
        default:
            return nil
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
    enum CodingKeys: String, CodingKey { case side }
}

private struct MatchResultDTO: Decodable {
    let query: MatchQueryInfoDTO
    let state: String
    let candidates: [MatchCandidateDTO]
    let gallerySize: Int
    enum CodingKeys: String, CodingKey {
        case query, candidates
        case state = "match_state"
        case gallerySize = "gallery_size"
    }
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
        case combinedScore = "merge_rank_score"
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
        case state = "match_state"
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
        return DashboardSnapshot(months: dto.months.map { .init(month: $0.month, sightings: $0.sightings, newIndividuals: $0.newIndividuals) }, species: species)
            .fillingMissingMonths(monthCount: query.resolvedMonthCount, now: query.until ?? Date())
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
        var items: [URLQueryItem] = []
        if request.scope == .currentView {
            if let search = request.query.search {
                items.append(URLQueryItem(name: "q", value: search))
            }
            items.append(contentsOf: request.query.species.map { URLQueryItem(name: "species", value: $0.apiValue) })
            if let condition = request.query.condition {
                items.append(URLQueryItem(name: "condition", value: condition.apiValue))
            }
        }
        items.append(URLQueryItem(name: "sort", value: request.query.sort.rawValue))
        items.append(URLQueryItem(name: "format", value: request.format.rawValue))
        items.append(URLQueryItem(name: "scope", value: request.scope.rawValue))
        items.append(URLQueryItem(name: "range", value: request.range.rawValue))
        let sortedFields = ExportField.allCases.filter { request.fields.contains($0) }
        items.append(contentsOf: sortedFields.map { URLQueryItem(name: "fields", value: $0.rawValue) })
        let (data, response) = try await client.requestData(
            path: "api/v1/exports/individuals",
            method: "GET",
            queryItems: items,
            accept: request.format.acceptHeader
        )
        let fallback = "individuals.\(request.format.fileExtension)"
        let filename = ExportFileBuilder.parseContentDispositionFilename(
            response.value(forHTTPHeaderField: "Content-Disposition"),
            fallback: fallback
        )
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
            gallerySize: dto.gallerySize,
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
        let sideEvidence = dto.photoA.candidates + dto.photoB.candidates
        let items = dto.candidates.map { paired -> MatchCandidateItem in
            var item = paired.toItem()
            if let sideMatch = sideEvidence.first(where: { $0.individualID == paired.individualID && $0.matchedPhotoSide == item.matchedPhotoSide.rawValue }) {
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
                    aboveThreshold: sideMatch.aboveThreshold,
                    lastSeenDate: item.lastSeenDate,
                    lastSeenLocation: item.lastSeenLocation,
                    condition: item.condition
                )
            }
            return item
        }
        return MatchSearchOutcome(
            querySide: .left,
            gallerySize: dto.photoA.gallerySize + dto.photoB.gallerySize,
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
        maxThreads: Int = 60
    ) async throws -> [OverlayAnnotationItem] {
        // Backend `/api/v1/match/overlay/annotations` strictly requires a square JPEG (<= 5% aspect delta).
        // Letterbox into a 512x512 square preserving facial scale geometry, then map query keypoints back.
        let prepared = SquareOverlayMapper.prepareSquareJPEG(from: imageData, squareSide: 512)
        let uploadData = prepared?.jpegData ?? imageData

        let queryItems = [
            URLQueryItem(name: "side", value: side.rawValue),
            URLQueryItem(name: "candidate_individual_id", value: candidateID.uuidString),
            URLQueryItem(name: "candidate_side", value: candidateSide.rawValue),
            URLQueryItem(name: "max_threads", value: String(maxThreads)),
        ]
        let part = MultipartPart(name: "file", filename: "query.jpg", contentType: "image/jpeg", data: uploadData)
        let dto: OverlayAnnotationsDTO = try await client.requestMultipart(
            path: "api/v1/match/overlay/annotations",
            method: "POST",
            queryItems: queryItems,
            parts: [part]
        )
        if let prepared {
            return SquareOverlayMapper.unmapAnnotations(dto.annotations, contentRect: prepared.contentRect)
        }
        return dto.annotations
    }

    func fetchOverlayPNG(
        imageData: Data,
        side: TurtlePhotoSide,
        candidateID: UUID,
        candidateSide: TurtlePhotoSide,
        maxThreads: Int = 35
    ) async throws -> Data {
        let uploadData = SquareOverlayMapper.prepareSquareJPEG(from: imageData, squareSide: 512)?.jpegData ?? imageData
        let queryItems = [
            URLQueryItem(name: "side", value: side.rawValue),
            URLQueryItem(name: "candidate_individual_id", value: candidateID.uuidString),
            URLQueryItem(name: "candidate_side", value: candidateSide.rawValue),
            URLQueryItem(name: "max_threads", value: String(maxThreads)),
        ]
        let part = MultipartPart(name: "file", filename: "query.jpg", contentType: "image/jpeg", data: uploadData)
        let (data, _) = try await client.requestMultipartData(
            path: "api/v1/match/overlay",
            method: "POST",
            queryItems: queryItems,
            parts: [part],
            accept: "image/png"
        )
        return data
    }

    func listPendingSightings(limit: Int = 50) async throws -> [PendingMobileSighting] {
        let queryItems = [
            URLQueryItem(name: "identified_only", value: "false"),
            URLQueryItem(name: "limit", value: String(min(200, max(1, limit)))),
            URLQueryItem(name: "offset", value: "0"),
        ]
        do {
            let page: V2Page<V2PendingLogDTO> = try await client.get("api/v2/logs", queryItems: queryItems)
            return page.items.compactMap { item -> PendingMobileSighting? in
                guard item.turtleID == nil else { return nil }
                let paths = item.photos
                    .filter { $0.markingId == nil }
                    .map(\.fetchPath)
                    .filter { !$0.isEmpty }
                return PendingMobileSighting(
                    id: item.id,
                    observedAt: item.observedAt,
                    locationName: item.location.name,
                    notes: item.notes,
                    photoPaths: paths
                )
            }
        } catch APIError.notFound {
            let page: V1LogListDTO = try await client.get("api/v1/logs", queryItems: queryItems)
            return page.items.compactMap { item -> PendingMobileSighting? in
                guard item.turtleID == nil else { return nil }
                let paths = item.photos
                    .filter { $0.markingID == nil }
                    .map(\.fetchPath)
                    .filter { !$0.isEmpty }
                return PendingMobileSighting(
                    id: item.id,
                    observedAt: item.timestamp,
                    locationName: item.placeName,
                    notes: item.notes,
                    photoPaths: paths
                )
            }
        }
    }

    func resolvePendingSighting(
        logID: UUID,
        turtleID: UUID,
        method: String = "manual",
        confidence: Double? = nil,
        notes: String? = nil
    ) async throws {
        let v2Body = V2ResolveLogPatch(
            turtleID: turtleID,
            identification: .init(method: method, confidence: confidence),
            notes: notes
        )
        do {
            _ = try await client.requestData(
                path: "api/v2/logs/\(logID.uuidString.lowercased())",
                method: "PATCH",
                body: try JSONEncoder.api.encode(v2Body)
            )
        } catch APIError.notFound {
            let v1Body = V1ResolveLogPatch(
                turtleID: turtleID,
                identificationMethod: method,
                matchConfidence: confidence,
                notes: notes
            )
            _ = try await client.requestData(
                path: "api/v1/logs/\(logID.uuidString.lowercased())",
                method: "PATCH",
                body: try JSONEncoder.api.encode(v1Body)
            )
        }
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

extension DashboardSnapshot {
    func fillingMissingMonths(monthCount: Int = 12, now: Date = Date()) -> DashboardSnapshot {
        let calendar = Calendar.current
        let clampedCount = max(1, min(60, monthCount))
        let byMonth = Dictionary(uniqueKeysWithValues: months.map { ($0.month, $0) })
        let normalized = (0..<clampedCount).compactMap { index -> Month? in
            guard let date = calendar.date(byAdding: .month, value: -(clampedCount - 1) + index, to: now) else { return nil }
            let key = String(format: "%04d-%02d", calendar.component(.year, from: date), calendar.component(.month, from: date))
            return byMonth[key] ?? Month(month: key, sightings: 0, newIndividuals: 0)
        }
        return DashboardSnapshot(months: normalized, species: species)
    }
}

final class DemoTurtleRepository: TurtleRepository {
    enum Dataset {
        case baliBaseline
        case panAsiaSuperAccount
        case worldSuperAccount
    }

    private let dataset: Dataset
    private var turtles: [Turtle]
    private var sightings: [Sighting]
    private var favoriteIDs: Set<String>
    private var uploadedPhotos: [String: Data] = [:]

    var fullCatalogForAnalytics: [Turtle] {
        turtles.map(withFavorite)
    }

    init(dataset: Dataset = .baliBaseline) {
        self.dataset = dataset
        switch dataset {
        case .baliBaseline:
            self.turtles = DemoFixtures.turtles
            self.sightings = DemoFixtures.sightings
            self.favoriteIDs = Set(["Turtle #004", "Turtle #005"])
        case .panAsiaSuperAccount:
            self.turtles = DemoFixtures.superAsiaTurtles
            self.sightings = DemoFixtures.superAsiaSightings
            self.favoriteIDs = Set(["ASIA-IN-001", "ASIA-ID-009", "ASIA-MY-014", "ASIA-JP-021"])
        case .worldSuperAccount:
            let world = DemoFixtures.worldSuperDataset
            self.turtles = world.turtles
            self.sightings = world.sightings
            self.favoriteIDs = Set(world.turtles.prefix(8).map(\.id))
        }
    }

    func listIndividuals(query: IndividualQuery) async throws -> Page<Turtle> {
        var results = turtles.filter { turtle in
            let searchMatches = query.search.map { value in
                turtle.displayName.localizedCaseInsensitiveContains(value)
                    || turtle.id.localizedCaseInsensitiveContains(value)
                    || (turtle.profileCode?.localizedCaseInsensitiveContains(value) ?? false)
                    || turtle.species.rawValue.localizedCaseInsensitiveContains(value)
                    || turtle.location.localizedCaseInsensitiveContains(value)
            } ?? true
            let speciesMatches = query.species.isEmpty || query.species.contains(turtle.species)
            let conditionMatches = query.condition == nil || turtle.condition == query.condition
            return searchMatches && speciesMatches && conditionMatches
        }
        if query.sort == .lastSeenDescending {
            let formatter = APIFormatters.display
            results.sort { lhs, rhs in
                let lhsDate = formatter.date(from: lhs.lastSeen) ?? .distantPast
                let rhsDate = formatter.date(from: rhs.lastSeen) ?? .distantPast
                return lhsDate > rhsDate
            }
        } else {
            results.sort { $0.displayName < $1.displayName }
        }
        let start = min(query.page.offset, results.count)
        let end = min(start + query.page.limit, results.count)
        return Page(items: results[start..<end].map { withFavorite($0) }, total: results.count, request: query.page)
    }

    func listFavorites() async throws -> [Turtle] {
        turtles.filter { favoriteIDs.contains($0.id) }.map(withFavorite)
    }

    func setFavorite(turtleID: String, isFavorite: Bool) async throws -> Bool {
        if isFavorite { favoriteIDs.insert(turtleID) } else { favoriteIDs.remove(turtleID) }
        return isFavorite
    }

    func dashboard(query: DashboardQuery) async throws -> DashboardSnapshot {
        let calendar = Calendar.current
        let endDate = query.until ?? Date()
        let count = query.resolvedMonthCount
        let monthKeys = (0..<count).compactMap { index -> String? in
            guard let date = calendar.date(byAdding: .month, value: -(count - 1) + index, to: endDate) else { return nil }
            return String(format: "%04d-%02d", calendar.component(.year, from: date), calendar.component(.month, from: date))
        }
        let scopedSightings = query.species.map { species in sightings.filter { $0.species == species } } ?? sightings
        let scopedTurtles = query.species.map { species in turtles.filter { $0.species == species } } ?? turtles
        let sightingCounts = Dictionary(grouping: scopedSightings, by: { monthKey(for: $0.date) }).mapValues(\.count)
        let newIndividualCounts = Dictionary(grouping: scopedTurtles, by: { monthKey(for: $0.firstRecorded) }).mapValues(\.count)
        let months = monthKeys.map { key in
            DashboardSnapshot.Month(
                month: key,
                sightings: sightingCounts[key] ?? 0,
                newIndividuals: newIndividualCounts[key] ?? 0
            )
        }
        let species = TurtleSpecies.allCases.filter { $0 != .unknown }.map { species in
            SpeciesSummary(
                id: species.apiValue,
                species: species,
                individuals: turtles.filter { $0.species == species }.count,
                sightings: turtles.filter { $0.species == species }.reduce(0) { $0 + $1.sightings }
            )
        }
        return DashboardSnapshot(months: months, species: species)
    }

    private var referenceLatestDate: Date {
        let formatter = APIFormatters.display
        return sightings.compactMap { formatter.date(from: $0.date) }.max() ?? Date()
    }

    private func cutoffDate(for period: MapPeriod, reference: Date) -> Date? {
        let calendar = Calendar.current
        switch period {
        case .sevenDays: return calendar.date(byAdding: .day, value: -7, to: reference)
        case .thirtyDays: return calendar.date(byAdding: .day, value: -30, to: reference)
        case .thisYear: return calendar.date(from: calendar.dateComponents([.year], from: reference))
        case .twelveMonths: return calendar.date(byAdding: .month, value: -11, to: reference)
        case .allTime: return nil
        }
    }

    private func cutoffDate(for range: ExportRange, reference: Date) -> Date? {
        let calendar = Calendar.current
        switch range {
        case .sevenDays: return calendar.date(byAdding: .day, value: -7, to: reference)
        case .thirtyDays: return calendar.date(byAdding: .day, value: -30, to: reference)
        case .thisYear: return calendar.date(from: calendar.dateComponents([.year], from: reference))
        case .all: return nil
        }
    }

    func mapSightings(query: MapQuery) async throws -> [Sighting] {
        let formatter = APIFormatters.display
        let cutoff = cutoffDate(for: query.period, reference: referenceLatestDate)
        return sightings.filter { sighting in
            let matchesSpecies = query.species == nil || query.species == sighting.species
            let matchesCondition = query.condition == nil || query.condition == sighting.condition
            let matchesPeriod: Bool
            if let cutoff, let sightingDate = formatter.date(from: sighting.date) {
                matchesPeriod = sightingDate >= cutoff
            } else {
                matchesPeriod = true
            }
            return matchesSpecies && matchesCondition && matchesPeriod
        }
    }

    func detail(for turtle: Turtle) async throws -> TurtleDetailData {
        let resolvedTurtle = turtles.first(where: { $0.id == turtle.id }) ?? turtle
        let formatter = APIFormatters.display
        let turtleSightings = sightings
            .filter { $0.turtleID == resolvedTurtle.id }
            .sorted {
                (formatter.date(from: $0.date) ?? .distantPast) > (formatter.date(from: $1.date) ?? .distantPast)
            }

        let sightingLogs: [TurtleLogSummary] = turtleSightings.enumerated().map { idx, sighting in
            let photoPaths = resolvedTurtle.identityPhotoPaths
            let note = idx == 0
                ? "Latest coastal encounter near \(sighting.location). Facial scute profile verified."
                : "Historical foraging observation recorded along \(sighting.location)."
            return TurtleLogSummary(
                id: sighting.id,
                date: sighting.date,
                location: sighting.location,
                status: idx == 0 ? "Sighting" : "Resighting",
                condition: sighting.condition,
                notes: note,
                coordinate: sighting.coordinate,
                sourceSightingID: sighting.id,
                photoPaths: photoPaths
            )
        }

        let latestSighting = turtleSightings.first
        let latestSightingID = latestSighting?.id ?? "measurement-\(resolvedTurtle.id)"
        let measurements = [
            demoMeasurement(for: resolvedTurtle, sightingID: latestSightingID, date: latestSighting?.date ?? resolvedTurtle.lastSeen)
        ]

        let bodyConditionLogs = demoBodyConditionLogs(for: resolvedTurtle, sightings: turtleSightings)
        return TurtleDetailData(
            turtle: withFavorite(resolvedTurtle),
            measurements: measurements,
            logs: sightingLogs + bodyConditionLogs
        )
    }

    private func demoMeasurement(for turtle: Turtle, sightingID: String, date: String) -> TurtleMeasurement {
        let hash = turtle.id.unicodeScalars.reduce(UInt64(0)) { ($0 &* 31) &+ UInt64($1.value) }
        let seed = Int(hash % 12)
        let offset = Double(seed) * 1.1
        switch turtle.species {
        case .leatherback:
            return TurtleMeasurement(id: sightingID, date: date, length: 142.0 + offset, width: 104.5 + offset * 0.6, weight: 295.0 + offset * 6.0)
        case .green:
            return TurtleMeasurement(id: sightingID, date: date, length: 88.0 + offset, width: 71.2 + offset * 0.7, weight: 82.0 + offset * 2.4)
        case .hawksbill:
            return TurtleMeasurement(id: sightingID, date: date, length: 74.5 + offset * 0.8, width: 59.4 + offset * 0.6, weight: 46.5 + offset * 1.6)
        case .oliveRidley:
            return TurtleMeasurement(id: sightingID, date: date, length: 64.0 + offset * 0.6, width: 58.0 + offset * 0.5, weight: 35.0 + offset * 1.2)
        case .loggerhead:
            return TurtleMeasurement(id: sightingID, date: date, length: 91.5 + offset * 0.8, width: 76.0 + offset * 0.6, weight: 98.0 + offset * 2.5)
        case .unknown:
            return TurtleMeasurement(id: sightingID, date: date, length: 80.0 + offset, width: 65.0 + offset * 0.6, weight: 52.0 + offset * 1.5)
        }
    }

    private func demoBodyConditionLogs(for turtle: Turtle, sightings: [Sighting]) -> [TurtleLogSummary] {
        guard let latest = sightings.first else { return [] }
        let previous = sightings.dropFirst().first
        let photos = turtle.identityPhotoPaths

        switch turtle.condition {
        case .injured:
            var records: [TurtleLogSummary] = [
                TurtleLogSummary(
                    id: "marking-injured-primary-\(turtle.id)",
                    date: latest.date,
                    location: latest.location,
                    status: "Wound",
                    condition: .injured,
                    notes: "Superficial abrasion observed on leading edge; active swimmer, monitor on next patrol.",
                    coordinate: latest.coordinate,
                    bodyPart: .flipperRight,
                    markingSeverity: "moderate",
                    sourceSightingID: latest.id,
                    photoPaths: photos
                ),
                TurtleLogSummary(
                    id: "marking-injured-carapace-\(turtle.id)",
                    date: latest.date,
                    location: latest.location,
                    status: "Scratch",
                    condition: .scarred,
                    notes: "Healed marginal scute notch noted on posterior carapace.",
                    coordinate: latest.coordinate,
                    bodyPart: .carapace,
                    markingSeverity: "minor",
                    sourceSightingID: latest.id,
                    photoPaths: photos
                ),
            ]
            if let previous {
                records.append(
                    TurtleLogSummary(
                        id: "marking-injured-prev-\(turtle.id)",
                        date: previous.date,
                        location: previous.location,
                        status: "Tag Scar",
                        condition: .scarred,
                        notes: "Old flipper tag notch documented during initial catalog entry.",
                        coordinate: previous.coordinate,
                        bodyPart: .flipperLeft,
                        markingSeverity: "minor",
                        sourceSightingID: previous.id,
                        photoPaths: photos
                    )
                )
            }
            return records

        case .scarred:
            var records: [TurtleLogSummary] = [
                TurtleLogSummary(
                    id: "marking-scarred-primary-\(turtle.id)",
                    date: latest.date,
                    location: latest.location,
                    status: "Tag Scar",
                    condition: .scarred,
                    notes: "Distinct healed notch on trailing margin useful for secondary visual verification.",
                    coordinate: latest.coordinate,
                    bodyPart: .flipperLeft,
                    markingSeverity: "minor",
                    sourceSightingID: latest.id,
                    photoPaths: photos
                ),
            ]
            if let previous {
                records.append(
                    TurtleLogSummary(
                        id: "marking-scarred-prev-\(turtle.id)",
                        date: previous.date,
                        location: previous.location,
                        status: "Barnacles",
                        condition: .scarred,
                        notes: "Light epibiont barnacle cluster along dorsal carapace rim.",
                        coordinate: previous.coordinate,
                        bodyPart: .carapace,
                        markingSeverity: "minor",
                        sourceSightingID: previous.id,
                        photoPaths: photos
                    )
                )
            }
            return records

        case .healthy:
            return [
                TurtleLogSummary(
                    id: "marking-healthy-check-\(turtle.id)",
                    date: latest.date,
                    location: latest.location,
                    status: "Healthy",
                    condition: .healthy,
                    notes: "Carapace and facial scales clear with no active wounds or entanglement marks.",
                    coordinate: latest.coordinate,
                    bodyPart: .carapace,
                    markingSeverity: "none",
                    sourceSightingID: latest.id,
                    photoPaths: photos
                ),
            ]

        case .unknown:
            return []
        }
    }

    func export(_ request: ExportRequest) async throws -> DownloadedFile {
        let effectiveQuery: IndividualQuery
        if request.scope == .all {
            effectiveQuery = IndividualQuery(
                search: nil,
                species: [],
                condition: nil,
                sort: request.query.sort,
                page: PageRequest(limit: max(turtles.count, 1000), offset: 0)
            )
        } else {
            effectiveQuery = IndividualQuery(
                search: request.query.search,
                species: request.query.species,
                condition: request.query.condition,
                sort: request.query.sort,
                page: PageRequest(limit: max(turtles.count, 1000), offset: 0)
            )
        }

        let page = try await listIndividuals(query: effectiveQuery)
        let formatter = APIFormatters.display
        let cutoff = cutoffDate(for: request.range, reference: referenceLatestDate)

        let dateFiltered: [Turtle]
        if let cutoff {
            dateFiltered = page.items.filter { turtle in
                guard let lastSeenDate = formatter.date(from: turtle.lastSeen) else { return false }
                return lastSeenDate >= cutoff
            }
        } else {
            dateFiltered = page.items
        }

        var rows: [ExportFileBuilder.Row] = []
        rows.reserveCapacity(dateFiltered.count)
        for turtle in dateFiltered {
            let detailData = try await detail(for: turtle)
            rows.append(ExportFileBuilder.Row(turtle: turtle, detail: detailData))
        }
        return ExportFileBuilder.build(request: request, rows: rows)
    }

    func fetchPhotoData(pathOrURL: String) async throws -> Data {
        if let stored = uploadedPhotos[pathOrURL] {
            return stored
        }
        if let direct = I3SSampleLibrary.loadImageData(named: pathOrURL) {
            return direct
        }
        let fallbackName = pathOrURL.lowercased().hasSuffix("right") ? "Zizo1_R.jpg" : "Amina1_L.jpg"
        if let fallback = I3SSampleLibrary.loadImageData(named: fallbackName) {
            return fallback
        }
        throw APIError.invalidResponse
    }

    func matchPhoto(imageData: Data, side: TurtlePhotoSide, limit: Int = 10) async throws -> MatchSearchOutcome {
        let items = turtles.prefix(limit).enumerated().map { idx, t -> MatchCandidateItem in
            let fused = max(0.02, 0.36 - Double(idx) * 0.08)
            let conf = idx == 0 ? 0.94 : max(0.08, 0.82 - Double(idx) * 0.14)
            let defaultPhoto = side == .right ? "Zizo1_R.jpg" : "Amina1_L.jpg"
            let candidatePhoto = side == .right ? (t.rightPhotoURL ?? defaultPhoto) : (t.leftPhotoURL ?? defaultPhoto)
            var candidate = MatchCandidateItem(
                individualID: t.backendID ?? UUID(),
                name: t.displayName,
                profileCode: t.profileCode ?? String(format: "000%03d", idx + 1),
                species: t.species,
                rank: idx + 1,
                fusedScore: fused,
                confidence: conf,
                confidencePercent: Int((conf * 100).rounded()),
                globalScore: max(0.25, 0.86 - Double(idx) * 0.07),
                localMatch: max(18, 28 - idx * 4),
                matchedPhotoSide: side,
                photoURL: candidatePhoto,
                aboveThreshold: idx < 2,
                lastSeenDate: t.lastSeen,
                lastSeenLocation: t.location,
                condition: t.condition
            )
            candidate.isBundledExample = true
            return candidate
        }
        return MatchSearchOutcome(
            querySide: side,
            gallerySize: turtles.count,
            matchState: "bundled_examples",
            candidates: Array(items),
            isDualPair: false,
            pairAgreed: nil
        )
    }

    func matchPhotoPair(leftData: Data, rightData: Data, limit: Int = 10) async throws -> MatchSearchOutcome {
        let single = try await matchPhoto(imageData: leftData, side: .left, limit: limit)
        return MatchSearchOutcome(
            querySide: .left,
            gallerySize: single.gallerySize * 2,
            matchState: "bundled_examples",
            candidates: single.candidates,
            isDualPair: true,
            pairAgreed: nil
        )
    }

    private var resolvedPendingLogIDs: Set<UUID> = []

    func fetchOverlayAnnotations(
        imageData: Data,
        side: TurtlePhotoSide,
        candidateID: UUID,
        candidateSide: TurtlePhotoSide,
        maxThreads: Int = 60
    ) async throws -> [OverlayAnnotationItem] {
        let querySampleName = side == .right ? "Zizo1_R.jpg" : "Amina3_L.jpg"
        let matchedTurtle = turtles.first { $0.backendID == candidateID }
            ?? DemoFixtures.turtles.first { $0.backendID == candidateID }
        let candSampleName = candidateSide == .right
            ? (matchedTurtle?.rightPhotoURL ?? "Zizo2_R.jpg")
            : (matchedTurtle?.leftPhotoURL ?? "Amina1_L.jpg")

        guard let qSample = I3SSampleLibrary.sample(forFilenameOrID: querySampleName),
              let cSample = I3SSampleLibrary.sample(forFilenameOrID: candSampleName) else {
            return []
        }

        let qw = Double(max(qSample.imageWidth, 1))
        let qh = Double(max(qSample.imageHeight, 1))
        let cw = Double(max(cSample.imageWidth, 1))
        let ch = Double(max(cSample.imageHeight, 1))

        let qPrefix = qSample.id.prefix { $0.isLetter }.lowercased()
        let cPrefix = cSample.id.prefix { $0.isLetter }.lowercased()
        let isSameIndividual = !qPrefix.isEmpty && qPrefix == cPrefix

        if isSameIndividual,
           qSample.ref1.count >= 2, qSample.ref2.count >= 2, qSample.ref3.count >= 2,
           cSample.ref1.count >= 2, cSample.ref2.count >= 2, cSample.ref3.count >= 2,
           let aff = AffineTransform2D.fit(pairs: [
               (ScalePoint(x: qSample.ref1[0] / qw, y: qSample.ref1[1] / qh),
                ScalePoint(x: cSample.ref1[0] / cw, y: cSample.ref1[1] / ch)),
               (ScalePoint(x: qSample.ref2[0] / qw, y: qSample.ref2[1] / qh),
                ScalePoint(x: cSample.ref2[0] / cw, y: cSample.ref2[1] / ch)),
               (ScalePoint(x: qSample.ref3[0] / qw, y: qSample.ref3[1] / qh),
                ScalePoint(x: cSample.ref3[0] / cw, y: cSample.ref3[1] / ch)),
           ]) {
            let cNorm = cSample.keypoints.compactMap { kp -> ScalePoint? in
                guard kp.count >= 2 else { return nil }
                return ScalePoint(x: kp[0] / cw, y: kp[1] / ch)
            }
            var items: [OverlayAnnotationItem] = []
            for (idx, qkp) in qSample.keypoints.enumerated() where qkp.count >= 2 {
                let qp = ScalePoint(x: qkp[0] / qw, y: qkp[1] / qh)
                let projected = aff.apply(qp)
                let target: ScalePoint
                if let nearest = cNorm.min(by: {
                    hypot($0.x - projected.x, $0.y - projected.y) < hypot($1.x - projected.x, $1.y - projected.y)
                }), hypot(nearest.x - projected.x, nearest.y - projected.y) < 0.045 {
                    target = nearest
                } else {
                    target = ScalePoint(
                        x: min(0.98, max(0.02, projected.x)),
                        y: min(0.98, max(0.02, projected.y))
                    )
                }
                items.append(OverlayAnnotationItem(
                    featureID: "xfeat-\(idx + 1)",
                    label: "xfeat_lighterglue_match",
                    score: max(0.58, 0.96 - Double(idx) * 0.015),
                    query: OverlayMatchPoint(x: qp.x, y: qp.y),
                    candidate: OverlayMatchPoint(x: target.x, y: target.y)
                ))
                if items.count >= max(1, maxThreads - 3) { break }
            }
            // Inject 3 realistic water/glare outliers so RANSAC visibly separates green inliers from red outliers.
            let outliers: [(ScalePoint, ScalePoint, Double)] = [
                (ScalePoint(x: 0.10, y: 0.14), ScalePoint(x: 0.86, y: 0.22), 0.34),
                (ScalePoint(x: 0.88, y: 0.82), ScalePoint(x: 0.18, y: 0.74), 0.29),
                (ScalePoint(x: 0.14, y: 0.84), ScalePoint(x: 0.78, y: 0.16), 0.26),
            ]
            for (i, out) in outliers.enumerated() where items.count < maxThreads {
                items.append(OverlayAnnotationItem(
                    featureID: "xfeat-outlier-\(i + 1)",
                    label: "xfeat_lighterglue_match",
                    score: out.2,
                    query: OverlayMatchPoint(x: out.0.x, y: out.0.y),
                    candidate: OverlayMatchPoint(x: out.1.x, y: out.1.y)
                ))
            }
            return items
        }

        // Impostor pair in Demo mode: scattered weak correspondences so RANSAC honestly reports Weak consensus.
        let count = min(10, min(maxThreads, min(qSample.keypoints.count, cSample.keypoints.count)))
        return (0..<count).map { idx in
            let qkp = qSample.keypoints[idx]
            let cIdx = (idx * 5 + 3) % cSample.keypoints.count
            let ckp = cSample.keypoints[cIdx]
            return OverlayAnnotationItem(
                featureID: "xfeat-weak-\(idx + 1)",
                label: "xfeat_lighterglue_match",
                score: max(0.18, 0.44 - Double(idx) * 0.025),
                query: OverlayMatchPoint(x: qkp[0] / qw, y: qkp[1] / qh),
                candidate: OverlayMatchPoint(x: ckp[0] / cw, y: ckp[1] / ch)
            )
        }
    }

    func listPendingSightings(limit: Int = 50) async throws -> [PendingMobileSighting] {
        let demoID = UUID(uuidString: "00000000-0000-4000-8999-000000000001")!
        guard !resolvedPendingLogIDs.contains(demoID) else { return [] }
        return [
            PendingMobileSighting(
                id: demoID,
                observedAt: Date().addingTimeInterval(-3600 * 5),
                locationName: "Nusa Penida North Reef (Mobile)",
                notes: "Marked 'Match later' from field patrol iPhone — strong glare near cheek.",
                photoPaths: ["Amina3_L.jpg", "Zizo1_R.jpg"]
            )
        ]
    }

    func resolvePendingSighting(
        logID: UUID,
        turtleID: UUID,
        method: String = "manual",
        confidence: Double? = nil,
        notes: String? = nil
    ) async throws {
        resolvedPendingLogIDs.insert(logID)
    }

    func createIndividual(_ draft: IndividualDraft) async throws -> Turtle {
        try draft.validate()
        let firstSeen = APIFormatters.display.string(from: draft.firstSeenAt)
        let created = Turtle(
            id: draft.id.uuidString,
            species: TurtleSpecies(apiValue: draft.species),
            location: "Imported",
            lastSeen: firstSeen,
            sightings: 1,
            condition: .unknown,
            firstRecorded: firstSeen,
            isFavorite: false,
            coordinate: nil,
            backendID: draft.id,
            leftPhotoURL: nil,
            rightPhotoURL: nil,
            name: draft.name,
            profileCode: draft.profileCode
        )
        turtles.insert(created, at: 0)
        return created
    }

    func uploadIndividualPhoto(individualID: UUID, side: TurtlePhotoSide, imageData: Data) async throws -> String {
        let key = "demo-upload://\(individualID.uuidString)/\(side.rawValue).jpg"
        uploadedPhotos[key] = imageData
        if let idx = turtles.firstIndex(where: { $0.backendID == individualID || $0.id == individualID.uuidString }) {
            let t = turtles[idx]
            turtles[idx] = Turtle(
                id: t.id,
                species: t.species,
                location: t.location,
                lastSeen: t.lastSeen,
                sightings: t.sightings,
                condition: t.condition,
                firstRecorded: t.firstRecorded,
                isFavorite: t.isFavorite,
                coordinate: t.coordinate,
                backendID: t.backendID,
                leftPhotoURL: side == .left ? key : t.leftPhotoURL,
                rightPhotoURL: side == .right ? key : t.rightPhotoURL,
                name: t.name,
                profileCode: t.profileCode
            )
        }
        return key
    }

    private func withFavorite(_ turtle: Turtle) -> Turtle {
        Turtle(
            id: turtle.id,
            species: turtle.species,
            location: turtle.location,
            lastSeen: turtle.lastSeen,
            sightings: turtle.sightings,
            condition: turtle.condition,
            firstRecorded: turtle.firstRecorded,
            isFavorite: favoriteIDs.contains(turtle.id),
            coordinate: turtle.coordinate,
            backendID: turtle.backendID,
            leftPhotoURL: turtle.leftPhotoURL,
            rightPhotoURL: turtle.rightPhotoURL,
            name: turtle.name,
            profileCode: turtle.profileCode
        )
    }

    private func monthKey(for displayDate: String) -> String {
        guard let date = APIFormatters.display.date(from: displayDate) else { return "unknown" }
        let components = Calendar.current.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }
}

enum DemoFixtures {
    static let turtles: [Turtle] = [
        Turtle(id: "Turtle #001", species: .hawksbill, location: "Kuta Beach", lastSeen: "17 Aug 2026", sightings: 5, condition: .injured, firstRecorded: "01 Mar 2026", isFavorite: false, coordinate: TurtleCoordinate(latitude: -8.7180, longitude: 115.1690), backendID: UUID(uuidString: "00000000-0000-4000-8000-000000000001"), leftPhotoURL: "Amina1_L.jpg", rightPhotoURL: "Amina1_R.jpg", name: "Amina", profileCode: "000001"),
        Turtle(id: "Turtle #002", species: .green, location: "Nusa Dua reef", lastSeen: "12 Aug 2026", sightings: 8, condition: .healthy, firstRecorded: "12 Apr 2026", isFavorite: false, coordinate: TurtleCoordinate(latitude: -8.7960, longitude: 115.2280), backendID: UUID(uuidString: "00000000-0000-4000-8000-000000000002"), leftPhotoURL: "Aikane1_L.jpg", rightPhotoURL: "Zizo1_R.jpg", name: "Aikane", profileCode: "000002"),
        Turtle(id: "Turtle #003", species: .oliveRidley, location: "Serangan Island", lastSeen: "09 Aug 2026", sightings: 4, condition: .scarred, firstRecorded: "21 Apr 2026", isFavorite: false, coordinate: TurtleCoordinate(latitude: -8.7240, longitude: 115.2500), backendID: UUID(uuidString: "00000000-0000-4000-8000-000000000003"), leftPhotoURL: "Ghost1_L.jpg", rightPhotoURL: "Amina2_R.jpg", name: "Ghost", profileCode: "000003"),
        Turtle(id: "Turtle #004", species: .green, location: "Sanur flats", lastSeen: "02 Aug 2026", sightings: 3, condition: .scarred, firstRecorded: "07 May 2026", isFavorite: true, coordinate: TurtleCoordinate(latitude: -8.6870, longitude: 115.2620), backendID: UUID(uuidString: "00000000-0000-4000-8000-000000000004"), leftPhotoURL: "Hoku1_L.jpg", rightPhotoURL: "Zizo2_R.jpg", name: "Hoku", profileCode: "000004"),
        Turtle(id: "Turtle #005", species: .leatherback, location: "Pantai Timur", lastSeen: "28 Jul 2026", sightings: 1, condition: .healthy, firstRecorded: "16 Jun 2026", isFavorite: true, coordinate: TurtleCoordinate(latitude: -8.7800, longitude: 115.2500), backendID: UUID(uuidString: "00000000-0000-4000-8000-000000000005"), leftPhotoURL: "Amina2_L.jpg", rightPhotoURL: nil, name: "Zizo", profileCode: "000005"),
        Turtle(id: "Turtle #006", species: .loggerhead, location: "Jimbaran Bay", lastSeen: "24 Jul 2026", sightings: 6, condition: .healthy, firstRecorded: "18 Feb 2026", isFavorite: false, coordinate: TurtleCoordinate(latitude: -8.7850, longitude: 115.1580), backendID: UUID(uuidString: "00000000-0000-4000-8000-000000000006"), leftPhotoURL: nil, rightPhotoURL: "Zizo1_R.jpg", name: "Koa", profileCode: "000006"),
        Turtle(id: "Turtle #007", species: .hawksbill, location: "Legian Beach", lastSeen: "19 Jul 2026", sightings: 7, condition: .injured, firstRecorded: "02 Jan 2026", isFavorite: false, coordinate: TurtleCoordinate(latitude: -8.7040, longitude: 115.1660), backendID: UUID(uuidString: "00000000-0000-4000-8000-000000000007"), leftPhotoURL: "Ghost2_L.jpg", rightPhotoURL: "Amina2_R.jpg", name: "Nalu", profileCode: "000007"),
        Turtle(id: "Turtle #008", species: .green, location: "Tuban Beach", lastSeen: "12 Jul 2026", sightings: 9, condition: .healthy, firstRecorded: "11 Jan 2026", isFavorite: false, coordinate: TurtleCoordinate(latitude: -8.7360, longitude: 115.1670), backendID: UUID(uuidString: "00000000-0000-4000-8000-000000000008"), leftPhotoURL: "Hoku2_L.jpg", rightPhotoURL: "Zizo2_R.jpg", name: "Moana", profileCode: "000008"),
    ]

    static let sightings: [Sighting] = {
        var result: [Sighting] = []
        for (index, turtle) in turtles.enumerated() {
            let coord = turtle.coordinate ?? TurtleCoordinate(latitude: -8.72, longitude: 115.20)
            result.append(
                Sighting(
                    name: turtle.displayName,
                    id: "demo-sighting-\(index + 1)",
                    turtleID: turtle.id,
                    species: turtle.species,
                    location: turtle.location,
                    date: turtle.lastSeen,
                    condition: turtle.condition,
                    coordinate: coord
                )
            )
            if turtle.sightings > 1 {
                result.append(
                    Sighting(
                        name: turtle.displayName,
                        id: "demo-sighting-prev-\(index + 1)",
                        turtleID: turtle.id,
                        species: turtle.species,
                        location: turtle.location,
                        date: turtle.firstRecorded,
                        condition: turtle.condition,
                        coordinate: coord
                    )
                )
            }
        }
        return result
    }()

    // MARK: - Pan-Asia Super Account Demo Dataset (SE Asia, India & Indian Ocean, East Asia)

    static let superAsiaTurtles: [Turtle] = [
        // South Asia / India & Indian Ocean
        Turtle(id: "ASIA-IN-001", species: .oliveRidley, location: "Gahirmatha, Odisha, India", lastSeen: "12 Nov 2026", sightings: 14, condition: .healthy, firstRecorded: "18 Dec 2025", isFavorite: true, coordinate: TurtleCoordinate(latitude: 20.715, longitude: 87.018), backendID: UUID(uuidString: "00000000-0000-4000-8100-000000000001"), leftPhotoURL: "Amina1_L.jpg", rightPhotoURL: "Amina1_R.jpg", name: "Kaveri", profileCode: "IND-OD-01"),
        Turtle(id: "ASIA-IN-002", species: .oliveRidley, location: "Rushikulya, Odisha, India", lastSeen: "05 Nov 2026", sightings: 9, condition: .scarred, firstRecorded: "14 Jan 2026", isFavorite: false, coordinate: TurtleCoordinate(latitude: 19.375, longitude: 85.075), backendID: UUID(uuidString: "00000000-0000-4000-8100-000000000002"), leftPhotoURL: "Ghost1_L.jpg", rightPhotoURL: "Amina2_R.jpg", name: "Chilika", profileCode: "IND-OD-02"),
        Turtle(id: "ASIA-IN-003", species: .green, location: "Havelock Reef, Andaman, India", lastSeen: "09 Nov 2026", sightings: 11, condition: .healthy, firstRecorded: "04 Feb 2026", isFavorite: false, coordinate: TurtleCoordinate(latitude: 11.976, longitude: 92.987), backendID: UUID(uuidString: "00000000-0000-4000-8100-000000000003"), leftPhotoURL: "Aikane1_L.jpg", rightPhotoURL: "Zizo1_R.jpg", name: "Swaraj", profileCode: "IND-AN-03"),
        Turtle(id: "ASIA-IN-004", species: .leatherback, location: "Little Andaman, India", lastSeen: "21 Oct 2026", sightings: 5, condition: .injured, firstRecorded: "03 Mar 2026", isFavorite: false, coordinate: TurtleCoordinate(latitude: 10.625, longitude: 92.548), backendID: UUID(uuidString: "00000000-0000-4000-8100-000000000004"), leftPhotoURL: "Hoku1_L.jpg", rightPhotoURL: "Zizo2_R.jpg", name: "Galathea", profileCode: "IND-AN-04"),
        Turtle(id: "ASIA-IN-005", species: .green, location: "Agatti Lagoon, Lakshadweep, India", lastSeen: "15 Nov 2026", sightings: 12, condition: .healthy, firstRecorded: "22 Dec 2025", isFavorite: false, coordinate: TurtleCoordinate(latitude: 10.858, longitude: 72.194), backendID: UUID(uuidString: "00000000-0000-4000-8100-000000000005"), leftPhotoURL: "Amina2_L.jpg", rightPhotoURL: "Zizo1_R.jpg", name: "Agatti", profileCode: "IND-LK-05"),
        Turtle(id: "ASIA-IN-006", species: .oliveRidley, location: "Pirotan Island, Gujarat, India", lastSeen: "28 Oct 2026", sightings: 6, condition: .scarred, firstRecorded: "11 Apr 2026", isFavorite: false, coordinate: TurtleCoordinate(latitude: 22.601, longitude: 69.956), backendID: UUID(uuidString: "00000000-0000-4000-8100-000000000006"), leftPhotoURL: "Ghost2_L.jpg", rightPhotoURL: "Amina2_R.jpg", name: "Kachchh", profileCode: "IND-GJ-06"),
        Turtle(id: "ASIA-LK-007", species: .loggerhead, location: "Rekawa Lagoon, Sri Lanka", lastSeen: "01 Nov 2026", sightings: 8, condition: .healthy, firstRecorded: "09 Feb 2026", isFavorite: false, coordinate: TurtleCoordinate(latitude: 6.046, longitude: 80.861), backendID: UUID(uuidString: "00000000-0000-4000-8100-000000000007"), leftPhotoURL: "Hoku2_L.jpg", rightPhotoURL: "Zizo2_R.jpg", name: "Rekawa", profileCode: "LKA-RK-07"),
        Turtle(id: "ASIA-MV-008", species: .hawksbill, location: "Lhaviyani Atoll, Maldives", lastSeen: "07 Nov 2026", sightings: 10, condition: .healthy, firstRecorded: "15 Jan 2026", isFavorite: false, coordinate: TurtleCoordinate(latitude: 5.402, longitude: 73.478), backendID: UUID(uuidString: "00000000-0000-4000-8100-000000000008"), leftPhotoURL: "Amina3_L.jpg", rightPhotoURL: "Amina1_R.jpg", name: "Naifaru", profileCode: "MDV-LH-08"),

        // Southeast Asia
        Turtle(id: "ASIA-ID-009", species: .hawksbill, location: "Nusa Penida, Bali, Indonesia", lastSeen: "16 Nov 2026", sightings: 13, condition: .injured, firstRecorded: "06 Dec 2025", isFavorite: true, coordinate: TurtleCoordinate(latitude: -8.728, longitude: 115.544), backendID: UUID(uuidString: "00000000-0000-4000-8100-000000000009"), leftPhotoURL: "Amina1_L.jpg", rightPhotoURL: "Amina1_R.jpg", name: "Amina", profileCode: "IDN-BA-09"),
        Turtle(id: "ASIA-ID-010", species: .green, location: "Serangan Reef, Bali, Indonesia", lastSeen: "10 Nov 2026", sightings: 9, condition: .healthy, firstRecorded: "25 Jan 2026", isFavorite: false, coordinate: TurtleCoordinate(latitude: -8.724, longitude: 115.250), backendID: UUID(uuidString: "00000000-0000-4000-8100-000000000010"), leftPhotoURL: "Aikane1_L.jpg", rightPhotoURL: "Zizo1_R.jpg", name: "Serangan", profileCode: "IDN-BA-10"),
        Turtle(id: "ASIA-ID-011", species: .leatherback, location: "Misool, Raja Ampat, Indonesia", lastSeen: "03 Nov 2026", sightings: 7, condition: .healthy, firstRecorded: "19 Mar 2026", isFavorite: false, coordinate: TurtleCoordinate(latitude: -1.915, longitude: 130.145), backendID: UUID(uuidString: "00000000-0000-4000-8100-000000000011"), leftPhotoURL: "Amina2_L.jpg", rightPhotoURL: nil, name: "Misool", profileCode: "IDN-RA-11"),
        Turtle(id: "ASIA-ID-012", species: .green, location: "Derawan Atoll, Indonesia", lastSeen: "14 Nov 2026", sightings: 15, condition: .healthy, firstRecorded: "12 Jan 2026", isFavorite: false, coordinate: TurtleCoordinate(latitude: 2.284, longitude: 118.248), backendID: UUID(uuidString: "00000000-0000-4000-8100-000000000012"), leftPhotoURL: "Hoku1_L.jpg", rightPhotoURL: "Zizo2_R.jpg", name: "Derawan", profileCode: "IDN-DE-12"),
        Turtle(id: "ASIA-ID-013", species: .hawksbill, location: "Wakatobi Reef, Indonesia", lastSeen: "19 Oct 2026", sightings: 6, condition: .scarred, firstRecorded: "08 May 2026", isFavorite: false, coordinate: TurtleCoordinate(latitude: -5.318, longitude: 123.595), backendID: UUID(uuidString: "00000000-0000-4000-8100-000000000013"), leftPhotoURL: "Ghost1_L.jpg", rightPhotoURL: "Amina2_R.jpg", name: "Hoga", profileCode: "IDN-WK-13"),
        Turtle(id: "ASIA-MY-014", species: .green, location: "Sipadan, Sabah, Malaysia", lastSeen: "11 Nov 2026", sightings: 16, condition: .healthy, firstRecorded: "02 Dec 2025", isFavorite: true, coordinate: TurtleCoordinate(latitude: 4.115, longitude: 118.628), backendID: UUID(uuidString: "00000000-0000-4000-8100-000000000014"), leftPhotoURL: "Aikane2_L.jpg", rightPhotoURL: "Zizo1_R.jpg", name: "Sipadan", profileCode: "MYS-SB-14"),
        Turtle(id: "ASIA-MY-015", species: .hawksbill, location: "Pulau Redang, Malaysia", lastSeen: "23 Oct 2026", sightings: 7, condition: .injured, firstRecorded: "27 Apr 2026", isFavorite: false, coordinate: TurtleCoordinate(latitude: 5.775, longitude: 103.008), backendID: UUID(uuidString: "00000000-0000-4000-8100-000000000015"), leftPhotoURL: "Ghost2_L.jpg", rightPhotoURL: "Amina1_R.jpg", name: "Chagar", profileCode: "MYS-TR-15"),
        Turtle(id: "ASIA-TH-016", species: .green, location: "Similan Islands, Thailand", lastSeen: "04 Nov 2026", sightings: 8, condition: .healthy, firstRecorded: "16 Mar 2026", isFavorite: false, coordinate: TurtleCoordinate(latitude: 8.650, longitude: 97.641), backendID: UUID(uuidString: "00000000-0000-4000-8100-000000000016"), leftPhotoURL: "Hoku2_L.jpg", rightPhotoURL: "Zizo2_R.jpg", name: "Andaman", profileCode: "THA-SM-16"),
        Turtle(id: "ASIA-TH-017", species: .hawksbill, location: "Koh Tao, Thailand", lastSeen: "29 Oct 2026", sightings: 5, condition: .scarred, firstRecorded: "04 Jun 2026", isFavorite: false, coordinate: TurtleCoordinate(latitude: 10.072, longitude: 99.839), backendID: UUID(uuidString: "00000000-0000-4000-8100-000000000017"), leftPhotoURL: "Amina3_L.jpg", rightPhotoURL: nil, name: "Tao", profileCode: "THA-KT-17"),
        Turtle(id: "ASIA-PH-018", species: .green, location: "Apo Reef, Philippines", lastSeen: "08 Nov 2026", sightings: 10, condition: .healthy, firstRecorded: "13 Feb 2026", isFavorite: false, coordinate: TurtleCoordinate(latitude: 12.662, longitude: 120.415), backendID: UUID(uuidString: "00000000-0000-4000-8100-000000000018"), leftPhotoURL: "Aikane1_L.jpg", rightPhotoURL: "Amina2_R.jpg", name: "Apo", profileCode: "PHL-AP-18"),
        Turtle(id: "ASIA-PH-019", species: .hawksbill, location: "El Nido, Palawan, Philippines", lastSeen: "15 Oct 2026", sightings: 6, condition: .healthy, firstRecorded: "20 May 2026", isFavorite: false, coordinate: TurtleCoordinate(latitude: 11.195, longitude: 119.392), backendID: UUID(uuidString: "00000000-0000-4000-8100-000000000019"), leftPhotoURL: "Hoku1_L.jpg", rightPhotoURL: "Zizo1_R.jpg", name: "Bacuit", profileCode: "PHL-PL-19"),
        Turtle(id: "ASIA-VN-020", species: .green, location: "Con Dao Islands, Vietnam", lastSeen: "06 Nov 2026", sightings: 9, condition: .healthy, firstRecorded: "07 Mar 2026", isFavorite: false, coordinate: TurtleCoordinate(latitude: 8.685, longitude: 106.607), backendID: UUID(uuidString: "00000000-0000-4000-8100-000000000020"), leftPhotoURL: "Amina1_L.jpg", rightPhotoURL: "Zizo2_R.jpg", name: "Bay Canh", profileCode: "VNM-CD-20"),

        // East Asia
        Turtle(id: "ASIA-JP-021", species: .loggerhead, location: "Zamami, Okinawa, Japan", lastSeen: "13 Nov 2026", sightings: 11, condition: .healthy, firstRecorded: "10 Jan 2026", isFavorite: true, coordinate: TurtleCoordinate(latitude: 26.228, longitude: 127.303), backendID: UUID(uuidString: "00000000-0000-4000-8100-000000000021"), leftPhotoURL: nil, rightPhotoURL: "Zizo1_R.jpg", name: "Kerama", profileCode: "JPN-OK-21"),
        Turtle(id: "ASIA-JP-022", species: .green, location: "Chichijima, Ogasawara, Japan", lastSeen: "22 Oct 2026", sightings: 7, condition: .healthy, firstRecorded: "28 Apr 2026", isFavorite: false, coordinate: TurtleCoordinate(latitude: 27.095, longitude: 142.191), backendID: UUID(uuidString: "00000000-0000-4000-8100-000000000022"), leftPhotoURL: "Hoku2_L.jpg", rightPhotoURL: "Amina1_R.jpg", name: "Bonin", profileCode: "JPN-OG-22"),
        Turtle(id: "ASIA-TW-023", species: .green, location: "Liuqiu Island, Taiwan", lastSeen: "30 Oct 2026", sightings: 8, condition: .injured, firstRecorded: "18 Feb 2026", isFavorite: false, coordinate: TurtleCoordinate(latitude: 22.342, longitude: 120.369), backendID: UUID(uuidString: "00000000-0000-4000-8100-000000000023"), leftPhotoURL: "Ghost1_L.jpg", rightPhotoURL: "Amina2_R.jpg", name: "Xiaoqiu", profileCode: "TWN-LQ-23"),
        Turtle(id: "ASIA-TW-024", species: .oliveRidley, location: "Penghu Channel, Taiwan", lastSeen: "18 Sep 2026", sightings: 4, condition: .healthy, firstRecorded: "11 Jun 2026", isFavorite: false, coordinate: TurtleCoordinate(latitude: 23.568, longitude: 119.566), backendID: UUID(uuidString: "00000000-0000-4000-8100-000000000024"), leftPhotoURL: "Amina2_L.jpg", rightPhotoURL: "Zizo2_R.jpg", name: "Penghu", profileCode: "TWN-PH-24"),
    ]

    static let superAsiaSightings: [Sighting] = {
        var result: [Sighting] = []
        let migrationHops: [String: (location: String, date: String, lat: Double, lon: Double)] = [
            "ASIA-IN-001": ("Rushikulya Offshore, India", "19 Sep 2026", 19.42, 85.15),
            "ASIA-IN-003": ("Neil Island, Andaman, India", "12 Aug 2026", 11.83, 93.04),
            "ASIA-IN-005": ("Bangaram Atoll, Lakshadweep", "24 Aug 2026", 10.94, 72.29),
            "ASIA-ID-009": ("Crystal Bay, Nusa Penida", "14 Aug 2026", -8.714, 115.458),
            "ASIA-ID-010": ("Sanur Reef, Bali, Indonesia", "29 Jul 2026", -8.687, 115.262),
            "ASIA-ID-012": ("Sangalaki Island, Indonesia", "10 Jul 2026", 2.092, 118.401),
            "ASIA-MY-014": ("Mabul Reef, Sabah, Malaysia", "03 Sep 2026", 4.245, 118.631),
            "ASIA-PH-018": ("Coron Passage, Philippines", "21 Aug 2026", 11.98, 120.20),
            "ASIA-JP-021": ("Aka Island, Okinawa, Japan", "07 Jul 2026", 26.198, 127.281),
            "ASIA-LK-007": ("Trincomalee Reef, Sri Lanka", "16 Jun 2026", 8.587, 81.215),
        ]
        for (index, turtle) in superAsiaTurtles.enumerated() {
            let coord = turtle.coordinate ?? TurtleCoordinate(latitude: 5.0, longitude: 105.0)
            result.append(
                Sighting(
                    name: turtle.displayName,
                    id: "asia-s-cur-\(index + 1)",
                    turtleID: turtle.id,
                    species: turtle.species,
                    location: turtle.location,
                    date: turtle.lastSeen,
                    condition: turtle.condition,
                    coordinate: coord
                )
            )
            if let hop = migrationHops[turtle.id] {
                result.append(
                    Sighting(
                        name: turtle.displayName,
                        id: "asia-s-mid-\(index + 1)",
                        turtleID: turtle.id,
                        species: turtle.species,
                        location: hop.location,
                        date: hop.date,
                        condition: turtle.condition,
                        coordinate: TurtleCoordinate(latitude: hop.lat, longitude: hop.lon)
                    )
                )
            }
            if turtle.sightings > 4 {
                result.append(
                    Sighting(
                        name: turtle.displayName,
                        id: "asia-s-first-\(index + 1)",
                        turtleID: turtle.id,
                        species: turtle.species,
                        location: turtle.location,
                        date: turtle.firstRecorded,
                        condition: turtle.condition,
                        coordinate: TurtleCoordinate(latitude: coord.latitude + 0.04, longitude: coord.longitude - 0.04)
                    )
                )
            }
        }
        return result
    }()

    // MARK: - World-Level Global Sea Turtle Super Account (~360 Turtles, ~1,700+ Sightings Worldwide)

    struct WorldHabitatSeed {
        let code: String
        let site: String
        let lat: Double
        let lon: Double
        let turtleCount: Int
        let spreadDeg: Double
        let primarySpecies: TurtleSpecies
        let secondarySpecies: TurtleSpecies
        let migrationDeltaLat: Double
        let migrationDeltaLon: Double
    }

    static let worldSuperDataset: (turtles: [Turtle], sightings: [Sighting]) = {
        let habitats: [WorldHabitatSeed] = [
            // Indonesia & Coral Triangle (high-density multi-island showcase for H3 Res 4–6)
            .init(code: "ID-BL", site: "Sanur & Nusa Penida Reef", lat: -8.715, lon: 115.320, turtleCount: 22, spreadDeg: 0.24, primarySpecies: .hawksbill, secondarySpecies: .green, migrationDeltaLat: -0.09, migrationDeltaLon: 0.22),
            .init(code: "ID-KM", site: "Komodo & Flores Channel", lat: -8.540, lon: 119.560, turtleCount: 14, spreadDeg: 0.35, primarySpecies: .green, secondarySpecies: .hawksbill, migrationDeltaLat: 0.14, migrationDeltaLon: -0.25),
            .init(code: "ID-RA", site: "Misool & Wayag, Raja Ampat", lat: -1.120, lon: 130.380, turtleCount: 18, spreadDeg: 0.72, primarySpecies: .leatherback, secondarySpecies: .hawksbill, migrationDeltaLat: -0.45, migrationDeltaLon: 0.35),
            .init(code: "ID-DR", site: "Derawan & Sangalaki Atoll", lat: 2.240, lon: 118.320, turtleCount: 16, spreadDeg: 0.32, primarySpecies: .green, secondarySpecies: .hawksbill, migrationDeltaLat: -0.18, migrationDeltaLon: 0.20),
            .init(code: "ID-BN", site: "Bunaken Marine Wall", lat: 1.620, lon: 124.760, turtleCount: 11, spreadDeg: 0.26, primarySpecies: .green, secondarySpecies: .oliveRidley, migrationDeltaLat: 0.12, migrationDeltaLon: 0.18),
            .init(code: "ID-WK", site: "Wakatobi Coral Atolls", lat: -5.330, lon: 123.620, turtleCount: 12, spreadDeg: 0.42, primarySpecies: .hawksbill, secondarySpecies: .green, migrationDeltaLat: -0.22, migrationDeltaLon: 0.28),
            .init(code: "ID-JV", site: "Pangumbahan Nesting Beach", lat: -7.320, lon: 106.400, turtleCount: 9, spreadDeg: 0.28, primarySpecies: .green, secondarySpecies: .oliveRidley, migrationDeltaLat: -0.15, migrationDeltaLon: -0.18),
            .init(code: "ID-MT", site: "Mentawai Outer Reefs", lat: -2.080, lon: 99.650, turtleCount: 8, spreadDeg: 0.45, primarySpecies: .leatherback, secondarySpecies: .hawksbill, migrationDeltaLat: -0.35, migrationDeltaLon: 0.25),

            // Southeast Asia
            .init(code: "MY-SP", site: "Sipadan & Mabul Reef", lat: 4.160, lon: 118.630, turtleCount: 14, spreadDeg: 0.28, primarySpecies: .green, secondarySpecies: .hawksbill, migrationDeltaLat: 0.16, migrationDeltaLon: -0.14),
            .init(code: "MY-RD", site: "Pulau Redang Sanctuary", lat: 5.780, lon: 103.010, turtleCount: 9, spreadDeg: 0.25, primarySpecies: .green, secondarySpecies: .hawksbill, migrationDeltaLat: -0.14, migrationDeltaLon: 0.16),
            .init(code: "PH-AP", site: "Apo Reef & Palawan", lat: 12.150, lon: 120.220, turtleCount: 13, spreadDeg: 0.65, primarySpecies: .green, secondarySpecies: .hawksbill, migrationDeltaLat: -0.45, migrationDeltaLon: -0.35),
            .init(code: "PH-TB", site: "Tubbataha Sulu Atoll", lat: 8.850, lon: 119.900, turtleCount: 10, spreadDeg: 0.30, primarySpecies: .hawksbill, secondarySpecies: .green, migrationDeltaLat: 0.25, migrationDeltaLon: 0.30),
            .init(code: "TH-SM", site: "Similan & Surin Reefs", lat: 8.750, lon: 97.680, turtleCount: 10, spreadDeg: 0.40, primarySpecies: .green, secondarySpecies: .oliveRidley, migrationDeltaLat: 0.32, migrationDeltaLon: 0.15),
            .init(code: "VN-CD", site: "Con Dao Bay Canh", lat: 8.690, lon: 106.640, turtleCount: 9, spreadDeg: 0.26, primarySpecies: .green, secondarySpecies: .hawksbill, migrationDeltaLat: 0.12, migrationDeltaLon: 0.14),
            .init(code: "PW-RK", site: "Palau Barrier Drop-off", lat: 7.340, lon: 134.460, turtleCount: 8, spreadDeg: 0.30, primarySpecies: .hawksbill, secondarySpecies: .green, migrationDeltaLat: -0.18, migrationDeltaLon: -0.15),

            // South Asia & Indian Ocean
            .init(code: "IN-OD", site: "Gahirmatha & Rushikulya Coast", lat: 20.150, lon: 86.250, turtleCount: 15, spreadDeg: 0.70, primarySpecies: .oliveRidley, secondarySpecies: .green, migrationDeltaLat: -0.60, migrationDeltaLon: -0.45),
            .init(code: "IN-AN", site: "Havelock & Little Andaman", lat: 11.450, lon: 92.820, turtleCount: 11, spreadDeg: 0.55, primarySpecies: .leatherback, secondarySpecies: .green, migrationDeltaLat: -0.40, migrationDeltaLon: 0.20),
            .init(code: "IN-LK", site: "Agatti Lagoon, Lakshadweep", lat: 10.820, lon: 72.350, turtleCount: 10, spreadDeg: 0.45, primarySpecies: .green, secondarySpecies: .hawksbill, migrationDeltaLat: 0.22, migrationDeltaLon: 0.25),
            .init(code: "LK-RK", site: "Rekawa & Hikkaduwa Coast", lat: 6.120, lon: 80.520, turtleCount: 9, spreadDeg: 0.38, primarySpecies: .loggerhead, secondarySpecies: .oliveRidley, migrationDeltaLat: 0.25, migrationDeltaLon: 0.45),
            .init(code: "MV-BA", site: "Baa & Lhaviyani Atolls", lat: 5.260, lon: 73.180, turtleCount: 12, spreadDeg: 0.55, primarySpecies: .hawksbill, secondarySpecies: .green, migrationDeltaLat: -0.35, migrationDeltaLon: 0.15),
            .init(code: "OM-RJ", site: "Ras Al Jinz Reserve", lat: 22.420, lon: 59.830, turtleCount: 10, spreadDeg: 0.32, primarySpecies: .green, secondarySpecies: .loggerhead, migrationDeltaLat: -0.30, migrationDeltaLon: -0.20),
            .init(code: "SC-AL", site: "Aldabra & Mahé Reefs", lat: -4.680, lon: 55.460, turtleCount: 9, spreadDeg: 0.42, primarySpecies: .hawksbill, secondarySpecies: .green, migrationDeltaLat: -0.25, migrationDeltaLon: 0.20),
            .init(code: "TZ-ZN", site: "Zanzibar & Mafia Channel", lat: -6.850, lon: 39.650, turtleCount: 10, spreadDeg: 0.65, primarySpecies: .green, secondarySpecies: .hawksbill, migrationDeltaLat: -0.45, migrationDeltaLon: 0.18),
            .init(code: "MG-NB", site: "Nosy Be Coral Banks", lat: -13.340, lon: 48.260, turtleCount: 8, spreadDeg: 0.35, primarySpecies: .hawksbill, secondarySpecies: .green, migrationDeltaLat: -0.25, migrationDeltaLon: -0.20),

            // East Asia & Oceania
            .init(code: "JP-OK", site: "Kerama & Zamami Reefs", lat: 26.220, lon: 127.300, turtleCount: 11, spreadDeg: 0.35, primarySpecies: .loggerhead, secondarySpecies: .green, migrationDeltaLat: 0.24, migrationDeltaLon: 0.32),
            .init(code: "JP-OG", site: "Chichijima, Ogasawara", lat: 27.090, lon: 142.190, turtleCount: 7, spreadDeg: 0.25, primarySpecies: .green, secondarySpecies: .loggerhead, migrationDeltaLat: -0.18, migrationDeltaLon: 0.14),
            .init(code: "TW-LQ", site: "Xiaoliuqiu Coral Shelf", lat: 22.340, lon: 120.370, turtleCount: 8, spreadDeg: 0.22, primarySpecies: .green, secondarySpecies: .hawksbill, migrationDeltaLat: 0.20, migrationDeltaLon: -0.18),
            .init(code: "AU-GB", site: "Heron & Lady Elliot Reef", lat: -23.620, lon: 152.120, turtleCount: 15, spreadDeg: 0.55, primarySpecies: .green, secondarySpecies: .loggerhead, migrationDeltaLat: -0.45, migrationDeltaLon: 0.30),
            .init(code: "AU-NG", site: "Ningaloo Marine Park", lat: -22.240, lon: 113.820, turtleCount: 11, spreadDeg: 0.45, primarySpecies: .loggerhead, secondarySpecies: .green, migrationDeltaLat: -0.35, migrationDeltaLon: -0.18),
            .init(code: "US-HI", site: "Maui & Oahu Reefs", lat: 20.880, lon: -156.680, turtleCount: 11, spreadDeg: 0.50, primarySpecies: .green, secondarySpecies: .hawksbill, migrationDeltaLat: 0.35, migrationDeltaLon: -0.45),

            // Americas & Caribbean
            .init(code: "CR-TG", site: "Tortuguero & Cahuita Coast", lat: 10.540, lon: -83.480, turtleCount: 15, spreadDeg: 0.45, primarySpecies: .green, secondarySpecies: .leatherback, migrationDeltaLat: -0.32, migrationDeltaLon: 0.25),
            .init(code: "EC-GL", site: "Isabela & Santa Cruz, Galápagos", lat: -0.680, lon: -90.620, turtleCount: 14, spreadDeg: 0.65, primarySpecies: .green, secondarySpecies: .hawksbill, migrationDeltaLat: 0.28, migrationDeltaLon: -0.35),
            .init(code: "MX-AK", site: "Akumal & Cozumel Reef", lat: 20.420, lon: -87.180, turtleCount: 13, spreadDeg: 0.40, primarySpecies: .loggerhead, secondarySpecies: .green, migrationDeltaLat: 0.30, migrationDeltaLon: 0.22),
            .init(code: "MX-BJ", site: "Magdalena Bay, Baja", lat: 24.680, lon: -112.150, turtleCount: 10, spreadDeg: 0.55, primarySpecies: .loggerhead, secondarySpecies: .oliveRidley, migrationDeltaLat: -0.40, migrationDeltaLon: 0.20),
            .init(code: "US-FL", site: "Florida Keys & Dry Tortugas", lat: 24.650, lon: -81.420, turtleCount: 14, spreadDeg: 0.60, primarySpecies: .loggerhead, secondarySpecies: .green, migrationDeltaLat: 0.45, migrationDeltaLon: 0.38),
            .init(code: "BQ-BN", site: "Bonaire & Klein Reef", lat: 12.160, lon: -68.290, turtleCount: 10, spreadDeg: 0.28, primarySpecies: .hawksbill, secondarySpecies: .green, migrationDeltaLat: 0.14, migrationDeltaLon: -0.18),
            .init(code: "BR-FN", site: "Fernando de Noronha", lat: -3.850, lon: -32.420, turtleCount: 11, spreadDeg: 0.30, primarySpecies: .hawksbill, secondarySpecies: .green, migrationDeltaLat: -0.25, migrationDeltaLon: -0.30),

            // East Atlantic & Mediterranean
            .init(code: "CV-BV", site: "Boa Vista & Sal Reefs", lat: 16.120, lon: -22.840, turtleCount: 11, spreadDeg: 0.42, primarySpecies: .loggerhead, secondarySpecies: .green, migrationDeltaLat: 0.30, migrationDeltaLon: -0.22),
            .init(code: "GR-ZK", site: "Laganas Bay, Zakynthos", lat: 37.720, lon: 20.900, turtleCount: 10, spreadDeg: 0.30, primarySpecies: .loggerhead, secondarySpecies: .green, migrationDeltaLat: -0.18, migrationDeltaLon: 0.22),
            .init(code: "TR-DL", site: "Dalyan & Iztuzu Shore", lat: 36.790, lon: 28.610, turtleCount: 9, spreadDeg: 0.28, primarySpecies: .loggerhead, secondarySpecies: .green, migrationDeltaLat: -0.16, migrationDeltaLon: 0.24),
        ]

        let turtleNames = [
            "Amina", "Chewie", "Kaveri", "Sipadan", "Kerama", "Derawan", "Misool", "Surya",
            "Aikane", "Hoku", "Moana", "Nalu", "Koa", "Zizo", "Kai", "Lani",
            "Coral", "Taro", "Raja", "Sagara", "Bintang", "Nusa", "Koral", "Tirta",
            "Marina", "Vela", "Solis", "Nereus", "Calypso", "Tethys", "Pelagia", "Onda",
            "Paz", "Brisa", "Cielo", "Lumi", "Sora", "Umi", "Kala", "Malia"
        ]
        let leftPhotos = ["Amina1_L.jpg", "Aikane1_L.jpg", "Ghost1_L.jpg", "Hoku1_L.jpg", "Amina2_L.jpg", "Ghost2_L.jpg", "Hoku2_L.jpg", "Amina3_L.jpg"]
        let rightPhotos = ["Amina1_R.jpg", "Zizo1_R.jpg", "Amina2_R.jpg", "Zizo2_R.jpg"]
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov"]

        // Deterministic seeded generator (Knuth LCG) for reproducible global coordinates & counts
        var rng: UInt64 = 2026_0518_42
        func nextUnit() -> Double {
            rng = rng &* 6364136223846793005 &+ 1442695040888963407
            return Double((rng >> 33) & 0x7FFF_FFFF) / Double(0x7FFF_FFFF)
        }
        func nextSigned() -> Double { (nextUnit() * 2.0) - 1.0 }

        var turtles: [Turtle] = []
        var sightings: [Sighting] = []
        var globalSeq = 0

        for habitat in habitats {
            for localIdx in 0..<habitat.turtleCount {
                globalSeq += 1
                let id = String(format: "WLD-%@-%03d", habitat.code, localIdx + 1)
                let baseName = turtleNames[(globalSeq - 1) % turtleNames.count]
                let displayName = "\(baseName) #\(globalSeq)"
                let species = (localIdx % 3 == 2) ? habitat.secondarySpecies : habitat.primarySpecies
                let conditionRoll = nextUnit()
                let condition: TurtleCondition = conditionRoll < 0.68 ? .healthy : (conditionRoll < 0.86 ? .scarred : (conditionRoll < 0.96 ? .injured : .unknown))

                let baseLat = max(-80.0, min(80.0, habitat.lat + nextSigned() * habitat.spreadDeg))
                let baseLon = habitat.lon + nextSigned() * habitat.spreadDeg

                let encounterCount = 3 + Int(nextUnit() * 4.0) // 3...6 sightings per turtle!
                let latestMonthIdx = min(months.count - 1, 7 + Int(nextUnit() * 4.0))
                let firstMonthIdx = max(0, latestMonthIdx - encounterCount)
                let latestDay = 1 + Int(nextUnit() * 27.0)
                let firstDay = 1 + Int(nextUnit() * 27.0)
                let lastSeen = String(format: "%02d %@ 2026", latestDay, months[latestMonthIdx])
                let firstRecorded = String(format: "%02d %@ 2026", firstDay, months[firstMonthIdx])

                let backendUUID = UUID(uuidString: String(format: "00000000-0000-4000-8200-%012d", globalSeq))
                let turtle = Turtle(
                    id: id,
                    species: species,
                    location: habitat.site,
                    lastSeen: lastSeen,
                    sightings: encounterCount,
                    condition: condition,
                    firstRecorded: firstRecorded,
                    isFavorite: globalSeq <= 8,
                    coordinate: TurtleCoordinate(latitude: baseLat, longitude: baseLon),
                    backendID: backendUUID,
                    leftPhotoURL: leftPhotos[globalSeq % leftPhotos.count],
                    rightPhotoURL: rightPhotos[globalSeq % rightPhotos.count],
                    name: displayName,
                    profileCode: String(format: "%@-%03d", habitat.code, localIdx + 1)
                )
                turtles.append(turtle)

                for hop in 0..<encounterCount {
                    let progress = Double(hop) / Double(max(encounterCount - 1, 1))
                    let hopLat = baseLat + habitat.migrationDeltaLat * progress + nextSigned() * 0.06
                    let hopLon = baseLon + habitat.migrationDeltaLon * progress + nextSigned() * 0.06
                    let monthIdx = min(months.count - 1, max(0, latestMonthIdx - hop))
                    let day = 1 + Int(nextUnit() * 27.0)
                    let dateStr = hop == 0 ? lastSeen : (hop == encounterCount - 1 ? firstRecorded : String(format: "%02d %@ 2026", day, months[monthIdx]))
                    sightings.append(
                        Sighting(
                            name: displayName,
                            id: "wld-s-\(globalSeq)-\(hop)",
                            turtleID: id,
                            species: species,
                            location: habitat.site,
                            date: dateStr,
                            condition: condition,
                            coordinate: TurtleCoordinate(latitude: hopLat, longitude: hopLon)
                        )
                    )
                }
            }
        }

        return (turtles, sightings)
    }()
}

// MARK: - Pending Mobile Sighting Sync DTOs (v2 primary + v1 fallback)

private struct V2PendingLogDTO: Decodable {
    let id: UUID
    let turtleID: UUID?
    let observedAt: Date
    let location: V2Location
    let notes: String?
    let photos: [V2LogPhoto]

    enum CodingKeys: String, CodingKey {
        case id, location, notes, photos
        case turtleID = "turtle_id"
        case observedAt = "observed_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        turtleID = try c.decodeIfPresent(UUID.self, forKey: .turtleID)
        observedAt = try c.decode(Date.self, forKey: .observedAt)
        location = try c.decode(V2Location.self, forKey: .location)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        photos = try c.decodeIfPresent([V2LogPhoto].self, forKey: .photos) ?? []
    }
}

private struct V1LogListDTO: Decodable {
    let items: [V1PendingLogDTO]
    let total: Int
    let limit: Int
    let offset: Int
}

private struct V1LogPhotoDTO: Decodable {
    let id: UUID
    let url: String
    let downloadURL: String?
    let markingID: UUID?

    enum CodingKeys: String, CodingKey {
        case id, url
        case downloadURL = "download_url"
        case markingID = "marking_id"
    }

    var fetchPath: String {
        if let downloadURL {
            let trimmed = downloadURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return url.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct V1PendingLogDTO: Decodable {
    let id: UUID
    let turtleID: UUID?
    let timestamp: Date
    let placeName: String
    let notes: String?
    let photos: [V1LogPhotoDTO]

    enum CodingKeys: String, CodingKey {
        case id, timestamp, notes, photos
        case turtleID = "turtle_id"
        case placeName = "place_name"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        turtleID = try c.decodeIfPresent(UUID.self, forKey: .turtleID)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        placeName = try c.decode(String.self, forKey: .placeName)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        photos = try c.decodeIfPresent([V1LogPhotoDTO].self, forKey: .photos) ?? []
    }
}

private struct V2ResolveLogPatch: Encodable {
    struct Identification: Encodable {
        let method: String
        let confidence: Double?
    }
    let turtleID: UUID
    let identification: Identification
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case identification, notes
        case turtleID = "turtle_id"
    }
}

private struct V1ResolveLogPatch: Encodable {
    let turtleID: UUID
    let identificationMethod: String
    let matchConfidence: Double?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case notes
        case turtleID = "turtle_id"
        case identificationMethod = "identification_method"
        case matchConfidence = "match_confidence"
    }
}

