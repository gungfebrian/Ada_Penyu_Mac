import Foundation

enum DataMode: String, CaseIterable, Identifiable {
    case demo
    case live

    var id: String { rawValue }

    var title: String {
        switch self {
        case .demo: "Demo mode"
        case .live: "Live API"
        }
    }
}

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

    init(
        id: String,
        date: String,
        location: String,
        status: String,
        condition: TurtleCondition?,
        notes: String?,
        coordinate: TurtleCoordinate?,
        bodyPart: TurtleBodyPart? = nil
    ) {
        self.id = id
        self.date = date
        self.location = location
        self.status = status
        self.condition = condition
        self.notes = notes
        self.coordinate = coordinate
        self.bodyPart = bodyPart
    }
}

struct TurtleDetailData {
    let turtle: Turtle
    let measurements: [TurtleMeasurement]
    let logs: [TurtleLogSummary]
}

protocol TurtleRepository: AnyObject {
    func listIndividuals(query: IndividualQuery) async throws -> Page<Turtle>
    func listFavorites() async throws -> [Turtle]
    func setFavorite(turtleID: String, isFavorite: Bool) async throws -> Bool
    func dashboard(query: DashboardQuery) async throws -> DashboardSnapshot
    func mapSightings(query: MapQuery) async throws -> [Sighting]
    func detail(for turtle: Turtle) async throws -> TurtleDetailData
    func export(_ request: ExportRequest) async throws -> DownloadedFile
}

enum APIError: LocalizedError {
    case invalidResponse
    case http(status: Int, message: String)
    case invalidURL
    case invalidFileName

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "The API returned an invalid response."
        case let .http(status, message): "API error \(status): \(message)"
        case .invalidURL: "The API URL is invalid."
        case .invalidFileName: "The downloaded file name is invalid."
        }
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
        default: self = .green
        }
    }
}

extension TurtleCondition {
    var apiValue: String {
        switch self {
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

final class APIClient {
    let baseURL: URL
    private let session: URLSession
    private let userID: String

    init(
        baseURL: URL = URL(string: UserDefaults.standard.string(forKey: "ada.apiBaseURL") ?? "http://127.0.0.1:8010")!,
        session: URLSession = .shared,
        userID: String = UserDefaults.standard.string(forKey: "ada.userID") ?? "00000000-0000-4000-8000-000000000001"
    ) {
        self.baseURL = baseURL
        self.session = session
        self.userID = userID
        UserDefaults.standard.set(userID, forKey: "ada.userID")
    }

    func get<T: Decodable>(_ path: String, queryItems: [URLQueryItem] = []) async throws -> T {
        try await request(path: path, method: "GET", queryItems: queryItems)
    }

    func getData(_ path: String, queryItems: [URLQueryItem] = []) async throws -> (Data, HTTPURLResponse) {
        try await requestData(path: path, method: "GET", queryItems: queryItems)
    }

    func request<T: Decodable>(path: String, method: String, queryItems: [URLQueryItem] = [], body: Data? = nil) async throws -> T {
        let (data, _) = try await requestData(path: path, method: method, queryItems: queryItems, body: body)
        do {
            return try JSONDecoder.api.decode(T.self, from: data)
        } catch {
            throw APIError.invalidResponse
        }
    }

    func requestData(path: String, method: String, queryItems: [URLQueryItem] = [], body: Data? = nil) async throws -> (Data, HTTPURLResponse) {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userID, forHTTPHeaderField: "X-User-Id")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Request failed"
            throw APIError.http(status: http.statusCode, message: message)
        }
        return (data, http)
    }
}

private extension JSONDecoder {
    static let api: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

private extension JSONEncoder {
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

private struct LogPageDTO: Decodable {
    let items: [LogDTO]
}

private struct LogDTO: Decodable {
    let id: UUID
    let timestamp: Date
    let placeName: String
    let statusKind: String
    let bodyCondition: String?
    let notes: String?
    let latitude: Double?
    let longitude: Double?
    let curvedCarapaceLength: Double?
    let curvedCarapaceWidth: Double?
    let weight: Double?

    enum CodingKeys: String, CodingKey {
        case id, timestamp
        case placeName = "place_name"
        case statusKind = "status_kind"
        case bodyCondition = "body_condition"
        case notes, latitude, longitude
        case curvedCarapaceLength = "curved_carapace_length"
        case curvedCarapaceWidth = "curved_carapace_width"
        case weight
    }
}

private extension IndividualDTO {
    func turtle() -> Turtle {
        return Turtle(
            id: name.isEmpty ? profileCode : name,
            species: TurtleSpecies(apiValue: species),
            location: lastSeenLocation ?? "Location not recorded",
            lastSeen: lastSeenDate.map(APIFormatters.display.string(from:)) ?? "Not recorded",
            sightings: totalSightings,
            condition: TurtleCondition(apiValue: currentHealthStatus) ?? .healthy,
            firstRecorded: APIFormatters.display.string(from: firstSeenDate),
            isFavorite: false,
            coordinate: nil,
            backendID: id
        )
    }
}

final class RemoteTurtleRepository: TurtleRepository {
    private let client: APIClient
    private var cache: [String: Turtle] = [:]

    init(client: APIClient = APIClient()) { self.client = client }

    func listIndividuals(query: IndividualQuery) async throws -> Page<Turtle> {
        let dto: IndividualPageDTO = try await client.get("api/v1/individuals", queryItems: query.queryItems)
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
        guard let turtle = cache[turtleID], let backendID = turtle.backendID else { return isFavorite }
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
            let condition = TurtleCondition(apiValue: item.condition) ?? .healthy
            let turtleID = item.name ?? "Unidentified turtle"
            return Sighting(id: item.logID.uuidString, turtleID: turtleID, species: TurtleSpecies(apiValue: species), location: item.placeName, date: APIFormatters.display.string(from: item.timestamp), condition: condition, coordinate: TurtleCoordinate(latitude: item.latitude, longitude: item.longitude))
        }
    }

    func detail(for turtle: Turtle) async throws -> TurtleDetailData {
        guard let backendID = turtle.backendID else { return TurtleDetailData(turtle: turtle, measurements: [], logs: []) }
        let logs: LogPageDTO = try await client.get("api/v1/individuals/\(backendID.uuidString)/logs", queryItems: [URLQueryItem(name: "limit", value: "200")])
        let measurements = logs.items.compactMap { log -> TurtleMeasurement? in
            guard log.curvedCarapaceLength != nil || log.curvedCarapaceWidth != nil || log.weight != nil else { return nil }
            return TurtleMeasurement(id: log.id.uuidString, date: APIFormatters.display.string(from: log.timestamp), length: log.curvedCarapaceLength, width: log.curvedCarapaceWidth, weight: log.weight)
        }
        let summaries = logs.items.map { log in
            TurtleLogSummary(id: log.id.uuidString, date: APIFormatters.display.string(from: log.timestamp), location: log.placeName, status: log.statusKind.replacingOccurrences(of: "_", with: " ").capitalized, condition: TurtleCondition(apiValue: log.bodyCondition), notes: log.notes, coordinate: log.latitude.flatMap { latitude in log.longitude.map { TurtleCoordinate(latitude: latitude, longitude: $0) } })
        }
        return TurtleDetailData(turtle: turtle, measurements: measurements, logs: summaries)
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

final class DemoTurtleRepository: TurtleRepository {
    private var turtles: [Turtle] = DemoFixtures.turtles
    private var sightings: [Sighting] = DemoFixtures.sightings
    private var favoriteIDs = Set(["Turtle #004", "Turtle #005"])

    func listIndividuals(query: IndividualQuery) async throws -> Page<Turtle> {
        var results = turtles.filter { turtle in
            let searchMatches = query.search.map { value in
                turtle.id.localizedCaseInsensitiveContains(value) || turtle.species.rawValue.localizedCaseInsensitiveContains(value) || turtle.location.localizedCaseInsensitiveContains(value)
            } ?? true
            let speciesMatches = query.species.isEmpty || query.species.contains(turtle.species)
            let conditionMatches = query.condition == nil || turtle.condition == query.condition
            return searchMatches && speciesMatches && conditionMatches
        }
        if query.sort == .lastSeenDescending {
            // Parse the display date so we don't fall back to lexicographic
            // ordering (which mis-orders "Aug" vs "Feb", etc.).
            let formatter = APIFormatters.display
            results.sort { lhs, rhs in
                let lhsDate = formatter.date(from: lhs.lastSeen) ?? .distantPast
                let rhsDate = formatter.date(from: rhs.lastSeen) ?? .distantPast
                return lhsDate > rhsDate
            }
        } else {
            results.sort { $0.id < $1.id }
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
        let monthKeys = (0..<12).compactMap { index -> String? in
            guard let date = calendar.date(byAdding: .month, value: -11 + index, to: Date()) else { return nil }
            return String(format: "%04d-%02d", calendar.component(.year, from: date), calendar.component(.month, from: date))
        }
        let scopedSightings = query.species.map { species in sightings.filter { $0.species == species } } ?? sightings
        let scopedTurtles = query.species.map { species in turtles.filter { $0.species == species } } ?? turtles
        let sightingCounts = Dictionary(grouping: scopedSightings, by: { monthKey(for: $0.date) })
            .mapValues(\.count)
        let newIndividualCounts = Dictionary(grouping: scopedTurtles, by: { monthKey(for: $0.firstRecorded) })
            .mapValues(\.count)
        let months = monthKeys.map { key in
            DashboardSnapshot.Month(
                month: key,
                sightings: sightingCounts[key] ?? 0,
                newIndividuals: newIndividualCounts[key] ?? 0
            )
        }
        let species = TurtleSpecies.allCases.map { species in
            SpeciesSummary(
                id: species.apiValue,
                species: species,
                individuals: turtles.filter { $0.species == species }.count,
                sightings: sightings.filter { $0.species == species }.count
            )
        }
        return DashboardSnapshot(months: months, species: species)
    }

    func mapSightings(query: MapQuery) async throws -> [Sighting] {
        sightings.filter { sighting in
            (query.species == nil || query.species == sighting.species) &&
            (query.condition == nil || query.condition == sighting.condition)
        }
    }

    func detail(for turtle: Turtle) async throws -> TurtleDetailData {
        let sightingLogs = sightings.filter { $0.turtleID == turtle.id }.map {
            TurtleLogSummary(id: $0.id, date: $0.date, location: $0.location, status: "Sighting", condition: $0.condition, notes: "Foraging near reef edge", coordinate: $0.coordinate)
        }
        let bodyConditionLogs = Self.demoBodyConditionLogs(for: turtle)
        let measurements = [
            TurtleMeasurement(id: "measurement-\(turtle.id)", date: turtle.lastSeen, length: 84.2, width: 68.4, weight: 31.6)
        ]
        return TurtleDetailData(turtle: withFavorite(turtle), measurements: measurements, logs: sightingLogs + bodyConditionLogs)
    }

    /// Synthesises body-condition records for the demo profile view so the
    /// Body Condition tab has something to render. Real body_part data will
    /// come from the API once that field lands server-side.
    private static func demoBodyConditionLogs(for turtle: Turtle) -> [TurtleLogSummary] {
        switch turtle.condition {
        case .healthy:
            return []
        case .injured:
            return [
                TurtleLogSummary(
                    id: "bc-\(turtle.id)-head",
                    date: turtle.lastSeen,
                    location: turtle.location,
                    status: "Injury",
                    condition: .injured,
                    notes: "Crack on the head, likely a boat strike. Linear fracture above the right eye socket, 3 cm. Consistent with propeller or hull contact. Animal responsive, no bleeding at time of observation.",
                    coordinate: turtle.coordinate,
                    bodyPart: .head
                ),
                TurtleLogSummary(
                    id: "bc-\(turtle.id)-shell-1",
                    date: "14 Jun 2026",
                    location: turtle.location,
                    status: "Injury",
                    condition: .injured,
                    notes: "Crack on the shell, likely a boat strike.",
                    coordinate: turtle.coordinate,
                    bodyPart: .carapace
                ),
                TurtleLogSummary(
                    id: "bc-\(turtle.id)-flipper",
                    date: "02 Jun 2026",
                    location: turtle.location,
                    status: "Scar",
                    condition: .scarred,
                    notes: "Faint healed scar along the left front flipper.",
                    coordinate: turtle.coordinate,
                    bodyPart: .flipperLeft
                ),
            ]
        case .scarred:
            return [
                TurtleLogSummary(
                    id: "bc-\(turtle.id)-shell",
                    date: turtle.firstRecorded,
                    location: turtle.location,
                    status: "Scar",
                    condition: .scarred,
                    notes: "Old healed abrasion across the carapace ridge.",
                    coordinate: turtle.coordinate,
                    bodyPart: .carapace
                ),
                TurtleLogSummary(
                    id: "bc-\(turtle.id)-tail",
                    date: turtle.firstRecorded,
                    location: turtle.location,
                    status: "Scar",
                    condition: .scarred,
                    notes: "Notch on the tail, fully healed.",
                    coordinate: turtle.coordinate,
                    bodyPart: .tail
                ),
            ]
        }
    }

    func export(_ request: ExportRequest) async throws -> DownloadedFile {
        let page = try await listIndividuals(query: request.query)
        let columns: [(header: String, value: (Turtle) -> String)] = [
            ("id", { $0.id }),
            ("species", { $0.species.rawValue }),
            ("location", { $0.location }),
            ("last_seen", { $0.lastSeen }),
            ("first_recorded", { $0.firstRecorded }),
            ("sightings", { String($0.sightings) }),
            ("condition", { $0.condition.rawValue }),
        ]
        let header = columns.map(\.header).joined(separator: ",")
        let rows = page.items.map { turtle in
            columns.map { Self.csvEscape($0.value(turtle)) }.joined(separator: ",")
        }
        let body = ([header] + rows).joined(separator: "\n") + "\n"
        return DownloadedFile(data: Data(body.utf8), filename: "turtle-individuals.csv", contentType: "text/csv")
    }

    /// Wraps values that contain commas, quotes, or newlines to keep the CSV
    /// well-formed. Non-conflicting values are returned untouched.
    private static func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }

    private func withFavorite(_ turtle: Turtle) -> Turtle {
        Turtle(id: turtle.id, species: turtle.species, location: turtle.location, lastSeen: turtle.lastSeen, sightings: turtle.sightings, condition: turtle.condition, firstRecorded: turtle.firstRecorded, isFavorite: favoriteIDs.contains(turtle.id), coordinate: turtle.coordinate, backendID: turtle.backendID)
    }

    private func monthKey(for displayDate: String) -> String {
        guard let date = APIFormatters.display.date(from: displayDate) else { return "unknown" }
        let components = Calendar.current.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }
}

enum DemoFixtures {
    static let turtles: [Turtle] = [
        Turtle(id: "Turtle #001", species: .hawksbill, location: "Kuta Beach", lastSeen: "17 Aug 2026", sightings: 5, condition: .injured, firstRecorded: "01 Mar 2026", isFavorite: false, coordinate: TurtleCoordinate(latitude: -8.7180, longitude: 115.1690), backendID: UUID(uuidString: "00000000-0000-4000-8000-000000000001")),
        Turtle(id: "Turtle #002", species: .green, location: "Nusa Dua reef", lastSeen: "12 Aug 2026", sightings: 8, condition: .healthy, firstRecorded: "12 Apr 2026", isFavorite: false, coordinate: TurtleCoordinate(latitude: -8.7960, longitude: 115.2280), backendID: UUID(uuidString: "00000000-0000-4000-8000-000000000002")),
        Turtle(id: "Turtle #003", species: .oliveRidley, location: "Serangan Island", lastSeen: "09 Aug 2026", sightings: 4, condition: .scarred, firstRecorded: "21 Apr 2026", isFavorite: false, coordinate: TurtleCoordinate(latitude: -8.7240, longitude: 115.2500), backendID: UUID(uuidString: "00000000-0000-4000-8000-000000000003")),
        Turtle(id: "Turtle #004", species: .green, location: "Sanur flats", lastSeen: "02 Aug 2026", sightings: 3, condition: .scarred, firstRecorded: "07 May 2026", isFavorite: true, coordinate: TurtleCoordinate(latitude: -8.6870, longitude: 115.2620), backendID: UUID(uuidString: "00000000-0000-4000-8000-000000000004")),
        Turtle(id: "Turtle #005", species: .leatherback, location: "Pantai Timur", lastSeen: "28 Jul 2026", sightings: 2, condition: .healthy, firstRecorded: "16 Jun 2026", isFavorite: true, coordinate: TurtleCoordinate(latitude: -8.7800, longitude: 115.2500), backendID: UUID(uuidString: "00000000-0000-4000-8000-000000000005")),
        Turtle(id: "Turtle #006", species: .loggerhead, location: "Jimbaran Bay", lastSeen: "24 Jul 2026", sightings: 6, condition: .healthy, firstRecorded: "18 Feb 2026", isFavorite: false, coordinate: TurtleCoordinate(latitude: -8.7850, longitude: 115.1580), backendID: UUID(uuidString: "00000000-0000-4000-8000-000000000006")),
        Turtle(id: "Turtle #007", species: .hawksbill, location: "Legian Beach", lastSeen: "19 Jul 2026", sightings: 7, condition: .injured, firstRecorded: "02 Jan 2026", isFavorite: false, coordinate: TurtleCoordinate(latitude: -8.7040, longitude: 115.1660), backendID: UUID(uuidString: "00000000-0000-4000-8000-000000000007")),
        Turtle(id: "Turtle #008", species: .green, location: "Tuban Beach", lastSeen: "12 Jul 2026", sightings: 9, condition: .healthy, firstRecorded: "11 Jan 2026", isFavorite: false, coordinate: TurtleCoordinate(latitude: -8.7360, longitude: 115.1670), backendID: UUID(uuidString: "00000000-0000-4000-8000-000000000008")),
    ]

    static let sightings: [Sighting] = turtles.enumerated().map { index, turtle in
        Sighting(id: "demo-sighting-\(index + 1)", turtleID: turtle.id, species: turtle.species, location: turtle.location, date: turtle.lastSeen, condition: turtle.condition, coordinate: turtle.coordinate ?? TurtleCoordinate(latitude: -8.72, longitude: 115.20))
    }

    static let speciesSummaries: [SpeciesSummary] = [
        SpeciesSummary(id: "olive-ridley", species: .oliveRidley, individuals: 2, sightings: 96),
        SpeciesSummary(id: "green", species: .green, individuals: 3, sightings: 84),
        SpeciesSummary(id: "loggerhead", species: .loggerhead, individuals: 1, sightings: 54),
        SpeciesSummary(id: "hawksbill", species: .hawksbill, individuals: 2, sightings: 42),
        SpeciesSummary(id: "leatherback", species: .leatherback, individuals: 1, sightings: 36),
    ]
}
