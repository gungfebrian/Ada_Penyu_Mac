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

    func testSightingsTimelineWindowSlidesAcrossHistoryAndSnapsToNow() async throws {
        let repo = DemoTurtleRepository(dataset: .panAsiaSuperAccount)
        let snapshot24 = try await repo.dashboard(query: .lastMonths(24))
        XCTAssertEqual(snapshot24.months.count, 24)
        XCTAssertEqual(snapshot24.months.last?.month, SightingsTimelineWindow.currentMonthKey())

        // Anchored at Now (offset = 0) with 6M span
        let atNow = SightingsTimelineWindow(allMonths: snapshot24.months, span: .sixMonths, endOffsetFromNow: 0)
        XCTAssertTrue(atNow.isAtNow)
        XCTAssertTrue(atNow.canScrub)
        XCTAssertEqual(atNow.visibleMonths.count, 6)
        XCTAssertEqual(atNow.maxOffset, 18)
        XCTAssertEqual(atNow.visibleMonths.last?.month, snapshot24.months.last?.month)
        XCTAssertFalse(atNow.rangeLabel.contains("Now"), "Header subtitle should stay clean without '· Now' clutter")
        XCTAssertEqual(
            atNow.rangeLabel,
            "\(SightingsTimelineWindow.shortMonthYear(atNow.visibleMonths.first!.month)) – \(SightingsTimelineWindow.shortMonthYear(atNow.visibleMonths.last!.month))"
        )

        // Full 2Y view on 24 months has nothing to scrub
        let fullSpan = SightingsTimelineWindow(allMonths: snapshot24.months, span: .twoYears, endOffsetFromNow: 0)
        XCTAssertFalse(fullSpan.canScrub)
        XCTAssertEqual(fullSpan.maxOffset, 0)

        // Slide 10 months into the past
        let earlier = SightingsTimelineWindow(allMonths: snapshot24.months, span: .sixMonths, endOffsetFromNow: 10)
        XCTAssertFalse(earlier.isAtNow)
        XCTAssertEqual(earlier.visibleMonths.count, 6)
        XCTAssertEqual(earlier.visibleMonths.last?.month, snapshot24.months[13].month)
        XCTAssertEqual(earlier.visibleMonths.first?.month, snapshot24.months[8].month)

        // Over-scrolling past oldest history clamps cleanly to maxOffset
        let clamped = SightingsTimelineWindow(allMonths: snapshot24.months, span: .oneYear, endOffsetFromNow: 99)
        XCTAssertEqual(clamped.clampedOffset, 12)
        XCTAssertEqual(clamped.visibleMonths.first?.month, snapshot24.months.first?.month)
        XCTAssertEqual(clamped.visibleMonths.count, 12)
    }

    func testSightingsTimelineXAxisTicksNeverCollideAndFormatShortMonth() {
        XCTAssertEqual(SightingsTimelineWindow.xAxisTickIndices(count: 0), [])
        XCTAssertEqual(SightingsTimelineWindow.xAxisTickIndices(count: 1), [0])
        XCTAssertEqual(SightingsTimelineWindow.xAxisTickIndices(count: 6), [0, 1, 2, 3, 4, 5])

        for count in [7, 8, 9, 10, 11, 12, 24] {
            let ticks = SightingsTimelineWindow.xAxisTickIndices(count: count)
            XCTAssertEqual(ticks.first, 0)
            XCTAssertEqual(ticks.last, count - 1)
            XCTAssertLessThanOrEqual(ticks.count, 6)
            for idx in 1..<ticks.count {
                XCTAssertGreaterThanOrEqual(
                    ticks[idx] - ticks[idx - 1],
                    2,
                    "Adjacent X-axis labels must stay separated for count=\(count): \(ticks)"
                )
            }
        }

        // 12M window must never render index 10 ("Oct") right next to index 11 ("Nov")
        let ticks12 = SightingsTimelineWindow.xAxisTickIndices(count: 12)
        XCTAssertEqual(ticks12.count, 6)
        XCTAssertFalse(ticks12.contains(10))
        XCTAssertEqual(SightingsTimelineWindow.shortMonth("2026-11"), "Nov")
    }

    func testSightingsTimelineScrubberViewportPillAndDragMath() async throws {
        let repo = DemoTurtleRepository(dataset: .panAsiaSuperAccount)
        let snapshot24 = try await repo.dashboard(query: .lastMonths(24))

        // 1Y inside 24M => proportional 50% viewport pill anchored to right edge at Now
        let atNow = SightingsTimelineWindow(allMonths: snapshot24.months, span: .oneYear, endOffsetFromNow: 0)
        let nowFrame = atNow.scrubberPillFrame(trackWidth: 300, minimumPillWidth: 44)
        XCTAssertEqual(nowFrame.width, 150, accuracy: 0.01)
        XCTAssertEqual(nowFrame.leading + nowFrame.width, 300, accuracy: 0.01)

        // Minimum pill width enforced on narrow tracks
        let narrowFrame = atNow.scrubberPillFrame(trackWidth: 60, minimumPillWidth: 44)
        XCTAssertEqual(narrowFrame.width, 44, accuracy: 0.01)
        XCTAssertEqual(narrowFrame.leading + narrowFrame.width, 60, accuracy: 0.01)

        // Oldest offset reaches leading == 0
        let oldest = SightingsTimelineWindow(allMonths: snapshot24.months, span: .oneYear, endOffsetFromNow: atNow.maxOffset)
        let oldestFrame = oldest.scrubberPillFrame(trackWidth: 300, minimumPillWidth: 44)
        XCTAssertEqual(oldestFrame.leading, 0, accuracy: 0.01)

        // Click/drag mapping along track and relative drag deltas
        XCTAssertEqual(atNow.offset(forTrackCenterX: 0, trackWidth: 300), atNow.maxOffset)
        XCTAssertEqual(atNow.offset(forTrackCenterX: 300, trackWidth: 300), 0)
        XCTAssertEqual(atNow.offset(fromStartingOffset: 0, dragDeltaX: -150, trackWidth: 300), atNow.maxOffset)
        XCTAssertEqual(oldest.offset(fromStartingOffset: atNow.maxOffset, dragDeltaX: 150, trackWidth: 300), 0)
    }

    func testMonotoneCubicControlPointsKeepFlatZeroRunsFlatWithoutUndershoot() {
        let baselineY: CGFloat = 140
        let topY: CGFloat = 10
        let values: [CGFloat] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 14, 57]
        let points: [CGPoint] = values.enumerated().map { idx, v in
            let x = CGFloat(idx) * 40
            let y = baselineY - (baselineY - topY) * (v / 57.0)
            return CGPoint(x: x, y: y)
        }

        let controls = SightingsTimelineWindow.monotoneCubicControlPoints(for: points)
        XCTAssertEqual(controls.count, points.count - 1)

        // Flat zero run (0...9) stays strictly on baselineY with zero dip below 0
        for i in 0..<9 {
            XCTAssertEqual(controls[i].cp1.y, baselineY, accuracy: 0.001)
            XCTAssertEqual(controls[i].cp2.y, baselineY, accuracy: 0.001)
        }

        // Transition out of flat 0 leaves horizontally and never dips below baselineY or overshoots next point
        XCTAssertEqual(controls[9].cp1.y, baselineY, accuracy: 0.001)
        XCTAssertLessThanOrEqual(controls[9].cp2.y, baselineY + 0.001)
        XCTAssertGreaterThanOrEqual(controls[9].cp2.y, points[10].y - 0.001)

        // Rising segment 14 -> 57 stays strictly within [y11, y10] with zero overshoot above peak
        XCTAssertLessThanOrEqual(controls[10].cp1.y, points[10].y + 0.001)
        XCTAssertGreaterThanOrEqual(controls[10].cp1.y, points[11].y - 0.001)
        XCTAssertLessThanOrEqual(controls[10].cp2.y, points[10].y + 0.001)
        XCTAssertGreaterThanOrEqual(controls[10].cp2.y, points[11].y - 0.001)
    }
}
