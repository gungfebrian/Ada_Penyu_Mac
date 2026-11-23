import Foundation
import SwiftUI

// MARK: - Widget Categories & Spans

enum DashboardWidgetCategory: String, CaseIterable, Identifiable, Codable, Hashable {
    case overview = "Overview"
    case populationEcology = "Scientist"
    case fieldAndCatalog = "Field Ranger"
    case healthAndTriage = "Vet & Health"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .populationEcology: "scope"
        case .fieldAndCatalog: "map"
        case .healthAndTriage: "cross.case"
        }
    }

    var matchingPreset: DashboardRolePreset {
        switch self {
        case .overview: .generalOverview
        case .populationEcology: .populationEcology
        case .fieldAndCatalog: .fieldRanger
        case .healthAndTriage: .healthTriage
        }
    }
}

enum DashboardWidgetSpan: String, CaseIterable, Identifiable, Codable, Hashable {
    case half
    case full

    var id: String { rawValue }

    var label: String {
        switch self {
        case .half: "Half width"
        case .full: "Full width"
        }
    }

    var icon: String {
        switch self {
        case .half: "rectangle.lefthalf.filled"
        case .full: "rectangle.fill"
        }
    }

    var toggled: DashboardWidgetSpan {
        self == .half ? .full : .half
    }
}

// MARK: - Widget Catalog Kinds

enum DashboardWidgetKind: String, CaseIterable, Identifiable, Codable, Hashable {
    case kpiOverview = "kpi_overview"
    case notSureQueue = "not_sure_queue"
    case sightingsTrend = "sightings_trend"
    case geographicMap = "geographic_map"
    case injuryTriage = "injury_triage"
    case recaptureAnalysis = "recapture_analysis"
    case habitatHotspots = "habitat_hotspots"
    case photoIDReadiness = "photo_id_readiness"
    case conditionBreakdown = "condition_breakdown"
    case speciesBreakdown = "species_breakdown"
    case recentSightings = "recent_sightings"
    case favoritesWatch = "favorites_watch"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .kpiOverview: "Observed Summary"
        case .notSureQueue: "Not Sure Queue"
        case .sightingsTrend: "Sightings Trend"
        case .geographicMap: "Coastal Map"
        case .injuryTriage: "Health Triage"
        case .recaptureAnalysis: "Mark-Recapture"
        case .habitatHotspots: "Reef Hotspots"
        case .photoIDReadiness: "Photo-ID Coverage"
        case .conditionBreakdown: "Body Condition"
        case .speciesBreakdown: "Species Observed"
        case .recentSightings: "Recent Resightings"
        case .favoritesWatch: "Watchlist"
        }
    }

    /// Explains the specific operational or scientific question this widget answers.
    var questionAnswered: String {
        switch self {
        case .kpiOverview:
            "What is our current population size, recapture rate, active injury count, and photo-ID readiness?"
        case .notSureQueue:
            "Which sightings were marked 'Not Sure' by field rangers and need scale-junction verification?"
        case .sightingsTrend:
            "Are field encounters increasing seasonally, and are we discovering new individuals or resighting known ones?"
        case .geographicMap:
            "Where are sea turtle encounters spatially distributed across our monitored coastal coordinates?"
        case .injuryTriage:
            "Which injured or scarred individuals need priority follow-up and where were they last observed?"
        case .recaptureAnalysis:
            "What share of our catalogued population are resident repeat-sightings versus single-encounter transients?"
        case .habitatHotspots:
            "Which beaches and reef sites have the highest encounter density and where are injuries clustering?"
        case .photoIDReadiness:
            "Which individuals are missing Left or Right profile photos needed for dual-side MiewID & I3S matching?"
        case .conditionBreakdown:
            "What proportion of catalogued turtles are Healthy, Scarred, or Injured across the monitored population?"
        case .speciesBreakdown:
            "How is our monitored population distributed by species, and which species has the highest resighting intensity?"
        case .recentSightings:
            "What were the latest field logs recorded by rangers and what condition were those individuals in?"
        case .favoritesWatch:
            "What is the latest status and location of the specific individuals my account is personally tracking?"
        }
    }

    var shortSummary: String {
        switch self {
        case .kpiOverview:
            "Observed population & recorded sightings banner plus recapture, triage, and dual-side photo KPIs."
        case .notSureQueue:
            "Queue of encounters marked 'Not Sure' with pre-loaded scale polygons and junction comparison."
        case .sightingsTrend:
            "12-month encounter curve with discovery vs. resighting ratio and species filtering."
        case .geographicMap:
            "Interactive coastal map preview of recent sighting pins with one-click jump to the full Map."
        case .injuryTriage:
            "Actionable queue of injured and scarred individuals with last known reef location."
        case .recaptureAnalysis:
            "Cohort breakdown (Resident 5+, Returning 2–4, Transient 1x) and top recaptured individuals."
        case .habitatHotspots:
            "Site-by-site ranking of turtle density, encounter volume, and localized injury pressure."
        case .photoIDReadiness:
            "Audit of Left + Right profile completeness with a checklist of turtles missing a side."
        case .conditionBreakdown:
            "Population health distribution bar and interactive condition filter shortcuts."
        case .speciesBreakdown:
            "Species counts, total sightings, and average encounters per individual."
        case .recentSightings:
            "Chronological feed of recent field encounters and resightings with condition filter pills."
        case .favoritesWatch:
            "Quick status monitor for individuals on your account's watchlist."
        }
    }

    var category: DashboardWidgetCategory {
        switch self {
        case .kpiOverview, .notSureQueue:
            .overview
        case .photoIDReadiness, .recaptureAnalysis, .speciesBreakdown, .sightingsTrend:
            .populationEcology
        case .injuryTriage, .conditionBreakdown:
            .healthAndTriage
        case .geographicMap, .habitatHotspots, .recentSightings, .favoritesWatch:
            .fieldAndCatalog
        }
    }

    var icon: String {
        switch self {
        case .kpiOverview: "gauge.with.dots.needle.67percent"
        case .notSureQueue: "questionmark.diamond.fill"
        case .sightingsTrend: "chart.xyaxis.line"
        case .geographicMap: "map.fill"
        case .injuryTriage: "cross.case.fill"
        case .recaptureAnalysis: "arrow.triangle.2.circlepath.circle"
        case .habitatHotspots: "mappin.and.ellipse"
        case .photoIDReadiness: "viewfinder.rectangular"
        case .conditionBreakdown: "heart.text.square"
        case .speciesBreakdown: "tortoise.fill"
        case .recentSightings: "clock.arrow.circlepath"
        case .favoritesWatch: "bookmark.fill"
        }
    }

    var defaultSpan: DashboardWidgetSpan {
        switch self {
        case .kpiOverview:
            .full
        case .notSureQueue, .sightingsTrend, .geographicMap, .injuryTriage, .recaptureAnalysis, .habitatHotspots,
             .photoIDReadiness, .conditionBreakdown, .speciesBreakdown, .recentSightings, .favoritesWatch:
            .half
        }
    }
}

// MARK: - Role Presets & Demo Account Personas

enum DashboardRolePreset: String, CaseIterable, Identifiable, Codable, Hashable {
    case generalOverview = "general_overview"
    case populationEcology = "population_ecology"
    case fieldRanger = "field_ranger"
    case healthTriage = "health_triage"

    static let scientist: DashboardRolePreset = .populationEcology

    var id: String { rawValue }

    var title: String {
        switch self {
        case .generalOverview: "Owner"
        case .populationEcology: "Scientist"
        case .fieldRanger: "Field Ranger"
        case .healthTriage: "Vet & Health"
        }
    }

    var hierarchyBadge: String {
        switch self {
        case .generalOverview: "Tier 1 · Organization Owner"
        case .populationEcology: "Tier 2 · Scientist"
        case .fieldRanger: "Tier 3 · Field Patrol"
        case .healthTriage: "Tier 3 · Clinical"
        }
    }

    var subtitle: String {
        switch self {
        case .generalOverview:
            "Organization Owner: summary banner, Not Sure review queue, resightings, trend, coastal map, and species."
        case .populationEcology:
            "Scientist hierarchy: population summary, Not Sure review queue, Photo-ID readiness, mark-recapture, and species."
        case .fieldRanger:
            "Patrol hierarchy: full-width coastal map, recent resightings, reef hotspot density, and missing photo sides."
        case .healthTriage:
            "Clinical hierarchy: full-width injured & scarred triage queue, body condition breakdown, and reef injury hotspots."
        }
    }

    var icon: String {
        switch self {
        case .generalOverview: "building.2.fill"
        case .populationEcology: "scope"
        case .fieldRanger: "binoculars.fill"
        case .healthTriage: "cross.case.fill"
        }
    }

    var defaultWidgets: [DashboardWidgetItem] {
        switch self {
        case .generalOverview:
            return [
                DashboardWidgetItem(kind: .kpiOverview, span: .full),
                DashboardWidgetItem(kind: .sightingsTrend, span: .half),
                DashboardWidgetItem(kind: .geographicMap, span: .half),
                DashboardWidgetItem(kind: .recentSightings, span: .half),
                DashboardWidgetItem(kind: .speciesBreakdown, span: .half),
                DashboardWidgetItem(kind: .notSureQueue, span: .half),
                DashboardWidgetItem(kind: .photoIDReadiness, span: .half),
            ]
        case .populationEcology:
            return [
                DashboardWidgetItem(kind: .kpiOverview, span: .full),
                DashboardWidgetItem(kind: .notSureQueue, span: .half),
                DashboardWidgetItem(kind: .photoIDReadiness, span: .half),
                DashboardWidgetItem(kind: .recaptureAnalysis, span: .half),
                DashboardWidgetItem(kind: .speciesBreakdown, span: .half),
                DashboardWidgetItem(kind: .sightingsTrend, span: .half),
                DashboardWidgetItem(kind: .conditionBreakdown, span: .half),
            ]
        case .fieldRanger:
            return [
                DashboardWidgetItem(kind: .geographicMap, span: .full),
                DashboardWidgetItem(kind: .recentSightings, span: .half),
                DashboardWidgetItem(kind: .habitatHotspots, span: .half),
                DashboardWidgetItem(kind: .photoIDReadiness, span: .half),
                DashboardWidgetItem(kind: .favoritesWatch, span: .half),
            ]
        case .healthTriage:
            return [
                DashboardWidgetItem(kind: .injuryTriage, span: .full, metricMode: "all_triage"),
                DashboardWidgetItem(kind: .conditionBreakdown, span: .half),
                DashboardWidgetItem(kind: .habitatHotspots, span: .half),
                DashboardWidgetItem(kind: .geographicMap, span: .half),
                DashboardWidgetItem(kind: .recentSightings, span: .half),
            ]
        }
    }
}

/// Allows switching between distinct account hierarchy roles in Demo mode
/// so each account's personalized widget workspace can be demonstrated and persisted independently.
enum DemoDashboardPersona: String, CaseIterable, Identifiable, Codable, Hashable {
    case worldSuperNetwork = "world_super_network"
    case demoResearcher = "demo_researcher"
    case superAsiaNetwork = "super_asia_network"
    case ecologistAmina = "ecologist_amina"
    case rangerWayan = "ranger_wayan"
    case vetPutu = "vet_putu"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .worldSuperNetwork: "World Super Account"
        case .demoResearcher: "Demo Owner"
        case .superAsiaNetwork: "Asia Super Account"
        case .ecologistAmina: "Dr. Amina Saleh"
        case .rangerWayan: "Ranger Wayan"
        case .vetPutu: "Dr. Putu Wijaya"
        }
    }

    var roleLabel: String {
        switch self {
        case .worldSuperNetwork: "Tier 1 · Global Ocean Network"
        case .demoResearcher: "Tier 1 · Organization Owner"
        case .superAsiaNetwork: "Tier 1 · SE Asia & India Network"
        case .ecologistAmina: "Tier 2 · Marine Scientist"
        case .rangerWayan: "Tier 3 · Field Patrol Ranger"
        case .vetPutu: "Tier 3 · Veterinary Triage"
        }
    }

    var email: String {
        switch self {
        case .worldSuperNetwork: "world-super@seaturtle.org"
        case .demoResearcher: "owner@seaturtle.org"
        case .superAsiaNetwork: "asia-super@seaturtle.org"
        case .ecologistAmina: "amina@seaturtle.org"
        case .rangerWayan: "wayan@seaturtle.org"
        case .vetPutu: "putu@seaturtle.org"
        }
    }

    var organizationName: String {
        switch self {
        case .worldSuperNetwork: "Global Sea Turtle Network"
        case .superAsiaNetwork: "Indo-Pacific Turtle Network"
        default: "Sea Turtle Group"
        }
    }

    var defaultPreset: DashboardRolePreset {
        switch self {
        case .worldSuperNetwork, .demoResearcher, .superAsiaNetwork: .generalOverview
        case .ecologistAmina: .populationEcology
        case .rangerWayan: .fieldRanger
        case .vetPutu: .healthTriage
        }
    }

    var demoDataset: DemoTurtleRepository.Dataset {
        switch self {
        case .worldSuperNetwork: .worldSuperAccount
        case .superAsiaNetwork: .panAsiaSuperAccount
        default: .baliBaseline
        }
    }

    var accountStorageKey: String {
        "demo:\(rawValue)"
    }
}

// MARK: - Widget Instance & Account Layout Configuration

struct DashboardWidgetItem: Identifiable, Codable, Hashable {
    var id: UUID
    var kind: DashboardWidgetKind
    var span: DashboardWidgetSpan
    var conditionFilter: String?
    var metricMode: String?

    init(
        id: UUID = UUID(),
        kind: DashboardWidgetKind,
        span: DashboardWidgetSpan? = nil,
        conditionFilter: String? = nil,
        metricMode: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.span = span ?? kind.defaultSpan
        self.conditionFilter = conditionFilter
        self.metricMode = metricMode
    }
}

struct DashboardAccountLayout: Codable, Hashable {
    var accountKey: String
    var activePreset: DashboardRolePreset?
    var widgets: [DashboardWidgetItem]
    var updatedAt: Date

    static func makeDefault(for accountKey: String, preset: DashboardRolePreset = .generalOverview) -> DashboardAccountLayout {
        DashboardAccountLayout(
            accountKey: accountKey,
            activePreset: preset,
            widgets: preset.defaultWidgets,
            updatedAt: Date()
        )
    }
}

// MARK: - Per-Account Persistence Store

final class DashboardLayoutStore {
    static let storageKey = "ada.dashboard.accountLayouts.v5"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadLayout(for accountKey: String, defaultPreset: DashboardRolePreset = .generalOverview) -> DashboardAccountLayout {
        let all = loadAllLayouts()
        if let existing = all[accountKey] {
            return existing
        }
        let created = DashboardAccountLayout.makeDefault(for: accountKey, preset: defaultPreset)
        saveLayout(created)
        return created
    }

    func saveLayout(_ layout: DashboardAccountLayout) {
        var all = loadAllLayouts()
        all[layout.accountKey] = layout
        if let data = try? JSONEncoder().encode(all) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    func resetLayout(for accountKey: String, to preset: DashboardRolePreset) -> DashboardAccountLayout {
        let layout = DashboardAccountLayout.makeDefault(for: accountKey, preset: preset)
        saveLayout(layout)
        return layout
    }

    private func loadAllLayouts() -> [String: DashboardAccountLayout] {
        guard let data = defaults.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([String: DashboardAccountLayout].self, from: data) else {
            return [:]
        }
        return decoded
    }
}

// MARK: - Deep Conservation Analytics Engine for Widgets

struct DashboardAnalytics {
    struct RecaptureCohort: Identifiable, Hashable {
        let id: String
        let title: String
        let subtitle: String
        let count: Int
        let fraction: Double
        let tint: Color
    }

    struct LocationHotspot: Identifiable, Hashable {
        let id: String
        let location: String
        let individualCount: Int
        let totalSightings: Int
        let injuredOrScarredCount: Int
        let speciesCount: Int
    }

    struct PhotoCoverageBreakdown: Hashable {
        struct IncompleteItem: Identifiable, Hashable {
            let turtle: Turtle
            let missingDescription: String
            var id: String { turtle.id }
        }

        let bothSidesCount: Int
        let leftOnlyCount: Int
        let rightOnlyCount: Int
        let missingBothCount: Int
        let totalCount: Int
        let incompleteIndividuals: [IncompleteItem]

        var dualSidePercent: Int {
            guard totalCount > 0 else { return 0 }
            return Int((Double(bothSidesCount) / Double(totalCount) * 100).rounded())
        }
    }

    struct ConditionDistributionItem: Identifiable, Hashable {
        let condition: TurtleCondition
        let count: Int
        let fraction: Double
        var id: String { condition.id }
    }

    let totalIndividuals: Int
    let totalCatalogSightings: Int
    let meanSightingsPerIndividual: Double
    let recapturedIndividualsCount: Int
    let recaptureRatePercent: Int
    let cohorts: [RecaptureCohort]
    let topRecapturedTurtles: [Turtle]

    let injuredTurtles: [Turtle]
    let scarredTurtles: [Turtle]
    let triageTurtles: [Turtle]
    let conditionDistribution: [ConditionDistributionItem]

    let hotspots: [LocationHotspot]
    let photoCoverage: PhotoCoverageBreakdown

    let sightingsLast12Months: Int
    let newIndividualsLast12Months: Int
    let resightingEventsLast12Months: Int
    let resightingSharePercent: Int

    static func compute(
        snapshot: DashboardSnapshot,
        turtles: [Turtle],
        sightings: [Sighting]
    ) -> DashboardAnalytics {
        let totalInd = turtles.count
        let totalSightings = turtles.reduce(0) { $0 + max($1.sightings, 0) }
        let meanSightings = totalInd > 0 ? Double(totalSightings) / Double(totalInd) : 0

        let residents = turtles.filter { $0.sightings >= 5 }
        let returning = turtles.filter { (2...4).contains($0.sightings) }
        let transients = turtles.filter { $0.sightings <= 1 }
        let recapturedCount = residents.count + returning.count
        let recapturePct = totalInd > 0 ? Int((Double(recapturedCount) / Double(totalInd) * 100).rounded()) : 0

        let denom = Double(max(totalInd, 1))
        let cohorts: [RecaptureCohort] = [
            RecaptureCohort(
                id: "resident",
                title: "Resident (5+ sightings)",
                subtitle: "High site fidelity individuals",
                count: residents.count,
                fraction: Double(residents.count) / denom,
                tint: AdaColors.green
            ),
            RecaptureCohort(
                id: "returning",
                title: "Returning (2–4 sightings)",
                subtitle: "Recaptured across multiple patrols",
                count: returning.count,
                fraction: Double(returning.count) / denom,
                tint: AdaColors.accent
            ),
            RecaptureCohort(
                id: "transient",
                title: "Single Encounter (1 sighting)",
                subtitle: "Newly enrolled or transient visitors",
                count: transients.count,
                fraction: Double(transients.count) / denom,
                tint: AdaColors.orange
            ),
        ]

        let topRecaptured = turtles.sorted {
            if $0.sightings != $1.sightings { return $0.sightings > $1.sightings }
            return $0.displayName < $1.displayName
        }

        let injured = turtles.filter { $0.condition == .injured }
        let scarred = turtles.filter { $0.condition == .scarred }
        let triage = (injured + scarred)

        let conditionOrder: [TurtleCondition] = [.healthy, .scarred, .injured, .unknown]
        let conditionDist = conditionOrder.map { cond in
            let count = turtles.filter { $0.condition == cond }.count
            return ConditionDistributionItem(
                condition: cond,
                count: count,
                fraction: totalInd > 0 ? Double(count) / Double(totalInd) : 0
            )
        }

        // Habitat hotspots grouped by location
        let groupedByLocation = Dictionary(grouping: turtles.filter { !$0.location.isEmpty && $0.location != "Not recorded" }, by: \.location)
        let hotspots: [LocationHotspot] = groupedByLocation.map { location, group in
            let sightingsSum = group.reduce(0) { $0 + max($1.sightings, 1) }
            let triageAtSite = group.filter { $0.condition == .injured || $0.condition == .scarred }.count
            let uniqueSpecies = Set(group.map(\.species)).count
            return LocationHotspot(
                id: location,
                location: location,
                individualCount: group.count,
                totalSightings: sightingsSum,
                injuredOrScarredCount: triageAtSite,
                speciesCount: uniqueSpecies
            )
        }
        .sorted {
            if $0.totalSightings != $1.totalSightings { return $0.totalSightings > $1.totalSightings }
            if $0.injuredOrScarredCount != $1.injuredOrScarredCount { return $0.injuredOrScarredCount > $1.injuredOrScarredCount }
            return $0.location < $1.location
        }

        // Photo-ID coverage analysis
        var both = 0
        var leftOnly = 0
        var rightOnly = 0
        var missingBoth = 0
        var incomplete: [PhotoCoverageBreakdown.IncompleteItem] = []

        for turtle in turtles {
            let hasLeft = (turtle.leftPhotoURL?.isEmpty == false)
            let hasRight = (turtle.rightPhotoURL?.isEmpty == false)
            switch (hasLeft, hasRight) {
            case (true, true):
                both += 1
            case (true, false):
                leftOnly += 1
                incomplete.append(.init(turtle: turtle, missingDescription: "Missing Right profile"))
            case (false, true):
                rightOnly += 1
                incomplete.append(.init(turtle: turtle, missingDescription: "Missing Left profile"))
            case (false, false):
                missingBoth += 1
                incomplete.append(.init(turtle: turtle, missingDescription: "Missing Left & Right profiles"))
            }
        }

        let photoCoverage = PhotoCoverageBreakdown(
            bothSidesCount: both,
            leftOnlyCount: leftOnly,
            rightOnlyCount: rightOnly,
            missingBothCount: missingBoth,
            totalCount: totalInd,
            incompleteIndividuals: incomplete
        )

        let sightings12m = snapshot.months.reduce(0) { $0 + $1.sightings }
        let newInd12m = snapshot.months.reduce(0) { $0 + $1.newIndividuals }
        let resightings12m = max(0, sightings12m - newInd12m)
        let resightingPct = sightings12m > 0 ? Int((Double(resightings12m) / Double(sightings12m) * 100).rounded()) : 0

        return DashboardAnalytics(
            totalIndividuals: totalInd,
            totalCatalogSightings: totalSightings,
            meanSightingsPerIndividual: meanSightings,
            recapturedIndividualsCount: recapturedCount,
            recaptureRatePercent: recapturePct,
            cohorts: cohorts,
            topRecapturedTurtles: topRecaptured,
            injuredTurtles: injured,
            scarredTurtles: scarred,
            triageTurtles: triage,
            conditionDistribution: conditionDist,
            hotspots: hotspots,
            photoCoverage: photoCoverage,
            sightingsLast12Months: sightings12m,
            newIndividualsLast12Months: newInd12m,
            resightingEventsLast12Months: resightings12m,
            resightingSharePercent: resightingPct
        )
    }
}
