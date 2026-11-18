import Combine
import SwiftUI

// MARK: - Domain & State Models for the Scientist Review Prototype

enum ReviewScenarioID: String, CaseIterable, Identifiable {
    case rankOneJunctionMismatch = "scenario1"
    case glareOcclusionUnsure = "scenario2"

    var id: String { rawValue }

    var shortTitle: String {
        switch self {
        case .rankOneJunctionMismatch:
            "Scenario 1 · Rank-1 Junction Mismatch"
        case .glareOcclusionUnsure:
            "Scenario 2 · Glare Hides Scales"
        }
    }

    var walkthroughSummary: String {
        switch self {
        case .rankOneJunctionMismatch:
            "Starting with clean Original photos. Toggle 'Scale outlines' to inspect numbered postocular junctions (1–6): Rank #1 Surya (84%) has a split 3-way junction at #3, whereas Rank #2 Amina (79%) matches all 6 junctions."
        case .glareOcclusionUnsure:
            "Specular water glare obscures central postocular scales (#2–#4) behind the right eye. Toggle 'Scale outlines' to view the occluded region, then choose 'Unsure' to save with an empty identity and request a better photo or second review."
        }
    }
}

enum CandidateReviewStatus: String, Equatable {
    case pending = "Pending"
    case rejected = "Rejected (Different)"
    case confirmed = "Confirmed (Same)"
}

enum JunctionTopologyState: String, Equatable {
    case isomorphicMatch
    case junctionMismatch
    case glareOccluded
    case sideMismatch
}

struct ReviewCandidateItem: Identifiable, Equatable {
    let id: String
    let rank: Int
    let displayName: String
    let profileCode: String
    let side: TurtlePhotoSide
    let sideMatchesSighting: Bool
    let captureDate: String
    let location: String
    let relativeMatchScore: Int
    let miewCosine: Double
    let xfeatMatchedPoints: Int
    let i3sDistance: Double?
    let i3sMatchedPairs: Int
    let junctionSummary: String
    let junctionDetail: String
    let topologyState: JunctionTopologyState
    let sampleImageName: String?
    var status: CandidateReviewStatus = .pending
}

struct ReviewSightingItem: Equatable {
    let sightingID: String
    let species: TurtleSpecies
    let side: TurtlePhotoSide
    let captureDate: String
    let location: String
    let rangerNote: String
    let hasSpecularGlare: Bool
    let sampleImageName: String?
}

struct SavedSightingReviewOutcome: Equatable {
    enum Resolution: String, Equatable {
        case linkedToExisting = "Linked to Existing Turtle"
        case savedUnsure = "Saved Unsure (Identity Empty)"
    }

    let resolution: Resolution
    let linkedCandidateID: String?
    let linkedCandidateName: String?
    let nominateForGalleryEnrollment: Bool
    let requestBetterPhoto: Bool
    let requestSecondReview: Bool
    let scientistNotes: String
}

enum ScientistComparisonLayoutMode: String, CaseIterable, Identifiable {
    case scales = "Numbered scales"
    case contours = "Photo contours"
    case sideBySide = "Side-by-Side (1:1)"
    case multiCandidateGrid = "Compare Multiple"
    case superimposeBlend = "Superimpose / Blink"

    var id: String { rawValue }
}

@MainActor
final class ScientistReviewViewModel: ObservableObject {
    @Published var activeScenario: ReviewScenarioID = .rankOneJunctionMismatch
    @Published private(set) var sighting: ReviewSightingItem
    @Published private(set) var candidates: [ReviewCandidateItem] = []
    @Published var selectedCandidateIndex: Int = 0

    // Layout & multi-photo comparison state
    @Published var layoutMode: ScientistComparisonLayoutMode = .sideBySide
    @Published var multiSelectedCandidateIDs: Set<String> = []
    @Published var showRealTurtlePhotographs: Bool = true
    @Published var showCrossPhotoThreads: Bool = true
    @Published var superimposeBlendOpacity: Double = 0.50

    // Comparison aids — starting view uses clean original photos (all false)
    @Published var showScaleOutlines: Bool = false
    @Published var showHeadRegionOutline: Bool = false
    @Published var showXFeatPoints: Bool = false
    @Published var showI3SBlobOverlay: Bool = false

    // Synchronized zoom & pan state
    @Published var syncZoomAndPan: Bool = true
    @Published var zoomScale: CGFloat = 1.0
    @Published var panOffset: CGSize = .zero

    // Evidence drawers
    @Published var isEvidenceDrawerExpanded: Bool = true
    @Published var isMoreEvidenceExpanded: Bool = false

    // Confirmation & Unsure workflow sheets
    @Published var isConfirmSameTurtlePresented: Bool = false
    @Published var nominateForGalleryReference: Bool = false
    @Published var confirmationNotes: String = ""

    @Published var isUnsureSheetPresented: Bool = false
    @Published var requestBetterPhoto: Bool = true
    @Published var requestSecondReview: Bool = true
    @Published var unsureNotes: String = ""

    @Published private(set) var savedOutcomes: [ReviewScenarioID: SavedSightingReviewOutcome] = [:]
    @Published private(set) var widerSearchExecuted: Set<ReviewScenarioID> = []
    @Published private(set) var auditLog: [String] = []

    init() {
        let initialCandidates = Self.makeCandidates(for: .rankOneJunctionMismatch)
        self.sighting = Self.makeSighting(for: .rankOneJunctionMismatch)
        self.candidates = initialCandidates
        self.multiSelectedCandidateIDs = Set(initialCandidates.map(\.id))
        appendAudit("Loaded Scientist Review Workspace (1440×900). Starting with Original photos.")
    }

    var selectedCandidate: ReviewCandidateItem {
        guard candidates.indices.contains(selectedCandidateIndex) else {
            return candidates[0]
        }
        return candidates[selectedCandidateIndex]
    }

    var multiComparisonCandidates: [ReviewCandidateItem] {
        let filtered = candidates.filter { multiSelectedCandidateIDs.contains($0.id) }
        return filtered.isEmpty ? candidates : filtered
    }

    var isShowingCleanOriginalPhotos: Bool {
        !showScaleOutlines && !showHeadRegionOutline && !showXFeatPoints && !showI3SBlobOverlay
    }

    var currentOutcome: SavedSightingReviewOutcome? {
        savedOutcomes[activeScenario]
    }

    func switchScenario(_ scenario: ReviewScenarioID) {
        activeScenario = scenario
        sighting = Self.makeSighting(for: scenario)
        let newCandidates = Self.makeCandidates(for: scenario)
        candidates = newCandidates
        multiSelectedCandidateIDs = Set(newCandidates.map(\.id))
        selectedCandidateIndex = 0
        resetOverlaysToOriginalPhotos()
        resetZoomAndPan()
        appendAudit("Switched to \(scenario.shortTitle) — starting with clean Original photos.")
    }

    func toggleMultiCandidateSelection(_ candidateID: String) {
        if multiSelectedCandidateIDs.contains(candidateID) {
            if multiSelectedCandidateIDs.count > 1 {
                multiSelectedCandidateIDs.remove(candidateID)
            }
        } else {
            multiSelectedCandidateIDs.insert(candidateID)
        }
    }

    func selectAllCandidatesForMultiCompare() {
        multiSelectedCandidateIDs = Set(candidates.map(\.id))
        layoutMode = .multiCandidateGrid
        appendAudit("Comparing sighting photo against all \(candidates.count) candidates simultaneously.")
    }

    func resetDemo() {
        savedOutcomes.removeAll()
        widerSearchExecuted.removeAll()
        auditLog.removeAll()
        isMoreEvidenceExpanded = false
        layoutMode = .sideBySide
        switchScenario(.rankOneJunctionMismatch)
        appendAudit("Reset demo: restored initial candidate lists, original photos, and local review state.")
    }

    func resetOverlaysToOriginalPhotos() {
        showScaleOutlines = false
        showHeadRegionOutline = false
        showXFeatPoints = false
        showI3SBlobOverlay = false
    }

    func resetZoomAndPan() {
        zoomScale = 1.0
        panOffset = .zero
    }

    func focusPostocularRegion() {
        zoomScale = 1.85
        panOffset = CGSize(width: -55, height: -20)
        appendAudit("Focused synchronized zoom (185%) on postocular scale junctions behind the eye.")
    }

    func selectCandidate(at index: Int) {
        guard candidates.indices.contains(index) else { return }
        selectedCandidateIndex = index
        let c = candidates[index]
        appendAudit("Selected Rank #\(c.rank) (\(c.displayName)) — updated right photo & evidence.")
    }

    func rejectSelectedCandidateAndAdvance() {
        guard candidates.indices.contains(selectedCandidateIndex) else { return }
        let rejected = candidates[selectedCandidateIndex]
        candidates[selectedCandidateIndex].status = .rejected
        appendAudit("Marked Rank #\(rejected.rank) (\(rejected.displayName)) as Different turtle (Rejected).")

        if let nextAfter = candidates.indices.first(where: { $0 > selectedCandidateIndex && candidates[$0].status == .pending }) {
            selectedCandidateIndex = nextAfter
            appendAudit("Advanced right pane to Rank #\(candidates[nextAfter].rank) (\(candidates[nextAfter].displayName)).")
        } else if let anyPending = candidates.indices.first(where: { candidates[$0].status == .pending }) {
            selectedCandidateIndex = anyPending
            appendAudit("Advanced right pane to Rank #\(candidates[anyPending].rank) (\(candidates[anyPending].displayName)).")
        } else {
            appendAudit("All shortlisted candidates rejected. Ready to save Unsure or run wider search.")
        }
    }

    func prepareSameTurtleConfirmation() {
        let cand = selectedCandidate
        nominateForGalleryReference = false
        if cand.topologyState == .isomorphicMatch {
            confirmationNotes = "Verified match to \(cand.displayName) (\(cand.profileCode)): postocular scale boundaries and numbered junctions 1–6 (including 4-way vertex #3) match."
        } else {
            confirmationNotes = "Manual verification note for \(cand.displayName)."
        }
        isConfirmSameTurtlePresented = true
    }

    func confirmSameTurtleIdentity() {
        guard candidates.indices.contains(selectedCandidateIndex) else { return }
        candidates[selectedCandidateIndex].status = .confirmed
        let cand = candidates[selectedCandidateIndex]
        let outcome = SavedSightingReviewOutcome(
            resolution: .linkedToExisting,
            linkedCandidateID: cand.profileCode,
            linkedCandidateName: cand.displayName,
            nominateForGalleryEnrollment: nominateForGalleryReference,
            requestBetterPhoto: false,
            requestSecondReview: false,
            scientistNotes: confirmationNotes
        )
        savedOutcomes[activeScenario] = outcome
        isConfirmSameTurtlePresented = false
        appendAudit("DEMO IN MEMORY · CONFIRMED SAME TURTLE: Linked \(sighting.sightingID) to \(cand.displayName) (\(cand.profileCode)). Gallery enrollment kept separate (\(nominateForGalleryReference ? "Nominated" : "Not enrolled")).")
    }

    func prepareUnsureSheet() {
        requestBetterPhoto = true
        requestSecondReview = true
        if activeScenario == .glareOcclusionUnsure {
            unsureNotes = "Specular water glare obscures central postocular junctions #2–#4 behind right eye (only dorsal #1 and ventral #5 visible). Cannot safely separate #023 Zizo from #031 Tirta; leaving identity empty."
        } else {
            unsureNotes = "Scale junction evidence remains inconclusive across candidates; saving sighting with identity empty for follow-up."
        }
        isUnsureSheetPresented = true
    }

    func saveUnsureDecision() {
        let outcome = SavedSightingReviewOutcome(
            resolution: .savedUnsure,
            linkedCandidateID: nil,
            linkedCandidateName: nil,
            nominateForGalleryEnrollment: false,
            requestBetterPhoto: requestBetterPhoto,
            requestSecondReview: requestSecondReview,
            scientistNotes: unsureNotes
        )
        savedOutcomes[activeScenario] = outcome
        isUnsureSheetPresented = false
        appendAudit("DEMO IN MEMORY · SAVED UNSURE: \(sighting.sightingID) saved with Identity = EMPTY. Request better photo: \(requestBetterPhoto ? "Yes" : "No"), Second review: \(requestSecondReview ? "Yes" : "No").")
    }

    func runWiderSearch() {
        guard !widerSearchExecuted.contains(activeScenario) else { return }
        widerSearchExecuted.insert(activeScenario)
        if activeScenario == .rankOneJunctionMismatch {
            candidates.append(
                ReviewCandidateItem(
                    id: "cand-ghost-4",
                    rank: 4,
                    displayName: "Turtle #004 · Ghost",
                    profileCode: "PEN-CM-004",
                    side: .left,
                    sideMatchesSighting: true,
                    captureDate: "28 Oct 2026",
                    location: "Crystal Bay",
                    relativeMatchScore: 61,
                    miewCosine: 0.69,
                    xfeatMatchedPoints: 12,
                    i3sDistance: 15.88,
                    i3sMatchedPairs: 25,
                    junctionSummary: "3/6 junctions match · #3, #4, #6 differ",
                    junctionDetail: "Added via crop-locked wider search: elongated postocular P2 scute does not match sighting.",
                    topologyState: .junctionMismatch,
                    sampleImageName: "Ghost1_L.jpg"
                )
            )
        } else {
            candidates.append(
                ReviewCandidateItem(
                    id: "cand-banyu-4",
                    rank: 4,
                    displayName: "Turtle #041 · Banyu",
                    profileCode: "PEN-CM-041",
                    side: .right,
                    sideMatchesSighting: true,
                    captureDate: "12 Oct 2026",
                    location: "Blue Corner",
                    relativeMatchScore: 64,
                    miewCosine: 0.70,
                    xfeatMatchedPoints: 11,
                    i3sDistance: 16.40,
                    i3sMatchedPairs: 19,
                    junctionSummary: "Glare still occludes #2–#4 on sighting",
                    junctionDetail: "Wider search cannot recover scale seams washed out by specular glare on the sighting photo; another photo is required.",
                    topologyState: .glareOccluded,
                    sampleImageName: "Zizo2_R.jpg"
                )
            )
        }
        if let addedId = candidates.last?.id {
            multiSelectedCandidateIDs.insert(addedId)
        }
        appendAudit("Simulated wider search: added a predefined Rank #4 candidate. No re-indexing or RANSAC was run.")
    }

    private func appendAudit(_ entry: String) {
        auditLog.insert(entry, at: 0)
    }

    // MARK: - Deterministic Scenario Fixtures

    static func makeSighting(for scenario: ReviewScenarioID) -> ReviewSightingItem {
        switch scenario {
        case .rankOneJunctionMismatch:
            return ReviewSightingItem(
                sightingID: "Sighting #S-2026-114",
                species: .green,
                side: .left,
                captureDate: "11 Nov 2026 · 08:42 WITA",
                location: "Crystal Bay, Nusa Penida",
                rangerNote: "Marked Not Sure by Ranger Wayan · Slight upward head pitch (+14°)",
                hasSpecularGlare: false,
                sampleImageName: "Amina3_L.jpg"
            )
        case .glareOcclusionUnsure:
            return ReviewSightingItem(
                sightingID: "Sighting #S-2026-118",
                species: .green,
                side: .right,
                captureDate: "11 Nov 2026 · 11:15 WITA",
                location: "Mangrove Point, Lembongan",
                rangerNote: "Marked Not Sure by Ranger Kadek · Surface sun glare behind right eye",
                hasSpecularGlare: true,
                sampleImageName: "Zizo1_R.jpg"
            )
        }
    }

    static func makeCandidates(for scenario: ReviewScenarioID) -> [ReviewCandidateItem] {
        switch scenario {
        case .rankOneJunctionMismatch:
            return [
                ReviewCandidateItem(
                    id: "cand-surya-1",
                    rank: 1,
                    displayName: "Turtle #019 · Surya",
                    profileCode: "PEN-CM-019",
                    side: .left,
                    sideMatchesSighting: true,
                    captureDate: "14 Aug 2026",
                    location: "Toyapakeh",
                    relativeMatchScore: 84,
                    miewCosine: 0.86,
                    xfeatMatchedPoints: 21,
                    i3sDistance: 11.77,
                    i3sMatchedPairs: 27,
                    junctionSummary: "5/6 match · Junction #3 MISMATCH",
                    junctionDetail: "Convincing Rank-1 lookalike: Junction #3 on the sighting is a 4-way X-vertex (5-sided C1 scale), whereas Surya splits #3 into two 3-way Y-junctions (6-sided C1 scale).",
                    topologyState: .junctionMismatch,
                    sampleImageName: "Aikane2_L.jpg"
                ),
                ReviewCandidateItem(
                    id: "cand-amina-2",
                    rank: 2,
                    displayName: "Turtle #007 · Amina",
                    profileCode: "PEN-CM-007",
                    side: .left,
                    sideMatchesSighting: true,
                    captureDate: "03 May 2026",
                    location: "Crystal Bay",
                    relativeMatchScore: 79,
                    miewCosine: 0.82,
                    xfeatMatchedPoints: 19,
                    i3sDistance: 12.11,
                    i3sMatchedPairs: 22,
                    junctionSummary: "6/6 junctions match (#1–#6 isomorphic)",
                    junctionDetail: "True individual: All 6 postocular and central temporal scale junctions (including the 4-way X-junction at #3 and pentagonal C1 scute) match the sighting.",
                    topologyState: .isomorphicMatch,
                    sampleImageName: "Amina1_L.jpg"
                ),
                ReviewCandidateItem(
                    id: "cand-aikane-3",
                    rank: 3,
                    displayName: "Turtle #012 · Aikane",
                    profileCode: "PEN-CM-012",
                    side: .left,
                    sideMatchesSighting: true,
                    captureDate: "19 Jan 2026",
                    location: "Manta Point",
                    relativeMatchScore: 68,
                    miewCosine: 0.74,
                    xfeatMatchedPoints: 14,
                    i3sDistance: 13.45,
                    i3sMatchedPairs: 27,
                    junctionSummary: "2/6 junctions match · #2–#5 differ",
                    junctionDetail: "Different turtle: Postocular stack has 3 scutes instead of 4; junctions #2–#5 do not correspond.",
                    topologyState: .junctionMismatch,
                    sampleImageName: "Aikane1_L.jpg"
                ),
            ]
        case .glareOcclusionUnsure:
            return [
                ReviewCandidateItem(
                    id: "cand-zizo-1",
                    rank: 1,
                    displayName: "Turtle #023 · Zizo",
                    profileCode: "PEN-CM-023",
                    side: .right,
                    sideMatchesSighting: true,
                    captureDate: "22 Jul 2026",
                    location: "Mangrove Point",
                    relativeMatchScore: 76,
                    miewCosine: 0.78,
                    xfeatMatchedPoints: 15,
                    i3sDistance: 13.20,
                    i3sMatchedPairs: 22,
                    junctionSummary: "2/5 visible · #2–#4 hidden by glare",
                    junctionDetail: "Dorsal #1 and ventral #5 align, but central postocular junctions #2–#4 are washed out by specular reflection on the sighting.",
                    topologyState: .glareOccluded,
                    sampleImageName: "Zizo2_R.jpg"
                ),
                ReviewCandidateItem(
                    id: "cand-tirta-2",
                    rank: 2,
                    displayName: "Turtle #031 · Tirta",
                    profileCode: "PEN-CM-031",
                    side: .right,
                    sideMatchesSighting: true,
                    captureDate: "09 Sep 2026",
                    location: "SD Point",
                    relativeMatchScore: 72,
                    miewCosine: 0.75,
                    xfeatMatchedPoints: 13,
                    i3sDistance: 14.10,
                    i3sMatchedPairs: 20,
                    junctionSummary: "2/5 visible · #2–#4 hidden by glare",
                    junctionDetail: "Dorsal #1 and ventral #5 are also compatible with Tirta; glare over #2–#4 prevents distinguishing Zizo from Tirta.",
                    topologyState: .glareOccluded,
                    sampleImageName: "Amina2_R.jpg"
                ),
                ReviewCandidateItem(
                    id: "cand-amina-left-3",
                    rank: 3,
                    displayName: "Turtle #007 · Amina (Left Only)",
                    profileCode: "PEN-CM-007",
                    side: .left,
                    sideMatchesSighting: false,
                    captureDate: "03 May 2026",
                    location: "Crystal Bay",
                    relativeMatchScore: 54,
                    miewCosine: 0.61,
                    xfeatMatchedPoints: 8,
                    i3sDistance: nil,
                    i3sMatchedPairs: 0,
                    junctionSummary: "Head-side mismatch (Right vs Left)",
                    junctionDetail: "Left and right facial scutes are asymmetrical. A Right-profile sighting cannot be verified against a Left-only gallery reference.",
                    topologyState: .sideMismatch,
                    sampleImageName: "Amina1_L.jpg"
                ),
            ]
        }
    }
}

// MARK: - Main Scientist Review Workspace View (1440 × 900 Target)

struct ScientistReviewWorkspaceView: View {
    var store: AppStore? = nil
    @StateObject private var vm = ScientistReviewViewModel()
    @StateObject private var scaleReviews = ScaleReviewStore()

    @State private var studioMode: PatternStudioMode = .oneVsThree
    private var isStudioPrimaryMode: Bool {
        vm.layoutMode == .contours || vm.layoutMode == .scales
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left + Center Comparison Area
            VStack(spacing: 0) {
                scenarioAndSimulationBar
                Divider().overlay(AdaColors.line)
                if !isStudioPrimaryMode {
                    comparisonAidsToolbar
                    Divider().overlay(AdaColors.line)
                }
                dualComparisonCanvases
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if !isStudioPrimaryMode {
                    Divider().overlay(AdaColors.line)
                    evidenceDrawerSection
                }
                Divider().overlay(AdaColors.line)
                decisionActionBar
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().overlay(AdaColors.line)

            // Slim Right Candidate Inspector
            bundledInspector
                .frame(width: 252)
                .background(AdaColors.canvas)
        }
        .background(AdaColors.canvas)
        .onAppear {
            syncRequestedReviewState()
        }
        .onChange(of: store?.reviewNavigationTrigger) { _, _ in
            syncRequestedReviewState()
        }
        .sheet(isPresented: $vm.isConfirmSameTurtlePresented) {
            confirmSameTurtleSheet
        }
        .sheet(isPresented: $vm.isUnsureSheetPresented) {
            saveUnsureSheet
        }
    }

    private func syncRequestedReviewState() {
        if let store {
            if vm.activeScenario != store.requestedReviewScenario { vm.switchScenario(store.requestedReviewScenario) }
            vm.layoutMode = store.requestedReviewLayoutMode
        }
        vm.isEvidenceDrawerExpanded = false
        vm.showScaleOutlines = true
        vm.showHeadRegionOutline = true
        vm.showCrossPhotoThreads = true
    }

    // MARK: - Compact Case & View Switcher Bar

    private var scenarioAndSimulationBar: some View {
        HStack(spacing: 10) {
            Picker("Sample case", selection: Binding(get: { vm.activeScenario }, set: { scenario in
                vm.switchScenario(scenario)
                vm.showScaleOutlines = true
                vm.showHeadRegionOutline = true
            })) {
                ForEach(ReviewScenarioID.allCases) { scenario in
                    Text(scenario.shortTitle).tag(scenario)
                }
            }
            .frame(maxWidth: 300)

            Picker("View", selection: $vm.layoutMode) {
                Text("Pattern 1 vs 3").tag(ScientistComparisonLayoutMode.contours)
                Text("Scale Manual").tag(ScientistComparisonLayoutMode.scales)
                Text("1:1 Photos").tag(ScientistComparisonLayoutMode.sideBySide)
                Text("Multi-Grid").tag(ScientistComparisonLayoutMode.multiCandidateGrid)
                Text("Blend").tag(ScientistComparisonLayoutMode.superimposeBlend)
            }
            .frame(maxWidth: 180)

            Spacer(minLength: 0)
            Button {
                vm.resetDemo()
                vm.layoutMode = .contours
                studioMode = .oneVsThree
                vm.isEvidenceDrawerExpanded = false
            } label: {
                Label("Reset practice", systemImage: "arrow.counterclockwise")
            }
            .controlSize(.small)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(AdaColors.card)
    }

    // MARK: - Comparison Aids & Synchronized Zoom Toolbar

    private var comparisonAidsToolbar: some View {
        ScrollView(.horizontal) {
        HStack(spacing: 8) {
            Text("Comparison Aids:")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AdaColors.secondaryInk)

            FilterChip(
                title: "Original photos",
                isSelected: vm.isShowingCleanOriginalPhotos,
                horizontalPadding: 11,
                unselectedBackground: AdaColors.canvas
            ) {
                vm.resetOverlaysToOriginalPhotos()
            }

            FilterChip(
                title: "Schematic outlines",
                isSelected: vm.showScaleOutlines,
                horizontalPadding: 11,
                unselectedBackground: AdaColors.canvas
            ) {
                vm.showScaleOutlines.toggle()
            }

            FilterChip(
                title: "Head region outline",
                isSelected: vm.showHeadRegionOutline,
                horizontalPadding: 11,
                unselectedBackground: AdaColors.canvas
            ) {
                vm.showHeadRegionOutline.toggle()
            }

            FilterChip(
                title: "Demo keypoints",
                isSelected: vm.showXFeatPoints,
                horizontalPadding: 11,
                unselectedBackground: AdaColors.canvas
            ) {
                vm.showXFeatPoints.toggle()
            }

            FilterChip(
                title: "I3S landmarks",
                isSelected: vm.showI3SBlobOverlay,
                horizontalPadding: 11,
                unselectedBackground: AdaColors.canvas
            ) {
                vm.showI3SBlobOverlay.toggle()
            }

            if vm.layoutMode == .sideBySide && (vm.showScaleOutlines || vm.showXFeatPoints) {
                Toggle("Match threads", isOn: $vm.showCrossPhotoThreads)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AdaColors.secondaryInk)
            }

            Spacer()

            Toggle("Sync zoom & pan", isOn: $vm.syncZoomAndPan)
                .toggleStyle(.checkbox)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AdaColors.secondaryInk)

            HStack(spacing: 4) {
                Button {
                    vm.zoomScale = max(1.0, vm.zoomScale - 0.25)
                    if vm.zoomScale == 1.0 { vm.panOffset = .zero }
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)

                Button {
                    vm.resetZoomAndPan()
                } label: {
                    Text("\(Int((vm.zoomScale * 100).rounded()))%")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.plain)

                Button {
                    vm.zoomScale = min(3.0, vm.zoomScale + 0.25)
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 6)
            .frame(height: 26)
            .background(AdaColors.canvas, in: Capsule())

            Button {
                vm.focusPostocularRegion()
            } label: {
                Text("Focus Scales (185%)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AdaColors.navy)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(AdaColors.accentSoft, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(AdaColors.card)
    }

    }

    // MARK: - Comparison Canvases (1:1 Side-by-Side | Multi-Candidate Grid | Superimpose Blend)

    private var dualComparisonCanvases: some View {
        Group {
            switch vm.layoutMode {
            case .scales:
                ScientistScalePhotos(queryName: vm.sighting.sampleImageName, galleryName: vm.selectedCandidate.sampleImageName, store: scaleReviews)
            case .contours:
                ScientistPatternStudioContainer(
                    sighting: vm.sighting,
                    candidates: vm.candidates,
                    selectedCandidateIndex: $vm.selectedCandidateIndex,
                    studioMode: $studioMode,
                    onConfirmCandidate: { idx in
                        vm.selectCandidate(at: idx)
                        vm.prepareSameTurtleConfirmation()
                    },
                    onRejectCandidate: { idx in
                        vm.selectCandidate(at: idx)
                        vm.rejectSelectedCandidateAndAdvance()
                    }
                )
            case .sideBySide:
                sideBySideComparisonCanvas
            case .multiCandidateGrid:
                multiCandidateComparisonCanvas
            case .superimposeBlend:
                superimposeComparisonCanvas
            }
        }
        .background(Color.black.opacity(0.92))
    }

    private var sideBySideComparisonCanvas: some View {
        let cand = vm.selectedCandidate
        return GeometryReader { geo in
            ZStack {
                HStack(spacing: 2) {
                    // Left: Sighting Photo (stays in place when changing candidates)
                    SimulatedTurtlePhotoPane(
                        headerBadge: "SIGHTING PHOTO (LEFT)",
                        title: vm.sighting.sightingID,
                        sideLabel: vm.sighting.side.title.uppercased(),
                        sideMatches: true,
                        dateAndLocation: "\(vm.sighting.captureDate) · \(vm.sighting.location)",
                        footerNote: vm.sighting.rangerNote,
                        sampleImageName: vm.sighting.sampleImageName,
                        showRealPhoto: vm.showRealTurtlePhotographs,
                        topologyState: vm.sighting.hasSpecularGlare ? .glareOccluded : .isomorphicMatch,
                        hasSpecularGlare: vm.sighting.hasSpecularGlare,
                        isLookalikeSplitJ3: false,
                        isRightProfile: vm.sighting.side == .right,
                        showScaleOutlines: vm.showScaleOutlines,
                        showHeadCrop: vm.showHeadRegionOutline,
                        showXFeatPoints: vm.showXFeatPoints,
                        showI3SBlobs: vm.showI3SBlobOverlay,
                        zoomScale: vm.zoomScale,
                        panOffset: $vm.panOffset
                    )

                    // Right: Selected Gallery Candidate Photo (updates when candidate changes)
                    SimulatedTurtlePhotoPane(
                        headerBadge: "GALLERY PHOTO · RANK #\(cand.rank)",
                        title: "\(cand.displayName) (\(cand.profileCode))",
                        sideLabel: cand.side.title.uppercased(),
                        sideMatches: cand.sideMatchesSighting,
                        dateAndLocation: "\(cand.captureDate) · \(cand.location)",
                        footerNote: cand.junctionSummary,
                        sampleImageName: cand.sampleImageName,
                        showRealPhoto: vm.showRealTurtlePhotographs,
                        topologyState: cand.topologyState,
                        hasSpecularGlare: false,
                        isLookalikeSplitJ3: cand.id == "cand-surya-1",
                        isRightProfile: cand.side == .right,
                        showScaleOutlines: vm.showScaleOutlines,
                        showHeadCrop: vm.showHeadRegionOutline,
                        showXFeatPoints: vm.showXFeatPoints,
                        showI3SBlobs: vm.showI3SBlobOverlay,
                        zoomScale: vm.zoomScale,
                        panOffset: $vm.panOffset
                    )
                }

                // Cross-photo correspondence lines when Scale outlines or XFeat points are active
                if vm.showCrossPhotoThreads && (vm.showScaleOutlines || vm.showXFeatPoints) {
                    Canvas { ctx, size in
                        let halfW = size.width * 0.5
                        let h = size.height
                        let leftSample = vm.sighting.sampleImageName.flatMap { I3SSampleLibrary.sample(forFilenameOrID: $0) }
                        let rightSample = cand.sampleImageName.flatMap { I3SSampleLibrary.sample(forFilenameOrID: $0) }

                        let mapPanePoint: (I3SSampleEntry?, Int, CGFloat, CGFloat, Bool) -> CGPoint = { sample, kpIndex, fallbackNX, fallbackNY, isRightPane in
                            let paneOffsetX: CGFloat = isRightPane ? halfW : 0
                            if let sample, sample.imageWidth > 0, sample.imageHeight > 0, sample.keypoints.indices.contains(kpIndex) {
                                let imgW = CGFloat(sample.imageWidth)
                                let imgH = CGFloat(sample.imageHeight)
                                let scale = max(halfW / imgW, h / imgH)
                                let originX = (halfW - imgW * scale) * 0.5
                                let originY = (h - imgH * scale) * 0.5
                                let kp = sample.keypoints[kpIndex]
                                let baseX = originX + CGFloat(kp[0]) * scale
                                let baseY = originY + CGFloat(kp[1]) * scale
                                let zoomedX = halfW * 0.5 + (baseX - halfW * 0.5) * vm.zoomScale + vm.panOffset.width
                                let zoomedY = h * 0.5 + (baseY - h * 0.5) * vm.zoomScale + vm.panOffset.height
                                return CGPoint(x: paneOffsetX + zoomedX, y: zoomedY)
                            }
                            let zoomedX = halfW * 0.5 + (fallbackNX * halfW - halfW * 0.5) * vm.zoomScale + vm.panOffset.width
                            let zoomedY = h * 0.5 + (fallbackNY * h - h * 0.5) * vm.zoomScale + vm.panOffset.height
                            return CGPoint(x: paneOffsetX + zoomedX, y: zoomedY)
                        }

                        if vm.showScaleOutlines {
                            let jMeta: [(Int, CGFloat, CGFloat, Bool)] = [
                                (0, 0.51, 0.31, true),
                                (1, 0.51, 0.40, !vm.sighting.hasSpecularGlare),
                                (2, 0.52, 0.49, cand.id != "cand-surya-1" && !vm.sighting.hasSpecularGlare && cand.topologyState == .isomorphicMatch),
                                (3, 0.52, 0.59, !vm.sighting.hasSpecularGlare && cand.topologyState == .isomorphicMatch),
                                (4, 0.61, 0.38, true),
                                (5, 0.62, 0.52, !vm.sighting.hasSpecularGlare && cand.topologyState == .isomorphicMatch),
                            ]
                            for (kpIdx, fx, fy, matches) in jMeta {
                                let p1 = mapPanePoint(leftSample, kpIdx, fx, fy, false)
                                let p2 = mapPanePoint(rightSample, kpIdx, fx, fy, true)
                                var path = Path()
                                path.move(to: p1)
                                path.addLine(to: p2)
                                let col: Color = vm.sighting.hasSpecularGlare && !matches ? .orange : (matches ? .green : .red)
                                ctx.stroke(
                                    path,
                                    with: .color(col.opacity(0.75)),
                                    style: StrokeStyle(lineWidth: matches ? 1.8 : 2.4, dash: matches ? [] : [6, 4])
                                )
                            }
                        } else if vm.showXFeatPoints {
                            for kpIdx in 0..<8 {
                                let p1 = mapPanePoint(leftSample, kpIdx, 0.45, 0.45, false)
                                let p2 = mapPanePoint(rightSample, kpIdx, 0.45, 0.45, true)
                                var path = Path()
                                path.move(to: p1)
                                path.addLine(to: p2)
                                ctx.stroke(path, with: .color(Color.cyan.opacity(0.65)), lineWidth: 1.5)
                            }
                        }
                    }
                    .allowsHitTesting(false)
                }
            }
        }
    }

    private var multiCandidateComparisonCanvas: some View {
        GeometryReader { geo in
            let leftWidth = max(290, geo.size.width * 0.35)
            HStack(spacing: 8) {
                // Pinned Sighting Photo on the Left
                SimulatedTurtlePhotoPane(
                    headerBadge: "PINNED SIGHTING PHOTO",
                    title: vm.sighting.sightingID,
                    sideLabel: vm.sighting.side.title.uppercased(),
                    sideMatches: true,
                    dateAndLocation: "\(vm.sighting.captureDate) · \(vm.sighting.location)",
                    footerNote: vm.sighting.rangerNote,
                    sampleImageName: vm.sighting.sampleImageName,
                    showRealPhoto: vm.showRealTurtlePhotographs,
                    topologyState: vm.sighting.hasSpecularGlare ? .glareOccluded : .isomorphicMatch,
                    hasSpecularGlare: vm.sighting.hasSpecularGlare,
                    isLookalikeSplitJ3: false,
                    isRightProfile: vm.sighting.side == .right,
                    showScaleOutlines: vm.showScaleOutlines,
                    showHeadCrop: vm.showHeadRegionOutline,
                    showXFeatPoints: vm.showXFeatPoints,
                    showI3SBlobs: vm.showI3SBlobOverlay,
                    zoomScale: vm.zoomScale,
                    panOffset: $vm.panOffset
                )
                .frame(width: leftWidth)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.cyan.opacity(0.6), lineWidth: 1.5)
                )

                // Simultaneous Multi-Candidate Grid on the Right
                ScrollView {
                    let cols = [
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8)
                    ]
                    LazyVGrid(columns: cols, spacing: 8) {
                        ForEach(vm.multiComparisonCandidates) { cand in
                            let isCurrentSelected = cand.id == vm.selectedCandidate.id
                            VStack(spacing: 0) {
                                SimulatedTurtlePhotoPane(
                                    headerBadge: "RANK #\(cand.rank) (\(cand.relativeMatchScore)%)",
                                    title: cand.displayName,
                                    sideLabel: cand.side.title.uppercased(),
                                    sideMatches: cand.sideMatchesSighting,
                                    dateAndLocation: cand.captureDate,
                                    footerNote: cand.junctionSummary,
                                    sampleImageName: cand.sampleImageName,
                                    showRealPhoto: vm.showRealTurtlePhotographs,
                                    topologyState: cand.topologyState,
                                    hasSpecularGlare: false,
                                    isLookalikeSplitJ3: cand.id == "cand-surya-1",
                                    isRightProfile: cand.side == .right,
                                    showScaleOutlines: vm.showScaleOutlines,
                                    showHeadCrop: vm.showHeadRegionOutline,
                                    showXFeatPoints: vm.showXFeatPoints,
                                    showI3SBlobs: vm.showI3SBlobOverlay,
                                    zoomScale: vm.zoomScale,
                                    panOffset: $vm.panOffset
                                )
                                .frame(height: max(195, (geo.size.height - 86) * 0.5))

                                // Quick per-card action bar inside Multi-Photo Grid
                                HStack(spacing: 6) {
                                    Button {
                                        if let idx = vm.candidates.firstIndex(where: { $0.id == cand.id }) {
                                            vm.selectCandidate(at: idx)
                                            vm.layoutMode = .sideBySide
                                        }
                                    } label: {
                                        Label("Focus 1:1", systemImage: "arrow.up.left.and.arrow.down.right")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 8)
                                            .frame(height: 22)
                                            .background(Color.white.opacity(0.14), in: Capsule())
                                    }
                                    .buttonStyle(.plain)

                                    Spacer()

                                    Button {
                                        if let idx = vm.candidates.firstIndex(where: { $0.id == cand.id }) {
                                            vm.selectCandidate(at: idx)
                                            vm.prepareSameTurtleConfirmation()
                                        }
                                    } label: {
                                        Text("Same turtle…")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 8)
                                            .frame(height: 22)
                                            .background(AdaColors.green, in: Capsule())
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        if let idx = vm.candidates.firstIndex(where: { $0.id == cand.id }) {
                                            vm.selectCandidate(at: idx)
                                            vm.rejectSelectedCandidateAndAdvance()
                                        }
                                    } label: {
                                        Text("Different")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 8)
                                            .frame(height: 22)
                                            .background(AdaColors.red, in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Color.black.opacity(0.85))
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(
                                        isCurrentSelected ? Color.green : Color.white.opacity(0.22),
                                        lineWidth: isCurrentSelected ? 2.0 : 1.0
                                    )
                            )
                        }
                    }
                }
            }
            .padding(8)
        }
    }

    private var superimposeComparisonCanvas: some View {
        let cand = vm.selectedCandidate
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("SUPERIMPOSE / BLINK COMPARE:")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.cyan)
                Text("0% Sighting (\(vm.sighting.sightingID))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                Slider(value: $vm.superimposeBlendOpacity, in: 0.0...1.0, step: 0.05)
                    .frame(width: 220)
                Text("100% Candidate (\(cand.displayName))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))

                Button("0% Sighting") { vm.superimposeBlendOpacity = 0.0 }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("50/50 Blend") { vm.superimposeBlendOpacity = 0.5 }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("100% Candidate") { vm.superimposeBlendOpacity = 1.0 }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.75))

            ZStack {
                SimulatedTurtlePhotoPane(
                    headerBadge: "BASE: SIGHTING PHOTO",
                    title: vm.sighting.sightingID,
                    sideLabel: vm.sighting.side.title.uppercased(),
                    sideMatches: true,
                    dateAndLocation: vm.sighting.captureDate,
                    footerNote: vm.sighting.rangerNote,
                    sampleImageName: vm.sighting.sampleImageName,
                    showRealPhoto: vm.showRealTurtlePhotographs,
                    topologyState: vm.sighting.hasSpecularGlare ? .glareOccluded : .isomorphicMatch,
                    hasSpecularGlare: vm.sighting.hasSpecularGlare,
                    isLookalikeSplitJ3: false,
                    isRightProfile: vm.sighting.side == .right,
                    showScaleOutlines: vm.showScaleOutlines,
                    showHeadCrop: vm.showHeadRegionOutline,
                    showXFeatPoints: vm.showXFeatPoints,
                    showI3SBlobs: vm.showI3SBlobOverlay,
                    zoomScale: vm.zoomScale,
                    panOffset: $vm.panOffset
                )
                .opacity(1.0 - vm.superimposeBlendOpacity * 0.85)

                SimulatedTurtlePhotoPane(
                    headerBadge: "OVERLAY: RANK #\(cand.rank) \(cand.displayName)",
                    title: "\(cand.displayName) (\(cand.profileCode))",
                    sideLabel: cand.side.title.uppercased(),
                    sideMatches: cand.sideMatchesSighting,
                    dateAndLocation: cand.captureDate,
                    footerNote: cand.junctionSummary,
                    sampleImageName: cand.sampleImageName,
                    showRealPhoto: vm.showRealTurtlePhotographs,
                    topologyState: cand.topologyState,
                    hasSpecularGlare: false,
                    isLookalikeSplitJ3: cand.id == "cand-surya-1",
                    isRightProfile: cand.side == .right,
                    showScaleOutlines: vm.showScaleOutlines,
                    showHeadCrop: vm.showHeadRegionOutline,
                    showXFeatPoints: vm.showXFeatPoints,
                    showI3SBlobs: vm.showI3SBlobOverlay,
                    zoomScale: vm.zoomScale,
                    panOffset: $vm.panOffset
                )
                .opacity(vm.superimposeBlendOpacity)
            }
        }
    }

    // MARK: - Evidence Drawer (Relative Match Score + More Evidence with I3S Pattern)

    private var evidenceDrawerSection: some View {
        let cand = vm.selectedCandidate
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        vm.isEvidenceDrawerExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: vm.isEvidenceDrawerExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                        Text("Evidence Drawer")
                            .font(.system(size: 12, weight: .semibold))
                        Text("· Relative match score \(cand.relativeMatchScore)% · \(cand.junctionSummary)")
                            .font(.system(size: 12))
                            .foregroundStyle(AdaColors.secondaryInk)
                    }
                    .foregroundStyle(AdaColors.ink)
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        vm.isMoreEvidenceExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text("More evidence (I3S Pattern)")
                            .font(.system(size: 11, weight: .semibold))
                        Image(systemName: vm.isMoreEvidenceExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(AdaColors.navy)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(AdaColors.card, in: Capsule())
                    .overlay(Capsule().stroke(AdaColors.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            if vm.isEvidenceDrawerExpanded {
                HStack(alignment: .top, spacing: 10) {
                    // 1. Backend Relative Match Score
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Relative match score")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AdaColors.secondaryInk)
                            Spacer()
                            Text("\(cand.relativeMatchScore)%")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(AdaColors.ink)
                        }
                        Text("MiewID cosine \(String(format: "%.2f", cand.miewCosine)). Relative to strongest shortlist rival, not P(same individual).")
                            .font(.system(size: 11))
                            .foregroundStyle(AdaColors.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AdaColors.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    // 2. Scale Junction Topology Evidence
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Postocular scale junctions")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AdaColors.secondaryInk)
                            Spacer()
                            Text(cand.junctionSummary)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(
                                    cand.topologyState == .isomorphicMatch
                                        ? AdaColors.green
                                        : (cand.topologyState == .glareOccluded ? AdaColors.orange : AdaColors.red)
                                )
                        }
                        Text(cand.junctionDetail)
                            .font(.system(size: 11))
                            .foregroundStyle(AdaColors.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AdaColors.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    // 3. XFeat Local Correspondences
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("XFeat correspondences")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AdaColors.secondaryInk)
                            Spacer()
                            Text("\(cand.xfeatMatchedPoints) pts")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(AdaColors.ink)
                        }
                        Text("Illustrative keypoint positions, not computed XFeat correspondences. Toggle 'XFeat points' to inspect the schematic.")
                            .font(.system(size: 11))
                            .foregroundStyle(AdaColors.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AdaColors.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }

            if vm.isMoreEvidenceExpanded {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text("I3S Pattern (v4.02)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(AdaColors.ink)
                            Text("Lower means closer patterns")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AdaColors.orange)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(AdaColors.orange.opacity(0.14), in: Capsule())
                            if let dist = cand.i3sDistance {
                                Text(String(format: "Distance: %.2f (%d/35 pairs)", dist, cand.i3sMatchedPairs))
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundStyle(AdaColors.ink)
                            } else {
                                Text("Unavailable (Head-side mismatch)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(AdaColors.red)
                            }
                        }
                        Text("Note: In ADA Penyu's 13-photo replay across 5 green turtles, genuine distances (3.28–15.55) overlapped rival distances (11.16–22.35) when the true turtle was absent.")
                            .font(.system(size: 11))
                            .foregroundStyle(AdaColors.secondaryInk)
                    }
                    Spacer()
                    Toggle("Show I3S 3-landmark & blobs", isOn: $vm.showI3SBlobOverlay)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(10)
                .background(AdaColors.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(AdaColors.canvas)
    }

    // MARK: - Always-Visible Scientist Decision Bar

    private var decisionActionBar: some View {
        Group {
            let cand = vm.selectedCandidate
            HStack(spacing: 10) {
                Text("\(vm.sighting.sightingID) vs #\(cand.rank) \(cand.displayName)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AdaColors.ink)
                    .lineLimit(1)

                if let outcome = vm.currentOutcome {
                    Text(outcome.resolution == .linkedToExisting ? "Confirmed" : "Saved Unsure")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(outcome.resolution == .linkedToExisting ? AdaColors.green : AdaColors.orange, in: Capsule())
                }

                Spacer()

                Button {
                    vm.prepareSameTurtleConfirmation()
                } label: {
                    Label("Same Turtle", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .background(AdaColors.green, in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    vm.rejectSelectedCandidateAndAdvance()
                } label: {
                    Label("Different", systemImage: "xmark.circle.fill")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .background(AdaColors.red, in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    vm.prepareUnsureSheet()
                } label: {
                    Label("Unsure…", systemImage: "questionmark.circle")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(AdaColors.ink)
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .background(AdaColors.canvas, in: Capsule())
                        .overlay(Capsule().stroke(AdaColors.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(AdaColors.card)
        }
    }

    private var bundledInspector: some View {
        let queryThumb = vm.sighting.sampleImageName.flatMap { I3SSampleLibrary.loadImage(named: $0) }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if let queryThumb {
                    Image(nsImage: queryThumb)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(vm.sighting.sightingID)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AdaColors.ink)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(vm.sighting.side.title)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(AdaColors.navy)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(AdaColors.canvas, in: Capsule())
                        Text(vm.sighting.location)
                            .font(.system(size: 10.5))
                            .foregroundStyle(AdaColors.secondaryInk)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(AdaColors.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack {
                Text("Candidates (\(vm.candidates.count))")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AdaColors.ink)
                Spacer()
                Button {
                    if vm.layoutMode == .contours {
                        studioMode = studioMode == .oneVsThree ? .oneToOne : .oneVsThree
                    } else if vm.layoutMode == .multiCandidateGrid {
                        vm.layoutMode = .sideBySide
                    } else {
                        vm.layoutMode = .contours
                        studioMode = .oneVsThree
                    }
                } label: {
                    Label(
                        (vm.layoutMode == .contours && studioMode == .oneVsThree)
                            ? "Focus 1:1"
                            : "1 vs 3",
                        systemImage: (vm.layoutMode == .contours && studioMode == .oneVsThree) ? "rectangle.split.2x1" : "square.grid.2x2"
                    )
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .frame(height: 22)
                    .background(AdaColors.navy, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            ScrollView {
                VStack(spacing: 7) {
                    ForEach(Array(vm.candidates.enumerated()), id: \.element.id) { index, item in
                        let isSelected = index == vm.selectedCandidateIndex
                        let isInMulti = vm.multiSelectedCandidateIDs.contains(item.id)
                        let candThumb = item.sampleImageName.flatMap { I3SSampleLibrary.loadImage(named: $0) }
                        Button {
                            vm.selectCandidate(at: index)
                        } label: {
                            HStack(spacing: 8) {
                                if vm.layoutMode == .multiCandidateGrid {
                                    Button {
                                        vm.toggleMultiCandidateSelection(item.id)
                                    } label: {
                                        Image(systemName: isInMulti ? "checkmark.square.fill" : "square")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(isInMulti ? AdaColors.accent : AdaColors.tertiaryInk)
                                    }
                                    .buttonStyle(.plain)
                                }

                                if let candThumb {
                                    Image(nsImage: candThumb)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 42, height: 42)
                                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                }

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 4) {
                                        Text("#\(item.rank)")
                                            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                            .foregroundStyle(isSelected ? .white : AdaColors.ink)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 1)
                                            .background(isSelected ? AdaColors.navy : AdaColors.canvas, in: Capsule())

                                        Text(item.displayName)
                                            .font(.system(size: 11.5, weight: .bold))
                                            .foregroundStyle(AdaColors.ink)
                                            .lineLimit(1)

                                        Spacer()

                                        Text("\(item.relativeMatchScore)%")
                                            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                            .foregroundStyle(AdaColors.secondaryInk)
                                    }

                                    HStack {
                                        Text(item.side.title)
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(item.sideMatchesSighting ? AdaColors.secondaryInk : AdaColors.red)
                                        Text("· \(item.captureDate)")
                                            .font(.system(size: 10))
                                            .foregroundStyle(AdaColors.secondaryInk)
                                            .lineLimit(1)
                                        Spacer()
                                        if item.status != .pending {
                                            Text(item.status.rawValue)
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundStyle(item.status == .confirmed ? AdaColors.green : AdaColors.red)
                                        }
                                    }
                                }
                            }
                            .padding(8)
                            .background(AdaColors.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(isSelected ? AdaColors.navy : AdaColors.line, lineWidth: isSelected ? 2 : 1)
                            )
                            .opacity(item.status == .rejected ? 0.60 : 1.0)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Button {
                vm.runWiderSearch()
            } label: {
                Label(
                    vm.widerSearchExecuted.contains(vm.activeScenario)
                        ? "Rank #4 Added"
                        : "Wider Search (+Rank #4)",
                    systemImage: "magnifyingglass.circle"
                )
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AdaColors.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(AdaColors.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(AdaColors.line, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(vm.widerSearchExecuted.contains(vm.activeScenario))
        }
        .padding(10)
    }

    // MARK: - Confirmation & Unsure Modals

    private var confirmSameTurtleSheet: some View {
        let cand = vm.selectedCandidate
        return VStack(alignment: .leading, spacing: 14) {
            Text("Demo · simulate identity confirmation")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(AdaColors.ink)

            Text("Link \(vm.sighting.sightingID) (\(vm.sighting.side.title)) to existing catalog individual \(cand.displayName) (\(cand.profileCode))?")
                .font(.system(size: 12))
                .foregroundStyle(AdaColors.secondaryInk)

            if cand.topologyState != .isomorphicMatch {
                Text("Warning: \(cand.junctionDetail)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AdaColors.red)
                    .padding(10)
                    .background(AdaColors.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            }

            Toggle("Nominate sighting photo for Gallery Reference admission (Separate decision)", isOn: $vm.nominateForGalleryReference)
                .font(.system(size: 12, weight: .medium))

            VStack(alignment: .leading, spacing: 4) {
                Text("Verification Note")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AdaColors.secondaryInk)
                TextField("Scientist verification note", text: $vm.confirmationNotes)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Cancel") {
                    vm.isConfirmSameTurtlePresented = false
                }
                Spacer()
                Button("Simulate confirmation") {
                    vm.confirmSameTurtleIdentity()
                }
                .buttonStyle(.borderedProminent)
                .tint(AdaColors.green)
            }
        }
        .padding(22)
        .frame(width: 460)
    }

    private var saveUnsureSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Demo · record unsure in memory")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(AdaColors.ink)

            Text("Preserves \(vm.sighting.sightingID) and review notes with the identity field empty so ambiguous or glare-occluded encounters never corrupt gallery records.")
                .font(.system(size: 12))
                .foregroundStyle(AdaColors.secondaryInk)

            Toggle("Request a better photo from ranger", isOn: $vm.requestBetterPhoto)
                .font(.system(size: 12, weight: .medium))

            Toggle("Request a second scientist review", isOn: $vm.requestSecondReview)
                .font(.system(size: 12, weight: .medium))

            VStack(alignment: .leading, spacing: 4) {
                Text("Demo notes · discarded on reset or app exit")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AdaColors.secondaryInk)
                TextEditor(text: $vm.unsureNotes)
                    .font(.system(size: 12))
                    .frame(height: 76)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(AdaColors.line, lineWidth: 1))
            }

            HStack {
                Button("Cancel") {
                    vm.isUnsureSheetPresented = false
                }
                Spacer()
                Button("Keep unsure in this demo") {
                    vm.saveUnsureDecision()
                }
                .buttonStyle(.borderedProminent)
                .tint(AdaColors.orange)
            }
        }
        .padding(22)
        .frame(width: 460)
    }
}

// MARK: - Simulated & Real Sea Turtle Head Photo + Overlays Canvas

private struct SimulatedTurtlePhotoPane: View {
    let headerBadge: String
    let title: String
    let sideLabel: String
    let sideMatches: Bool
    let dateAndLocation: String
    let footerNote: String
    let sampleImageName: String?
    let showRealPhoto: Bool
    let topologyState: JunctionTopologyState
    let hasSpecularGlare: Bool
    let isLookalikeSplitJ3: Bool
    let isRightProfile: Bool
    let showScaleOutlines: Bool
    let showHeadCrop: Bool
    let showXFeatPoints: Bool
    let showI3SBlobs: Bool
    let zoomScale: CGFloat
    @Binding var panOffset: CGSize

    @State private var dragStartOffset: CGSize? = nil
    @State private var extractedPatterns: [DetectedScalePattern] = []
    @State private var extractedROI: [ScalePoint] = []
    @State private var extractedKey: String = ""

    private var matchedSampleEntry: I3SSampleEntry? {
        guard let sampleImageName else { return nil }
        return I3SSampleLibrary.sample(forFilenameOrID: sampleImageName)
    }

    private var loadedSampleImage: NSImage? {
        guard showRealPhoto, let sample = matchedSampleEntry else { return nil }
        return I3SSampleLibrary.loadImage(for: sample)
    }

    var body: some View {
        ZStack {
            // Interactive Photo + Anatomical Overlay Canvas
            GeometryReader { geo in
                ZStack {
                    if let realImg = loadedSampleImage {
                        Image(nsImage: realImg)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()

                    }

                    Canvas { context, size in
                        drawSimulatedTurtleHead(
                            in: &context,
                            size: size,
                            overRealPhoto: loadedSampleImage != nil,
                            imageSize: loadedSampleImage?.size
                        )
                    }
                }
                .scaleEffect(zoomScale)
                .offset(panOffset)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let base = dragStartOffset ?? panOffset
                            if dragStartOffset == nil { dragStartOffset = panOffset }
                            panOffset = CGSize(
                                width: base.width + value.translation.width,
                                height: base.height + value.translation.height
                            )
                        }
                        .onEnded { _ in
                            dragStartOffset = nil
                        }
                )
            }
            .task(id: "\(sampleImageName ?? "")|\(showScaleOutlines)") {
                await extractRealPatternsIfNeeded()
            }

            // Top & Bottom Overlay Chrome
            VStack {
                HStack(spacing: 8) {
                    Text(headerBadge)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.cyan)
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(sideLabel)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(sideMatches ? Color.green : Color.red)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.12), in: Capsule())
                    Spacer()
                    if !extractedPatterns.isEmpty && showScaleOutlines {
                        Text("\(extractedPatterns.count) scales")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(Color.mint)
                    } else {
                        Text(dateAndLocation)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.82))
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
                .padding(8)

                Spacer()

                HStack {
                    Text(footerNote)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.68))
            }
        }
        .clipped()
    }

    @MainActor
    private func extractRealPatternsIfNeeded() async {
        let key = sampleImageName ?? ""
        guard showScaleOutlines, let img = loadedSampleImage else { return }
        if extractedKey == key && !extractedPatterns.isEmpty { return }
        let sample = matchedSampleEntry
        let side: TurtlePhotoSide = isRightProfile ? .right : .left
        guard let raster = PatternContourEngine.underwaterLuminance(from: img, maxDimension: 360) else { return }
        let sampleROIPoints: [ScalePoint] = {
            guard let s = sample, s.imageWidth > 0, s.imageHeight > 0, s.roi.count >= 3 else { return [] }
            let w = Double(s.imageWidth)
            let h = Double(s.imageHeight)
            return s.roi.compactMap { pair in
                pair.count >= 2 ? ScalePoint(x: pair[0] / w, y: pair[1] / h) : nil
            }
        }()
        let result = await Task.detached(priority: .userInitiated) { () -> ([ScalePoint], [DetectedScalePattern]) in
            let roi = sampleROIPoints.count >= 3
                ? sampleROIPoints
                : PatternContourEngine.detectFacialPatternROI(from: raster, side: side).roi
            let patterns = PatternContourEngine.extractPatterns(from: raster, roiPolygon: roi)
            return (roi, patterns)
        }.value
        extractedROI = result.0
        extractedPatterns = result.1
        extractedKey = key
    }

    private func drawSimulatedTurtleHead(
        in context: inout GraphicsContext,
        size: CGSize,
        overRealPhoto: Bool,
        imageSize: CGSize?
    ) {
        let w = size.width
        let h = size.height
        if !overRealPhoto {
            let bgRect = CGRect(origin: .zero, size: size)
            context.fill(
                Path(bgRect),
                with: .linearGradient(
                    Gradient(colors: [Color(red: 0.05, green: 0.23, blue: 0.29), Color(red: 0.03, green: 0.12, blue: 0.17)]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: h)
                )
            )
        }

        let mapX: (CGFloat) -> CGFloat = { normX in
            let x = isRightProfile ? (1.0 - normX) : normX
            return x * w
        }
        let mapY: (CGFloat) -> CGFloat = { normY in normY * h }

        // Pixel-accurate mapping for bundled real photographs using their .fgp calibration
        let sample = matchedSampleEntry
        let imgW = CGFloat(sample?.imageWidth ?? Int(imageSize?.width ?? 1000))
        let imgH = CGFloat(sample?.imageHeight ?? Int(imageSize?.height ?? 750))
        let fillScale = max(w / max(imgW, 1), h / max(imgH, 1))
        let fillOriginX = (w - imgW * fillScale) * 0.5
        let fillOriginY = (h - imgH * fillScale) * 0.5
        let mapSamplePixel: (Double, Double) -> CGPoint = { px, py in
            CGPoint(x: fillOriginX + CGFloat(px) * fillScale, y: fillOriginY + CGFloat(py) * fillScale)
        }
        let mapNormalizedPoint: (ScalePoint) -> CGPoint = { pt in
            CGPoint(x: fillOriginX + pt.x * imgW * fillScale, y: fillOriginY + pt.y * imgH * fillScale)
        }

        if !overRealPhoto {
            // Head silhouette
            var headPath = Path()
            headPath.move(to: CGPoint(x: mapX(0.22), y: mapY(0.55)))
            headPath.addQuadCurve(to: CGPoint(x: mapX(0.32), y: mapY(0.26)), control: CGPoint(x: mapX(0.20), y: mapY(0.36)))
            headPath.addQuadCurve(to: CGPoint(x: mapX(0.78), y: mapY(0.32)), control: CGPoint(x: mapX(0.55), y: mapY(0.20)))
            headPath.addLine(to: CGPoint(x: mapX(0.78), y: mapY(0.76)))
            headPath.addQuadCurve(to: CGPoint(x: mapX(0.22), y: mapY(0.55)), control: CGPoint(x: mapX(0.45), y: mapY(0.74)))
            headPath.closeSubpath()
            context.fill(headPath, with: .color(Color(red: 0.24, green: 0.33, blue: 0.27)))
            context.stroke(headPath, with: .color(Color(red: 0.72, green: 0.82, blue: 0.74)), lineWidth: 2.2)

            // Eye orbit
            let eyeCenter = CGPoint(x: mapX(0.35), y: mapY(0.42))
            let eyeRect = CGRect(x: eyeCenter.x - 22, y: eyeCenter.y - 17, width: 44, height: 34)
            context.fill(Path(ellipseIn: eyeRect), with: .color(Color.black.opacity(0.82)))
            context.stroke(Path(ellipseIn: eyeRect), with: .color(Color.white.opacity(0.65)), lineWidth: 2)
        }

        // Real extracted numbered facial scale pattern contours on actual photos
        if overRealPhoto && showScaleOutlines && !extractedPatterns.isEmpty {
            if extractedROI.count >= 3 {
                var roiPath = Path()
                for (idx, pt) in extractedROI.enumerated() {
                    let c = mapNormalizedPoint(pt)
                    if idx == 0 { roiPath.move(to: c) } else { roiPath.addLine(to: c) }
                }
                roiPath.closeSubpath()
                context.stroke(
                    roiPath,
                    with: .color(Color.cyan.opacity(0.48)),
                    style: StrokeStyle(lineWidth: 1.3, dash: [6, 4])
                )
            }
            for scale in extractedPatterns {
                guard scale.polygon.count >= 3 else { continue }
                var poly = Path()
                for (idx, pt) in scale.polygon.enumerated() {
                    let c = mapNormalizedPoint(pt)
                    if idx == 0 { poly.move(to: c) } else { poly.addLine(to: c) }
                }
                poly.closeSubpath()
                context.fill(poly, with: .color(Color.mint.opacity(0.14)))
                context.stroke(poly, with: .color(Color.mint.opacity(0.95)), style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round))

                let center = mapNormalizedPoint(scale.centroid)
                let pillRect = CGRect(x: center.x - 8, y: center.y - 7, width: 16, height: 14)
                context.fill(Path(roundedRect: pillRect, cornerRadius: 4), with: .color(Color.black.opacity(0.76)))
                context.draw(
                    Text("\(scale.number)").font(.system(size: 9, weight: .bold, design: .rounded)).foregroundStyle(Color.mint),
                    at: center
                )
            }
        } else if !overRealPhoto {
            let polygons: [[(CGFloat, CGFloat)]] = [
                [(0.42, 0.32), (0.51, 0.31), (0.51, 0.40), (0.43, 0.41)],
                [(0.43, 0.41), (0.51, 0.40), (0.52, 0.49), (0.43, 0.50)],
                [(0.43, 0.50), (0.52, 0.49), (0.52, 0.59), (0.44, 0.58)],
                [(0.51, 0.40), (0.61, 0.38), (0.62, 0.52), (0.52, 0.49)],
                [(0.52, 0.49), (0.62, 0.52), (0.60, 0.62), (0.52, 0.59)],
            ]
            for (idx, poly) in polygons.enumerated() {
                var p = Path()
                for (pIdx, pt) in poly.enumerated() {
                    let c = CGPoint(x: mapX(pt.0), y: mapY(pt.1))
                    if pIdx == 0 { p.move(to: c) } else { p.addLine(to: c) }
                }
                p.closeSubpath()
                context.fill(p, with: .color(Color(red: 0.11, green: 0.18, blue: 0.14)))
                context.stroke(p, with: .color(Color.mint), lineWidth: 2.4)
                if showScaleOutlines {
                    let cx = poly.map(\.0).reduce(0, +) / CGFloat(poly.count)
                    let cy = poly.map(\.1).reduce(0, +) / CGFloat(poly.count)
                    context.draw(
                        Text("\(idx + 1)").font(.system(size: 10, weight: .bold)).foregroundStyle(.white),
                        at: CGPoint(x: mapX(cx), y: mapY(cy))
                    )
                }
            }
        }

        // Glare highlight indicator when glare occludes center scales
        if hasSpecularGlare && showScaleOutlines {
            let glareCenter: CGPoint = {
                if overRealPhoto, let sample, sample.keypoints.count > 2 {
                    return mapSamplePixel(sample.keypoints[2][0], sample.keypoints[2][1])
                }
                return CGPoint(x: mapX(0.53), y: mapY(0.49))
            }()
            let glareRect = CGRect(x: glareCenter.x - 52, y: glareCenter.y - 38, width: 104, height: 76)
            context.fill(Path(ellipseIn: glareRect), with: .color(Color.yellow.opacity(0.14)))
            context.stroke(
                Path(ellipseIn: glareRect),
                with: .color(Color.yellow.opacity(0.85)),
                style: StrokeStyle(lineWidth: 1.8, dash: [6, 4])
            )
        }

        // Head Region Outline (Real .fgp Cheek ROI Polygon)
        if showHeadCrop {
            if overRealPhoto, let sample, sample.roi.count >= 3 {
                var roiPath = Path()
                for (idx, pair) in sample.roi.enumerated() where pair.count >= 2 {
                    let pt = mapSamplePixel(pair[0], pair[1])
                    if idx == 0 { roiPath.move(to: pt) } else { roiPath.addLine(to: pt) }
                }
                roiPath.closeSubpath()
                context.fill(roiPath, with: .color(Color.cyan.opacity(0.08)))
                context.stroke(
                    roiPath,
                    with: .color(Color.cyan),
                    style: StrokeStyle(lineWidth: 2.2, dash: [8, 5])
                )
            } else {
                let cropRect = CGRect(x: w * 0.18, y: h * 0.18, width: w * 0.64, height: h * 0.64)
                context.stroke(
                    Path(roundedRect: cropRect, cornerRadius: 10),
                    with: .color(Color.cyan),
                    style: StrokeStyle(lineWidth: 2.0, dash: [8, 5])
                )
            }
        }

        // XFeat Correspondences anchored to actual cheek keypoints
        if showXFeatPoints {
            if overRealPhoto, let sample, !sample.keypoints.isEmpty {
                for kp in sample.keypoints.prefix(12) where kp.count >= 2 {
                    let pt = mapSamplePixel(kp[0], kp[1])
                    let rect = CGRect(x: pt.x - 5.5, y: pt.y - 5.5, width: 11, height: 11)
                    context.fill(Path(ellipseIn: rect), with: .color(Color.cyan.opacity(0.55)))
                    context.stroke(Path(ellipseIn: rect), with: .color(.white), lineWidth: 1.5)
                }
            } else {
                let xfeatCoords: [(CGFloat, CGFloat)] = [
                    (0.28, 0.52), (0.36, 0.38), (0.45, 0.36),
                    (0.47, 0.46), (0.56, 0.44), (0.56, 0.56),
                ]
                for (xx, xy) in xfeatCoords {
                    let pt = CGPoint(x: mapX(xx), y: mapY(xy))
                    let rect = CGRect(x: pt.x - 6, y: pt.y - 6, width: 12, height: 12)
                    context.fill(Path(ellipseIn: rect), with: .color(Color.purple.opacity(0.45)))
                    context.stroke(Path(ellipseIn: rect), with: .color(Color.purple), lineWidth: 2)
                }
            }
        }

        // I3S 3-Landmark & 35-Blob Overlay anchored to exact .fgp calibration
        if showI3SBlobs {
            if overRealPhoto, let sample {
                for kp in sample.keypoints where kp.count >= 3 {
                    let pt = mapSamplePixel(kp[0], kp[1])
                    let r = max(4, CGFloat(kp[2]) * 0.42 * fillScale)
                    let rect = CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)
                    context.stroke(Path(ellipseIn: rect), with: .color(Color.red.opacity(0.85)), lineWidth: 1.4)
                }
                for ref in [sample.ref1, sample.ref2, sample.ref3] where ref.count >= 2 {
                    let pt = mapSamplePixel(ref[0], ref[1])
                    let rect = CGRect(x: pt.x - 6, y: pt.y - 6, width: 12, height: 12)
                    context.fill(Path(ellipseIn: rect), with: .color(Color.blue))
                    context.stroke(Path(ellipseIn: rect), with: .color(.white), lineWidth: 1.8)
                }
            } else {
                let landmarks: [(CGFloat, CGFloat)] = [(0.23, 0.56), (0.31, 0.42), (0.61, 0.30)]
                for (lx, ly) in landmarks {
                    let pt = CGPoint(x: mapX(lx), y: mapY(ly))
                    let rect = CGRect(x: pt.x - 6, y: pt.y - 6, width: 12, height: 12)
                    context.fill(Path(ellipseIn: rect), with: .color(Color.blue))
                    context.stroke(Path(ellipseIn: rect), with: .color(.white), lineWidth: 1.5)
                }
            }
        }
    }
}

/// Bridges ScientistReviewWorkspaceView sighting + ranked candidates into PatternContourStudioView.
private struct ScientistPatternStudioContainer: View {
    let sighting: ReviewSightingItem
    let candidates: [ReviewCandidateItem]
    @Binding var selectedCandidateIndex: Int
    @Binding var studioMode: PatternStudioMode
    let onConfirmCandidate: (Int) -> Void
    let onRejectCandidate: (Int) -> Void

    @State private var queryImage: NSImage?
    @State private var candidateImages: [String: NSImage] = [:]

    private var queryTarget: PatternComparisonTarget {
        let sample = sighting.sampleImageName.flatMap { I3SSampleLibrary.sample(forFilenameOrID: $0) }
        return PatternComparisonTarget(
            id: sighting.sightingID,
            rank: 0,
            title: sighting.sightingID,
            subtitle: "\(sighting.side.title) · \(sighting.location)",
            side: sighting.side,
            sideMatches: true,
            image: queryImage,
            sampleEntry: sample,
            fingerprint: nil,
            customROI: nil
        )
    }

    private var candidateTargets: [PatternComparisonTarget] {
        candidates.map { item in
            let sample = item.sampleImageName.flatMap { I3SSampleLibrary.sample(forFilenameOrID: $0) }
            return PatternComparisonTarget(
                id: item.id,
                rank: item.rank,
                title: item.displayName,
                subtitle: "\(item.profileCode) · \(item.relativeMatchScore)%",
                side: item.side,
                sideMatches: item.sideMatchesSighting,
                image: candidateImages[item.id],
                sampleEntry: sample,
                fingerprint: nil,
                customROI: nil
            )
        }
    }

    private var selectedIDBinding: Binding<String> {
        Binding(
            get: {
                guard candidates.indices.contains(selectedCandidateIndex) else {
                    return candidates.first?.id ?? ""
                }
                return candidates[selectedCandidateIndex].id
            },
            set: { nextID in
                if let idx = candidates.firstIndex(where: { $0.id == nextID }) {
                    selectedCandidateIndex = idx
                }
            }
        )
    }

    private var loadKey: String {
        "\(sighting.sampleImageName ?? "")|\(candidates.map(\.id).joined(separator: ","))"
    }

    var body: some View {
        PatternContourStudioView(
            query: queryTarget,
            candidates: candidateTargets,
            selectedCandidateID: selectedIDBinding,
            mode: $studioMode,
            onSelectCandidateID: { nextID in
                if let idx = candidates.firstIndex(where: { $0.id == nextID }) {
                    selectedCandidateIndex = idx
                }
            },
            onConfirmCandidate: { target in
                if let idx = candidates.firstIndex(where: { $0.id == target.id }) {
                    onConfirmCandidate(idx)
                }
            },
            onRejectCandidate: { target in
                if let idx = candidates.firstIndex(where: { $0.id == target.id }) {
                    onRejectCandidate(idx)
                }
            }
        )
        .task(id: loadKey) {
            queryImage = sighting.sampleImageName.flatMap { I3SSampleLibrary.loadImage(named: $0) }
            var loaded: [String: NSImage] = [:]
            for cand in candidates {
                if let img = cand.sampleImageName.flatMap({ I3SSampleLibrary.loadImage(named: $0) }) {
                    loaded[cand.id] = img
                }
            }
            candidateImages = loaded
        }
    }
}

private struct ScientistScalePhotos: View {
    let queryName: String?
    let galleryName: String?
    @ObservedObject var store: ScaleReviewStore
    @State private var query: NSImage?
    @State private var gallery: NSImage?
    private var key: String { "\(queryName ?? "")|\(galleryName ?? "")" }
    var body: some View {
        ScaleReviewComparisonView(
            queryImage: query,
            galleryImage: gallery,
            store: store,
            querySampleName: queryName,
            gallerySampleName: galleryName
        )
            .task(id: key) {
                query = queryName.flatMap { I3SSampleLibrary.loadImage(named: $0) }
                gallery = galleryName.flatMap { I3SSampleLibrary.loadImage(named: $0) }
            }
    }
}
