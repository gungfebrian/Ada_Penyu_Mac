import XCTest
@testable import Ada_Penyu_Desktop

@MainActor
final class DashboardWidgetTests: XCTestCase {
    private func makeIsolatedDefaults() -> UserDefaults {
        let suiteName = "ada.test.dashboard.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    func testEachAccountPersistsIndependentPersonalizedWidgetLayout() {
        let defaults = makeIsolatedDefaults()
        let layoutStore = DashboardLayoutStore(defaults: defaults)
        let store = AppStore(
            repository: DemoTurtleRepository(),
            dashboardLayoutStore: layoutStore
        )
        store.enterDemoWorkspace(persona: .demoResearcher)
        XCTAssertTrue(store.isAuthenticated)
        XCTAssertTrue(store.isDemoBypassActive)

        // Default demo account (Demo Owner) starts with Owner preset including Not Sure Review Queue
        XCTAssertEqual(store.demoPersona, .demoResearcher)
        XCTAssertEqual(store.accountName, "Demo Owner")
        XCTAssertEqual(store.dashboardLayout.activePreset, .generalOverview)
        XCTAssertTrue(store.dashboardLayout.widgets.contains(where: { $0.kind == .notSureQueue }))
        let initialCount = store.dashboardLayout.widgets.count
        XCTAssertGreaterThanOrEqual(initialCount, 4)

        // Opening Not Sure Review from Owner dashboard routes to .scientistReview with requested scenario
        store.openNotSureReview(scenario: .glareOcclusionUnsure, layoutMode: .scales)
        XCTAssertEqual(store.activeSection, .scientistReview)
        XCTAssertEqual(store.requestedReviewScenario, .glareOcclusionUnsure)
        XCTAssertEqual(store.requestedReviewLayoutMode, .scales)

        // Customize Demo Researcher's dashboard: add Habitat Hotspots and resize first widget
        store.addDashboardWidget(.habitatHotspots, span: .full)
        XCTAssertTrue(store.dashboardLayout.widgets.contains(where: { $0.kind == .habitatHotspots && $0.span == .full }))
        XCTAssertNil(store.dashboardLayout.activePreset)

        // Switch to Ranger Wayan account — should have Field Ranger preset, untouched by Demo Researcher's edits
        store.selectDemoPersona(.rangerWayan)
        XCTAssertEqual(store.accountName, "Ranger Wayan")
        XCTAssertEqual(store.dashboardLayout.activePreset, .fieldRanger)
        XCTAssertTrue(store.dashboardLayout.widgets.contains(where: { $0.kind == .photoIDReadiness }))

        // Remove Favorites Watch from Ranger Wayan's layout
        if let favWidget = store.dashboardLayout.widgets.first(where: { $0.kind == .favoritesWatch }) {
            store.removeDashboardWidget(id: favWidget.id)
        }
        XCTAssertFalse(store.dashboardLayout.widgets.contains(where: { $0.kind == .favoritesWatch }))

        // Switch back to Demo Researcher — custom Habitat Hotspots widget is still preserved
        store.selectDemoPersona(.demoResearcher)
        XCTAssertTrue(store.dashboardLayout.widgets.contains(where: { $0.kind == .habitatHotspots && $0.span == .full }))

        // Switch back to Ranger Wayan — Favorites Watch removal is still preserved
        store.selectDemoPersona(.rangerWayan)
        XCTAssertFalse(store.dashboardLayout.widgets.contains(where: { $0.kind == .favoritesWatch }))
    }

    func testWidgetReorderingResizingAndPerWidgetFiltersPersist() {
        let defaults = makeIsolatedDefaults()
        let layoutStore = DashboardLayoutStore(defaults: defaults)
        let store = AppStore(
            repository: DemoTurtleRepository(),
            dashboardLayoutStore: layoutStore
        )

        store.applyDashboardPreset(.healthTriage)
        let firstID = store.dashboardLayout.widgets[0].id
        let secondID = store.dashboardLayout.widgets[1].id

        store.moveDashboardWidget(id: secondID, direction: -1)
        XCTAssertEqual(store.dashboardLayout.widgets[0].id, secondID)
        XCTAssertEqual(store.dashboardLayout.widgets[1].id, firstID)

        // Verify drag-and-drop move (fromID -> toID)
        store.moveDashboardWidget(fromID: firstID, toID: secondID)
        XCTAssertEqual(store.dashboardLayout.widgets[0].id, firstID)
        XCTAssertEqual(store.dashboardLayout.widgets[1].id, secondID)
        store.moveDashboardWidget(fromID: secondID, toID: firstID)
        XCTAssertEqual(store.dashboardLayout.widgets[0].id, secondID)

        let originalSpan = store.dashboardLayout.widgets[0].span
        store.toggleDashboardWidgetSpan(id: secondID)
        XCTAssertEqual(store.dashboardLayout.widgets[0].span, originalSpan.toggled)

        store.updateDashboardWidgetOptions(id: secondID, conditionFilter: "Injured", metricMode: "injured_only")
        XCTAssertEqual(store.dashboardLayout.widgets[0].conditionFilter, "Injured")
        XCTAssertEqual(store.dashboardLayout.widgets[0].metricMode, "injured_only")

        // Reload from store to verify persistence
        let reloaded = layoutStore.loadLayout(for: store.currentDashboardAccountKey)
        XCTAssertEqual(reloaded.widgets[0].id, secondID)
        XCTAssertEqual(reloaded.widgets[0].span, originalSpan.toggled)
        XCTAssertEqual(reloaded.widgets[0].metricMode, "injured_only")
    }

    func testScientistPresetAndRoleHierarchyOrdering() {
        let defaults = makeIsolatedDefaults()
        let layoutStore = DashboardLayoutStore(defaults: defaults)
        let store = AppStore(
            repository: DemoTurtleRepository(),
            dashboardLayoutStore: layoutStore
        )

        store.enterDemoWorkspace(persona: .ecologistAmina)
        XCTAssertEqual(store.accountRoleLabel, "Tier 2 · Marine Scientist")
        XCTAssertEqual(store.dashboardLayout.activePreset, .scientist)

        let kinds = store.dashboardLayout.widgets.map(\.kind)
        // Scientist hierarchy starts with full-width summary, followed by Not Sure queue, Photo-ID readiness & Mark-Recapture
        XCTAssertEqual(kinds.first, .kpiOverview)
        XCTAssertTrue(kinds.contains(.notSureQueue))
        XCTAssertTrue(kinds.contains(.photoIDReadiness))
        XCTAssertTrue(kinds.contains(.recaptureAnalysis))
        XCTAssertTrue(kinds.contains(.speciesBreakdown))
        XCTAssertTrue(kinds.contains(.conditionBreakdown))
    }

    func testAllWidgetsDefineExplicitResearchQuestions() {
        for kind in DashboardWidgetKind.allCases {
            XCTAssertFalse(kind.title.isEmpty)
            XCTAssertFalse(kind.questionAnswered.isEmpty)
            XCTAssertTrue(kind.questionAnswered.hasSuffix("?"), "Expected question for \(kind.rawValue) to end with '?'")
            XCTAssertFalse(kind.shortSummary.isEmpty)
        }
    }

    func testDashboardAnalyticsSynthesizesRecaptureTriageHotspotsAndPhotoIDCoverage() async throws {
        let repo = DemoTurtleRepository()
        let snapshot = try await repo.dashboard(query: .lastTwelveMonths)
        let analytics = DashboardAnalytics.compute(
            snapshot: snapshot,
            turtles: DemoFixtures.turtles,
            sightings: DemoFixtures.sightings
        )

        XCTAssertEqual(analytics.totalIndividuals, 8)
        XCTAssertEqual(analytics.totalCatalogSightings, DemoFixtures.turtles.reduce(0) { $0 + $1.sightings })
        XCTAssertEqual(analytics.recapturedIndividualsCount, 7)
        XCTAssertEqual(analytics.recaptureRatePercent, 88)

        // Triage counts match DemoFixtures (2 injured, 2 scarred)
        XCTAssertEqual(analytics.injuredTurtles.count, 2)
        XCTAssertEqual(analytics.scarredTurtles.count, 2)
        XCTAssertEqual(analytics.triageTurtles.count, 4)

        // Photo coverage: 6 have both sides, 1 left-only, 1 right-only
        XCTAssertEqual(analytics.photoCoverage.bothSidesCount, 6)
        XCTAssertEqual(analytics.photoCoverage.leftOnlyCount, 1)
        XCTAssertEqual(analytics.photoCoverage.rightOnlyCount, 1)
        XCTAssertEqual(analytics.photoCoverage.dualSidePercent, 75)

        // Hotspots should include Kuta Beach and Nusa Dua reef
        XCTAssertFalse(analytics.hotspots.isEmpty)
        XCTAssertTrue(analytics.hotspots.contains(where: { $0.location == "Kuta Beach" && $0.injuredOrScarredCount > 0 }))
    }

    func testSuperAsiaAccountDemoLoadsMultiRegionIndoPacificTurtlesAndSightings() async throws {
        let defaults = makeIsolatedDefaults()
        let layoutStore = DashboardLayoutStore(defaults: defaults)
        let store = AppStore(
            repository: DemoTurtleRepository(),
            dashboardLayoutStore: layoutStore
        )

        store.enterDemoWorkspace(persona: .superAsiaNetwork)
        XCTAssertEqual(store.demoPersona, .superAsiaNetwork)
        XCTAssertEqual(store.accountOrganization, "Indo-Pacific Turtle Network")
        XCTAssertEqual(store.selectedMapPeriod, .allTime)

        // General overview matches Picture 2 core 5 cards + 2 operational cards
        let kinds = store.dashboardLayout.widgets.map(\.kind)
        XCTAssertEqual(Array(kinds.prefix(5)), [.kpiOverview, .sightingsTrend, .geographicMap, .recentSightings, .speciesBreakdown])
        XCTAssertTrue(kinds.contains(.notSureQueue))
        XCTAssertTrue(kinds.contains(.photoIDReadiness))

        let repo = DemoTurtleRepository(dataset: .panAsiaSuperAccount)
        let page = try await repo.listIndividuals(query: IndividualQuery(page: PageRequest(limit: 50)))
        XCTAssertGreaterThanOrEqual(page.total, 20)
        XCTAssertTrue(page.items.contains(where: { $0.location.contains("India") }))
        XCTAssertTrue(page.items.contains(where: { $0.location.contains("Indonesia") }))
        XCTAssertTrue(page.items.contains(where: { $0.location.contains("Malaysia") }))
        XCTAssertTrue(page.items.contains(where: { $0.location.contains("Japan") }))

        let asiaSightings = try await repo.mapSightings(query: MapQuery(period: .allTime, page: PageRequest(limit: 200)))
        XCTAssertGreaterThanOrEqual(asiaSightings.count, 30)
    }
}
