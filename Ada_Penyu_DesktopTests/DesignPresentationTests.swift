import XCTest
@testable import Ada_Penyu_Desktop

@MainActor
final class DesignPresentationTests: XCTestCase {
    func testDashboardSummaryDoesNotInventReturningCountsForInconsistentData() {
        let snapshot = DashboardSnapshot(months: [.init(month: "2026-10", sightings: 12, newIndividuals: 7)],
            species: [.init(id: "green", species: .green, individuals: 4, sightings: 12)])
        XCTAssertEqual(snapshot.metrics.observed, 4)
        XCTAssertEqual(snapshot.metrics.sightings, 12)
        XCTAssertNil(snapshot.metrics.seenAgain)
    }

    func testEmptyDashboardHasNoInvalidAverage() {
        let snapshot = DashboardSnapshot(months: [], species: [])
        XCTAssertEqual(snapshot.metrics.monthlyAverage, 0)
        XCTAssertEqual(snapshot.metrics.seenAgain, 0)
    }

    func testResightingsGroupByIdentityAndKeepChronologicalPreviousEncounter() {
        let records = [sighting("a", turtle: "one", date: "3 Oct 2026"), sighting("b", turtle: "two", date: "5 Oct 2026"),
                       sighting("c", turtle: "one", date: "1 Oct 2026"), sighting("d", turtle: "one", date: "2 Oct 2026")]
        let rows = RecentResighting.rows(from: records)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.latest.id, "a")
        XCTAssertEqual(rows.first?.previous.id, "d")
    }

    func testMapCanOpenTurtleOutsideLoadedCatalogPage() {
        let record = sighting(UUID().uuidString, turtle: UUID().uuidString, date: "3 Oct 2026")
        let reference = record.turtleReference
        XCTAssertEqual(reference.backendID?.uuidString, record.turtleID)
        XCTAssertEqual(reference.displayName, "Same display name")
        XCTAssertEqual(reference.firstRecorded, "Not recorded")
    }

    func testCatalogPagingRequestsOffsetAndResetsWhenFilterChanges() async {
        let repository = PagingRepository()
        let store = AppStore(repository: repository)
        await store.bootstrap()
        await store.loadIndividualsPage(2)
        XCTAssertEqual(repository.requests.last?.page.offset, 20)
        XCTAssertEqual(store.individualsOffset, 20)
        store.selectedSpecies = .green
        XCTAssertEqual(store.currentIndividualQuery.page.offset, 0)
        XCTAssertEqual(store.currentIndividualQuery.species, [.green])
    }

    func testFailedPageKeepsPreviousPageAndRows() async {
        let repository = PagingRepository()
        let store = AppStore(repository: repository)
        await store.bootstrap()
        let previousIDs = store.turtles.map(\.id)
        repository.failIndividuals = true
        await store.loadIndividualsPage(2)
        XCTAssertEqual(store.individualsOffset, 0)
        XCTAssertEqual(store.turtles.map(\.id), previousIDs)
        XCTAssertNotNil(store.lastError)
    }

    func testRapidPageClicksDoNotStartOverlappingPageRequests() async {
        let repository = PagingRepository()
        let store = AppStore(repository: repository)
        await store.bootstrap()
        let held = expectation(description: "Page one held")
        repository.onHold = { held.fulfill() }
        repository.holdNext = true
        let pageOne = Task { await store.loadIndividualsPage(1) }
        await fulfillment(of: [held], timeout: 2)
        repository.failIndividuals = true
        await store.loadIndividualsPage(2)
        XCTAssertEqual(repository.requests.count, 2)
        repository.pending?.resume(returning: Page(items: [TestTurtleRepository.turtle], total: 35, request: PageRequest(limit: 10, offset: 10)))
        await pageOne.value
        XCTAssertEqual(store.individualsOffset, 10)
        XCTAssertEqual(store.totalIndividuals, 35)
    }

    func testSightingsFilterReloadsWithoutOpeningMap() async {
        let repository = PagingRepository()
        let store = AppStore(repository: repository)
        await store.bootstrap()
        store.activeSection = .sightings
        let changed = expectation(description: "Species reaches repository")
        repository.onMapRequest = { changed.fulfill() }
        store.mapSpecies = .green
        await fulfillment(of: [changed], timeout: 2)
        XCTAssertEqual(repository.mapQueries.last?.species, .green)
    }

    func testOlderCatalogResponseCannotReplaceNewFilter() async {
        let repository = PagingRepository()
        let store = AppStore(repository: repository)
        let held = expectation(description: "Old page held")
        repository.onHold = { held.fulfill() }
        repository.holdNext = true
        let oldRequest = Task { await store.reloadIndividuals() }
        await fulfillment(of: [held], timeout: 2)
        store.selectedSpecies = .green
        await store.reloadIndividuals()
        repository.pending?.resume(returning: Page(items: [], total: 999, request: PageRequest()))
        _ = await oldRequest.value
        XCTAssertEqual(store.totalIndividuals, 35)
        XCTAssertFalse(store.turtles.isEmpty)
    }

    func testOlderFullRefreshCannotReplaceANewerCatalogRequestForTheSameFilter() async {
        let repository = PagingRepository()
        let store = AppStore(repository: repository)
        let held = expectation(description: "Full refresh held")
        repository.onHold = { held.fulfill() }
        repository.holdNext = true
        let oldRefresh = Task { await store.reloadAll() }
        await fulfillment(of: [held], timeout: 2)
        await store.reloadIndividuals()
        repository.pending?.resume(returning: Page(items: [], total: 999, request: PageRequest()))
        await oldRefresh.value
        XCTAssertEqual(store.totalIndividuals, 35)
        XCTAssertFalse(store.turtles.isEmpty)
        XCTAssertFalse(store.isIndividualsLoading)
        XCTAssertFalse(store.isLoading)
    }

    func testProfileRetainsBackendCodeForDisplay() throws {
        let profile = try JSONDecoder.api.decode(V2Profile.self, from: APIFixtures.data(APIFixtures.profile))
        XCTAssertEqual(profile.turtle().profileCode, profile.profileCode)
    }

    private func sighting(_ id: String, turtle: String, date: String) -> Sighting {
        Sighting(name: "Same display name", id: id, turtleID: turtle, species: .green, location: "Reef", date: date,
                 condition: .unknown, coordinate: .init(latitude: -8.7, longitude: 115.2))
    }
}

private final class PagingRepository: TurtleRepository {
    var requests: [IndividualQuery] = []
    var failIndividuals = false
    var mapQueries: [MapQuery] = []
    var onMapRequest: (() -> Void)?
    var holdNext = false
    var onHold: (() -> Void)?
    var pending: CheckedContinuation<Page<Turtle>, Error>?

    func listIndividuals(query: IndividualQuery) async throws -> Page<Turtle> {
        requests.append(query)
        if failIndividuals { throw APIError.invalidResponse }
        if holdNext {
            holdNext = false
            return try await withCheckedThrowingContinuation { continuation in
                pending = continuation
                onHold?()
            }
        }
        return Page(items: [TestTurtleRepository.turtle], total: 35, request: query.page)
    }
    func listFavorites() async throws -> [Turtle] { [] }
    func setFavorite(turtleID: String, isFavorite: Bool) async throws -> Bool { isFavorite }
    func dashboard(query: DashboardQuery) async throws -> DashboardSnapshot { .init(months: [], species: []) }
    func mapSightings(query: MapQuery) async throws -> [Sighting] {
        mapQueries.append(query)
        onMapRequest?()
        return []
    }
    func detail(for turtle: Turtle) async throws -> TurtleDetailData { .init(turtle: turtle, measurements: [], logs: []) }
    func export(_ request: ExportRequest) async throws -> DownloadedFile { throw APIError.invalidResponse }
}
