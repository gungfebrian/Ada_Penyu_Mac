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
    @Published var selectedMapPeriod: MapPeriod = .thirtyDays {
        didSet { scheduleMapReload() }
    }
    @Published var mapSpecies: TurtleSpecies? {
        didSet { scheduleMapReload() }
    }
    @Published var mapCondition: TurtleCondition? {
        didSet { scheduleMapReload() }
    }
    @Published var sort: IndividualSort = .lastSeenDescending {
        didSet { scheduleIndividualsReload() }
    }
    @Published var individualsPageSize = 10 {
        didSet { scheduleIndividualsReload() }
    }
    @Published private(set) var individualsOffset = 0
    @Published private(set) var isIndividualsLoading = false
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
    @Published private(set) var accountRoleLabel = "Conservation Lead"
    @Published private(set) var isDemoBypassActive = false
    @Published private(set) var demoPersona: DemoDashboardPersona = .demoResearcher
    @Published private(set) var dashboardLayout: DashboardAccountLayout = DashboardAccountLayout.makeDefault(
        for: DemoDashboardPersona.demoResearcher.accountStorageKey,
        preset: .generalOverview
    )
    @Published var isEditingDashboardWidgets = false
    @Published var isWidgetPickerPresented = false
    @Published var requestedReviewScenario: ReviewScenarioID = .rankOneJunctionMismatch
    @Published var requestedReviewLayoutMode: ScientistComparisonLayoutMode = .sideBySide
    @Published var reviewNavigationTrigger = UUID()
    @Published private(set) var apiBaseURLString: String
    @Published private(set) var isAuthenticated = false
    @Published private(set) var isRestoring = false
    @Published private(set) var sessionGeneration = UUID()

    private var client: APIClient
    private var repository: TurtleRepository
    private let dashboardLayoutStore: DashboardLayoutStore
    private let hasInjectedRepository: Bool
    private var hasBootstrapped = false
    private var searchTask: Task<Void, Never>?
    private var mapTask: Task<Void, Never>?
    private var individualRequest = 0
    private var mapRequest = 0
    private var dashboardRequest = 0
    private var allRequest = 0
    private var photoCache: [String: NSImage] = [:]
    private var canLoadRecords: Bool { isAuthenticated || hasInjectedRepository }

    init(
        repository: TurtleRepository? = nil,
        client: APIClient? = nil,
        dashboardLayoutStore: DashboardLayoutStore = DashboardLayoutStore()
    ) {
        let client = client ?? APIClient()
        self.client = client
        self.dashboardLayoutStore = dashboardLayoutStore
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

    var currentDashboardAccountKey: String {
        if !isDemoBypassActive, let user = client.account {
            return "live:\(user.id.uuidString.lowercased())"
        }
        if !isDemoBypassActive, !authEmail.isEmpty {
            return "live:\(authEmail.lowercased())"
        }
        return demoPersona.accountStorageKey
    }

    var currentAccountDefaultPreset: DashboardRolePreset {
        if !isDemoBypassActive, let user = client.account {
            return user.role == .ranger ? .fieldRanger : .generalOverview
        }
        return demoPersona.defaultPreset
    }

    private func updateAccount() {
        if isDemoBypassActive {
            isAuthenticated = true
            authEmail = demoPersona.email
            accountName = demoPersona.displayName
            accountOrganization = "Sea Turtle Group"
            accountRoleLabel = demoPersona.roleLabel
        } else {
            isAuthenticated = client.account != nil
            authEmail = client.account?.email ?? ""
            accountName = client.account?.displayName ?? "Researcher"
            accountOrganization = client.account?.organisationName ?? ""
            accountRoleLabel = client.account?.role == .ranger ? "Field Patrol Ranger" : "Organization Owner"
        }
        syncDashboardLayoutForCurrentAccount()
    }

    private func syncDashboardLayoutForCurrentAccount() {
        dashboardLayout = dashboardLayoutStore.loadLayout(
            for: currentDashboardAccountKey,
            defaultPreset: currentAccountDefaultPreset
        )
    }

    // MARK: - Quick Demo Bypass & Per-Account Widget Personalization

    func enterDemoWorkspace(persona: DemoDashboardPersona = .demoResearcher) {
        client.logout()
        isDemoBypassActive = true
        demoPersona = persona
        isEditingDashboardWidgets = false
        clearPrivateState(keepDemoMode: true)
        repository = DemoTurtleRepository()
        updateAccount()
        let generation = sessionGeneration
        Task {
            guard sessionGeneration == generation else { return }
            await reloadAll()
        }
    }

    func selectDemoPersona(_ persona: DemoDashboardPersona) {
        demoPersona = persona
        isEditingDashboardWidgets = false
        updateAccount()
    }

    func openNotSureReview(
        scenario: ReviewScenarioID = .rankOneJunctionMismatch,
        layoutMode: ScientistComparisonLayoutMode = .sideBySide
    ) {
        selectedTurtle = nil
        requestedReviewScenario = scenario
        requestedReviewLayoutMode = layoutMode
        reviewNavigationTrigger = UUID()
        activeSection = .scientistReview
    }

    func applyDashboardPreset(_ preset: DashboardRolePreset) {
        dashboardLayout = dashboardLayoutStore.resetLayout(for: currentDashboardAccountKey, to: preset)
    }

    func addDashboardWidget(_ kind: DashboardWidgetKind, span: DashboardWidgetSpan? = nil) {
        guard !dashboardLayout.widgets.contains(where: { $0.kind == kind }) else { return }
        var next = dashboardLayout
        next.widgets.append(DashboardWidgetItem(kind: kind, span: span ?? kind.defaultSpan))
        next.activePreset = nil
        next.updatedAt = Date()
        dashboardLayout = next
        dashboardLayoutStore.saveLayout(next)
    }

    func removeDashboardWidget(id: UUID) {
        var next = dashboardLayout
        next.widgets.removeAll { $0.id == id }
        next.activePreset = nil
        next.updatedAt = Date()
        dashboardLayout = next
        dashboardLayoutStore.saveLayout(next)
    }

    func toggleDashboardWidgetSpan(id: UUID) {
        guard let index = dashboardLayout.widgets.firstIndex(where: { $0.id == id }) else { return }
        var next = dashboardLayout
        next.widgets[index].span = next.widgets[index].span.toggled
        next.activePreset = nil
        next.updatedAt = Date()
        dashboardLayout = next
        dashboardLayoutStore.saveLayout(next)
    }

    func moveDashboardWidget(id: UUID, direction: Int) {
        guard let index = dashboardLayout.widgets.firstIndex(where: { $0.id == id }) else { return }
        let targetIndex = index + direction
        guard dashboardLayout.widgets.indices.contains(targetIndex) else { return }
        var next = dashboardLayout
        let item = next.widgets.remove(at: index)
        next.widgets.insert(item, at: targetIndex)
        next.activePreset = nil
        next.updatedAt = Date()
        dashboardLayout = next
        dashboardLayoutStore.saveLayout(next)
    }

    func moveDashboardWidget(fromID: UUID, toID: UUID) {
        guard fromID != toID,
              let fromIndex = dashboardLayout.widgets.firstIndex(where: { $0.id == fromID }),
              let toIndex = dashboardLayout.widgets.firstIndex(where: { $0.id == toID }) else { return }
        var next = dashboardLayout
        let item = next.widgets.remove(at: fromIndex)
        next.widgets.insert(item, at: toIndex)
        next.activePreset = nil
        next.updatedAt = Date()
        dashboardLayout = next
        dashboardLayoutStore.saveLayout(next)
    }

    func updateDashboardWidgetOptions(id: UUID, conditionFilter: String? = nil, metricMode: String? = nil) {
        guard let index = dashboardLayout.widgets.firstIndex(where: { $0.id == id }) else { return }
        var next = dashboardLayout
        next.widgets[index].conditionFilter = conditionFilter
        next.widgets[index].metricMode = metricMode
        next.updatedAt = Date()
        dashboardLayout = next
        dashboardLayoutStore.saveLayout(next)
    }

    private func clearPrivateState(keepDemoMode: Bool = false) {
        if !keepDemoMode {
            isDemoBypassActive = false
        }
        sessionGeneration = UUID()
        searchTask?.cancel()
        mapTask?.cancel()
        photoCache.removeAll()
        turtles = []
        favoriteTurtles = []
        sightings = []
        dashboard = DashboardSnapshot(months: [], species: [])
        totalIndividuals = 0
        individualsOffset = 0
        isIndividualsLoading = false
        individualRequest += 1
        dismissDetail()
        isLoading = false
        lastError = nil
        repository = isDemoBypassActive ? DemoTurtleRepository() : RemoteTurtleRepository(client: client)
    }

    deinit { searchTask?.cancel(); mapTask?.cancel() }

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
        allRequest += 1
        let allRevision = allRequest
        individualRequest += 1
        let individualRevision = individualRequest
        mapRequest += 1
        let mapRevision = mapRequest
        dashboardRequest += 1
        let dashboardRevision = dashboardRequest
        let individualQuery = currentIndividualQuery
        let mapQuery = currentMapQuery
        let dashboardQuery = currentDashboardQuery
        isLoading = true
        isIndividualsLoading = true
        lastError = nil
        defer {
            if sessionGeneration == generation, allRequest == allRevision { isLoading = false }
            if sessionGeneration == generation, individualRequest == individualRevision { isIndividualsLoading = false }
        }
        do {
            async let individuals = repository.listIndividuals(query: individualQuery)
            async let favorites = repository.listFavorites()
            async let dashboard = repository.dashboard(query: dashboardQuery)
            async let sightings = repository.mapSightings(query: mapQuery)
            let (page, favoriteItems, snapshot, mapItems) = try await (individuals, favorites, dashboard, sightings)
            guard sessionGeneration == generation else { return }
            if individualRequest == individualRevision, currentIndividualQuery == individualQuery {
                turtles = page.items
                totalIndividuals = page.total
                favoriteTurtles = favoriteItems
            }
            if dashboardRequest == dashboardRevision, chartSpecies == dashboardQuery.species { self.dashboard = snapshot }
            if mapRequest == mapRevision, currentMapQuery == mapQuery { self.sightings = mapItems }
        } catch {
            guard sessionGeneration == generation, allRequest == allRevision,
                  individualRequest == individualRevision, currentIndividualQuery == individualQuery,
                  mapRequest == mapRevision, currentMapQuery == mapQuery,
                  dashboardRequest == dashboardRevision, chartSpecies == dashboardQuery.species else { return }
            if !(error is CancellationError) { lastError = error.localizedDescription }
        }
    }

    @discardableResult
    func reloadIndividuals() async -> Bool {
        guard canLoadRecords else { return false }
        let generation = sessionGeneration
        let query = currentIndividualQuery
        individualRequest += 1
        let request = individualRequest
        isIndividualsLoading = true
        defer { if individualRequest == request { isIndividualsLoading = false } }
        do {
            async let pageResult = repository.listIndividuals(query: query)
            async let favoritesResult = repository.listFavorites()
            let (page, favorites) = try await (pageResult, favoritesResult)
            guard sessionGeneration == generation, currentIndividualQuery == query, individualRequest == request else { return false }
            turtles = page.items
            totalIndividuals = page.total
            favoriteTurtles = favorites
            lastError = nil
            return true
        } catch {
            if sessionGeneration == generation, currentIndividualQuery == query, individualRequest == request,
               !(error is CancellationError) { lastError = error.localizedDescription }
            return false
        }
    }

    func loadIndividualsPage(_ pageIndex: Int) async {
        guard !isIndividualsLoading else { return }
        let previousOffset = individualsOffset
        let lastPage = max(0, (totalIndividuals - 1) / max(1, individualsPageSize))
        individualsOffset = min(max(0, pageIndex), lastPage) * max(1, individualsPageSize)
        let query = currentIndividualQuery
        let generation = sessionGeneration
        let succeeded = await reloadIndividuals()
        if !succeeded, sessionGeneration == generation, currentIndividualQuery == query {
            individualsOffset = previousOffset
        }
    }

    func reloadMap() async {
        guard canLoadRecords else { return }
        let generation = sessionGeneration
        let query = currentMapQuery
        mapRequest += 1
        let request = mapRequest
        do {
            let values = try await repository.mapSightings(query: query)
            guard sessionGeneration == generation, mapRequest == request, currentMapQuery == query else { return }
            sightings = values
        } catch {
            if sessionGeneration == generation, mapRequest == request, currentMapQuery == query, !(error is CancellationError) { lastError = error.localizedDescription }
        }
    }

    func reloadDashboard() async {
        guard canLoadRecords else { return }
        let generation = sessionGeneration
        dashboardRequest += 1
        let request = dashboardRequest
        do {
            let value = try await repository.dashboard(query: currentDashboardQuery)
            guard sessionGeneration == generation, dashboardRequest == request else { return }
            dashboard = value
        } catch {
            if sessionGeneration == generation, dashboardRequest == request, !(error is CancellationError) { lastError = error.localizedDescription }
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
                        name: value.name,
                        profileCode: value.profileCode
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
        photoCache.removeAll()
        return try await repository.matchPhoto(imageData: imageData, side: side, limit: limit)
    }

    func matchPhotoPair(leftData: Data, rightData: Data, limit: Int = 10) async throws -> MatchSearchOutcome {
        photoCache.removeAll()
        return try await repository.matchPhotoPair(leftData: leftData, rightData: rightData, limit: limit)
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
        IndividualQuery(search: searchText, species: selectedSpecies.map { [$0] } ?? [], condition: selectedCondition, sort: sort,
                        page: PageRequest(limit: individualsPageSize, offset: individualsOffset))
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
        individualsOffset = 0
        turtles = []
        totalIndividuals = 0
        isIndividualsLoading = canLoadRecords
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled, let self else { return }
            await self.reloadIndividuals()
        }
    }

    private func scheduleMapReload() {
        sightings = []
        mapTask?.cancel()
        mapTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled, let self else { return }
            await self.reloadMap()
        }
    }

}
