import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

enum SettingsDetailTarget: Equatable, Identifiable {
    case overview
    case detail(SettingsDetailRoute)

    var id: String {
        switch self {
        case .overview: "overview"
        case .detail(let route): route.id
        }
    }
}

@MainActor
final class AppStore: ObservableObject {
    let organizationKeySettings: OrganizationAPIKeySettings
    let passwordSecurity: PasswordSecurityModel
    let organisationSettings: OrganisationSettingsModel
    let localization: LocalizationManager
    let contourPreferences: DesktopContourPreferencesStore
    @Published private var currentSection: AppSection = .dashboard
    @Published var settingsDetail: SettingsDetailRoute? = nil
    @Published var pendingSettingsDetailTarget: SettingsDetailTarget? = nil
    var activeSection: AppSection {
        get { currentSection }
        set { requestNavigation(to: newValue) }
    }
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
    @Published private(set) var analyticsTurtles: [Turtle] = []
    @Published private(set) var favoriteTurtles: [Turtle] = []
    @Published private(set) var sightings: [Sighting] = []
    @Published private(set) var dashboard: DashboardSnapshot = DashboardSnapshot(months: [], species: [])
    @Published private(set) var trendMonths: [DashboardSnapshot.Month] = []
    @Published var selectedTurtle: Turtle?
    @Published private(set) var detailOrigin: AppSection = .individuals
    @Published private(set) var selectedDetail: TurtleDetailData?
    @Published private(set) var isDetailLoading = false
    @Published private(set) var detailError: String?
    @Published private(set) var totalIndividuals = 0
    @Published private(set) var isLoading = false
    @Published private(set) var isExporting = false
    @Published private(set) var isImporting = false
    @Published private(set) var importProgressText: String?
    @Published private(set) var lastError: String?
    @Published private(set) var statusMessage: String?
    @Published private(set) var sessionNotice: String?
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
    @Published var requestedReviewLayoutMode: ScientistComparisonLayoutMode = .contours
    @Published var requestedEscalatedCaseID: UUID? = nil
    @Published private(set) var escalatedNotSureCases: [EscalatedNotSureCase] = []
    /// Waiting sightings from `GET /api/v2/logs?identified_only=false`, using the iOS waiting rule.
    @Published private(set) var waitingLogs: [OrganizationLog] = []
    @Published private(set) var isOpeningWaitingLog = false
    @Published private(set) var notSureQueueError: String?
    @Published private(set) var isSyncingMobileQueue = false
    @Published private(set) var mobileReviewRows: [MobileReviewSighting] = []
    @Published private(set) var hasMoreMobileReviews = false
    private var mobileReviewOffset = 0
    private var mobileReviewLoaded = false
    private struct PendingReviewAttempt {
        let command: ReviewRematchCommand
        let crop: Data?
    }
    private var pendingReviewAttempts: [UUID: PendingReviewAttempt] = [:]
    private var pendingReviewRejections: [String: ReviewRejectionCommand] = [:]
    private var pendingReviewIdentities: [String: ReviewIdentityCommand] = [:]
    private var pendingReviewNewTurtles: [String: ReviewNewTurtleCommand] = [:]
    private var reviewCandidateRecords: [UUID: [ReviewMatchResult.Candidate]] = [:]
    private var reviewPageOffsets: [UUID: Int] = [:]
    private var reviewOperationIDs: [UUID: UUID] = [:]
    private var reviewQueryEvidence: [UUID: [ReviewQueryEvidence]] = [:]

    @Published var isReviewPracticePresented = false
    @Published var reviewNavigationTrigger = UUID()
    @Published private(set) var apiBaseURLString: String
    @Published private(set) var isAuthenticated = false
    @Published private(set) var isRestoring = false
    @Published private(set) var sessionGeneration = UUID()

    private var client: APIClient
    private var repository: TurtleRepository
    private let dashboardLayoutStore: DashboardLayoutStore
    private let reviewJournal: NotSureReviewJournal
    private var loadedReviewScope: String?
    private let hasInjectedRepository: Bool
    private var hasBootstrapped = false
    private var searchTask: Task<Void, Never>?
    private var mapTask: Task<Void, Never>?
    private var demoReloadTask: Task<Void, Never>?
    private var individualRequest = 0
    private var mapRequest = 0
    private var dashboardRequest = 0
    private var allRequest = 0
    private var photoCache: [String: NSImage] = [:]
    @Published private(set) var reviewThumbnails: [String: NSImage] = [:]
    private var photoDelivery: PhotoDelivery?
    private var reviewContexts: [UUID: ReviewPhotoContext] = [:]
    private var reviewReferences: [UUID: [String: PhotoReference]] = [:]
    private var reviewSideReferences: [UUID: [String: PhotoReference]] = [:]
    private var reviewReferenceEpoch: [UUID: Int] = [:]
    private lazy var reviewPhotoMetadata = ReviewPhotoMetadataStore { [weak self] context in
        guard let self else { throw CancellationError() }
        return try await self.repository.reviewPhotoMetadata(logID: context.logID, attemptID: context.attemptID)
    }
    private var queueRenewal: Task<Void, Never>?
    private var queuePhotoEpoch = 0

    private func deliveryLoader() -> PhotoDelivery {
        let scope = "\(apiBaseURLString)-\(sessionGeneration.uuidString)-\(notSureReviewScope ?? "")"
        if let current = photoDelivery, current.scope == scope { return current }
        photoDelivery?.clear()
        let loader = PhotoDelivery(scope: scope) { [weak self] path in
            guard let self else { throw CancellationError() }
            let data = try await self.repository.fetchPhotoData(pathOrURL: path)
            guard NSImage(data: data) != nil else { throw NotSureReviewError.invalidPhoto }
            return data
        }
        photoDelivery = loader
        return loader
    }

    private var keySettingsObservation: AnyCancellable?
    private var localizationObservation: AnyCancellable?
    private var contourPreferencesObservation: AnyCancellable?
    var canLoadRecords: Bool { isAuthenticated || hasInjectedRepository }

    init(
        repository: TurtleRepository? = nil,
        client: APIClient? = nil,
        dashboardLayoutStore: DashboardLayoutStore? = nil,
        reviewJournal: NotSureReviewJournal? = nil,
        localization: LocalizationManager? = nil,
        contourPreferences: DesktopContourPreferencesStore? = nil
    ) {
        let client = client ?? APIClient()
        self.client = client
        self.organizationKeySettings = OrganizationAPIKeySettings(client: client)
        self.passwordSecurity = PasswordSecurityModel(client: client)
        self.organisationSettings = OrganisationSettingsModel(client: client)
        self.localization = localization ?? LocalizationManager()
        self.contourPreferences = contourPreferences ?? DesktopContourPreferencesStore()
        self.dashboardLayoutStore = dashboardLayoutStore ?? DashboardLayoutStore()
        self.reviewJournal = reviewJournal ?? NotSureReviewJournal()
        self.apiBaseURLString = client.baseURL.absoluteString
        self.hasInjectedRepository = repository != nil
        self.repository = repository ?? RemoteTurtleRepository(client: client)
        keySettingsObservation = organizationKeySettings.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
        localizationObservation = self.localization.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
        contourPreferencesObservation = self.contourPreferences.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
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

    func requestNavigation(to section: AppSection) {
        guard section != currentSection else { return }
        if currentSection == .settings {
            guard organizationKeySettings.requestLeave(to: section) else { return }
            organizationKeySettings.leave()
            settingsDetail = nil
            pendingSettingsDetailTarget = nil
        }
        dismissDetail()
        currentSection = section
    }

    func openSettings() {
        guard isAuthenticated else { return }
        if currentSection == .settings {
            if settingsDetail != nil {
                requestSettingsDetail(nil)
            }
            return
        }
        requestNavigation(to: .settings)
    }

    @discardableResult
    func requestSettingsDetail(_ route: SettingsDetailRoute?) -> Bool {
        guard route != settingsDetail else { return true }
        if settingsDetail == .developerAPIKey && route != .developerAPIKey {
            if organizationKeySettings.isChanging {
                return false
            }
            if organizationKeySettings.newSecret != nil && !organizationKeySettings.hasSavedSecret {
                pendingSettingsDetailTarget = route.map(SettingsDetailTarget.detail) ?? .overview
                return false
            }
            organizationKeySettings.leave()
        }
        pendingSettingsDetailTarget = nil
        settingsDetail = route
        return true
    }

    @discardableResult
    func requestSettingsBack() -> Bool {
        switch settingsDetail {
        case .addRanger, .rangerDetails:
            return requestSettingsDetail(.manageRangers)
        case .none:
            return true
        default:
            return requestSettingsDetail(nil)
        }
    }

    func discardKeyAndCompleteSettingsDetailNavigation() {
        guard let target = pendingSettingsDetailTarget else { return }
        pendingSettingsDetailTarget = nil
        organizationKeySettings.acknowledgeSaved()
        organizationKeySettings.leave()
        switch target {
        case .overview:
            settingsDetail = nil
        case .detail(let route):
            settingsDetail = route
        }
    }

    func cancelPendingSettingsDetailNavigation() {
        pendingSettingsDetailTarget = nil
    }

    func discardKeyAndNavigate(to destination: AppSection? = nil) {
        guard let destination = destination ?? organizationKeySettings.pendingDestination else { return }
        organizationKeySettings.acknowledgeSaved()
        requestNavigation(to: destination)
    }

    var currentLiveUser: AppUser? {
        isDemoBypassActive ? nil : client.account
    }

    var isLiveOwner: Bool {
        currentLiveUser?.role == .owner && currentLiveUser?.organisationID != nil
    }

    var isLiveRanger: Bool {
        currentLiveUser?.role == .ranger && currentLiveUser?.organisationID != nil
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
        organizationKeySettings.configure(client: client, user: client.account, isDemo: isDemoBypassActive)
        passwordSecurity.configure(client: client, user: client.account, isDemo: isDemoBypassActive)
        organisationSettings.configure(client: client, user: client.account, isDemo: isDemoBypassActive)
        contourPreferences.configure(
            baseURLString: apiBaseURLString,
            user: client.account,
            isDemo: isDemoBypassActive,
            demoPersonaKey: demoPersona.accountStorageKey
        )
        if isDemoBypassActive {
            isAuthenticated = true
            authEmail = demoPersona.email
            accountName = demoPersona.displayName
            accountOrganization = demoPersona.organizationName
            accountRoleLabel = demoPersona.roleLabel
        } else {
            isAuthenticated = client.account != nil
            authEmail = client.account?.email ?? ""
            accountName = client.account?.displayName ?? "Researcher"
            accountOrganization = client.account?.organisationName ?? ""
            accountRoleLabel = client.account?.role == .ranger ? "Field Patrol Ranger" : "Organization Owner"
        }
        syncDashboardLayoutForCurrentAccount()
        if loadedReviewScope != notSureReviewScope {
            reloadNotSureQueue()
        }
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
        let dataset = persona.demoDataset
        repository = DemoTurtleRepository(dataset: dataset)
        if persona == .superAsiaNetwork || persona == .worldSuperNetwork {
            selectedMapPeriod = .allTime
        }
        updateAccount()
        let generation = sessionGeneration
        demoReloadTask?.cancel()
        demoReloadTask = Task {
            guard sessionGeneration == generation, !Task.isCancelled else { return }
            await reloadAll()
        }
    }

    func selectDemoPersona(_ persona: DemoDashboardPersona) {
        let datasetChanged = demoPersona.demoDataset != persona.demoDataset
        demoPersona = persona
        isEditingDashboardWidgets = false
        if datasetChanged && isDemoBypassActive {
            clearPrivateState(keepDemoMode: true)
            repository = DemoTurtleRepository(dataset: persona.demoDataset)
            if persona == .superAsiaNetwork || persona == .worldSuperNetwork {
                selectedMapPeriod = .allTime
            }
            updateAccount()
            let generation = sessionGeneration
            demoReloadTask?.cancel()
            demoReloadTask = Task {
                guard sessionGeneration == generation, !Task.isCancelled else { return }
                await reloadAll()
            }
        } else {
            updateAccount()
        }
    }

    var pendingNotSureCases: [EscalatedNotSureCase] {
        escalatedNotSureCases.filter { $0.decision == .pending }
    }

    /// Sidebar and catalog count. Same pending set the Not Sure inbox shows.
    var notSureAttentionCount: Int {
        let reviewed = Set(escalatedNotSureCases.filter { $0.decision != .pending }.compactMap(\.sourceLogID))
        let remoteIDs = Set(mobileReviewRows.map(\.id))
        let remotePending = mobileReviewRows.filter { !reviewed.contains($0.id) }.count
        let localPending = pendingNotSureCases.filter { !remoteIDs.contains($0.sourceLogID ?? $0.id) }.count
        return remotePending + localPending
    }

    private var notSureReviewScope: String? {
        if isDemoBypassActive { return demoPersona.accountStorageKey }
        guard let account = client.account, let organization = account.organisationID else { return nil }
        return "live|\(client.baseURL.absoluteString)|\(organization.uuidString)|\(account.id.uuidString)"
    }

    func reloadNotSureQueue() {
        let scope = notSureReviewScope
        if loadedReviewScope != scope {
            escalatedNotSureCases = []
            requestedEscalatedCaseID = nil
            loadedReviewScope = scope
        }
        notSureQueueError = nil
        guard let scope else { return }
        do {
            escalatedNotSureCases = try reviewJournal.load(scope: scope)
        } catch {
            notSureQueueError = "Could not load the reviews saved on this Mac. \(error.localizedDescription)"
        }
    }

    func openNotSureReview(caseID: UUID? = nil) {
        dismissDetail()
        requestedEscalatedCaseID = caseID
        reviewNavigationTrigger = UUID()
        activeSection = .scientistReview
    }

    func openNotSureReview(scenario: ReviewScenarioID, layoutMode: ScientistComparisonLayoutMode = .contours) {
        requestedReviewScenario = scenario
        requestedReviewLayoutMode = layoutMode
        openNotSureReview()
        isReviewPracticePresented = true
    }

    func escalateToNotSureReview(_ item: EscalatedNotSureCase) throws {
        guard item.queryImage != nil else { throw NotSureReviewError.invalidPhoto }
        if let existing = escalatedNotSureCases.first(where: {
            $0.side == item.side && $0.isExample == item.isExample && $0.queryPhotoData == item.queryPhotoData
        }) {
            if existing.decision == .pending {
                var updated = existing
                let seen = Set(existing.candidates.map(\.id))
                updated.candidates.append(contentsOf: item.candidates.filter { !seen.contains($0.id) })
                try saveNotSureCase(updated)
            }
            openNotSureReview(caseID: existing.id)
            return
        }
        try saveNotSureCase(item)
        openNotSureReview(caseID: item.id)
    }

    func updateNotSureCase(_ id: UUID, action: NotSureReviewAction) throws {
        guard var item = escalatedNotSureCases.first(where: { $0.id == id }) else {
            throw NotSureReviewError.caseUnavailable
        }
        if case .reopen = action, item.hasDurableIdentityDecision, !isDemoBypassActive {
            throw APIError.conflict("This sighting is already identified. Its saved decision cannot be reopened locally.")
        }
        try item.apply(action)
        try saveNotSureCase(item)
    }

    /// A server-backed verdict becomes local only after the server accepts its provenance.
    func resolveNotSureCaseAndSyncBackend(_ id: UUID, action: NotSureReviewAction) async throws {
        guard var updated = escalatedNotSureCases.first(where: { $0.id == id }) else {
            throw NotSureReviewError.caseUnavailable
        }
        if case .recommend = action, updated.sourceLogID != nil, !isDemoBypassActive, updated.desktopReview == nil {
            throw APIError.validation("Start a desktop review before confirming a match from this workspace.")
        }
        if case .resolveAsNewTurtle = action, updated.sourceLogID != nil, !isDemoBypassActive {
            throw APIError.validation("Enter the new turtle details and confirm the reviewed photos before saving.")
        }
        try updated.apply(action)
        let generation = sessionGeneration
        let scope = notSureReviewScope
        var confirmedLogID: UUID?
        var identityKey: String?
        if case .recommend(let candidateID, let note) = action, let logID = updated.sourceLogID,
           let turtleID = UUID(uuidString: candidateID), canLoadRecords {
            do {
                if !isDemoBypassActive {
                    guard let attemptID = updated.matchAttemptID else {
                        throw APIError.validation("Run a new match before confirming this legacy review.")
                    }
                    if updated.desktopReview != nil {
                        let key = "\(id):\(attemptID):\(turtleID):\(note)"
                        let command = pendingReviewIdentities[key] ?? ReviewIdentityCommand(attemptID: attemptID, turtleID: turtleID, note: note)
                        pendingReviewIdentities[key] = command
                        try await repository.confirmDesktopReview(logID: logID, command: command)
                        try checkReviewContext(generation, scope: scope)
                        guard escalatedNotSureCases.first(where: { $0.id == id })?.matchAttemptID == attemptID else { throw CancellationError() }
                        identityKey = key
                    } else {
                        try await repository.confirmReview(logID: logID, attemptID: attemptID, turtleID: turtleID)
                    }
                } else {
                    try await repository.resolvePendingSighting(logID: logID, turtleID: turtleID, method: "manual", confidence: nil, notes: note)
                }
            } catch APIError.conflict(let detail) {
                try checkReviewContext(generation, scope: scope)
                await loadMobileReviewQueue()
                throw APIError.conflict(detail + " Refresh or reopen this case to review the current sighting.")
            }
            guard generation == sessionGeneration, scope == notSureReviewScope else { throw CancellationError() }
            confirmedLogID = logID
        }
        guard generation == sessionGeneration, scope == notSureReviewScope else { throw CancellationError() }
        // Keep notes/annotations saved while the request was in flight.
        guard var current = escalatedNotSureCases.first(where: { $0.id == id }) else { throw NotSureReviewError.caseUnavailable }
        try current.apply(action)
        try saveNotSureCase(current)
        if let confirmedLogID {
            removeMobileReviewRow(confirmedLogID)
            reviewOperationIDs[confirmedLogID] = UUID()
            statusMessage = "Confirmed match synced to sighting log"
        }
        if let identityKey { pendingReviewIdentities.removeValue(forKey: identityKey) }
    }

    /// A camera match stores the query without a photo id. The sighting head photo
    /// saved afterward is the reference a desktop search can send.
    private func linkedReviewInputs(_ inputs: [ReviewQueryInput], sighting: MobileReviewSighting) -> [ReviewQueryInput] {
        inputs.map { input in
            guard input.photoID == nil, input.file == nil else { return input }
            let sameSide = sighting.headPhotos.filter { $0.side == input.side }
            if sameSide.count == 1, let photo = sameSide.first {
                return ReviewQueryInput(photoID: photo.id, side: input.side, file: nil)
            }
            if sighting.headPhotos.count == 1, let photo = sighting.headPhotos.first,
               photo.side == nil || photo.side == input.side {
                return ReviewQueryInput(photoID: photo.id, side: input.side, file: nil)
            }
            return input
        }
    }

    /// A 70% gallery retry compares every uniquely sided head photo. A one-sided
    /// sighting, a cropped photo, and a 100% expansion stay on their existing inputs.
    private func pairedReviewInputs(_ inputs: [ReviewQueryInput], sighting: MobileReviewSighting) -> [ReviewQueryInput] {
        let linked = linkedReviewInputs(inputs, sighting: sighting)
        guard let defaults = sighting.defaultInputs,
              Set(defaults.map(\.side)) == Set([TurtlePhotoSide.left, .right]) else { return linked }
        var bySide: [TurtlePhotoSide: ReviewQueryInput] = [:]
        for input in defaults { bySide[input.side] = input }
        for input in linked { bySide[input.side] = input }
        return [TurtlePhotoSide.left, .right].compactMap { bySide[$0] }
    }

    func startDesktopReviewIfNeeded(_ caseID: UUID) async throws {
        guard let item = escalatedNotSureCases.first(where: { $0.id == caseID }),
              item.desktopReview == nil, item.decision == .pending,
              item.sourceLogID != nil, !isDemoBypassActive, !item.isExample else { return }
        try await findNotSureCandidates(for: caseID)
    }

    func expandNotSureReview(_ caseID: UUID) async throws {
        try await findNotSureCandidates(for: caseID, reviewCoverage: 100)
    }

    func hasMoreNotSureCandidates(_ caseID: UUID) -> Bool {
        guard let item = escalatedNotSureCases.first(where: { $0.id == caseID }), let state = item.desktopReview else { return false }
        return (reviewPageOffsets[caseID] ?? item.candidates.count) < state.candidateTotal
    }

    func loadMoreNotSureCandidates(_ caseID: UUID) async throws {
        guard let item = escalatedNotSureCases.first(where: { $0.id == caseID }),
              let logID = item.sourceLogID, let attemptID = item.matchAttemptID,
              hasMoreNotSureCandidates(caseID) else { return }
        let generation = sessionGeneration, scope = notSureReviewScope
        let offset = reviewPageOffsets[caseID] ?? item.candidates.count
        let operationID = reviewOperationIDs[logID]
        let page = try await repository.reviewCandidatePage(logID: logID, attemptID: attemptID, limit: 50, offset: offset)
        try checkReviewContext(generation, scope: scope)
        guard let current = escalatedNotSureCases.first(where: { $0.id == caseID }), current.matchAttemptID == attemptID,
              (reviewPageOffsets[caseID] ?? current.candidates.count) == offset else { throw CancellationError() }
        guard page.offset == offset, page.total == page.review.candidateTotal,
              !page.items.isEmpty, page.offset + page.items.count <= page.total else {
            throw APIError.invalidResponse
        }
        var combined = reviewCandidateRecords[caseID] ?? []
        var ids = Set(combined.map { $0.turtle.id })
        combined += page.items.filter { ids.insert($0.turtle.id).inserted }
        let sighting = try await repository.reviewSighting(id: logID)
        try checkReviewContext(generation, scope: scope)
        guard escalatedNotSureCases.first(where: { $0.id == caseID })?.matchAttemptID == attemptID else { throw CancellationError() }
        let result = ReviewMatchResult(id: attemptID, querySides: current.reviewInputs?.map(\.side) ?? [current.side],
            candidates: combined, queries: reviewQueryEvidence[caseID], review: page.review)
        try await hydrateMobileReview(sighting, result: result, generation: generation, scope: scope, operationID: operationID)
        reviewPageOffsets[caseID] = offset + page.items.count
    }

    func setNotSureCandidateRejected(caseID: UUID, candidateID: String, rejected: Bool) async throws {
        guard let item = escalatedNotSureCases.first(where: { $0.id == caseID }) else { throw NotSureReviewError.caseUnavailable }
        if item.sourceLogID == nil || isDemoBypassActive {
            try updateNotSureCase(caseID, action: rejected ? .rejectCandidate(candidateID) : .restoreCandidate(candidateID))
            return
        }
        guard item.desktopReview != nil, let logID = item.sourceLogID, let attemptID = item.matchAttemptID else {
            throw APIError.validation("Start a desktop review before saving candidate decisions.")
        }
        guard item.decision == .pending, item.candidates.contains(where: { $0.id == candidateID }),
              let turtleID = UUID(uuidString: candidateID) else { throw NotSureReviewError.invalidCandidate }
        let generation = sessionGeneration, scope = notSureReviewScope
        let key = "\(caseID):\(attemptID):\(candidateID):\(rejected)"
        let command = pendingReviewRejections[key] ?? ReviewRejectionCommand(candidateID: turtleID, rejected: rejected)
        pendingReviewRejections[key] = command
        let state = try await repository.saveReviewRejection(logID: logID, attemptID: attemptID, command: command)
        try checkReviewContext(generation, scope: scope)
        guard var current = escalatedNotSureCases.first(where: { $0.id == caseID }), current.matchAttemptID == attemptID,
              current.decision == .pending else { throw CancellationError() }
        current.adoptDesktopReview(state)
        try saveNotSureCase(current)
        reviewOperationIDs[logID] = UUID()
        pendingReviewRejections.removeValue(forKey: key)
    }

    func createNotSureTurtle(caseID: UUID, draft: IndividualDraft, photosAdequate: Bool, note: String) async throws {
        guard let item = escalatedNotSureCases.first(where: { $0.id == caseID }), let logID = item.sourceLogID,
              let attemptID = item.matchAttemptID, item.decision == .pending else { throw NotSureReviewError.caseUnavailable }
        guard item.desktopReview?.canCreateNew == true else {
            throw APIError.validation("Search all reference photos and reject every nonmatching candidate before creating a turtle.")
        }
        try draft.validate()
        let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard photosAdequate, !note.isEmpty else { throw APIError.validation("Confirm photo quality and enter a decision reason.") }
        let generation = sessionGeneration, scope = notSureReviewScope
        let key = "\(caseID):\(attemptID)"
        let command: ReviewNewTurtleCommand
        if let pending = pendingReviewNewTurtles[key], pending.note == note,
           pending.turtle.profileCode == draft.profileCode, pending.turtle.name == draft.name,
           pending.turtle.species == draft.species {
            command = pending
        } else {
            command = ReviewNewTurtleCommand(note: note, photosAdequate: photosAdequate, turtle: draft)
            pendingReviewNewTurtles[key] = command
        }
        try await repository.createReviewTurtle(logID: logID, attemptID: attemptID, command: command)
        try checkReviewContext(generation, scope: scope)
        guard var current = escalatedNotSureCases.first(where: { $0.id == caseID }), current.matchAttemptID == attemptID else { throw CancellationError() }
        try current.apply(.resolveAsNewTurtle(note: note))
        try saveNotSureCase(current)
        pendingReviewNewTurtles.removeValue(forKey: key)
        removeMobileReviewRow(logID)
        reviewOperationIDs[logID] = UUID()
        statusMessage = "New turtle created and linked to the sighting"
    }

    private func removeMobileReviewRow(_ logID: UUID) {
        let removed = mobileReviewRows.filter { $0.id == logID }.count
        mobileReviewRows.removeAll { $0.id == logID }
        mobileReviewOffset = max(0, mobileReviewOffset - removed)
    }

    func hasPendingNotSureMatch(_ caseID: UUID) -> Bool {
        guard let logID = escalatedNotSureCases.first(where: { $0.id == caseID })?.sourceLogID else { return false }
        return pendingReviewAttempts[logID] != nil
    }

    /// One metadata request per page. No image or inference work belongs in this path.
    func loadMobileReviewQueue(loadMore: Bool = false, ifNeeded: Bool = false) async {
        guard canLoadRecords, !isSyncingMobileQueue, !(ifNeeded && mobileReviewLoaded) else { return }
        let generation = sessionGeneration
        let scope = notSureReviewScope
        let offset = loadMore ? mobileReviewOffset : 0
        isSyncingMobileQueue = true
        notSureQueueError = nil
        defer { if generation == sessionGeneration { isSyncingMobileQueue = false } }
        do {
            let page = try await repository.reviewQueue(limit: 50, offset: offset)
            try Task.checkCancellation()
            guard generation == sessionGeneration, scope == notSureReviewScope else { return }
            let rows = page.items.filter { $0.turtleID == nil && !$0.isDraft }
            if loadMore {
                let ids = Set(mobileReviewRows.map(\.id))
                mobileReviewRows.append(contentsOf: rows.filter { !ids.contains($0.id) })
            } else { mobileReviewRows = rows }
            mobileReviewOffset = page.offset + page.items.count
            hasMoreMobileReviews = !page.items.isEmpty && mobileReviewOffset < page.total
            mobileReviewLoaded = true
        } catch {
            if generation == sessionGeneration, !(error is CancellationError), !Task.isCancelled {
                notSureQueueError = "Could not load pending sightings. " + error.localizedDescription
            }
        }
    }

    /// Reloads the same organization log page iOS uses. Does not download photos or create local cases.
    @discardableResult
    func syncMobilePendingSightings() async -> Int {
        guard canLoadRecords, !isSyncingMobileQueue else { return 0 }
        let generation = sessionGeneration
        isSyncingMobileQueue = true
        notSureQueueError = nil
        defer {
            if sessionGeneration == generation { isSyncingMobileQueue = false }
        }
        await loadWaitingLogs()
        guard sessionGeneration == generation else { return 0 }
        if notSureQueueError == nil {
            let count = waitingLogs.count
            statusMessage = "\(count) unidentified sighting\(count == 1 ? "" : "s")"
        }
        return waitingLogs.count
    }

    /// Opens one waiting log: loads its detail and face photos, then the existing review screen.
    func openWaitingLog(_ id: UUID) async {
        guard !isOpeningWaitingLog else { return }
        let generation = sessionGeneration
        isOpeningWaitingLog = true
        notSureQueueError = nil
        defer { if sessionGeneration == generation { isOpeningWaitingLog = false } }
        do {
            let log = try await repository.fetchLog(id: id)
            guard sessionGeneration == generation else { return }
            if let existing = escalatedNotSureCases.first(where: { $0.sourceLogID == id }) {
                openNotSureReview(caseID: existing.id)
                return
            }
            let reviewCase = try await makeReviewCase(from: log)
            guard sessionGeneration == generation else { return }
            try saveNotSureCase(reviewCase)
            openNotSureReview(caseID: reviewCase.id)
        } catch {
            guard sessionGeneration == generation, !(error is CancellationError) else { return }
            notSureQueueError = error.localizedDescription
        }
    }

    /// Assigns a turtle on the saved sighting (`PATCH /api/v2/logs/{id}`) and refreshes the waiting list.
    func confirmWaitingLog(_ id: UUID, turtleID: UUID) async throws {
        try await repository.resolvePendingSighting(
            logID: id,
            turtleID: turtleID,
            method: "manual",
            confidence: nil,
            notes: nil
        )
        await loadWaitingLogs()
    }

    private func loadWaitingLogs() async {
        let generation = sessionGeneration
        do {
            let logs = try await fetchWaitingLogs(generation: generation)
            guard sessionGeneration == generation else { return }
            waitingLogs = logs
        } catch {
            guard sessionGeneration == generation, !(error is CancellationError) else { return }
            notSureQueueError = "Could not load unidentified sightings. \(error.localizedDescription)"
        }
    }

    private func fetchWaitingLogs(generation: UUID) async throws -> [OrganizationLog] {
        var collected: [OrganizationLog] = []
        var offset = 0
        var total = Int.max
        while offset < total {
            let page = try await repository.listLogs(identifiedOnly: false, limit: 50, offset: offset)
            guard sessionGeneration == generation else { throw CancellationError() }
            collected.append(contentsOf: page.items)
            total = page.total
            offset += page.items.count
            if page.items.isEmpty { break }
        }
        return collected.filter { OrganizationLog.isWaiting($0) }
    }

    private func makeReviewCase(from log: OrganizationLog) async throws -> EscalatedNotSureCase {
        let faces = log.facePhotos
        guard let primary = faces.first(where: { $0.side == .left }) ?? faces.first else {
            throw NotSureReviewError.invalidPhoto
        }
        let primaryData = try await facePhotoData(logID: log.id, photo: primary)
        let companionPhoto = faces.first { $0.id != primary.id && ($0.side == .right || primary.side == nil) }
        let companionData: Data?
        if let companionPhoto {
            companionData = try await facePhotoData(logID: log.id, photo: companionPhoto)
        } else {
            companionData = nil
        }
        let title = log.locationName.trimmingCharacters(in: .whitespacesAndNewlines)
        var reviewCase = EscalatedNotSureCase(
            title: title.isEmpty ? "Mobile sighting" : title,
            side: primary.side ?? .left,
            photo: NotSureReviewPhoto(data: primaryData),
            companion: companionData.map { NotSureReviewPhoto(data: $0) },
            queryFingerprint: nil,
            queryROI: [],
            candidates: [],
            submittedBy: "Mobile Patrol",
            isExample: isDemoBypassActive,
            sourceLogID: log.id,
            createdAt: log.observedAt
        )
        if let note = log.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            try reviewCase.apply(.saveNote(note))
        }
        return reviewCase
    }

    private func facePhotoData(logID: UUID, photo: OrganizationLogPhoto) async throws -> Data {
        let path = "api/v2/logs/\(logID.uuidString.lowercased())/photos/\(photo.id.uuidString.lowercased())"
        let data = try await repository.fetchPhotoData(pathOrURL: path)
        guard NSImage(data: data) != nil else { throw NotSureReviewError.invalidPhoto }
        return data
    }

    func prepareMobileReview(_ logID: UUID, inputs: [ReviewQueryInput]? = nil) async throws {
        let operationID = UUID()
        reviewOperationIDs[logID] = operationID
        let generation = sessionGeneration
        let scope = notSureReviewScope
        let sighting = try await repository.reviewSighting(id: logID)
        try checkReviewContext(generation, scope: scope)
        guard sighting.turtleID == nil, !sighting.isDraft else {
            removeMobileReviewRow(logID)
            throw APIError.conflict("This sighting has already changed. Return to the queue and refresh.")
        }
        if let index = mobileReviewRows.firstIndex(where: { $0.id == logID }) { mobileReviewRows[index] = sighting }
        if isDemoBypassActive {
            try await prepareDemoReview(sighting, generation: generation, scope: scope)
            return
        }
        var result: ReviewMatchResult
        var usedAttemptID: UUID?
        if let pending = pendingReviewAttempts[logID], inputs.map({ $0 == pending.command.inputs }) ?? true {
            usedAttemptID = pending.command.attemptID
            result = try await repository.rematchReview(logID: logID, command: pending.command, crop: pending.crop)
            try checkReviewContext(generation, scope: scope)
        } else if inputs == nil, sighting.matchResult != nil, let saved = try await repository.reviewMatchResults(logID: logID).first {
            result = saved
        } else {
            guard let selected = inputs ?? sighting.defaultInputs else { throw ReviewInputSelectionRequired(sighting: sighting) }
            let pending = PendingReviewAttempt(command: ReviewRematchCommand(attemptID: UUID(), inputs: selected, reviewCoverage: 70), crop: nil)
            pendingReviewAttempts[logID] = pending
            usedAttemptID = pending.command.attemptID
            result = try await repository.rematchReview(logID: logID, command: pending.command, crop: nil)
            try checkReviewContext(generation, scope: scope)
        }
        try checkReviewContext(generation, scope: scope)
        if let usedAttemptID, let command = pendingReviewAttempts[logID]?.command,
           command.attemptID == usedAttemptID, result.review?.coveragePercent != command.reviewCoverage {
            throw APIError.validation("This server does not support desktop review yet. Update the backend before retrying.")
        }
        try await hydrateMobileReview(sighting, result: result, generation: generation, scope: scope, operationID: operationID)
        try checkReviewContext(generation, scope: scope)
        if let usedAttemptID, pendingReviewAttempts[logID]?.command.attemptID == usedAttemptID {
            pendingReviewAttempts.removeValue(forKey: logID)
        }
    }

    private func checkReviewContext(_ generation: UUID, scope: String?) throws {
        try Task.checkCancellation()
        guard generation == sessionGeneration, scope == notSureReviewScope else { throw CancellationError() }
    }

    private func hydrateMobileReview(_ sighting: MobileReviewSighting, result: ReviewMatchResult, generation: UUID, scope: String?, recordDeltas: Bool = false, operationID: UUID? = nil) async throws {
        let context = ReviewPhotoContext(logID: sighting.id, attemptID: result.id)
        let metadata = try await reviewPhotoMetadata.load(context, refreshing: true)
        try checkReviewContext(generation, scope: scope)
        let observedEpoch = reviewPhotoMetadata.epoch(context)
        let desktopState: DesktopReviewState?
        if result.review != nil {
            desktopState = try await repository.reviewState(logID: sighting.id, attemptID: result.id)
            try checkReviewContext(generation, scope: scope)
        } else { desktopState = nil }
        var evidence = result.queries ?? []
        if metadata == nil && result.queries == nil {
            evidence = try await repository.reviewQueries(logID: sighting.id, attemptID: result.id)
        }
        let selected: [(TurtlePhotoSide, PhotoReference, UUID?)]
        if let metadata {
            guard !metadata.queries.isEmpty else {
                throw APIError.notFound("Historical query photo unavailable. Start a new match to review current photos.")
            }
            selected = metadata.queries.map { ($0.side, $0.photo, $0.photoID) }
        } else if !evidence.isEmpty {
            selected = evidence.map { ($0.side, PhotoReference(url: $0.url), $0.photoID) }
        } else {
            guard !result.querySides.isEmpty, sighting.headPhotos.allSatisfy({ $0.side != nil }) else {
                throw ReviewInputSelectionRequired(sighting: sighting)
            }
            selected = try result.querySides.map { side in
                let photos = sighting.headPhotos.filter { $0.side == side }
                guard photos.count == 1, let photo = photos.first else { throw ReviewInputSelectionRequired(sighting: sighting) }
                return (side, photo.reference, Optional(photo.id))
            }
        }
        guard let primary = selected.first else { throw NotSureReviewError.invalidPhoto }
        func queryBytes(_ entry: (TurtlePhotoSide, PhotoReference, UUID?)) async throws -> Data {
            var renewal: PhotoDelivery.Renewal?
            if metadata != nil {
                renewal = { [weak self] in
                    guard let self else { throw CancellationError() }
                    let refreshed = try await self.reviewPhotoMetadata.load(context, after: observedEpoch)
                    return refreshed?.queries.first(where: { $0.side == entry.0 })?.photo
                }
            }
            guard let bytes = try await deliveryLoader().data(for: entry.1, representation: .original, renewal: renewal) else {
                throw NotSureReviewError.invalidPhoto
            }
            try checkReviewContext(generation, scope: scope)
            return bytes
        }
        let bytes = try await queryBytes(primary)
        var companion: NotSureReviewPhoto?
        if let other = selected.dropFirst().first {
            companion = NotSureReviewPhoto(data: try await queryBytes(other))
        }
        var freshReferences: [String: PhotoReference] = [:]
        var sideReferences: [String: PhotoReference] = [:]
        let references = result.candidates.map { candidate in
            let side: TurtlePhotoSide = primary.0
            let delivered = metadata?.candidates.first { $0.turtleID == candidate.turtle.id && $0.side == side }
            let legacy = side == .left ? candidate.turtle.identityPhotos?.left : candidate.turtle.identityPhotos?.right
            let ref: PhotoReference?
            if metadata != nil { ref = delivered?.photo }
            else { ref = legacy ?? (candidate.turtle.identityPhotos == nil ? PhotoReference(url: "/api/v2/individuals/\(candidate.turtle.id.uuidString.lowercased())/photos/\(side.rawValue)") : nil) }
            if let ref { freshReferences[candidate.turtle.id.uuidString] = ref }
            for photoSide in TurtlePhotoSide.allCases {
                if let sideRef = candidateSideReference(candidate, side: photoSide, metadata: metadata) {
                    sideReferences["\(candidate.turtle.id.uuidString)|\(photoSide.rawValue)"] = sideRef
                }
            }
            return EscalatedNotSureCandidate(id: candidate.turtle.id.uuidString, rank: candidate.rank,
                name: candidate.turtle.name, profileCode: candidate.turtle.profileCode, side: side, sideMatches: true,
                dateText: "", location: "", confidencePercent: Int((candidate.confidence * 100).rounded()), photo: nil,
                photoPath: ref?.url, photoRevision: ref?.revision, photoAvailability: delivered?.availability,
                sampleImageName: nil, fingerprint: nil, isBundledExample: false)
        }
        try checkReviewContext(generation, scope: scope)
        guard reviewOperationIDs[sighting.id] == operationID else { throw CancellationError() }
        var item = escalatedNotSureCases.first(where: { $0.sourceLogID == sighting.id }) ?? EscalatedNotSureCase(
            id: sighting.id, title: sighting.location.name, side: primary.0, photo: NotSureReviewPhoto(data: bytes),
            companion: companion, queryFingerprint: nil, queryROI: [], candidates: [], submittedBy: "Mobile Patrol",
            isExample: false, sourceLogID: sighting.id, createdAt: sighting.observedAt)
        if recordDeltas {
            let previous = Dictionary(uniqueKeysWithValues: item.candidates.map { ($0.id, $0) })
            item.reMatchDeltasByCandidateID = Dictionary(uniqueKeysWithValues: references.map { reference in
                (reference.id, CandidateReMatchDelta(previousRank: previous[reference.id]?.rank, newRank: reference.rank,
                    previousConfidence: previous[reference.id]?.confidencePercent, newConfidence: reference.confidencePercent))
            })
        }
        // Preserve notes, verdict and annotations on ordinary revisits of the same attempt.
        if item.matchAttemptID != result.id {
            item.candidates = references
        } else {
            item.candidates = references.map { fresh in
                var candidate = fresh
                candidate.photo = fresh.photoPath == nil ? nil : item.candidates.first(where: {
                    $0.id == fresh.id && $0.side == fresh.side && $0.photoRevision == fresh.photoRevision
                })?.photo
                return candidate
            }
        }
        item.replaceQueryEvidence(side: primary.0, photo: NotSureReviewPhoto(data: bytes), companion: companion)
        item.matchAttemptID = result.id
        if let desktopState { item.adoptDesktopReview(desktopState) }
        else { item.desktopReview = nil }
        reviewQueryEvidence[item.id] = selected.map { ReviewQueryEvidence(side: $0.0, photoID: $0.2, url: $0.1.url) }
        reviewCandidateRecords[item.id] = result.candidates
        reviewPageOffsets[item.id] = result.candidates.count
        item.reviewInputs = selected.map { ReviewQueryInput(photoID: $0.2, side: $0.0, file: nil) }
        reviewContexts[item.id] = context
        reviewReferences[item.id] = freshReferences
        reviewSideReferences[item.id] = sideReferences
        reviewReferenceEpoch[item.id] = observedEpoch
        reviewThumbnails = reviewThumbnails.filter { $0.key.hasPrefix(item.id.uuidString + ":") }

        if item.note.isEmpty, let note = sighting.notes, !note.isEmpty { try item.apply(.saveNote(note)) }
        try checkReviewContext(generation, scope: scope)
        try saveNotSureCase(item)
    }

    private func candidateRenewal(caseID: UUID, candidateID: String, side: TurtlePhotoSide) -> PhotoDelivery.Renewal? {
        guard let context = reviewContexts[caseID] else { return nil }
        let issuedEpoch = reviewReferenceEpoch[caseID] ?? 0
        return { [weak self] in
            guard let self else { throw CancellationError() }
            guard self.reviewContexts[caseID] == context else { throw CancellationError() }
            let metadata = try await self.reviewPhotoMetadata.load(context, after: issuedEpoch)
            guard self.reviewContexts[caseID] == context else { throw CancellationError() }
            self.adoptReviewPhotos(caseID: caseID, metadata: metadata, context: context)
            return metadata?.candidates.first { $0.turtleID.uuidString == candidateID && $0.side == side }?.photo
        }
    }

    private func adoptReviewPhotos(caseID: UUID, metadata: ReviewPhotoDelivery?, context: ReviewPhotoContext) {
        guard let metadata else { return }
        var refs = reviewReferences[caseID] ?? [:]
        for candidate in metadata.candidates {
            if let photo = candidate.photo {
                refs[candidate.turtleID.uuidString] = photo
            }
        }
        reviewReferences[caseID] = refs
        reviewReferenceEpoch[caseID] = reviewPhotoMetadata.epoch(context)
    }

    private func candidateSideReference(_ candidate: ReviewMatchResult.Candidate, side: TurtlePhotoSide, metadata: ReviewPhotoDelivery?) -> PhotoReference? {
        if let metadata, let pinned = metadata.candidates.first(where: { $0.turtleID == candidate.turtle.id && $0.side == side }) {
            return pinned.photo
        }
        let legacy = side == .left ? candidate.turtle.identityPhotos?.left : candidate.turtle.identityPhotos?.right
        if let legacy { return legacy }
        guard candidate.turtle.identityPhotos == nil else { return nil }
        return PhotoReference(url: "/api/v2/individuals/\(candidate.turtle.id.uuidString.lowercased())/photos/\(side.rawValue)")
    }

    /// The Left/Right chip changes which head is on screen. Candidate photos follow that side.
    func alignNotSureCandidatePhotos(caseID: UUID, side: TurtlePhotoSide) async throws {
        guard let item = escalatedNotSureCases.first(where: { $0.id == caseID }) else { return }
        let generation = sessionGeneration
        let scope = notSureReviewScope
        let attempt = item.matchAttemptID
        for candidate in item.candidates where candidate.side != side {
            guard let ref = reviewSideReferences[caseID]?["\(candidate.id)|\(side.rawValue)"] else { continue }
            guard let bytes = try await deliveryLoader().data(for: ref, representation: .original,
                renewal: candidateRenewal(caseID: caseID, candidateID: candidate.id, side: side)),
                  NSImage(data: bytes) != nil else { continue }
            try checkReviewContext(generation, scope: scope)
            guard var current = escalatedNotSureCases.first(where: { $0.id == caseID }), current.matchAttemptID == attempt,
                  let index = current.candidates.firstIndex(where: { $0.id == candidate.id && $0.side != side }) else { continue }
            current.candidates[index].side = side
            current.candidates[index].sideMatches = true
            current.candidates[index].photo = NotSureReviewPhoto(data: bytes)
            current.candidates[index].photoPath = ref.url
            current.candidates[index].photoRevision = ref.revision
            reviewReferences[caseID]?[candidate.id] = ref
            reviewThumbnails[caseID.uuidString + ":" + candidate.id] = NSImage(data: bytes)
            try saveNotSureCase(current)
        }
    }

    func loadNotSureCandidatePhoto(caseID: UUID, candidateID: String) async throws {
        guard let item = escalatedNotSureCases.first(where: { $0.id == caseID }),
              let candidate = item.candidates.first(where: { $0.id == candidateID }), candidate.photo == nil,
              let path = candidate.photoPath else { return }
        let generation = sessionGeneration
        let scope = notSureReviewScope
        let attempt = item.matchAttemptID
        let ref = reviewReferences[caseID]?[candidateID] ?? PhotoReference(url: path)
        guard let bytes = try await deliveryLoader().data(for: ref, representation: .original,
            renewal: candidateRenewal(caseID: caseID, candidateID: candidateID, side: candidate.side)) else {
            throw NotSureReviewError.invalidPhoto
        }
        try checkReviewContext(generation, scope: scope)
        guard var current = escalatedNotSureCases.first(where: { $0.id == caseID }), current.matchAttemptID == attempt,
              let index = current.candidates.firstIndex(where: { $0.id == candidateID && $0.photoPath == path && $0.photoRevision == candidate.photoRevision }) else { return }
        current.candidates[index].photo = NotSureReviewPhoto(data: bytes)
        try saveNotSureCase(current)
    }

    func prefetchNotSureCandidatePhotos(caseID: UUID, priorityCandidateID: String?) async throws {
        guard let item = escalatedNotSureCases.first(where: { $0.id == caseID }) else { return }
        let primary = item.candidates.firstIndex { $0.id == priorityCandidateID } ?? 0
        let ordered = Array(item.candidates.dropFirst(primary).prefix(2))
        let keep = Set(ordered.map(\.id))
        let loader = deliveryLoader()
        let keys = Set(ordered.compactMap { reviewReferences[caseID]?[$0.id]?.key(scope: loader.scope, representation: .original) })
        loader.cancelOriginals(except: keys)
        // Bound decoded candidate originals to this selection and one neighbour.
        for index in escalatedNotSureCases.indices {
            for candidate in escalatedNotSureCases[index].candidates.indices {
                if escalatedNotSureCases[index].id != caseID || !keep.contains(escalatedNotSureCases[index].candidates[candidate].id) {
                    escalatedNotSureCases[index].candidates[candidate].photo = nil
                }
            }
        }
        for candidate in ordered {
            try Task.checkCancellation()
            do { try await loadNotSureCandidatePhoto(caseID: caseID, candidateID: candidate.id) }
            catch is CancellationError { throw CancellationError() }
            catch { if candidate.id == priorityCandidateID { throw error } }
        }
    }

    func loadNotSureThumbnail(caseID: UUID, candidateID: String) async {
        guard let item = escalatedNotSureCases.first(where: { $0.id == caseID }),
              let candidate = item.candidates.first(where: { $0.id == candidateID }),
              let ref = reviewReferences[caseID]?[candidateID], ref.revision != nil else { return }
        let generation = sessionGeneration
        let scope = notSureReviewScope
        do {
            guard let data = try await deliveryLoader().data(for: ref, representation: .thumbnail,
                renewal: candidateRenewal(caseID: caseID, candidateID: candidateID, side: candidate.side)) else { return }
            try checkReviewContext(generation, scope: scope)
            reviewThumbnails[caseID.uuidString + ":" + candidateID] = NSImage(data: data)
        } catch { /* Keep a placeholder; original comparison remains independent. */ }
    }

    func loadQueueThumbnail(sightingID: UUID, photo: MobileReviewPhoto) async -> NSImage? {
        let generation = sessionGeneration
        let epoch = queuePhotoEpoch
        do {
            let data = try await deliveryLoader().data(for: photo.reference, representation: .thumbnail) { [weak self] in
                guard let self else { throw CancellationError() }
                if self.queuePhotoEpoch == epoch {
                    if let pending = self.queueRenewal { await pending.value }
                    else {
                        let task = Task { await self.loadMobileReviewQueue() }
                        self.queueRenewal = task
                        await task.value
                        self.queueRenewal = nil
                        self.queuePhotoEpoch += 1
                    }
                }
                return self.mobileReviewRows.first(where: { $0.id == sightingID })?.photos.first(where: { $0.id == photo.id })?.reference
            }
            guard generation == sessionGeneration, !Task.isCancelled, let data else { return nil }
            return NSImage(data: data)
        } catch { return nil }
    }

    private func prepareDemoReview(_ sighting: MobileReviewSighting, generation: UUID, scope: String?) async throws {
        if escalatedNotSureCases.contains(where: { $0.sourceLogID == sighting.id }) { return }
        guard let inputs = sighting.defaultInputs, let first = inputs.first,
              let photo = sighting.headPhotos.first(where: { $0.id == first.photoID }) else { throw ReviewInputSelectionRequired(sighting: sighting) }
        let data = try await repository.fetchPhotoData(pathOrURL: photo.fetchPath)
        var companion: Data?
        if let other = inputs.dropFirst().first, let source = sighting.headPhotos.first(where: { $0.id == other.photoID }) {
            companion = try await repository.fetchPhotoData(pathOrURL: source.fetchPath)
        }
        let outcome = try await repository.matchPhoto(imageData: data, side: first.side, limit: 6)
        let references = outcome.candidates.map { candidate in
            EscalatedNotSureCandidate(id: candidate.id.uuidString, rank: candidate.rank, name: candidate.name,
                profileCode: candidate.profileCode ?? "", side: candidate.matchedPhotoSide, sideMatches: candidate.matchedPhotoSide == first.side,
                dateText: candidate.lastSeenDate ?? "", location: candidate.lastSeenLocation ?? "", confidencePercent: candidate.confidencePercent,
                photo: nil, photoPath: candidate.photoURL, sampleImageName: candidate.photoURL, fingerprint: nil, isBundledExample: true)
        }
        var item = EscalatedNotSureCase(id: sighting.id, title: sighting.location.name, side: first.side,
            photo: NotSureReviewPhoto(data: data), companion: companion.map { NotSureReviewPhoto(data: $0) },
            queryFingerprint: nil, queryROI: [], candidates: references, submittedBy: "Mobile Patrol", isExample: true,
            sourceLogID: sighting.id, createdAt: sighting.observedAt)
        if let note = sighting.notes, !note.isEmpty { try item.apply(.saveNote(note)) }
        try checkReviewContext(generation, scope: scope)
        try saveNotSureCase(item)
    }

    func findNotSureCandidates(
        for id: UUID,
        overridePhotoData: Data? = nil,
        usePairedSide: Bool = false,
        retryPreviousAttempt: Bool = false,
        reviewCoverage: Int = 70
    ) async throws {
        guard let item = escalatedNotSureCases.first(where: { $0.id == id }) else {
            throw NotSureReviewError.caseUnavailable
        }
        guard !isDemoBypassActive, !item.isExample, isAuthenticated else {
            throw NotSureReviewError.searchUnavailable
        }
        guard item.decision == .pending else { throw NotSureReviewError.alreadyReviewed }
        let generation = sessionGeneration
        let scope = notSureReviewScope
        if let logID = item.sourceLogID {
            let operationID = UUID()
            reviewOperationIDs[logID] = operationID
            let sighting = try await repository.reviewSighting(id: logID)
            try checkReviewContext(generation, scope: scope)
            guard reviewOperationIDs[logID] == operationID else { throw CancellationError() }
            let pending: PendingReviewAttempt
            if retryPreviousAttempt {
                guard let retry = pendingReviewAttempts[logID] else { throw APIError.validation("There is no failed match to retry.") }
                let inputs = (retry.command.reviewCoverage == 70 && retry.crop == nil)
                    ? pairedReviewInputs(retry.command.inputs, sighting: sighting)
                    : linkedReviewInputs(retry.command.inputs, sighting: sighting)
                if inputs == retry.command.inputs {
                    pending = retry
                } else {
                    pending = PendingReviewAttempt(command: ReviewRematchCommand(
                        attemptID: UUID(), inputs: inputs, reviewCoverage: retry.command.reviewCoverage,
                        parentAttemptID: retry.command.parentAttemptID), crop: retry.crop)
                    pendingReviewAttempts[logID] = pending
                }
            } else {
                let remembered = (usePairedSide ? sighting.defaultInputs : nil) ?? item.reviewInputs ?? sighting.defaultInputs
                guard let sources = remembered.map({ linkedReviewInputs($0, sighting: sighting) }),
                      let primary = sources.first(where: { $0.side == item.side }) else {
                    throw ReviewInputSelectionRequired(sighting: sighting)
                }
                var inputs = (usePairedSide || reviewCoverage == 100) ? sources : [primary]
                if reviewCoverage == 70, overridePhotoData == nil {
                    inputs = pairedReviewInputs(inputs, sighting: sighting)
                }
                if overridePhotoData != nil, let index = inputs.firstIndex(where: { $0.side == item.side }) {
                    inputs[index] = ReviewQueryInput(photoID: primary.photoID, side: primary.side, file: "query_1")
                }
                let parentID: UUID?
                if reviewCoverage == 100 {
                    guard item.desktopReview?.coveragePercent == 70, let attemptID = item.matchAttemptID,
                          overridePhotoData == nil else {
                        throw APIError.validation("Run the 70% review before searching all reference photos.")
                    }
                    parentID = attemptID
                } else { parentID = nil }
                if let retry = pendingReviewAttempts[logID], retry.command.reviewCoverage == reviewCoverage,
                   retry.command.parentAttemptID == parentID, retry.command.inputs == inputs, retry.crop == overridePhotoData {
                    pending = retry
                } else {
                    pending = PendingReviewAttempt(command: ReviewRematchCommand(attemptID: UUID(), inputs: inputs,
                        reviewCoverage: reviewCoverage, parentAttemptID: parentID), crop: overridePhotoData)
                    pendingReviewAttempts[logID] = pending
                }
            }
            let result = try await repository.rematchReview(logID: logID, command: pending.command, crop: pending.crop)
            guard result.review?.coveragePercent == pending.command.reviewCoverage else {
                throw APIError.validation("This server does not support desktop review yet. Update the backend before retrying.")
            }
            try checkReviewContext(generation, scope: scope)
                try await hydrateMobileReview(sighting, result: result, generation: generation, scope: scope, recordDeltas: true, operationID: operationID)
            try checkReviewContext(generation, scope: scope)
            if pendingReviewAttempts[logID]?.command.attemptID == pending.command.attemptID {
                pendingReviewAttempts.removeValue(forKey: logID)
            }
            return
        }
        let isHumanGuidedReMatch = overridePhotoData != nil || usePairedSide

        let result: MatchSearchOutcome
        if let logID = item.sourceLogID {
            let attemptID = UUID()
            if usePairedSide, let companionData = item.companion?.data {
                let leftBytes = item.side == .left ? (overridePhotoData ?? item.queryPhotoData) : companionData
                let rightBytes = item.side == .right ? (overridePhotoData ?? item.queryPhotoData) : companionData
                result = try await repository.matchLoggedPhotoPair(
                    logID: logID, attemptID: attemptID, leftData: leftBytes, rightData: rightBytes, limit: 8
                )
            } else {
                result = try await repository.matchLoggedPhoto(
                    logID: logID,
                    attemptID: attemptID,
                    imageData: overridePhotoData ?? item.queryPhotoData,
                    side: item.side,
                    limit: 8
                )
            }
        } else if usePairedSide, let companionData = item.companion?.data {
            let leftBytes = item.side == .left ? (overridePhotoData ?? item.queryPhotoData) : companionData
            let rightBytes = item.side == .right ? (overridePhotoData ?? item.queryPhotoData) : companionData
            result = try await matchPhotoPair(leftData: leftBytes, rightData: rightBytes, limit: 8)
        } else {
            result = try await matchPhoto(imageData: overridePhotoData ?? item.queryPhotoData, side: item.side, limit: 8)
        }

        var references: [EscalatedNotSureCandidate] = []
        for candidate in result.candidates where (usePairedSide || candidate.matchedPhotoSide == item.side) {
            try Task.checkCancellation()
            guard sessionGeneration == generation, notSureReviewScope == scope else { throw CancellationError() }
            let path = candidate.photoURL ?? "/api/v1/individuals/\(candidate.id.uuidString)/photos/\(candidate.matchedPhotoSide.rawValue)"
            let image = await loadPhoto(for: path)
            references.append(EscalatedNotSureCandidate(
                id: candidate.id.uuidString,
                rank: candidate.rank,
                name: candidate.name,
                profileCode: candidate.profileCode ?? "",
                side: candidate.matchedPhotoSide,
                sideMatches: candidate.matchedPhotoSide == item.side || usePairedSide,
                dateText: candidate.lastSeenDate ?? "",
                location: candidate.lastSeenLocation ?? "",
                confidencePercent: candidate.confidencePercent,
                photo: NotSureReviewPhoto(snapshot: image),
                sampleImageName: nil,
                fingerprint: nil,
                isBundledExample: false
            ))
        }
        try Task.checkCancellation()
        guard sessionGeneration == generation, notSureReviewScope == scope else { throw CancellationError() }
        guard var updated = escalatedNotSureCases.first(where: { $0.id == id }), updated.decision == .pending else {
            throw NotSureReviewError.caseUnavailable
        }

        if isHumanGuidedReMatch {
            // Compute honest before -> after rank & confidence deltas and refresh candidate ordering.
            let oldByID = Dictionary(uniqueKeysWithValues: updated.candidates.map { ($0.id, $0) })
            var deltas: [String: CandidateReMatchDelta] = [:]
            var refreshed: [EscalatedNotSureCandidate] = []
            var seenIDs = Set<String>()

            for reference in references {
                seenIDs.insert(reference.id)
                let prev = oldByID[reference.id]
                let photo = NotSureReviewPhoto.refreshed(
                    reference.photo, side: reference.side, previous: prev?.photo, previousSide: prev?.side
                )
                refreshed.append(EscalatedNotSureCandidate(
                    id: reference.id,
                    rank: reference.rank,
                    name: reference.name,
                    profileCode: reference.profileCode,
                    side: reference.side,
                    sideMatches: reference.sideMatches,
                    dateText: reference.dateText,
                    location: reference.location,
                    confidencePercent: reference.confidencePercent,
                    photo: photo,
                    sampleImageName: reference.sampleImageName,
                    fingerprint: prev?.fingerprint,
                    isBundledExample: reference.isBundledExample
                ))
                deltas[reference.id] = CandidateReMatchDelta(
                    previousRank: prev?.rank,
                    newRank: reference.rank,
                    previousConfidence: prev?.confidencePercent,
                    newConfidence: reference.confidencePercent
                )
            }
            // Keep any previously reviewed or rejected candidates that fell out of top-8 at the tail.
            for existing in updated.candidates where !seenIDs.contains(existing.id) {
                refreshed.append(existing)
            }
            updated.candidates = refreshed
            updated.reMatchDeltasByCandidateID = deltas.isEmpty ? nil : deltas
        } else {
            var merged = updated.candidates
            for reference in references {
                if let index = merged.firstIndex(where: { $0.id == reference.id }) {
                    if merged[index].image == nil { merged[index] = reference }
                } else {
                    merged.append(reference)
                }
            }
            updated.candidates = merged
        }
        try saveNotSureCase(updated)
    }

    private func saveNotSureCase(_ item: EscalatedNotSureCase) throws {
        guard let scope = notSureReviewScope, scope == loadedReviewScope else {
            throw NotSureReviewError.accountUnavailable
        }
        try reviewJournal.save(item, scope: scope)
        if let index = escalatedNotSureCases.firstIndex(where: { $0.id == item.id }) {
            escalatedNotSureCases[index] = item
        } else {
            escalatedNotSureCases.insert(item, at: 0)
        }
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
        organizationKeySettings.leave()
        passwordSecurity.invalidateAndClear()
        organisationSettings.reset()
        settingsDetail = nil
        pendingSettingsDetailTarget = nil
        sessionNotice = nil
        if !keepDemoMode {
            isDemoBypassActive = false
        }
        sessionGeneration = UUID()
        searchTask?.cancel()
        mapTask?.cancel()
        demoReloadTask?.cancel()
        photoCache.removeAll()
        photoDelivery?.clear(); photoDelivery = nil
        reviewPhotoMetadata.clear()
        reviewContexts.removeAll(); reviewReferences.removeAll(); reviewSideReferences.removeAll(); reviewReferenceEpoch.removeAll(); reviewThumbnails.removeAll()
        queueRenewal?.cancel(); queueRenewal = nil; queuePhotoEpoch += 1

        turtles = []
        analyticsTurtles = []
        favoriteTurtles = []
        sightings = []
        dashboard = DashboardSnapshot(months: [], species: [])
        trendMonths = []
        totalIndividuals = 0
        individualsOffset = 0
        isIndividualsLoading = false
        individualRequest += 1
        dismissDetail()
        escalatedNotSureCases.removeAll()
        waitingLogs = []
        isOpeningWaitingLog = false
        mobileReviewRows.removeAll()
        hasMoreMobileReviews = false
        mobileReviewOffset = 0
        mobileReviewLoaded = false
        pendingReviewAttempts.removeAll()
        pendingReviewRejections.removeAll()
        pendingReviewIdentities.removeAll()
        pendingReviewNewTurtles.removeAll()
        reviewCandidateRecords.removeAll()
        reviewPageOffsets.removeAll()
        reviewOperationIDs.removeAll()
        reviewQueryEvidence.removeAll()
        requestedEscalatedCaseID = nil
        loadedReviewScope = nil
        notSureQueueError = nil
        isSyncingMobileQueue = false
        isReviewPracticePresented = false
        isLoading = false
        isExporting = false
        isImporting = false
        importProgressText = nil
        lastError = nil
        statusMessage = nil
        let demoDataset = demoPersona.demoDataset
        repository = isDemoBypassActive ? DemoTurtleRepository(dataset: demoDataset) : RemoteTurtleRepository(client: client)
    }

    deinit { searchTask?.cancel(); mapTask?.cancel(); demoReloadTask?.cancel() }

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
        await loadWaitingLogs()
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
            async let trendSnapshot = try? repository.dashboard(query: currentTrendDashboardQuery)
            async let sightings = repository.mapSightings(query: mapQuery)
            let (page, favoriteItems, snapshot, trend, mapItems) = try await (individuals, favorites, dashboard, trendSnapshot, sightings)
            guard sessionGeneration == generation else { return }
            if individualRequest == individualRevision, currentIndividualQuery == individualQuery {
                turtles = page.items
                analyticsTurtles = (repository as? DemoTurtleRepository)?.fullCatalogForAnalytics ?? page.items
                totalIndividuals = page.total
                favoriteTurtles = favoriteItems
            }
            if dashboardRequest == dashboardRevision, chartSpecies == dashboardQuery.species {
                self.dashboard = snapshot
                self.trendMonths = trend?.months.isEmpty == false ? (trend?.months ?? snapshot.months) : snapshot.months
            }
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

    var allKnownTurtles: [Turtle] {
        var seen = Set<String>()
        var combined: [Turtle] = []
        for source in [analyticsTurtles, turtles, favoriteTurtles] {
            for turtle in source where seen.insert(turtle.id).inserted {
                combined.append(turtle)
            }
        }
        return combined
    }

    func turtle(forID id: String) -> Turtle? {
        turtles.first(where: { $0.id == id })
            ?? analyticsTurtles.first(where: { $0.id == id })
            ?? favoriteTurtles.first(where: { $0.id == id })
    }

    func reloadMap() async {
        guard canLoadRecords else { return }
        mapTask?.cancel()
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
            async let value = repository.dashboard(query: currentDashboardQuery)
            async let trend = try? repository.dashboard(query: currentTrendDashboardQuery)
            let (snapshot, trendSnapshot) = try await (value, trend)
            guard sessionGeneration == generation, dashboardRequest == request else { return }
            dashboard = snapshot
            trendMonths = trendSnapshot?.months.isEmpty == false ? (trendSnapshot?.months ?? snapshot.months) : snapshot.months
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
        isExporting = true
        statusMessage = nil
        Task {
            defer {
                if sessionGeneration == generation { isExporting = false }
            }
            guard sessionGeneration == generation else { return }
            do {
                let file = try await repository.export(request)
                guard sessionGeneration == generation else { return }
                let panel = NSSavePanel()
                panel.nameFieldStringValue = file.filename
                panel.allowedContentTypes = Self.allowedContentTypes(for: request.format)
                guard panel.runModal() == .OK, let url = panel.url else { return }
                try file.data.write(to: url, options: .atomic)
                statusMessage = "Exported \(url.lastPathComponent)"
            } catch {
                if sessionGeneration == generation, !(error is CancellationError) { lastError = error.localizedDescription }
            }
        }
    }

    static func allowedContentTypes(for format: ExportFormat) -> [UTType] {
        switch format {
        case .csv: [.commaSeparatedText]
        case .xlsx: [UTType(filenameExtension: "xlsx") ?? .data]
        case .pdf: [.pdf]
        }
    }

    // MARK: - Batch Import & Not Sure Queue Handoff

    struct ImportExecutionSummary: Equatable, Sendable {
        let importedCount: Int
        let escalatedToNotSureCount: Int
        let failedCount: Int
        let summaryText: String
    }

    var existingProfileCodes: Set<String> {
        Set(allKnownTurtles.compactMap(\.profileCode))
    }

    func importPhotoEncounters(
        _ encounters: [StagedPhotoEncounter],
        destination: PhotoBatchDestination
    ) async -> ImportExecutionSummary {
        guard !encounters.isEmpty else {
            return ImportExecutionSummary(importedCount: 0, escalatedToNotSureCount: 0, failedCount: 0, summaryText: "Nothing to import")
        }
        let generation = sessionGeneration
        isImporting = true
        statusMessage = nil
        lastError = nil
        defer {
            if sessionGeneration == generation {
                isImporting = false
                importProgressText = nil
            }
        }

        var imported = 0
        var escalated = 0
        var failed = 0
        var usedCodes = existingProfileCodes
        var autoCodeSeed = 200_001

        for (index, encounter) in encounters.enumerated() {
            guard sessionGeneration == generation, !Task.isCancelled else { break }
            importProgressText = "Importing \(index + 1) of \(encounters.count)…"

            do {
                switch destination {
                case .notSureQueue:
                    let reviewCase = EscalatedNotSureCase(
                        title: encounter.title,
                        side: encounter.primary.side,
                        photo: NotSureReviewPhoto(data: encounter.primary.jpegData),
                        companion: encounter.companion.map { NotSureReviewPhoto(data: $0.jpegData) },
                        queryFingerprint: nil,
                        queryROI: [],
                        candidates: [],
                        submittedBy: accountName,
                        isExample: isDemoBypassActive
                    )
                    try saveNotSureCase(reviewCase)
                    imported += 1
                    escalated += 1

                case .matchAndTriage:
                    let outcome: MatchSearchOutcome
                    if let left = encounter.leftPhoto, let right = encounter.rightPhoto {
                        outcome = try await matchPhotoPair(leftData: left.jpegData, rightData: right.jpegData, limit: 6)
                    } else {
                        outcome = try await matchPhoto(imageData: encounter.primary.jpegData, side: encounter.primary.side, limit: 6)
                    }
                    guard sessionGeneration == generation else { break }

                    var references: [EscalatedNotSureCandidate] = []
                    for cand in outcome.candidates {
                        let path = cand.photoURL ?? "/api/v1/individuals/\(cand.id.uuidString)/photos/\(cand.matchedPhotoSide.rawValue)"
                        let img = await loadPhoto(for: path)
                        references.append(EscalatedNotSureCandidate(
                            id: cand.id.uuidString,
                            rank: cand.rank,
                            name: cand.name,
                            profileCode: cand.profileCode ?? "",
                            side: cand.matchedPhotoSide,
                            sideMatches: cand.matchedPhotoSide == encounter.primary.side || encounter.isPaired,
                            dateText: cand.lastSeenDate ?? "",
                            location: cand.lastSeenLocation ?? "",
                            confidencePercent: cand.confidencePercent,
                            photo: NotSureReviewPhoto(snapshot: img),
                            sampleImageName: isDemoBypassActive ? (path as NSString).lastPathComponent : nil,
                            fingerprint: nil,
                            isBundledExample: isDemoBypassActive
                        ))
                    }

                    let reviewCase = EscalatedNotSureCase(
                        title: encounter.title,
                        side: encounter.primary.side,
                        photo: NotSureReviewPhoto(data: encounter.primary.jpegData),
                        companion: encounter.companion.map { NotSureReviewPhoto(data: $0.jpegData) },
                        queryFingerprint: nil,
                        queryROI: [],
                        candidates: references,
                        submittedBy: accountName,
                        isExample: isDemoBypassActive
                    )
                    try saveNotSureCase(reviewCase)
                    imported += 1
                    escalated += 1

                case .enrollNew:
                    while usedCodes.contains(String(format: "%06d", autoCodeSeed)) { autoCodeSeed += 1 }
                    let code = String(format: "%06d", autoCodeSeed)
                    usedCodes.insert(code)
                    autoCodeSeed += 1

                    let draft = IndividualDraft(
                        profileCode: code,
                        name: encounter.title,
                        species: TurtleSpecies.unknown.apiValue,
                        sex: "unknown",
                        firstSeenAt: encounter.capturedAt ?? Date()
                    )
                    let created = try await repository.createIndividual(draft)
                    guard sessionGeneration == generation else { break }
                    if let backendID = created.backendID {
                        if let left = encounter.leftPhoto {
                            _ = try await repository.uploadIndividualPhoto(individualID: backendID, side: .left, imageData: left.jpegData)
                        }
                        if let right = encounter.rightPhoto {
                            _ = try await repository.uploadIndividualPhoto(individualID: backendID, side: .right, imageData: right.jpegData)
                        }
                    }
                    imported += 1
                }
            } catch {
                failed += 1
            }
        }

        if destination == .enrollNew && imported > 0 && sessionGeneration == generation {
            demoReloadTask?.cancel()
            await reloadAll()
        }

        let summaryText: String
        switch destination {
        case .matchAndTriage:
            summaryText = "Matched & sent \(escalated) encounter\(escalated == 1 ? "" : "s") to Not Sure"
        case .notSureQueue:
            summaryText = "Added \(escalated) encounter\(escalated == 1 ? "" : "s") to Not Sure"
        case .enrollNew:
            summaryText = "Enrolled \(imported) turtle\(imported == 1 ? "" : "s")"
        }
        let suffix = failed > 0 ? " (\(failed) failed)" : ""
        let fullText = summaryText + suffix
        if sessionGeneration == generation {
            statusMessage = fullText
            if escalated > 0 {
                openNotSureReview(caseID: escalatedNotSureCases.first?.id)
            }
        }
        return ImportExecutionSummary(
            importedCount: imported,
            escalatedToNotSureCount: escalated,
            failedCount: failed,
            summaryText: fullText
        )
    }

    func importCatalogRows(_ rows: [StagedCatalogRow]) async -> ImportExecutionSummary {
        let validRows = rows.filter(\.isValid)
        guard !validRows.isEmpty else {
            return ImportExecutionSummary(importedCount: 0, escalatedToNotSureCount: 0, failedCount: rows.count, summaryText: "No valid rows to import")
        }
        let generation = sessionGeneration
        isImporting = true
        statusMessage = nil
        lastError = nil
        defer {
            if sessionGeneration == generation {
                isImporting = false
                importProgressText = nil
            }
        }

        var imported = 0
        var failed = 0
        for (idx, row) in validRows.enumerated() {
            guard sessionGeneration == generation, !Task.isCancelled, let draft = row.draft else { break }
            importProgressText = "Importing \(idx + 1) of \(validRows.count)…"
            do {
                _ = try await repository.createIndividual(draft)
                imported += 1
            } catch {
                failed += 1
            }
        }

        if imported > 0 && sessionGeneration == generation {
            demoReloadTask?.cancel()
            await reloadAll()
        }

        let text = "Imported \(imported) individual\(imported == 1 ? "" : "s")" + (failed > 0 ? " (\(failed) failed)" : "")
        if sessionGeneration == generation { statusMessage = text }
        return ImportExecutionSummary(importedCount: imported, escalatedToNotSureCount: 0, failedCount: failed, summaryText: text)
    }

    func importNotSureBundleCases(_ cases: [EscalatedNotSureCase]) -> Int {
        var imported = 0
        for item in cases {
            if (try? saveNotSureCase(item)) != nil {
                imported += 1
            }
        }
        if imported > 0 {
            statusMessage = "Imported \(imported) Not Sure case\(imported == 1 ? "" : "s")"
            openNotSureReview()
        }
        return imported
    }

    func exportNotSureQueue() {
        guard !escalatedNotSureCases.isEmpty else {
            statusMessage = "No Not Sure cases to export"
            return
        }
        do {
            let data = try NotSureReviewBundle.encode(escalatedNotSureCases, account: accountName)
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "ada-penyu-not-sure-queue.json"
            panel.allowedContentTypes = [.json]
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try data.write(to: url, options: .atomic)
            statusMessage = "Exported \(escalatedNotSureCases.count) Not Sure case\(escalatedNotSureCases.count == 1 ? "" : "s") to \(url.lastPathComponent)"
        } catch {
            lastError = error.localizedDescription
        }
    }

    func clearError() { lastError = nil }
    func clearStatusMessage() { statusMessage = nil }

    func signIn(email: String, password: String, rememberMe: Bool) async throws {
        clearPrivateState()
        isAuthenticated = false
        _ = try await client.login(email: email, password: password, rememberMe: rememberMe)
        clearPrivateState()
        updateAccount()
        await reloadAll()
    }

    func signOut() {
        client.logout()
        clearPrivateState()
        updateAccount()
    }

    func completePasswordChangeSignOut() {
        signOut()
        sessionNotice = "Password updated. Please sign in with your new password."
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

    var currentTrendDashboardQuery: DashboardQuery {
        DashboardQuery.lastMonths(24, species: chartSpecies)
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
        mapTask?.cancel()
        mapTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(260))
            guard !Task.isCancelled, let self else { return }
            await self.reloadMap()
        }
    }

}
