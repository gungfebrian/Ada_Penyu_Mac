import XCTest
@testable import Ada_Penyu_Desktop

@MainActor
final class AppFlowTests: XCTestCase {
    func testIndividualsQueryBuildsStableQueryItems() throws {
        let query = IndividualQuery(
            search: "Turtle #001",
            species: [.hawksbill],
            condition: .injured,
            sort: .lastSeenDescending,
            page: PageRequest(limit: 25, offset: 50)
        )

        XCTAssertEqual(query.queryItems.map(\.description), [
            "q=Turtle #001",
            "species=hawksbill",
            "condition=injured",
            "sort=last_seen_desc",
            "limit=25",
            "offset=50",
        ])
    }

    func testDemoRepositoryPreservesFavoriteToggleAsynchronousFlow() async throws {
        let repository = DemoTurtleRepository()
        let turtles = try await repository.listIndividuals(query: .default)
        XCTAssertEqual(turtles.items.count, 8)

        let favorite = try await repository.setFavorite(turtleID: turtles.items[0].id, isFavorite: true)
        XCTAssertTrue(favorite)
        let favorites = try await repository.listFavorites()
        XCTAssertTrue(favorites.contains(where: { $0.id == turtles.items[0].id }))
    }

    func testStoreStartsInLiveMode() {
        let store = AppStore(repository: DemoTurtleRepository())

        XCTAssertEqual(store.mode, .live)
    }

    func testSelectingIndividualKeepsOriginSectionForModalPresentation() {
        let store = AppStore(repository: DemoTurtleRepository())
        store.activeSection = .favorites

        store.select(DemoFixtures.turtles[3])

        XCTAssertEqual(store.activeSection, .favorites)
        XCTAssertEqual(store.selectedTurtle?.id, "Turtle #004")
        XCTAssertEqual(store.detailOrigin, .favorites)
    }

    func testDismissingModalPreventsInFlightDetailFromReappearing() async throws {
        let store = AppStore(repository: DemoTurtleRepository())

        store.select(DemoFixtures.turtles[3])
        store.dismissDetail()
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertNil(store.selectedTurtle)
        XCTAssertNil(store.selectedDetail)
        XCTAssertFalse(store.isDetailLoading)
    }

    func testDemoDashboardAggregatesFixtureRecordsInsteadOfFabricatingValues() async throws {
        let repository = DemoTurtleRepository()

        let snapshot = try await repository.dashboard(query: .lastTwelveMonths)

        XCTAssertEqual(snapshot.months.reduce(0) { $0 + $1.sightings }, DemoFixtures.sightings.count)
        XCTAssertEqual(snapshot.months.reduce(0) { $0 + $1.newIndividuals }, DemoFixtures.turtles.count)
    }
}
