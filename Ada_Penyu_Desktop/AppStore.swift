import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppStore: ObservableObject {
    @Published var activeSection: AppSection = .dashboard
    @Published var searchText = "" {
        didSet { scheduleIndividualsReload() }
    }
    // Species and body condition are one sidebar filter, not two — picking
    // either clears the other so exactly one filter chip is ever active at
    // once, and the individuals list is always scoped by just that one thing.
    @Published var selectedSpecies: TurtleSpecies? {
        didSet {
            if selectedSpecies != nil, selectedCondition != nil { selectedCondition = nil }
            scheduleIndividualsReload()
        }
    }
    @Published var selectedCondition: TurtleCondition? {
        didSet {
            if selectedCondition != nil, selectedSpecies != nil { selectedSpecies = nil }
            scheduleIndividualsReload()
        }
    }
    @Published var selectedMapPeriod: MapPeriod = .thirtyDays
    @Published var mapSpecies: TurtleSpecies?
    @Published var mapCondition: TurtleCondition?
    @Published var sort: IndividualSort = .lastSeenDescending
    @Published var chartMode: ChartMode = .sightings
    @Published var chartSpecies: TurtleSpecies? {
        didSet { Task { await reloadDashboard() } }
    }
    @Published private(set) var turtles: [Turtle] = []
    @Published private(set) var favoriteTurtles: [Turtle] = []
    @Published private(set) var sightings: [Sighting] = []
    @Published private(set) var dashboard: DashboardSnapshot = DashboardSnapshot(months: [], species: [])
    @Published var selectedTurtle: Turtle?
    @Published private(set) var detailOrigin: AppSection = .individuals
    @Published private(set) var selectedDetail: TurtleDetailData?
    @Published private(set) var isDetailLoading = false
    @Published private(set) var detailError: String?
    @Published private(set) var totalIndividuals = 0
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?
    @Published var isAuthSheetPresented = false
    @Published private(set) var authEmail = ""
    @Published private(set) var accountName = "Researcher"
    @Published private(set) var accountOrganization = ""
    @Published private(set) var apiBaseURLString: String
    @Published private(set) var isAuthenticated = false
    @Published private(set) var isRestoring = false
    @Published private(set) var sessionGeneration = UUID()

    private var client: APIClient
    private var repository: TurtleRepository
    private let hasInjectedRepository: Bool
    private var hasBootstrapped = false
    private var searchTask: Task<Void, Never>?
    private var photoCache: [String: NSImage] = [:]
    private var canLoadRecords: Bool { isAuthenticated || hasInjectedRepository }

    init(repository: TurtleRepository? = nil, client: APIClient? = nil) {
        let client = client ?? APIClient()
        self.client = client
        self.apiBaseURLString = client.baseURL.absoluteString
        self.hasInjectedRepository = repository != nil
        self.repository = repository ?? RemoteTurtleRepository(client: client)
        observeSession()
        updateAccount()
    }

    private func observeSession() {
        client.authorization?.onContextChanged = { [weak self] _ in self?.updateAccount() }
        client.authorization?.onSessionEnded = { [weak self] message in
            self?.clearPrivateState()
            self?.updateAccount()
            self?.lastError = message
        }
        client.authorization?.onContextFailure = { [weak self] error in self?.lastError = error.localizedDescription }
    }

    private func updateAccount() {
        isAuthenticated = client.account != nil
        authEmail = client.account?.email ?? ""
        accountName = client.account?.displayName ?? "Researcher"
        accountOrganization = client.account?.organisationName ?? ""
    }

    private func clearPrivateState() {
        sessionGeneration = UUID()
        searchTask?.cancel()
        photoCache.removeAll()
        turtles = []
        favoriteTurtles = []
        sightings = []
        dashboard = DashboardSnapshot(months: [], species: [])
        totalIndividuals = 0
        dismissDetail()
        isLoading = false
        lastError = nil
        repository = RemoteTurtleRepository(client: client)
    }

    deinit { searchTask?.cancel() }

    func bootstrap() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        if !hasInjectedRepository, !isAuthenticated {
            isRestoring = true
            do { try await client.restoreSession(); updateAccount() }
            catch { lastError = error.localizedDescription }
            isRestoring = false
        }
        if canLoadRecords { await reloadAll() }
    }

    func reloadAll() async {
        guard canLoadRecords else { return }
        let generation = sessionGeneration
        isLoading = true
        lastError = nil
        do {
            async let individuals = repository.listIndividuals(query: currentIndividualQuery)
            async let favorites = repository.listFavorites()
            async let dashboard = repository.dashboard(query: currentDashboardQuery)
            async let sightings = repository.mapSightings(query: currentMapQuery)
            let (individualPage, favoriteItems, dashboardSnapshot, mapItems) = try await (individuals, favorites, dashboard, sightings)
            guard sessionGeneration == generation else { return }
            turtles = individualPage.items
            totalIndividuals = individualPage.total
            favoriteTurtles = favoriteItems
            self.dashboard = dashboardSnapshot
            self.sightings = mapItems
        } catch {
            guard sessionGeneration == generation else { return }
            if !(error is CancellationError) { lastError = error.localizedDescription }
        }
        isLoading = false
    }

    func reloadIndividuals() async {
        guard canLoadRecords else { return }
        let generation = sessionGeneration
        do {
            let page = try await repository.listIndividuals(query: currentIndividualQuery)
            guard sessionGeneration == generation else { return }
            turtles = page.items
            totalIndividuals = page.total
            let favorites = try await repository.listFavorites()
            guard sessionGeneration == generation else { return }
            favoriteTurtles = favorites
            lastError = nil
        } catch {
            if sessionGeneration == generation, !(error is CancellationError) { lastError = error.localizedDescription }
        }
    }

    func reloadMap() async {
        guard canLoadRecords else { return }
        let generation = sessionGeneration
        do {
            let values = try await repository.mapSightings(query: currentMapQuery)
            guard sessionGeneration == generation else { return }
            sightings = values
        } catch {
            if sessionGeneration == generation, !(error is CancellationError) { lastError = error.localizedDescription }
        }
    }

    func reloadDashboard() async {
        guard canLoadRecords else { return }
        let generation = sessionGeneration
        do {
            let value = try await repository.dashboard(query: currentDashboardQuery)
            guard sessionGeneration == generation else { return }
            dashboard = value
        } catch {
            if sessionGeneration == generation, !(error is CancellationError) { lastError = error.localizedDescription }
        }
    }

    func select(_ turtle: Turtle) {
        detailOrigin = activeSection
        selectedTurtle = turtle
        selectedDetail = nil
        detailError = nil
        isDetailLoading = true
        Task { await loadDetail(for: turtle) }
    }

    func dismissDetail() {
        selectedTurtle = nil
        selectedDetail = nil
        detailError = nil
        isDetailLoading = false
    }

    func loadDetail(for turtle: Turtle) async {
        guard canLoadRecords else { return }
        let generation = sessionGeneration
        do {
            let detail = try await repository.detail(for: turtle)
            guard sessionGeneration == generation, selectedTurtle?.id == turtle.id else { return }
            selectedDetail = detail
            detailError = nil
        } catch {
            guard sessionGeneration == generation, selectedTurtle?.id == turtle.id else { return }
            detailError = error.localizedDescription
        }
        if selectedTurtle?.id == turtle.id { isDetailLoading = false }
    }

    func toggleFavorite(_ turtle: Turtle) {
        guard canLoadRecords else { return }
        let generation = sessionGeneration
        let repository = repository
        let nextValue = !favoriteTurtles.contains(where: { $0.id == turtle.id })
        Task {
            guard sessionGeneration == generation else { return }
            do {
                _ = try await repository.setFavorite(turtleID: turtle.id, isFavorite: nextValue)
                let favorites = try await repository.listFavorites()
                guard sessionGeneration == generation else { return }
                favoriteTurtles = favorites
                turtles = turtles.map { value in
                    guard value.id == turtle.id else { return value }
                    return Turtle(
                        id: value.id,
                        species: value.species,
                        location: value.location,
                        lastSeen: value.lastSeen,
                        sightings: value.sightings,
                        condition: value.condition,
                        firstRecorded: value.firstRecorded,
                        isFavorite: nextValue,
                        coordinate: value.coordinate,
                        backendID: value.backendID,
                        leftPhotoURL: value.leftPhotoURL,
                        rightPhotoURL: value.rightPhotoURL,
                        name: value.name
                    )
                }
            } catch {
                if sessionGeneration == generation, !(error is CancellationError) { lastError = error.localizedDescription }
            }
        }
    }

    func export(_ request: ExportRequest) {
        guard canLoadRecords else { return }
        let generation = sessionGeneration
        let repository = repository
        Task {
            guard sessionGeneration == generation else { return }
            do {
                let file = try await repository.export(request)
                guard sessionGeneration == generation else { return }
                let panel = NSSavePanel()
                panel.nameFieldStringValue = file.filename
                panel.allowedContentTypes = [.data]
                guard panel.runModal() == .OK, let url = panel.url else { return }
                try file.data.write(to: url, options: .atomic)
            } catch {
                if sessionGeneration == generation, !(error is CancellationError) { lastError = error.localizedDescription }
            }
        }
    }

    func clearError() { lastError = nil }

    func signIn(email: String, password: String, rememberMe: Bool) async throws {
        clearPrivateState()
        isAuthenticated = false
        _ = try await client.login(email: email, password: password, rememberMe: rememberMe)
        updateAccount()
        clearPrivateState()
        await reloadAll()
    }

    func signOut() {
        client.logout()
        clearPrivateState()
        updateAccount()
    }

    #if DEBUG
    func changeBackend(_ raw: String?) throws {
        let url = try raw.map(APIConfig.validatedURL) ?? APIConfig.defaultURL
        client.logout()
        if raw == nil { BackendEndpointOverride.reset() }
        else { BackendEndpointOverride.save(url) }
        client = APIClient(baseURL: url)
        observeSession()
        apiBaseURLString = url.absoluteString
        clearPrivateState()
        updateAccount()
    }
    #endif

    func loadPhoto(for pathOrURL: String?) async -> NSImage? {
        guard canLoadRecords, let pathOrURL, !pathOrURL.isEmpty else { return nil }
        let generation = sessionGeneration
        if let cached = photoCache[pathOrURL] {
            return cached
        }
        do {
            let data = try await repository.fetchPhotoData(pathOrURL: pathOrURL)
            guard sessionGeneration == generation else { return nil }
            if let image = NSImage(data: data) {
                photoCache[pathOrURL] = image
                return image
            }
        } catch { return nil }
        return nil
    }

    func matchPhoto(imageData: Data, side: TurtlePhotoSide, limit: Int = 10) async throws -> MatchSearchOutcome {
        try await repository.matchPhoto(imageData: imageData, side: side, limit: limit)
    }

    func matchPhotoPair(leftData: Data, rightData: Data, limit: Int = 10) async throws -> MatchSearchOutcome {
        try await repository.matchPhotoPair(leftData: leftData, rightData: rightData, limit: limit)
    }

    func fetchOverlayAnnotations(
        imageData: Data,
        side: TurtlePhotoSide,
        candidateID: UUID,
        candidateSide: TurtlePhotoSide,
        maxThreads: Int = 35
    ) async throws -> [OverlayAnnotationItem] {
        try await repository.fetchOverlayAnnotations(
            imageData: imageData,
            side: side,
            candidateID: candidateID,
            candidateSide: candidateSide,
            maxThreads: maxThreads
        )
    }

    func fetchOverlayPNG(
        imageData: Data,
        side: TurtlePhotoSide,
        candidateID: UUID,
        candidateSide: TurtlePhotoSide,
        maxThreads: Int = 35
    ) async throws -> Data {
        try await repository.fetchOverlayPNG(
            imageData: imageData,
            side: side,
            candidateID: candidateID,
            candidateSide: candidateSide,
            maxThreads: maxThreads
        )
    }

    func confirmMatchAndAttachPhoto(individualID: UUID, side: TurtlePhotoSide, imageData: Data) async throws {
        let generation = sessionGeneration
        let repository = repository
        let url = try await repository.uploadIndividualPhoto(individualID: individualID, side: side, imageData: imageData)
        guard sessionGeneration == generation else { throw CancellationError() }
        photoCache.removeValue(forKey: url)
        await reloadAll()
    }

    func enrollNewIndividual(_ draft: IndividualDraft, leftPhoto: Data?, rightPhoto: Data?) async throws -> Turtle {
        let generation = sessionGeneration
        let repository = repository
        let created = try await repository.createIndividual(draft)
        guard sessionGeneration == generation else { throw CancellationError() }
        if let backendID = created.backendID {
            if let leftPhoto { _ = try await repository.uploadIndividualPhoto(individualID: backendID, side: .left, imageData: leftPhoto) }
            guard sessionGeneration == generation else { throw CancellationError() }
            if let rightPhoto { _ = try await repository.uploadIndividualPhoto(individualID: backendID, side: .right, imageData: rightPhoto) }
        }
        guard sessionGeneration == generation else { throw CancellationError() }
        await reloadAll()
        return created
    }

    var currentIndividualQuery: IndividualQuery {
        IndividualQuery(search: searchText, species: selectedSpecies.map { [$0] } ?? [], condition: selectedCondition, sort: sort)
    }

    var currentDashboardQuery: DashboardQuery {
        var query = DashboardQuery.lastTwelveMonths
        query.species = chartSpecies
        return query
    }

    var currentMapQuery: MapQuery {
        MapQuery(period: selectedMapPeriod, species: mapSpecies, condition: mapCondition, page: PageRequest(limit: 200))
    }

    private func scheduleIndividualsReload() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled, let self else { return }
            await self.reloadIndividuals()
        }
    }

}
