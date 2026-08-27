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
    @Published private(set) var mode: DataMode
    @Published private(set) var isUsingFallback = false

    private var repository: TurtleRepository
    private var searchTask: Task<Void, Never>?

    init(mode: DataMode = .live, repository: TurtleRepository? = nil) {
        self.mode = mode
        if let repository {
            self.repository = repository
        } else if mode == .live {
            self.repository = RemoteTurtleRepository()
        } else {
            self.repository = DemoTurtleRepository()
        }
    }

    deinit { searchTask?.cancel() }

    func bootstrap() async {
        await reloadAll()
    }

    func reloadAll() async {
        isLoading = true
        lastError = nil
        if mode == .live { isUsingFallback = false }
        do {
            async let individuals = repository.listIndividuals(query: currentIndividualQuery)
            async let favorites = repository.listFavorites()
            async let dashboard = repository.dashboard(query: currentDashboardQuery)
            async let sightings = repository.mapSightings(query: currentMapQuery)
            let (individualPage, favoriteItems, dashboardSnapshot, mapItems) = try await (individuals, favorites, dashboard, sightings)
            turtles = individualPage.items
            totalIndividuals = individualPage.total
            favoriteTurtles = favoriteItems
            self.dashboard = dashboardSnapshot
            self.sightings = mapItems
        } catch {
            if mode == .live {
                await switchToDemoFallback(message: error.localizedDescription)
            } else {
                lastError = error.localizedDescription
            }
        }
        isLoading = false
    }

    func reloadIndividuals() async {
        do {
            let page = try await repository.listIndividuals(query: currentIndividualQuery)
            turtles = page.items
            totalIndividuals = page.total
            favoriteTurtles = try await repository.listFavorites()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func reloadMap() async {
        do {
            sightings = try await repository.mapSightings(query: currentMapQuery)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func reloadDashboard() async {
        do {
            dashboard = try await repository.dashboard(query: currentDashboardQuery)
        } catch {
            lastError = error.localizedDescription
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
        do {
            let detail = try await repository.detail(for: turtle)
            guard selectedTurtle?.id == turtle.id else { return }
            selectedDetail = detail
            detailError = nil
        } catch {
            guard selectedTurtle?.id == turtle.id else { return }
            detailError = error.localizedDescription
        }
        if selectedTurtle?.id == turtle.id { isDetailLoading = false }
    }

    func toggleFavorite(_ turtle: Turtle) {
        let nextValue = !favoriteTurtles.contains(where: { $0.id == turtle.id })
        Task {
            do {
                _ = try await repository.setFavorite(turtleID: turtle.id, isFavorite: nextValue)
                favoriteTurtles = try await repository.listFavorites()
                turtles = turtles.map { value in
                    guard value.id == turtle.id else { return value }
                    return Turtle(id: value.id, species: value.species, location: value.location, lastSeen: value.lastSeen, sightings: value.sightings, condition: value.condition, firstRecorded: value.firstRecorded, isFavorite: nextValue, coordinate: value.coordinate, backendID: value.backendID)
                }
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func switchMode(to newMode: DataMode) {
        guard newMode != mode else { return }
        mode = newMode
        isUsingFallback = false
        repository = newMode == .live ? RemoteTurtleRepository() : DemoTurtleRepository()
        Task { await reloadAll() }
    }

    func export(_ request: ExportRequest) {
        Task {
            do {
                let file = try await repository.export(request)
                let panel = NSSavePanel()
                panel.nameFieldStringValue = file.filename
                panel.allowedContentTypes = [.data]
                guard panel.runModal() == .OK, let url = panel.url else { return }
                try file.data.write(to: url, options: .atomic)
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func clearError() { lastError = nil }

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

    private func switchToDemoFallback(message: String) async {
        isUsingFallback = true
        lastError = "Live API unavailable — showing demo data."
        mode = .demo
        repository = DemoTurtleRepository()
        await reloadAll()
        if !message.isEmpty { lastError = "Live API unavailable — showing demo data." }
    }
}
