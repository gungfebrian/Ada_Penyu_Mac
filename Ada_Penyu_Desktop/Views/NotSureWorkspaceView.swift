import AppKit
import SwiftUI

enum NotSureStageMode: String, CaseIterable, Identifiable {
    case compare = "Compare"
    case contours = "Contours #"
    case align = "Align"

    var id: Self { self }

    var icon: String {
        switch self {
        case .compare: "photo.on.rectangle"
        case .contours: "number.circle"
        case .align: "point.3.connected.trianglepath.dotted"
        }
    }
}

struct NotSureWorkspaceView: View {
    @ObservedObject var store: AppStore
    let onOpenPractice: () -> Void
    var initialStageMode: NotSureStageMode = .compare

    @State private var selectedCaseID: UUID?
    @State private var sessionCaseIDs: [UUID] = []
    @State private var showsReviewed = false
    @State private var preparedMobileID: UUID?
    @State private var preparationError: String?
    @State private var inputSelection: MobileReviewSighting?
    @State private var chosenPhotoID: UUID?
    @State private var chosenSide: TurtlePhotoSide?
    @State private var sourcePreview: NSImage?
    @State private var sourcePreviewLoading = false
    @State private var sourcePreviewRetry = UUID()

    @State private var preparationRetry = UUID()

    private var pendingMobileRows: [MobileReviewSighting] {
        let locallyReviewed = Set(store.escalatedNotSureCases.filter { $0.decision != .pending }.compactMap(\.sourceLogID))
        return store.mobileReviewRows.filter { !locallyReviewed.contains($0.id) }
    }
    private var remoteRows: [MobileReviewSighting] { showsReviewed ? [] : pendingMobileRows }
    private var remoteIDs: Set<UUID> { Set(store.mobileReviewRows.map(\.id)) }
    private var selectedMobileLogID: UUID? {
        guard let id = selectedCaseID else { return nil }
        if let local = store.escalatedNotSureCases.first(where: { $0.id == id || $0.sourceLogID == id }), local.decision != .pending {
            return nil
        }
        return remoteIDs.contains(id) ? id : store.escalatedNotSureCases.first(where: { $0.id == id })?.sourceLogID
    }


    private var pendingCount: Int {
        store.pendingNotSureCases.filter { !remoteIDs.contains($0.sourceLogID ?? $0.id) }.count + pendingMobileRows.count
    }
    private var reviewedCount: Int { store.escalatedNotSureCases.filter { $0.decision != .pending }.count }

    private var visibleCases: [EscalatedNotSureCase] {
        store.escalatedNotSureCases
            .filter { ($0.decision != .pending) == showsReviewed && (showsReviewed || !remoteIDs.contains($0.sourceLogID ?? $0.id)) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var activeQueueIDs: [UUID] {
        let existingIDs = Set(store.escalatedNotSureCases.map(\.id)).union(remoteIDs)
        let validSession = sessionCaseIDs.filter { existingIDs.contains($0) }
        if let selectedCaseID, validSession.contains(selectedCaseID) { return validSession }
        return remoteRows.map(\.id) + visibleCases.map(\.id)
    }

    var body: some View {
        Group {
            if let selectedCaseID, selectedMobileLogID != nil, preparedMobileID != selectedCaseID {
                mobilePreparation
            } else if let selectedID = selectedCaseID, let item = store.escalatedNotSureCases.first(where: { $0.id == selectedID || $0.sourceLogID == selectedID }) {
                let queueIDs = activeQueueIDs
                let index = queueIDs.firstIndex(of: selectedID) ?? 0
                NotSureCaseDetail(
                    store: store,
                    item: item,
                    initialStageMode: initialStageMode,
                    queueIndex: index,
                    queueCount: max(queueIDs.count, 1),
                    onPrevious: index > 0 ? { chosenPhotoID = nil; chosenSide = nil; selectedCaseID = queueIDs[index - 1] } : nil,
                    onNext: index + 1 < queueIDs.count ? { chosenPhotoID = nil; chosenSide = nil; selectedCaseID = queueIDs[index + 1] } : nil,
                    onBack: {
                        showsReviewed = item.decision != .pending
                        selectedCaseID = nil
                        sessionCaseIDs = []
                    }
                )
                .id("\(item.id)-\(item.matchAttemptID?.uuidString ?? "local")")
            } else {
                inbox
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AdaColors.canvas)
        .foregroundStyle(AdaColors.ink)
        .task(id: store.sessionGeneration) { await store.loadMobileReviewQueue() }
        .task(id: "\(selectedCaseID?.uuidString ?? "")-\(selectedMobileLogID?.uuidString ?? "local")-\(preparationRetry)") {
            guard let id = selectedCaseID, let logID = selectedMobileLogID else { return }
            preparationError = nil
            inputSelection = nil
            preparedMobileID = nil
            do {
                let inputs: [ReviewQueryInput]?
                if let photoID = chosenPhotoID, let side = chosenSide {
                    inputs = [ReviewQueryInput(photoID: photoID, side: side, file: nil)]
                } else { inputs = nil }
                try await store.prepareMobileReview(logID, inputs: inputs)
                try Task.checkCancellation()
                preparedMobileID = id
            } catch let choice as ReviewInputSelectionRequired {
                guard !Task.isCancelled else { return }
                inputSelection = choice.sighting
            } catch {
                guard !Task.isCancelled else { return }
                preparationError = error.localizedDescription
            }
        }
        .onChange(of: store.sessionGeneration) { _, _ in
            selectedCaseID = nil
            sessionCaseIDs = []
            preparedMobileID = nil
            chosenPhotoID = nil
            chosenSide = nil
        }
        .onAppear(perform: openRequestedCase)
        .onChange(of: store.reviewNavigationTrigger) { _, _ in
            selectedCaseID = nil
            sessionCaseIDs = []
            openRequestedCase()
        }
    }

    // MARK: - Inbox

    private var inbox: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                HStack(spacing: 3) {
                    queuePill("Pending", count: pendingCount, reviewed: false)
                    queuePill("Reviewed", count: reviewedCount, reviewed: true)
                }
                .padding(3)
                .background(AdaColors.card, in: Capsule())
                .overlay(Capsule().stroke(AdaColors.line, lineWidth: 1))

                Spacer(minLength: 0)

                if store.canLoadRecords {
                    Button {
                        Task { await store.loadMobileReviewQueue() }
                    } label: {
                        HStack(spacing: 6) {
                            if store.isSyncingMobileQueue {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text(store.isSyncingMobileQueue ? "Loading…" : "Refresh")
                        }
                    }
                    .buttonStyle(NotSurePillButtonStyle(.secondary, height: 34))
                    .disabled(store.isSyncingMobileQueue)
                    .help("Refresh pending sightings")
                }

                if !store.escalatedNotSureCases.isEmpty {
                    Button {
                        store.exportNotSureQueue()
                    } label: {
                        Label("Export queue", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(NotSurePillButtonStyle(.subtle, height: 34))
                    .help("Export Not Sure queue as JSON for another Mac")
                }

                Button(action: onOpenPractice) {
                    Label("Practice", systemImage: "graduationcap")
                }
                .buttonStyle(NotSurePillButtonStyle(.subtle, height: 34))
            }

            if let error = store.notSureQueueError {
                HStack(spacing: 12) {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.system(size: 12))
                        .foregroundStyle(AdaColors.red)
                    Spacer()
                    Button("Retry") { Task { await store.loadMobileReviewQueue() } }
                        .buttonStyle(AdaPillButtonStyle(secondary: true))
                }
                .adaCard(padding: 14, radius: 18)
            }

            if visibleCases.isEmpty && remoteRows.isEmpty {
                emptyQueue
                if !showsReviewed && store.hasMoreMobileReviews {
                    Button("Load more") { Task { await store.loadMobileReviewQueue(loadMore: true) } }
                        .buttonStyle(AdaPillButtonStyle(secondary: true)).disabled(store.isSyncingMobileQueue)
                }
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        if !remoteRows.isEmpty { mobileCaseList }
                        if !visibleCases.isEmpty { caseList }
                        if !showsReviewed && store.hasMoreMobileReviews {
                            Button("Load more") { Task { await store.loadMobileReviewQueue(loadMore: true) } }
                                .buttonStyle(AdaPillButtonStyle(secondary: true))
                                .disabled(store.isSyncingMobileQueue)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .padding(.horizontal, AdaLayout.pagePadding)
        .padding(.top, 18)
    }

    private func queuePill(_ title: String, count: Int, reviewed: Bool) -> some View {
        let selected = showsReviewed == reviewed
        return Button { showsReviewed = reviewed } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 12, weight: selected ? .semibold : .medium))
                Text(count, format: .number)
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(selected ? Color.white.opacity(0.18) : AdaColors.surfaceMuted, in: Capsule())
            }
            .foregroundStyle(selected ? .white : AdaColors.secondaryInk)
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(selected ? AdaColors.navy : .clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(count)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var emptyQueue: some View {
        VStack(spacing: 12) {
            if store.isSyncingMobileQueue && !showsReviewed { ProgressView("Loading pending sightings…") }
            Image(systemName: showsReviewed ? "checkmark.circle" : "tray")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(AdaColors.secondaryInk)
            Text(showsReviewed ? "No reviewed cases" : store.isSyncingMobileQueue ? "" : "No pending cases")
                .font(.system(size: 16, weight: .semibold))
            if !showsReviewed {
                HStack(spacing: 10) {
                    if store.canLoadRecords {
                        Button("Refresh") {
                            Task { await store.loadMobileReviewQueue() }
                        }
                        .buttonStyle(AdaPillButtonStyle(secondary: true))
                    }
                    Button("Open Photo ID") { store.activeSection = .identification }
                        .buttonStyle(AdaPillButtonStyle())
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .adaCard(padding: 24, radius: AdaLayout.cardRadius)
    }

    private var mobileCaseList: some View {
        LazyVStack(spacing: 0) {
            ForEach(remoteRows) { row in
                Button {
                    chosenPhotoID = nil
                    chosenSide = nil
                    preparedMobileID = nil
                    sessionCaseIDs = remoteRows.map(\.id) + visibleCases.map(\.id)
                    selectedCaseID = row.id
                } label: {
                    HStack(spacing: 16) {
                        ReviewQueueThumbnail(store: store, sightingID: row.id, photo: row.headPhotos.first)
                            .frame(width: 68, height: 68)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(row.location.name).font(.system(size: 15, weight: .semibold))
                            Text("Mobile · \(row.headPhotos.count) photos · \(row.matchResult == nil ? "Waiting to match" : "Saved results")")
                                .font(.system(size: 12)).foregroundStyle(AdaColors.secondaryInk)
                            Text(row.observedAt.formatted(date: .abbreviated, time: .omitted))
                                .font(.system(size: 12)).foregroundStyle(AdaColors.secondaryInk)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 20).padding(.vertical, 14).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if row.id != remoteRows.last?.id { Divider().padding(.horizontal, 20) }
            }
        }
        .adaCard(padding: 0, radius: AdaLayout.cardRadius)
    }

    private var mobilePreparation: some View {
        VStack(alignment: .leading, spacing: 18) {
            Button("Back to queue") {
                selectedCaseID = nil
                chosenPhotoID = nil
                chosenSide = nil
            }.buttonStyle(AdaPillButtonStyle(secondary: true))
            if let choice = inputSelection {
                Text("Choose a head photo and side").font(.title2.bold())
                if choice.headPhotos.isEmpty {
                    Text("This sighting has no head photos available for matching.")
                } else {
                    Picker("Head photo", selection: $chosenPhotoID) {
                        Text("Choose a photo").tag(UUID?.none)
                        ForEach(choice.headPhotos) { photo in
                            Text("\(photo.id.uuidString.prefix(8)) · \(photo.side?.shortLabel ?? "Side unknown")").tag(Optional(photo.id))
                        }
                    }
                    .onChange(of: chosenPhotoID) { _, id in
                        chosenSide = choice.headPhotos.first(where: { $0.id == id })?.side
                    }
                    Group {
                        if let sourcePreview {
                            Image(nsImage: sourcePreview).resizable().scaledToFit().frame(maxHeight: 220)
                        } else if sourcePreviewLoading { ProgressView("Loading photo…") }
                        else if chosenPhotoID != nil {
                            Button("Retry photo preview") { sourcePreviewRetry = UUID() }
                        }
                    }
                    .task(id: "\(chosenPhotoID?.uuidString ?? "")-\(sourcePreviewRetry)") {
                        sourcePreview = nil
                        sourcePreviewLoading = false
                        guard let photo = choice.headPhotos.first(where: { $0.id == chosenPhotoID }) else { return }
                        sourcePreviewLoading = true
                        let image = await store.loadPhoto(for: photo.fetchPath)
                        guard !Task.isCancelled else { return }
                        sourcePreview = image
                        sourcePreviewLoading = false
                    }
                    Picker("Side", selection: $chosenSide) {
                        Text("Choose a side").tag(TurtlePhotoSide?.none)
                        ForEach(TurtlePhotoSide.allCases) { side in Text(side.shortLabel).tag(Optional(side)) }
                    }
                    .disabled(choice.headPhotos.first(where: { $0.id == chosenPhotoID })?.side != nil)
                    Button("Match selected photo") { preparationRetry = UUID() }
                        .buttonStyle(AdaPillButtonStyle())
                        .disabled(chosenPhotoID == nil || chosenSide == nil)
                }
            } else if let error = preparationError {
                Text(error).foregroundStyle(AdaColors.red)
                Button("Retry") { preparationRetry = UUID() }.buttonStyle(AdaPillButtonStyle())
            } else { ProgressView("Preparing this case…") }
            Spacer()
        }
        .padding(AdaLayout.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var caseList: some View {
        let cases = visibleCases
        return LazyVStack(spacing: 0) {
            ForEach(cases) { item in
                let savedAnchors = item.savedAnchorMaxCount
                let topScore = item.candidates.filter { !item.rejectedCandidateIDs.contains($0.id) }.first?.confidencePercent
                Button {
                    sessionCaseIDs = cases.map(\.id)
                    selectedCaseID = item.id
                } label: {
                    HStack(spacing: 16) {
                        HStack(spacing: 6) {
                            NotSureThumbnail(image: item.queryImage, size: 68, radius: 12)
                            if let companion = item.companionImage {
                                NotSureThumbnail(image: companion, size: 68, radius: 12)
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.title)
                                .font(.system(size: 15, weight: .semibold))
                                .lineLimit(1)
                            HStack(spacing: 6) {
                                if item.isFromMobileQueue {
                                    NotSureMetaTag(
                                        title: "Mobile",
                                        tint: AdaColors.accent,
                                        background: AdaColors.accentSoft
                                    )
                                }
                                NotSureMetaTag(
                                    title: item.companionImage == nil ? item.side.shortLabel : "Left + Right",
                                    tint: AdaColors.navy,
                                    background: AdaColors.navy.opacity(0.08)
                                )
                                NotSureMetaTag(
                                    title: item.candidates.count == 1 ? "1 candidate" : "\(item.candidates.count) candidates",
                                    tint: AdaColors.secondaryInk
                                )
                                if let topScore, !item.isExample {
                                    NotSureMetaTag(title: "Top \(topScore)%", tint: AdaColors.accent, background: AdaColors.accentSoft)
                                }
                                if savedAnchors >= 3 {
                                    NotSureMetaTag(
                                        title: "\(savedAnchors) pins",
                                        tint: AdaColors.green,
                                        background: AdaColors.green.opacity(0.11)
                                    )
                                }
                                Text(item.createdAt.formatted(date: .abbreviated, time: .omitted))
                                    .font(.system(size: 12))
                                    .foregroundStyle(AdaColors.secondaryInk)
                            }
                        }

                        Spacer(minLength: 0)

                        NotSureStatusPill(item: item)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AdaColors.secondaryInk)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                if item.id != cases.last?.id {
                    Divider().padding(.horizontal, 20)
                }
            }
        }
        .adaCard(padding: 0, radius: AdaLayout.cardRadius)
    }

    private func openRequestedCase() {
        guard let requested = store.requestedEscalatedCaseID else { return }
        store.requestedEscalatedCaseID = nil
        guard let item = store.escalatedNotSureCases.first(where: { $0.id == requested }) else { return }
        showsReviewed = item.decision != .pending
        sessionCaseIDs = store.escalatedNotSureCases
            .filter { ($0.decision != .pending) == showsReviewed }
            .sorted { $0.updatedAt > $1.updatedAt }
            .map(\.id)
        selectedCaseID = item.id
    }
}

// MARK: - Case Detail (Obvious · Easy · Possible | Zero Page Scroll | Real CV + Pixel Warp)

private struct NotSureCaseDetail: View {
    private enum ComparePresentation: String, CaseIterable, Identifiable {
        case sideBySide = "Side by side"
        case curtain = "Curtain"
        case blend = "Blend"
        var id: Self { self }
    }

    private enum AlignPresentation: String, CaseIterable, Identifiable {
        case pins = "Pins"
        case curtain = "Curtain"
        case blend = "Blend"
        var id: Self { self }
    }

    private enum DecisionOutcome: Identifiable {
        case sameTurtle(id: String, name: String, image: NSImage?)
        case newTurtle
        case needsPhoto

        var id: String {
            switch self {
            case .sameTurtle(let id, _, _): "same-\(id)"
            case .newTurtle: "new-turtle"
            case .needsPhoto: "needs-photo"
            }
        }

        var title: String {
            switch self {
            case .sameTurtle(_, let name, _): name
            case .newTurtle: "New turtle"
            case .needsPhoto: "Needs photo"
            }
        }

        var badgeTitle: String {
            switch self {
            case .sameTurtle: "Same turtle"
            case .newTurtle: "Not in gallery"
            case .needsPhoto: "Retake needed"
            }
        }

        var confirmTitle: String {
            switch self {
            case .sameTurtle: "Confirm match"
            case .newTurtle: "Save new turtle"
            case .needsPhoto: "Save needs photo"
            }
        }

        var accentColor: Color {
            switch self {
            case .sameTurtle: AdaColors.navy
            case .newTurtle: AdaColors.accent
            case .needsPhoto: AdaColors.orange
            }
        }

        var symbolName: String {
            switch self {
            case .sameTurtle: "checkmark.circle.fill"
            case .newTurtle: "plus.circle.fill"
            case .needsPhoto: "camera.fill"
            }
        }

        var reasonChips: [String] {
            switch self {
            case .sameTurtle:
                ["Warped scales lock", "AI inliers match", "Both sides match"]
            case .newTurtle:
                ["Different pattern", "Warped sutures diverge", "Not in gallery"]
            case .needsPhoto:
                ["Glare / blur", "Extreme angle", "Opposite side"]
            }
        }

        func action(note: String) -> NotSureReviewAction {
            switch self {
            case .sameTurtle(let id, _, _): .recommend(id, note: note)
            case .newTurtle: .resolveAsNewTurtle(note: note)
            case .needsPhoto: .requestBetterPhoto(note: note)
            }
        }
    }

    private struct ContourCacheKey: Hashable {
        let imageID: ObjectIdentifier
        let side: TurtlePhotoSide
        let detailBucket: Int
        let roiHash: Int
    }

    private struct AIAnnotationKey: Hashable {
        let candidateID: String
        let side: TurtlePhotoSide
    }

    private struct WarpCacheKey: Hashable {
        let queryID: ObjectIdentifier
        let candidateID: ObjectIdentifier
        let anchorsSignature: Int
    }

    @ObservedObject var store: AppStore
    let item: EscalatedNotSureCase
    let queueIndex: Int
    let queueCount: Int
    let onPrevious: (() -> Void)?
    let onNext: (() -> Void)?
    let onBack: () -> Void

    // Primary stage state (Obvious & Easy)
    @State private var stageMode: NotSureStageMode
    @State private var selectedCandidateID = ""
    @State private var candidatePhotoError: String?

    @State private var showsRejected = false
    @State private var showingCompanionSide = false

    // Compare Mode: Side by side / Curtain / Blend + Live Backend XFeat/LighterGlue RANSAC
    @State private var comparePresentation: ComparePresentation = .sideBySide
    @State private var curtainPosition: CGFloat = 0.50
    @State private var overlayOpacity: Double = 0.55
    @State private var isBlinking = false
    @State private var blinkShowsCandidate = false
    @State private var viewports = NotSureComparisonViewports()
    @State private var patchSession = NotSurePatchSession()
    @State private var patchViewports = NotSureComparisonViewports()
    @State private var showsPatchTool = false
    @State private var showsPatchPreviews = false
    @State private var showsPatchOutlines = true
    @GestureState private var sightingMagnification: CGFloat = 1
    @GestureState private var candidateMagnification: CGFloat = 1
    @GestureState private var overlayMagnification: CGFloat = 1

    // Backend XFeat/LighterGlue Correspondences + Geometric Consensus (RANSAC)
    @State private var showsAIMatches = false
    @State private var showsAIOutliers = false
    @State private var aiAnnotationsCache: [AIAnnotationKey: [OverlayAnnotationItem]] = [:]
    @State private var aiConsensusCache: [AIAnnotationKey: GeometricConsensusReport] = [:]
    @State private var isLoadingAIAnnotations = false
    @State private var selectedAIFeatureID: String?

    // Upgraded Ocean-Masked + Eyeball-Free Contours & Interactive Manual Editing
    @State private var contourCache: [ContourCacheKey: ExtractedScaleAnalysis] = [:]
    @State private var isExtractingContours = false
    @State private var selectedQueryScale: Int?
    @State private var selectedCandidateScale: Int?
    @State private var isAddingManualLandmark = false
    @State private var showsSutureMesh = false

    // True Human-Assisted Registration (Free Pixel + Scale Pins + CoreImage Pixel Warp)
    @State private var anchorsByCandidateID: [String: [ManualAnchorPair]]
    @State private var pendingQueryPin: (point: ScalePoint, scaleNumber: Int?)?
    @State private var alignPresentation: AlignPresentation = .pins
    @State private var showWarpedContoursOnPhoto = false
    @State private var warpedPhotoCache: [WarpCacheKey: NSImage] = [:]
    @State private var isRenderingWarp = false

    // Progressive Disclosure Options (Possible — inside single `⋯` popover)
    @State private var showsOptionsPopover = false
    @State private var linesOnly = false
    @State private var detailSensitivity: Double = 0.48
    @State private var customQueryROI: [ScalePoint]?
    @State private var showsCropSheet = false
    @State private var isCropResearching = false

    // Search & Verdict Sheet
    @State private var inlineError: String?
    @State private var searchRequest: UUID?
    @State private var isSearching = false
    @State private var searchCoverage = 70
    @State private var retryPendingSearch = false
    @State private var queuedCrop: (rect: CGRect, rotation: Double, usePair: Bool)?
    @State private var pageTask: Task<Void, Never>?
    @State private var viewIsActive = false
    @State private var isSavingCandidateReview = false
    @State private var isLoadingMoreCandidates = false
    @State private var newTurtleName = ""
    @State private var newTurtleCode = ""
    @State private var newTurtleSpecies: TurtleSpecies? = nil
    @State private var newTurtlePhotosAdequate = false
    @State private var newTurtleID = UUID()
    @State private var isSavingVerdict = false
    @State private var confirmation: DecisionOutcome?
    @State private var selectedChip = ""
    @State private var confirmationNote = ""

    private static let stageDark = Color(red: 10 / 255, green: 21 / 255, blue: 33 / 255)
    private static let stageChipBg = Color.white.opacity(0.11)

    init(
        store: AppStore,
        item: EscalatedNotSureCase,
        initialStageMode: NotSureStageMode = .compare,
        queueIndex: Int,
        queueCount: Int,
        onPrevious: (() -> Void)?,
        onNext: (() -> Void)?,
        onBack: @escaping () -> Void
    ) {
        self.store = store
        self.item = item
        self.queueIndex = queueIndex
        self.queueCount = queueCount
        self.onPrevious = onPrevious
        self.onNext = onNext
        self.onBack = onBack
        self._stageMode = State(initialValue: initialStageMode)
        self._anchorsByCandidateID = State(initialValue: item.manualAnchorsByCandidateID ?? [:])
        self._customQueryROI = State(initialValue: item.queryROI.count >= 3 ? item.queryROI : nil)
    }

    // MARK: Derived Properties

    private var isPending: Bool { item.decision == .pending }

    private var liveSearchAvailable: Bool {
        isPending && store.isAuthenticated && !store.isDemoBypassActive && !item.isExample
    }

    private var aiAnnotationsAvailable: Bool {
        guard let cand = selectedCandidate, UUID(uuidString: cand.id) != nil else { return false }
        return store.canLoadRecords
    }

    private var availableCandidates: [EscalatedNotSureCandidate] {
        item.candidates.filter { !item.rejectedCandidateIDs.contains($0.id) }
    }

    private var rejectedCandidates: [EscalatedNotSureCandidate] {
        item.candidates.filter { item.rejectedCandidateIDs.contains($0.id) }
    }

    private var displayedCandidates: [EscalatedNotSureCandidate] {
        showsRejected ? rejectedCandidates : availableCandidates
    }

    private var selectedCandidate: EscalatedNotSureCandidate? {
        let preferred = selectedCandidateID.isEmpty ? item.recommendedCandidateID : selectedCandidateID
        let pool = displayedCandidates
        return pool.first { $0.id == preferred }
            ?? pool.first(where: { $0.sideMatches && $0.image != nil })
            ?? pool.first
    }

    private var sightingPatchSource: NotSurePatchSource? {
        displayedQueryImage.map { NotSurePatchSource(photo: $0, side: activeSightingSide) }
    }

    private var candidatePatchSource: NotSurePatchSource? {
        guard let candidate = selectedCandidate, let image = candidate.image else { return nil }
        return NotSurePatchSource(photo: image, side: candidate.side, candidateID: candidate.id)
    }

    private var canSelectPatches: Bool {
        sightingPatchSource != nil && candidatePatchSource?.side == activeSightingSide
    }

    private var activeSightingSide: TurtlePhotoSide {
        showingCompanionSide && item.companionImage != nil ? item.side.opposite : item.side
    }

    private var displayedQueryImage: NSImage? {
        showingCompanionSide && item.companionImage != nil ? item.companionImage : item.queryImage
    }

    private var displayedQueryPhotoData: Data {
        showingCompanionSide && item.companion != nil ? (item.companion?.data ?? item.queryPhotoData) : item.queryPhotoData
    }

    private var detailBucket: Int { Int((detailSensitivity * 100).rounded()) }

    private var queryROIHash: Int {
        guard !showingCompanionSide, let roi = customQueryROI, !roi.isEmpty else { return 0 }
        var hasher = Hasher()
        for pt in roi {
            hasher.combine(Int((pt.x * 1000).rounded()))
            hasher.combine(Int((pt.y * 1000).rounded()))
        }
        return hasher.finalize()
    }

    private var queryCacheKey: ContourCacheKey? {
        guard let image = displayedQueryImage else { return nil }
        return ContourCacheKey(
            imageID: ObjectIdentifier(image),
            side: activeSightingSide,
            detailBucket: detailBucket,
            roiHash: queryROIHash
        )
    }

    private var candidateCacheKey: ContourCacheKey? {
        guard let cand = selectedCandidate, let image = cand.image else { return nil }
        return ContourCacheKey(
            imageID: ObjectIdentifier(image),
            side: cand.side,
            detailBucket: detailBucket,
            roiHash: 0
        )
    }

    private var queryAnalysis: ExtractedScaleAnalysis? { queryCacheKey.flatMap { contourCache[$0] } }
    private var candidateAnalysis: ExtractedScaleAnalysis? { candidateCacheKey.flatMap { contourCache[$0] } }

    private var excludedQueryScales: Set<Int> {
        showingCompanionSide ? [] : (item.excludedQueryScaleNumbers ?? [])
    }

    private var customQueryLandmarks: [ManualScaleLandmark] {
        showingCompanionSide ? [] : (item.customQueryLandmarks ?? [])
    }

    private var visibleQueryPatterns: [DetectedScalePattern] {
        (queryAnalysis?.patterns ?? []).filter { !excludedQueryScales.contains($0.number) }
    }

    private var visibleCandidatePatterns: [DetectedScalePattern] {
        candidateAnalysis?.patterns ?? []
    }

    private var activeAIKey: AIAnnotationKey? {
        guard let cand = selectedCandidate else { return nil }
        return AIAnnotationKey(candidateID: cand.id, side: activeSightingSide)
    }

    private var activeAIAnnotations: [OverlayAnnotationItem] {
        activeAIKey.flatMap { aiAnnotationsCache[$0] } ?? []
    }

    private var activeConsensus: GeometricConsensusReport? {
        activeAIKey.flatMap { aiConsensusCache[$0] }
    }

    private var activeAnchors: [ManualAnchorPair] {
        guard let cand = selectedCandidate else { return [] }
        return anchorsByCandidateID[cand.id] ?? []
    }

    private var alignmentResult: HumanAssistedAlignmentResult {
        HumanAssistedAlignmentEvaluator.evaluate(
            anchors: activeAnchors,
            queryPatterns: visibleQueryPatterns
        )
    }

    private var activeWarpKey: WarpCacheKey? {
        guard alignmentResult.isReadyForWarp,
              let qImg = displayedQueryImage,
              let cImg = selectedCandidate?.image else { return nil }
        var hasher = Hasher()
        for a in activeAnchors {
            hasher.combine(Int((a.queryPoint.x * 2000).rounded()))
            hasher.combine(Int((a.queryPoint.y * 2000).rounded()))
            hasher.combine(Int((a.candidatePoint.x * 2000).rounded()))
            hasher.combine(Int((a.candidatePoint.y * 2000).rounded()))
        }
        return WarpCacheKey(
            queryID: ObjectIdentifier(qImg),
            candidateID: ObjectIdentifier(cImg),
            anchorsSignature: hasher.finalize()
        )
    }

    private var warpedQueryImage: NSImage? {
        activeWarpKey.flatMap { warpedPhotoCache[$0] }
    }

    private var contourExtractionTrigger: String {
        guard stageMode != .compare else { return "compare" }
        return "\(stageMode.rawValue)|\(queryCacheKey?.hashValue ?? 0)|\(candidateCacheKey?.hashValue ?? 0)"
    }

    private var aiLoadTrigger: String {
        guard showsAIMatches, let key = activeAIKey else { return "off" }
        return "\(key.candidateID)|\(key.side.rawValue)"
    }

    private var canConfirmSameTurtle: Bool {
        guard isPending, !isSearching, !isSavingVerdict, !isSavingCandidateReview, let selectedCandidate else { return false }
        if item.sourceLogID != nil && !store.isDemoBypassActive && item.desktopReview == nil { return false }
        return item.canRecommend(selectedCandidate)
    }

    private var hasAdvancedOverrides: Bool {
        linesOnly || showsSutureMesh || showsAIOutliers || detailBucket != 48 || customQueryROI != nil
    }

    private var effectiveOverlayAlpha: Double {
        isBlinking ? (blinkShowsCandidate ? 1.0 : 0.0) : overlayOpacity
    }

    /// Number of RANSAC AI inliers supporting a specific query scale polygon (for real AI↔Scale corroboration).
    private func aiSupportCount(forQueryScale pattern: DetectedScalePattern) -> Int {
        guard let consensus = activeConsensus, consensus.inlierCount > 0 else { return 0 }
        return activeAIAnnotations.reduce(0) { acc, ann in
            guard consensus.inlierFeatureIDs.contains(ann.featureID) else { return acc }
            let qp = ScalePoint(x: ann.query.x, y: ann.query.y)
            let hit = ScalePhotoReview.contains(qp, polygon: pattern.polygon)
                || hypot(qp.x - pattern.centroid.x, qp.y - pattern.centroid.y) <= 0.028
            return acc + (hit ? 1 : 0)
        }
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 12) {
            topBar
            HStack(spacing: 14) {
                stageContainer
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                candidateRail
                    .frame(width: 274)
                    .frame(maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let inlineError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(AdaColors.red)
                    Text(inlineError)
                        .font(.system(size: 12))
                        .foregroundStyle(AdaColors.red)
                    Spacer()
                    if store.hasPendingNotSureMatch(item.id) {
                        Button("Retry match") {
                            retryPendingSearch = true
                            queuedCrop = nil
                            searchRequest = UUID()
                        }
                        .disabled(isSearching)
                    }
                    Button("Dismiss") { self.inlineError = nil }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AdaColors.secondaryInk)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(AdaColors.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if let error = candidatePhotoError {
                HStack {
                    Text(error).font(.caption).foregroundStyle(AdaColors.red)
                    Button("Retry photo") {
                        guard let candidate = selectedCandidate else { return }
                        Task {
                            do {
                                try await store.loadNotSureCandidatePhoto(caseID: item.id, candidateID: candidate.id)
                                candidatePhotoError = nil
                            } catch { candidatePhotoError = error.localizedDescription }
                        }
                    }
                }
            }
            verdictBar
        }
        .padding(.horizontal, AdaLayout.pagePadding)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: "\(item.matchAttemptID?.uuidString ?? "")-\(selectedCandidate?.id ?? "")") {
            guard let candidate = selectedCandidate else { return }
            candidatePhotoError = nil
            do { try await store.prefetchNotSureCandidatePhotos(caseID: item.id, priorityCandidateID: candidate.id) }
            catch { if !Task.isCancelled { candidatePhotoError = error.localizedDescription } }
        }
        .task(id: contourExtractionTrigger) {
            guard stageMode != .compare else { return }
            await extractVisibleContours()
        }
        .task(id: aiLoadTrigger) {
            guard showsAIMatches else { return }
            await loadAIAnnotationsForActiveCandidate()
        }
        .task(id: activeWarpKey) {
            await renderWarpedPhotoIfNeeded()
        }
        .task(id: searchRequest) {
            guard searchRequest != nil else { return }
            if let crop = queuedCrop {
                queuedCrop = nil
                await runCroppedLiveSearch(rect: crop.rect, rotationDegrees: crop.rotation, usePairedSide: crop.usePair)
            } else {
                let retry = retryPendingSearch
                retryPendingSearch = false
                await runLiveSearch(overridePhotoData: nil, usePairedSide: false, retryPreviousAttempt: retry, coverage: searchCoverage)
            }
        }
        .task(id: item.id) {
            newTurtleID = UUID()
            newTurtleName = ""
            newTurtleCode = ""
            newTurtleSpecies = nil
            newTurtlePhotosAdequate = false
            guard liveSearchAvailable else { return }
            if item.sourceLogID != nil {
                guard item.desktopReview == nil else { return }
            } else { guard item.candidates.isEmpty else { return } }
            searchCoverage = 70
            searchRequest = UUID()
        }
        .task(id: isBlinking) {
            guard isBlinking else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { break }
                withAnimation(.easeInOut(duration: 0.10)) { blinkShowsCandidate.toggle() }
            }
        }
        .onChange(of: sightingPatchSource, initial: true) { _, _ in updatePatchSources() }
        .onChange(of: candidatePatchSource) { _, _ in updatePatchSources() }
        .onChange(of: activeSightingSide) { _, _ in
            viewports.sighting = NotSurePhotoViewport()
            viewports.overlay = NotSurePhotoViewport()
        }
        .onChange(of: selectedCandidate?.id) { _, _ in
            viewports.candidate = NotSurePhotoViewport()
            viewports.overlay = NotSurePhotoViewport()
            selectedCandidateScale = nil
            pendingQueryPin = nil
            selectedAIFeatureID = nil
            if activeAnchors.count < 3 { alignPresentation = .pins }
            if selectedCandidate?.image == nil { isBlinking = false }
            migrateLegacyPairsIntoAnchorsIfNeeded()
        }
        .onChange(of: stageMode) { _, mode in
            showsPatchTool = false
            isBlinking = false
            pendingQueryPin = nil
            isAddingManualLandmark = false
            if mode == .align {
                migrateLegacyPairsIntoAnchorsIfNeeded()
                if alignmentResult.isReadyForWarp && alignPresentation == .pins {
                    alignPresentation = .curtain
                }
            }
        }
        .onAppear { viewIsActive = true }
        .onDisappear {
            viewIsActive = false
            pageTask?.cancel()
            searchRequest = nil
        }
        .sheet(item: $confirmation) { verdictSheet(for: $0) }
        .sheet(isPresented: $showsCropSheet) {
            NotSureHeadCropSheet(
                image: item.queryImage,
                hasCompanionSide: item.companionImage != nil,
                initialRect: initialCropRect(),
                liveSearchAvailable: liveSearchAvailable,
                isSearching: isCropResearching,
                onApplyLocal: { rect in
                    applyLocalCropROI(rect)
                    showsCropSheet = false
                },
                onCropAndResearch: { rect, rotationDeg, usePair in
                    queuedCrop = (rect, rotationDeg, usePair)
                    retryPendingSearch = false
                    searchCoverage = 70
                    searchRequest = UUID()
                },
                onCancel: {
                    if isCropResearching { searchRequest = nil }
                    showsCropSheet = false
                }
            )
        }
    }

    // MARK: - 1. Slim Top Bar

    private var topBar: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                Label("Queue", systemImage: "chevron.left")
            }
            .buttonStyle(NotSurePillButtonStyle(.subtle, height: 34, bold: true))

            Text(item.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AdaColors.ink)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)

            if item.isFromMobileQueue {
                NotSureMetaTag(title: "Mobile", tint: AdaColors.accent, background: AdaColors.accentSoft)
            }

            if item.companionImage != nil {
                pairedSideToggle
            } else {
                NotSureMetaTag(
                    title: item.side.shortLabel,
                    tint: AdaColors.navy,
                    background: AdaColors.navy.opacity(0.08)
                )
            }

            Spacer(minLength: 8)

            stageModeCapsule

            optionsMenuButton

            queueStepper

            NotSureStatusPill(item: item)
        }
        .frame(height: 36)
    }

    private var pairedSideToggle: some View {
        HStack(spacing: 2) {
            ForEach(TurtlePhotoSide.allCases) { side in
                let active = activeSightingSide == side
                Button {
                    withAnimation(.easeOut(duration: 0.14)) {
                        showingCompanionSide = (side != item.side)
                        selectedQueryScale = nil
                        pendingQueryPin = nil
                        selectedAIFeatureID = nil
                    }
                } label: {
                    Text(side.shortLabel)
                        .font(.system(size: 11.5, weight: active ? .semibold : .medium))
                        .foregroundStyle(active ? .white : AdaColors.secondaryInk)
                        .padding(.horizontal, 11)
                        .frame(height: 26)
                        .background(active ? AdaColors.navy : .clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .padding(3)
        .background(AdaColors.card, in: Capsule())
        .overlay(Capsule().stroke(AdaColors.line, lineWidth: 1))
        .fixedSize()
    }

    private var stageModeCapsule: some View {
        HStack(spacing: 2) {
            ForEach(NotSureStageMode.allCases) { mode in
                let active = stageMode == mode
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { stageMode = mode }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 11, weight: .semibold))
                        Text(mode.rawValue)
                            .font(.system(size: 12, weight: active ? .semibold : .medium))
                    }
                    .foregroundStyle(active ? .white : AdaColors.secondaryInk)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(active ? AdaColors.navy : .clear, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .padding(3)
        .background(AdaColors.card, in: Capsule())
        .overlay(Capsule().stroke(AdaColors.line, lineWidth: 1))
        .fixedSize()
    }

    private var optionsMenuButton: some View {
        Button { showsOptionsPopover.toggle() } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(hasAdvancedOverrides ? .white : AdaColors.ink)
                .frame(width: 34, height: 34)
                .background(hasAdvancedOverrides ? AdaColors.navy : AdaColors.card, in: Circle())
                .overlay(Circle().stroke(hasAdvancedOverrides ? .clear : AdaColors.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("Tools & crop")
        .accessibilityLabel("Tools and crop options")
        .adaFloatingPopup(isPresented: $showsOptionsPopover, placement: .belowTrailing, verticalGap: 8) {
            optionsPopover
        }
    }

    private var optionsPopover: some View {
        AdaPopupCardSurface(width: 262, padding: 10) {
            AdaPopupRow(
                title: "Keratin suture mesh",
                icon: "square.grid.3x3",
                badge: showsSutureMesh ? "On" : "Off",
                isSelected: showsSutureMesh
            ) {
                showsSutureMesh.toggle()
                if showsSutureMesh && stageMode == .compare { stageMode = .contours }
            }

            AdaPopupRow(
                title: "Lines only",
                icon: "scribble.variable",
                badge: linesOnly ? "On" : "Off",
                isSelected: linesOnly
            ) {
                linesOnly.toggle()
                if linesOnly && stageMode == .compare { stageMode = .contours }
            }

            AdaPopupRow(
                title: "Show AI outliers",
                icon: "exclamationmark.triangle",
                badge: showsAIOutliers ? "On" : "Off",
                isSelected: showsAIOutliers
            ) {
                showsAIOutliers.toggle()
                if showsAIOutliers && !showsAIMatches { showsAIMatches = true }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Contour detail")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AdaColors.ink)
                    Spacer()
                    Text("\(detailBucket)%")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(AdaColors.secondaryInk)
                }
                Slider(value: $detailSensitivity, in: 0.25...0.75, step: 0.05)
                    .tint(AdaColors.navy)
                    .controlSize(.small)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider().padding(.vertical, 4)

            AdaPopupRow(
                title: liveSearchAvailable ? "Crop, Tilt & Re-match" : "Crop head area",
                icon: "crop.rotate",
                badge: customQueryROI != nil ? "Active" : nil,
                isSelected: customQueryROI != nil,
                isDisabled: !isPending || item.queryImage == nil
            ) {
                showsOptionsPopover = false
                showsCropSheet = true
            }

            if hasAdvancedOverrides {
                AdaPopupRow(title: "Reset tools", icon: "arrow.counterclockwise", isSubdued: true) {
                    linesOnly = false
                    showsSutureMesh = false
                    showsAIOutliers = false
                    detailSensitivity = 0.48
                    customQueryROI = nil
                    showsOptionsPopover = false
                }
            }
        }
    }

    private var queueStepper: some View {
        HStack(spacing: 2) {
            stepperArrow("chevron.left", label: "Previous case", action: onPrevious)
            Text("\(queueIndex + 1)/\(queueCount)")
                .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                .padding(.horizontal, 4)
            stepperArrow("chevron.right", label: "Next case", action: onNext)
        }
        .padding(.horizontal, 5)
        .frame(height: 34)
        .background(AdaColors.card, in: Capsule())
        .overlay(Capsule().stroke(AdaColors.line, lineWidth: 1))
        .fixedSize()
    }

    private func stepperArrow(_ symbol: String, label: String, action: (() -> Void)?) -> some View {
        Button { action?() } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 24, height: 24)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(action == nil ? AdaColors.secondaryInk.opacity(0.32) : AdaColors.ink)
        .disabled(action == nil)
        .accessibilityLabel(label)
    }

    // MARK: - 2. Photo Comparison Stage (~75% Width, Dark Neutral Frame)

    private var stageContainer: some View {
        VStack(spacing: 0) {
            stageToolbar
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            stageBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Self.stageDark)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var stageToolbar: some View {
        HStack(spacing: 8) {
            switch stageMode {
            case .compare:
                compareControls
            case .contours:
                if showsPatchTool {
                    patchControls
                } else {
                    contourControls
                }
            case .align:
                alignControls
            }

            Spacer(minLength: 6)

            if isExtractingContours || isLoadingAIAnnotations || isRenderingWarp {
                ProgressView()
                    .controlSize(.mini)
                    .tint(.white)
                    .accessibilityLabel("Processing visual alignment")
            }

            if showsPatchTool && stageMode == .contours {
                if showsPatchPreviews && canSelectPatches {
                    zoomControls("Sighting", scale: patchViewports.sighting.magnified(by: sightingMagnification).scale, viewport: $patchViewports.sighting)
                    zoomControls("Candidate", scale: patchViewports.candidate.magnified(by: candidateMagnification).scale, viewport: $patchViewports.candidate)
                }
            } else {
                zoomControls
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
    }

    // MARK: Compare Mode Controls (Side by Side / Curtain / Blend + Real XFeat RANSAC)

    @ViewBuilder
    private var compareControls: some View {
        HStack(spacing: 2) {
            ForEach(ComparePresentation.allCases) { mode in
                darkModeChip(mode.rawValue, active: comparePresentation == mode) {
                    withAnimation(.easeOut(duration: 0.14)) {
                        comparePresentation = mode
                        if mode != .blend { isBlinking = false }
                    }
                }
            }
        }
        .padding(3)
        .background(Self.stageChipBg, in: Capsule())

        if comparePresentation == .blend, selectedCandidate?.image != nil {
            blinkButton
            opacitySlider(leftLabel: "S", rightLabel: "C")
        }

        if comparePresentation == .sideBySide, aiAnnotationsAvailable {
            Button {
                withAnimation(.easeOut(duration: 0.14)) {
                    showsAIMatches.toggle()
                    if !showsAIMatches { selectedAIFeatureID = nil }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10.5, weight: .semibold))
                    Text("AI Matches")
                        .font(.system(size: 11.5, weight: .semibold))
                }
                .foregroundStyle(showsAIMatches ? Self.stageDark : .white)
                .padding(.horizontal, 11)
                .frame(height: 28)
                .background(showsAIMatches ? Color.cyan : Self.stageChipBg, in: Capsule())
            }
            .buttonStyle(.plain)
            .help("Load XFeat/LighterGlue correspondences filtered by RANSAC geometric consensus")

            if showsAIMatches, let consensus = activeConsensus {
                let toneColor: Color = {
                    switch consensus.strength {
                    case .strong: AdaColors.green
                    case .moderate: .cyan
                    case .weak, .insufficient: AdaColors.orange
                    }
                }()
                darkInfoPill(consensus.shortBadgeText, accent: toneColor)

                if consensus.canAutoSeedWarp {
                    Button {
                        seedAlignmentFromConsensus(consensus, switchToCurtain: true)
                    } label: {
                        HStack(spacing: 4) {
                            Text("Warp photo")
                            Image(systemName: "arrow.right")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Self.stageDark)
                        .padding(.horizontal, 11)
                        .frame(height: 28)
                        .background(Color.white, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Seed 4 RANSAC inliers and warp the real sighting photo onto the candidate")
                }
            }
        }
    }

    // MARK: Contours # Mode Controls (Interactive Real Annotation Editing)

    @ViewBuilder
    private var contourControls: some View {
        darkModeChip("Compare scales", active: false) {
            isAddingManualLandmark = false
            showsPatchTool = true
        }

        Button {
            withAnimation(.easeOut(duration: 0.14)) {
                isAddingManualLandmark.toggle()
            }
        } label: {
            Label(isAddingManualLandmark ? "Click cheek…" : "Mark scale", systemImage: isAddingManualLandmark ? "mappin.and.ellipse" : "plus.circle")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(isAddingManualLandmark ? Self.stageDark : .white)
                .padding(.horizontal, 11)
                .frame(height: 28)
                .background(isAddingManualLandmark ? Color.cyan : Self.stageChipBg, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isPending || showingCompanionSide)
        .help("Click anywhere on the sighting photo to annotate a scale missed under glare")

        if let qNum = selectedQueryScale,
           let qPat = visibleQueryPatterns.first(where: { $0.number == qNum }) {
            let hits = aiSupportCount(forQueryScale: qPat)
            let label = hits > 0
                ? "S #\(qPat.number) · \(qPat.vertexCount)-sided · \(hits) AI"
                : "S #\(qPat.number) · \(qPat.vertexCount)-sided"
            darkInfoPill(label, accent: .cyan)

            if isPending && !showingCompanionSide {
                Button {
                    excludeQueryScale(qPat.number)
                } label: {
                    Label("Hide false", systemImage: "eye.slash")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AdaColors.orange)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(AdaColors.orange.opacity(0.18), in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Exclude false-positive scale contour from this case")
            }
        }

        if let cNum = selectedCandidateScale,
           let cPat = visibleCandidatePatterns.first(where: { $0.number == cNum }) {
            darkInfoPill("C #\(cPat.number) · \(cPat.vertexCount)-sided", accent: AdaColors.orange)
        }

        if !excludedQueryScales.isEmpty || !customQueryLandmarks.isEmpty {
            Button {
                _ = perform(.clearManualScaleEdits)
                selectedQueryScale = nil
            } label: {
                Text("Reset edits (\(excludedQueryScales.count + customQueryLandmarks.count))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.82))
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Self.stageChipBg, in: Capsule())
            }
            .buttonStyle(.plain)
        } else if selectedQueryScale == nil && selectedCandidateScale == nil && !isAddingManualLandmark {
            Text("Click any scale to inspect · Right-click to exclude")
                .font(.system(size: 11.5))
                .foregroundStyle(Color.white.opacity(0.62))
                .lineLimit(1)
        }
    }

    // MARK: Align Mode Controls (True Pixel-Warped Human-Assisted Registration)

    @ViewBuilder
    private var alignControls: some View {
        let count = activeAnchors.count
        let result = alignmentResult

        HStack(spacing: 7) {
            HStack(spacing: 3.5) {
                ForEach(0..<4, id: \.self) { idx in
                    Circle()
                        .fill(idx < count ? (idx == 3 ? AdaColors.green : Color.cyan) : Color.white.opacity(0.24))
                        .frame(width: 6.5, height: 6.5)
                }
            }
            Text(result.pillText)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(result.isWarning ? AdaColors.orange : .white)
        }
        .padding(.horizontal, 11)
        .frame(height: 28)
        .background(
            result.isWarning ? AdaColors.orange.opacity(0.20) : Self.stageChipBg,
            in: Capsule()
        )

        if pendingQueryPin != nil {
            darkInfoPill("Click matching spot on Candidate", accent: .cyan)
            Button {
                pendingQueryPin = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 24, height: 24)
                    .background(Self.stageChipBg, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Cancel pending pin")
        }

        if result.isReadyForWarp {
            HStack(spacing: 2) {
                ForEach(AlignPresentation.allCases) { mode in
                    darkModeChip(mode.rawValue, active: alignPresentation == mode) {
                        withAnimation(.easeOut(duration: 0.14)) {
                            alignPresentation = mode
                            if mode != .blend { isBlinking = false }
                        }
                    }
                }
            }
            .padding(3)
            .background(Self.stageChipBg, in: Capsule())

            if alignPresentation == .blend {
                blinkButton
                opacitySlider(leftLabel: "S", rightLabel: "C")
            }

            if alignPresentation != .pins {
                Button {
                    showWarpedContoursOnPhoto.toggle()
                } label: {
                    Text("Lines")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(showWarpedContoursOnPhoto ? Self.stageDark : .white.opacity(0.84))
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(showWarpedContoursOnPhoto ? Color.cyan : Self.stageChipBg, in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Toggle warped scale outlines on top of pixel-registered photos")
            }
        }

        if selectedCandidate?.image != nil {
            Button {
                Task { await autoAlignCurrentCandidate() }
            } label: {
                Label(count >= 3 ? "Re-seed AI" : "Auto-align", systemImage: "sparkles")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 11)
                    .frame(height: 28)
                    .background(Self.stageChipBg, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isLoadingAIAnnotations)
            .help("Seed 4 pins from RANSAC AI inliers (or scale-constellation RANSAC fallback)")
        }

        if !activeAnchors.isEmpty {
            Button { undoLastAnchor() } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.84))
                    .frame(width: 28, height: 28)
                    .background(Self.stageChipBg, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Undo last pin")

            Button { clearAnchors() } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.76))
                    .frame(width: 28, height: 28)
                    .background(Self.stageChipBg, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Clear all pins")
        }
    }

    private var blinkButton: some View {
        Button { isBlinking.toggle() } label: {
            Label("Blink", systemImage: isBlinking ? "pause.fill" : "eye")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(isBlinking ? Self.stageDark : .white)
                .padding(.horizontal, 11)
                .frame(height: 28)
                .background(isBlinking ? Color.white : Self.stageChipBg, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func opacitySlider(leftLabel: String, rightLabel: String) -> some View {
        HStack(spacing: 6) {
            Button(leftLabel) { isBlinking = false; overlayOpacity = 0 }
                .buttonStyle(.plain)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.72))
            Slider(
                value: Binding(
                    get: { effectiveOverlayAlpha },
                    set: { isBlinking = false; overlayOpacity = $0 }
                ),
                in: 0...1
            )
            .tint(AdaColors.accent)
            .frame(minWidth: 68, maxWidth: 108)
            .accessibilityLabel("Overlay opacity")
            Button(rightLabel) { isBlinking = false; overlayOpacity = 1 }
                .buttonStyle(.plain)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.72))
        }
    }

    private func darkModeChip(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: active ? .semibold : .medium))
                .foregroundStyle(active ? Self.stageDark : Color.white.opacity(0.82))
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(active ? Color.white : .clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func darkInfoPill(_ text: String, accent: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(accent).frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(Self.stageChipBg, in: Capsule())
    }

    private var usesOverlayViewport: Bool {
        switch stageMode {
        case .compare:
            comparePresentation != .sideBySide
        case .contours:
            false
        case .align:
            alignPresentation != .pins && alignmentResult.isReadyForWarp
        }
    }

    private var sightingViewport: NotSurePhotoViewport {
        viewports.sighting.magnified(by: sightingMagnification)
    }

    private var candidateViewport: NotSurePhotoViewport {
        viewports.candidate.magnified(by: candidateMagnification)
    }

    private var overlayViewport: NotSurePhotoViewport {
        viewports.overlay.magnified(by: overlayMagnification)
    }

    @ViewBuilder
    private var zoomControls: some View {
        if usesOverlayViewport {
            zoomControls("Comparison", scale: overlayViewport.scale, viewport: $viewports.overlay)
                .disabled(displayedQueryImage == nil && selectedCandidate?.image == nil)
        } else {
            zoomControls("Sighting", scale: sightingViewport.scale, viewport: $viewports.sighting)
                .disabled(displayedQueryImage == nil)
            zoomControls("Candidate", scale: candidateViewport.scale, viewport: $viewports.candidate)
                .disabled(selectedCandidate?.image == nil)
        }
    }

    private func zoomControls(
        _ label: String,
        scale: CGFloat,
        viewport: Binding<NotSurePhotoViewport>
    ) -> some View {
        VStack(spacing: 0) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
                .accessibilityHidden(true)
            HStack(spacing: 2) {
                zoomStepButton("minus", label: "Zoom out · \(label)", disabled: scale <= 1) {
                    withAnimation(.easeOut(duration: 0.14)) { viewport.wrappedValue.stepZoom(by: -0.5) }
                }
                Button {
                    withAnimation(.easeOut(duration: 0.14)) { viewport.wrappedValue = NotSurePhotoViewport() }
                } label: {
                    Text("\(Int((scale * 100).rounded()))%")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .frame(minWidth: 36, minHeight: 22)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reset zoom · \(label)")
                .accessibilityValue("\(Int((scale * 100).rounded()))%")
                .help("Reset zoom · \(label)")
                zoomStepButton("plus", label: "Zoom in · \(label)", disabled: scale >= NotSurePhotoViewport.maximumScale) {
                    withAnimation(.easeOut(duration: 0.14)) { viewport.wrappedValue.stepZoom(by: 0.5) }
                }
            }
        }
        .padding(.horizontal, 5)
        .frame(height: 36)
        .background(Self.stageChipBg, in: RoundedRectangle(cornerRadius: 12))
        .fixedSize()
    }

    private func pinchZoom(
        _ viewport: Binding<NotSurePhotoViewport>,
        magnification: GestureState<CGFloat>
    ) -> some Gesture {
        MagnifyGesture()
            .updating(magnification) { value, factor, _ in
                factor = value.magnification
            }
            .onEnded { value in
                viewport.wrappedValue = viewport.wrappedValue.magnified(by: value.magnification)
            }
    }

    private func zoomStepButton(_ symbol: String, label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 22, height: 22)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(disabled ? Color.white.opacity(0.32) : .white)
        .disabled(disabled)
        .accessibilityLabel(label)
    }

    private func updatePatchSources() {
        patchSession.updateSources(sighting: sightingPatchSource, candidate: candidatePatchSource)
        patchViewports = NotSureComparisonViewports()
        showsPatchPreviews = false
    }

    @ViewBuilder
    private var patchControls: some View {
        darkModeChip("Back to Contours", active: false) { showsPatchTool = false }
        if !canSelectPatches {
            let message = if displayedQueryImage == nil || selectedCandidate?.image == nil {
                "Both photos are needed"
            } else if item.companionImage != nil, let side = selectedCandidate?.side {
                "Switch the sighting to \(side.shortLabel)"
            } else {
                "Photos must show the same side"
            }
            Text(message).font(.caption).foregroundStyle(.white)
        } else if showsPatchPreviews {
            darkModeChip("Edit patches", active: false) { showsPatchPreviews = false }
            darkModeChip("Outlines", active: showsPatchOutlines) { showsPatchOutlines.toggle() }
        } else {
            darkModeChip("Compare patches", active: false) {
                patchViewports = NotSureComparisonViewports()
                showsPatchPreviews = true
            }
            .disabled(patchSession.sighting == nil || patchSession.candidate == nil)
            Text("Drag a box around the same scales in both photos")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
        }
    }

    private func patchStage(sighting: NSImage, candidate: NSImage) -> some View {
        HStack(spacing: 1) {
            patchPane(
                image: sighting, patch: $patchSession.sighting, patterns: visibleQueryPatterns,
                viewport: $patchViewports.sighting, magnification: sightingMagnification,
                gestureState: $sightingMagnification, badge: "SIGHTING · \(activeSightingSide.shortLabel.uppercased())",
                accent: .cyan
            )
            .id(sightingPatchSource)
            patchPane(
                image: candidate, patch: $patchSession.candidate, patterns: visibleCandidatePatterns,
                viewport: $patchViewports.candidate, magnification: candidateMagnification,
                gestureState: $candidateMagnification, badge: selectedCandidate?.name ?? "CANDIDATE",
                accent: AdaColors.orange
            )
            .id(candidatePatchSource)
        }
    }

    private func patchPane(
        image: NSImage,
        patch: Binding<CGRect?>,
        patterns: [DetectedScalePattern],
        viewport: Binding<NotSurePhotoViewport>,
        magnification: CGFloat,
        gestureState: GestureState<CGFloat>,
        badge: String,
        accent: Color
    ) -> some View {
        Group {
            if showsPatchPreviews, let rect = patch.wrappedValue {
                NotSurePatchPreview(
                    image: image, patch: rect, outlines: showsPatchOutlines ? patterns : [],
                    accent: accent, viewport: viewport.wrappedValue.magnified(by: magnification),
                    onPanChanged: { viewport.wrappedValue.dragDelta = $0 },
                    onPanEnded: { viewport.wrappedValue.commitPan($0) }
                )
                .simultaneousGesture(pinchZoom(viewport, magnification: gestureState))
            } else {
                NotSurePatchPicker(image: image, accent: accent, patch: patch)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            stageCornerBadge(badge).padding(10).allowsHitTesting(false)
        }
    }

    // MARK: Stage Body

    @ViewBuilder
    private var stageBody: some View {
        if stageMode == .contours, showsPatchTool, canSelectPatches,
           let sighting = displayedQueryImage, let candidate = selectedCandidate?.image {
            patchStage(sighting: sighting, candidate: candidate)
        } else if stageMode == .compare && comparePresentation == .curtain {
            curtainWipeCanvas(
                leftImage: displayedQueryImage,
                rightImage: selectedCandidate?.image,
                leftLabel: "SIGHTING",
                rightLabel: selectedCandidate?.name ?? "CANDIDATE",
                warpedContours: nil
            )
        } else if stageMode == .compare && comparePresentation == .blend {
            blendOverlayCanvas(
                baseImage: displayedQueryImage,
                topImage: selectedCandidate?.image,
                topAlpha: effectiveOverlayAlpha,
                badge: isBlinking
                    ? (blinkShowsCandidate ? (selectedCandidate?.name ?? "Candidate") : "Sighting")
                    : "Raw Blend · \(Int((overlayOpacity * 100).rounded()))%",
                warpedContours: nil
            )
        } else if stageMode == .align && alignPresentation == .curtain && alignmentResult.isReadyForWarp {
            curtainWipeCanvas(
                leftImage: warpedQueryImage ?? displayedQueryImage,
                rightImage: selectedCandidate?.image,
                leftLabel: "SIGHTING (WARPED · \(alignmentResult.transform?.modeLabel.uppercased() ?? "ALIGNED"))",
                rightLabel: selectedCandidate?.name ?? "CANDIDATE",
                warpedContours: showWarpedContoursOnPhoto ? alignmentResult.warpedContours : nil
            )
        } else if stageMode == .align && alignPresentation == .blend && alignmentResult.isReadyForWarp {
            blendOverlayCanvas(
                baseImage: selectedCandidate?.image,
                topImage: warpedQueryImage,
                topAlpha: 1.0 - effectiveOverlayAlpha,
                badge: isBlinking
                    ? (blinkShowsCandidate ? (selectedCandidate?.name ?? "Candidate") : "Sighting (Warped)")
                    : "Pixel-Warped Blend · \(Int(((1.0 - overlayOpacity) * 100).rounded()))% Sighting",
                warpedContours: showWarpedContoursOnPhoto ? alignmentResult.warpedContours : nil
            )
        } else {
            sideBySideStage
        }
    }

    // MARK: Side-by-Side Stage (+ Cross-Pane AI RANSAC Threads & Draggable Precision Pins)

    private var sideBySideStage: some View {
        let aiInlierIDs = activeConsensus?.inlierFeatureIDs ?? []
        return GeometryReader { stageGeo in
            ZStack {
                HStack(spacing: 0) {
                    queryStagePane
                    Rectangle().fill(Color.white.opacity(0.10)).frame(width: 1)
                    candidateStagePane
                }

                // Cross-pane RANSAC-filtered XFeat/LighterGlue threads in Compare + AI Matches mode
                if stageMode == .compare && showsAIMatches,
                   let qImg = displayedQueryImage,
                   let cImg = selectedCandidate?.image,
                   !activeAIAnnotations.isEmpty {
                    aiThreadsOverlay(
                        stageSize: stageGeo.size,
                        queryImage: qImg,
                        candidateImage: cImg,
                        annotations: activeAIAnnotations,
                        inlierIDs: aiInlierIDs
                    )
                }
            }
            .clipped()
        }
    }

    private var queryStagePane: some View {
        let queryBadge = "SIGHTING · \(activeSightingSide.shortLabel.uppercased())"
        let showContoursLayer = stageMode == .contours || (stageMode == .align && !linesOnly)
        let pins: [NotSurePanePin] = stageMode == .align
            ? activeAnchors.map { NotSurePanePin(id: $0.id, label: $0.label, point: $0.queryPoint, source: $0.source) }
            : []
        let excludeHandler: ((Int) -> Void)? = (stageMode == .contours && isPending && !showingCompanionSide)
            ? { num in excludeQueryScale(num) }
            : nil

        return NotSurePhotoPane(
            image: displayedQueryImage,
            badge: queryBadge,
            emptyLabel: "No photo",
            accent: .cyan,
            showContours: showContoursLayer,
            showScaleBadges: stageMode == .contours,
            showsSutureMesh: showsSutureMesh && stageMode == .contours,
            linesOnly: linesOnly && stageMode != .compare,
            patterns: visibleQueryPatterns,
            mesh: queryAnalysis?.mesh ?? .empty,
            customLandmarks: customQueryLandmarks,
            highlightedScale: selectedQueryScale,
            pairedNumbers: Set(activeAnchors.compactMap(\.queryScaleNumber)),
            anchors: pins,
            pendingPoint: stageMode == .align ? pendingQueryPin?.point : nil,
            allowsFreeTap: stageMode == .align || isAddingManualLandmark,
            zoomScale: sightingViewport.scale,
            panOffset: sightingViewport.offset,
            onPanChanged: { viewports.sighting.dragDelta = $0 },
            onPanEnded: { viewports.sighting.commitPan($0) },
            onTapScale: handleQueryScaleTap,
            onExcludeScale: excludeHandler,
            onTapNormalizedPoint: handleQueryFreeTap,
            onDragAnchor: { id, pt in moveAnchor(id: id, isQuery: true, to: pt) },
            onDeleteAnchor: deleteAnchor(id:),
            onDeleteLandmark: { id in _ = perform(.removeCustomQueryLandmark(id)) }
        )
        .simultaneousGesture(
            pinchZoom($viewports.sighting, magnification: $sightingMagnification),
            including: displayedQueryImage == nil ? .none : .all
        )
    }

    private var candidateStagePane: some View {
        let candBadge: String = {
            guard let cand = selectedCandidate else { return "CANDIDATE" }
            let score = cand.isBundledExample ? "SAMPLE" : (item.desktopReview == nil ? "\(cand.confidencePercent)%" : "Score \(cand.confidencePercent)%")
            return "#\(cand.rank) \(cand.name) · \(score)"
        }()
        let showContoursLayer = stageMode == .contours || (stageMode == .align && !linesOnly)
        let pins: [NotSurePanePin] = stageMode == .align
            ? activeAnchors.map { NotSurePanePin(id: $0.id, label: $0.label, point: $0.candidatePoint, source: $0.source) }
            : []

        return NotSurePhotoPane(
            image: selectedCandidate?.image,
            badge: candBadge,
            warningBadge: selectedCandidate.flatMap { $0.sideMatches ? nil : "Opposite side" },
            emptyLabel: selectedCandidate == nil ? "No candidate" : "No photo",
            accent: AdaColors.orange,
            showContours: showContoursLayer,
            showScaleBadges: stageMode == .contours,
            showsSutureMesh: showsSutureMesh && stageMode == .contours,
            linesOnly: linesOnly && stageMode != .compare,
            patterns: visibleCandidatePatterns,
            mesh: candidateAnalysis?.mesh ?? .empty,
            customLandmarks: [],
            highlightedScale: selectedCandidateScale,
            pairedNumbers: Set(activeAnchors.compactMap(\.candidateScaleNumber)),
            anchors: pins,
            pendingPoint: nil,
            allowsFreeTap: stageMode == .align && pendingQueryPin != nil,
            zoomScale: candidateViewport.scale,
            panOffset: candidateViewport.offset,
            onPanChanged: { viewports.candidate.dragDelta = $0 },
            onPanEnded: { viewports.candidate.commitPan($0) },
            onTapScale: handleCandidateScaleTap,
            onExcludeScale: nil,
            onTapNormalizedPoint: handleCandidateFreeTap,
            onDragAnchor: { id, pt in moveAnchor(id: id, isQuery: false, to: pt) },
            onDeleteAnchor: deleteAnchor(id:),
            onDeleteLandmark: nil
        )
        .simultaneousGesture(
            pinchZoom($viewports.candidate, magnification: $candidateMagnification),
            including: selectedCandidate?.image == nil ? .none : .all
        )
    }

    @ViewBuilder
    private func aiThreadsOverlay(
        stageSize: CGSize,
        queryImage: NSImage,
        candidateImage: NSImage,
        annotations: [OverlayAnnotationItem],
        inlierIDs: Set<String>
    ) -> some View {
        let paneWidth = max(1, (stageSize.width - 1) * 0.5)
        let paneSize = CGSize(width: paneWidth, height: stageSize.height)
        let qFitted = NotSurePhotoGeometry.aspectFitRect(imageSize: queryImage.size, in: paneSize)
        let cFitted = NotSurePhotoGeometry.aspectFitRect(imageSize: candidateImage.size, in: paneSize)
        let rightOriginX = paneWidth + 1

        let displayed = annotations.filter { ann in
            inlierIDs.contains(ann.featureID) || showsAIOutliers
        }

        ZStack(alignment: .bottom) {
            Canvas { ctx, _ in
                for ann in displayed {
                    let isInlier = inlierIDs.contains(ann.featureID)
                    let isSelected = selectedAIFeatureID == ann.featureID
                    let qPt = Self.screenPoint(
                        from: ScalePoint(x: ann.query.x, y: ann.query.y),
                        fitted: qFitted,
                        container: paneSize,
                        zoom: sightingViewport.scale,
                        pan: sightingViewport.offset
                    )
                    var cPt = Self.screenPoint(
                        from: ScalePoint(x: ann.candidate.x, y: ann.candidate.y),
                        fitted: cFitted,
                        container: paneSize,
                        zoom: candidateViewport.scale,
                        pan: candidateViewport.offset
                    )
                    cPt.x += rightOriginX

                    var line = Path()
                    line.move(to: qPt)
                    line.addLine(to: cPt)

                    let alpha: Double = {
                        if let sel = selectedAIFeatureID {
                            return sel == ann.featureID ? 1.0 : 0.08
                        }
                        return isInlier ? 0.58 : 0.28
                    }()

                    let strokeColor: Color = isInlier ? AdaColors.green : AdaColors.red
                    let style = isInlier
                        ? StrokeStyle(lineWidth: isSelected ? 2.4 : 1.25, lineCap: .round)
                        : StrokeStyle(lineWidth: 1.0, lineCap: .round, dash: [4, 4])

                    ctx.stroke(line, with: .color(strokeColor.opacity(alpha)), style: style)

                    let r: CGFloat = isSelected ? 4.5 : (isInlier ? 3.2 : 2.5)
                    let qDot = Path(ellipseIn: CGRect(x: qPt.x - r, y: qPt.y - r, width: r * 2, height: r * 2))
                    let cDot = Path(ellipseIn: CGRect(x: cPt.x - r, y: cPt.y - r, width: r * 2, height: r * 2))
                    ctx.fill(qDot, with: .color(strokeColor.opacity(min(1.0, alpha + 0.3))))
                    ctx.fill(cDot, with: .color(strokeColor.opacity(min(1.0, alpha + 0.3))))
                }
            }
            .allowsHitTesting(false)

            // Tappable endpoints for top 24 displayed correspondences
            ForEach(Array(displayed.prefix(24))) { ann in
                let isInlier = inlierIDs.contains(ann.featureID)
                let qPt = Self.screenPoint(
                    from: ScalePoint(x: ann.query.x, y: ann.query.y),
                    fitted: qFitted,
                    container: paneSize,
                    zoom: sightingViewport.scale,
                    pan: sightingViewport.offset
                )
                Button {
                    selectedAIFeatureID = (selectedAIFeatureID == ann.featureID) ? nil : ann.featureID
                } label: {
                    Circle().fill(Color.clear).frame(width: 18, height: 18).contentShape(Circle())
                }
                .buttonStyle(.plain)
                .position(qPt)
                .help("\(isInlier ? "RANSAC Inlier" : "Rejected Outlier") · \(Int(((ann.score ?? 0) * 100).rounded()))% XFeat")
            }

            if let selID = selectedAIFeatureID,
               let ann = annotations.first(where: { $0.featureID == selID }) {
                let isInlier = inlierIDs.contains(ann.featureID)
                HStack(spacing: 8) {
                    Circle()
                        .fill(isInlier ? AdaColors.green : AdaColors.red)
                        .frame(width: 7, height: 7)
                    Text(isInlier ? "Geometric Inlier" : "Rejected Outlier")
                        .font(.system(size: 11.5, weight: .semibold))
                    Text("· XFeat \(Int(((ann.score ?? 0) * 100).rounded()))%")
                        .font(.system(size: 11.5).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.75))
                    Button { selectedAIFeatureID = nil } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9.5, weight: .bold))
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.76), in: Capsule())
                .padding(.bottom, 12)
            }
        }
    }

    // MARK: Draggable Split Curtain Wipe Canvas (Works for BOTH Raw & Pixel-Warped Photos!)

    private func curtainWipeCanvas(
        leftImage: NSImage?,
        rightImage: NSImage?,
        leftLabel: String,
        rightLabel: String,
        warpedContours: [WarpedPatternContour]?
    ) -> some View {
        GeometryReader { geo in
            let w = max(1, geo.size.width)
            let h = max(1, geo.size.height)
            let splitX = min(max(curtainPosition, 0.04), 0.96) * w
            let refSize = rightImage?.size ?? leftImage?.size ?? geo.size
            let fitted = NotSurePhotoGeometry.aspectFitRect(imageSize: refSize, in: geo.size)

            ZStack {
                // Right half (Candidate full canvas)
                if let rightImage {
                    Image(nsImage: rightImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: w, height: h)
                        .scaleEffect(overlayViewport.scale)
                        .offset(overlayViewport.offset)
                }

                // Left half (Pixel-warped Sighting clipped sharply at splitX!)
                if let leftImage {
                    Image(nsImage: leftImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: w, height: h)
                        .scaleEffect(overlayViewport.scale)
                        .offset(overlayViewport.offset)
                        .mask(alignment: .leading) {
                            Rectangle().frame(width: splitX)
                        }
                }

                // Optional warped scale contours projected onto candidate frame
                if let warpedContours, !warpedContours.isEmpty {
                    Canvas { ctx, _ in
                        for warped in warpedContours {
                            let path = NotSurePhotoGeometry.polygonPath(warped.polygon, in: fitted)
                            ctx.stroke(path, with: .color(Color.cyan.opacity(0.9)), lineWidth: 1.7)
                        }
                    }
                    .scaleEffect(overlayViewport.scale)
                    .offset(overlayViewport.offset)
                    .allowsHitTesting(false)
                }

                // Crisp draggable vertical divider handle
                Rectangle()
                    .fill(Color.white.opacity(0.92))
                    .frame(width: 2, height: h)
                    .shadow(color: .black.opacity(0.5), radius: 3)
                    .position(x: splitX, y: h * 0.5)
                    .allowsHitTesting(false)

                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Image(systemName: "chevron.right")
                }
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Self.stageDark)
                .frame(width: 34, height: 34)
                .background(Color.white, in: Circle())
                .shadow(color: .black.opacity(0.45), radius: 6, y: 2)
                .position(x: splitX, y: h * 0.5)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            curtainPosition = min(0.96, max(0.04, value.location.x / w))
                        }
                )
                .accessibilityLabel("Drag divider to compare warped sighting against candidate")
            }
            .frame(width: w, height: h)
            .clipped()
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { value in
                        if viewports.overlay.isZoomed {
                            viewports.overlay.dragDelta = value.translation
                        } else {
                            curtainPosition = min(0.96, max(0.04, value.location.x / w))
                        }
                    }
                    .onEnded { value in
                        viewports.overlay.commitPan(value.translation)
                    }
            )
            .simultaneousGesture(pinchZoom($viewports.overlay, magnification: $overlayMagnification))
            .overlay(alignment: .topLeading) {
                stageCornerBadge(leftLabel).padding(12)
            }
            .overlay(alignment: .topTrailing) {
                stageCornerBadge(rightLabel).padding(12)
            }
        }
    }

    // MARK: Pixel-Registered Blend & Blink Canvas

    private func blendOverlayCanvas(
        baseImage: NSImage?,
        topImage: NSImage?,
        topAlpha: Double,
        badge: String,
        warpedContours: [WarpedPatternContour]?
    ) -> some View {
        GeometryReader { geo in
            let refSize = baseImage?.size ?? topImage?.size ?? geo.size
            let fitted = NotSurePhotoGeometry.aspectFitRect(imageSize: refSize, in: geo.size)

            ZStack {
                if let baseImage, !linesOnly {
                    Image(nsImage: baseImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .scaleEffect(overlayViewport.scale)
                        .offset(overlayViewport.offset)
                }
                if let topImage, !linesOnly {
                    Image(nsImage: topImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .scaleEffect(overlayViewport.scale)
                        .offset(overlayViewport.offset)
                        .opacity(min(1, max(0, topAlpha)))
                }
                if let warpedContours, !warpedContours.isEmpty {
                    Canvas { ctx, _ in
                        for warped in warpedContours {
                            let path = NotSurePhotoGeometry.polygonPath(warped.polygon, in: fitted)
                            ctx.fill(path, with: .color(Color.cyan.opacity(0.12)))
                            ctx.stroke(path, with: .color(Color.cyan.opacity(0.95)), lineWidth: 1.9)
                        }
                    }
                    .scaleEffect(overlayViewport.scale)
                    .offset(overlayViewport.offset)
                    .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .contentShape(Rectangle())
            .gesture(overlayPanGesture)
            .simultaneousGesture(pinchZoom($viewports.overlay, magnification: $overlayMagnification))
            .overlay(alignment: .topLeading) {
                stageCornerBadge(badge).padding(12)
            }
        }
    }

    private func stageCornerBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.58), in: Capsule())
    }

    private var overlayPanGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                guard viewports.overlay.isZoomed else { return }
                viewports.overlay.dragDelta = value.translation
            }
            .onEnded { value in
                viewports.overlay.commitPan(value.translation)
            }
    }

    // MARK: - 3. Slim Right Candidate Rail (+ Direct Crop/Re-Match & Delta Badges)

    private var candidateRail: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("Candidates")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(AdaColors.ink)

                Text("\(availableCandidates.count)")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(AdaColors.secondaryInk)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(AdaColors.surfaceMuted, in: Capsule())

                Spacer(minLength: 0)

                if !rejectedCandidates.isEmpty {
                    Button {
                        withAnimation(.easeOut(duration: 0.14)) { showsRejected.toggle() }
                    } label: {
                        Text(showsRejected ? "Active" : "Rejected (\(rejectedCandidates.count))")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(showsRejected ? AdaColors.navy : AdaColors.secondaryInk)
                    }
                    .buttonStyle(.plain)
                }

                if isPending && item.queryImage != nil {
                    Button { showsCropSheet = true } label: {
                        Image(systemName: "crop.rotate")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(customQueryROI != nil ? AdaColors.accent : AdaColors.secondaryInk)
                    }
                    .buttonStyle(.plain)
                    .disabled(isSearching || isSavingCandidateReview || isLoadingMoreCandidates || isSavingVerdict)
                    .help(liveSearchAvailable ? "Crop, level tilt & re-match" : "Crop head region")
                }

                if liveSearchAvailable {
                    Button { searchCoverage = 70; searchRequest = UUID() } label: {
                        if isSearching {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AdaColors.secondaryInk)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isSearching || isSavingCandidateReview || isLoadingMoreCandidates || isSavingVerdict)
                    .help("Search gallery again")
                }
            }

            if let state = item.desktopReview {
                DesktopReviewProgressCard(state: state, isSearching: isSearching,
                    isBusy: isSearching || isSavingCandidateReview || isLoadingMoreCandidates,
                    onSearchAll: { searchCoverage = 100; searchRequest = UUID() },
                    onStopWaiting: { searchRequest = nil })
            } else if isSearching {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Searching reference photos…").font(.caption)
                    Button("Stop waiting") { searchRequest = nil }
                }
            }

            if displayedCandidates.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    if isSearching {
                        ProgressView()
                        Text("Searching the gallery")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AdaColors.secondaryInk)
                    } else {
                        Image(systemName: showsRejected ? "arrow.uturn.backward.circle" : "person.crop.circle.badge.questionmark")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(AdaColors.secondaryInk)
                        Text(showsRejected ? "No rejected candidates" : (item.candidates.isEmpty ? "No candidates" : "All candidates ruled out"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AdaColors.secondaryInk)
                            .multilineTextAlignment(.center)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(displayedCandidates) { candidate in
                            candidateCard(candidate)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            if store.hasMoreNotSureCandidates(item.id) {
                Button {
                    isLoadingMoreCandidates = true
                    pageTask = Task {
                        defer { isLoadingMoreCandidates = false }
                        do { try await store.loadMoreNotSureCandidates(item.id) }
                        catch is CancellationError { }
                        catch { inlineError = error.localizedDescription }
                    }
                } label: {
                    HStack {
                        if isLoadingMoreCandidates { ProgressView().controlSize(.mini) }
                        Text("Load more candidates")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isLoadingMoreCandidates || isSearching || isSavingCandidateReview)
            }

            if !isPending && !item.note.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Decision note")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(AdaColors.secondaryInk)
                    Text(item.note)
                        .font(.system(size: 12))
                        .foregroundStyle(AdaColors.ink)
                        .lineLimit(3)
                }
            }
        }
        .adaCard(padding: 14, radius: 22)
    }

    private func candidateCard(_ candidate: EscalatedNotSureCandidate) -> some View {
        let selected = selectedCandidate?.id == candidate.id
        let rejected = item.rejectedCandidateIDs.contains(candidate.id)
        let pinCount = anchorsByCandidateID[candidate.id]?.count ?? 0
        let delta = item.reMatchDeltasByCandidateID?[candidate.id]

        return HStack(spacing: 10) {
            Button {
                selectedCandidateID = candidate.id
            } label: {
                HStack(spacing: 10) {
                    NotSureThumbnail(image: candidate.photoRevision == nil ? candidate.image : store.reviewThumbnails[item.id.uuidString + ":" + candidate.id], size: 46, radius: 10)
                        .task(id: "\(item.matchAttemptID?.uuidString ?? "")-\(candidate.id)") {
                            await store.loadNotSureThumbnail(caseID: item.id, candidateID: candidate.id)
                        }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(candidate.name)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(AdaColors.ink)
                            .lineLimit(1)
                        if candidate.photoAvailability == "unknown_legacy" || candidate.photoAvailability == "unavailable" {
                            Text("Historical photo unavailable").font(.caption2).foregroundStyle(AdaColors.secondaryInk)
                        }
                        HStack(spacing: 4) {
                            NotSureMetaTag(
                                title: item.desktopReview != nil && !candidate.isBundledExample ? "Score \(candidate.confidencePercent)%" : candidate.evidenceLabel,
                                tint: selected ? AdaColors.navy : AdaColors.secondaryInk,
                                background: selected ? AdaColors.navy.opacity(0.10) : AdaColors.surfaceMuted
                            )
                            if let deltaText = delta?.badgeText {
                                NotSureMetaTag(
                                    title: deltaText,
                                    tint: delta?.isPositive == true ? AdaColors.green : AdaColors.orange,
                                    background: (delta?.isPositive == true ? AdaColors.green : AdaColors.orange).opacity(0.12)
                                )
                            } else if !candidate.sideMatches {
                                NotSureMetaTag(
                                    title: "Wrong side",
                                    tint: AdaColors.red,
                                    background: AdaColors.red.opacity(0.11)
                                )
                            } else if pinCount >= 3 {
                                NotSureMetaTag(
                                    title: "\(pinCount) pins",
                                    tint: AdaColors.green,
                                    background: AdaColors.green.opacity(0.11)
                                )
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isPending && !isSearching {
                Button {
                    setCandidateRejected(candidate, rejected: !rejected)
                } label: {
                    Image(systemName: rejected ? "arrow.uturn.backward" : "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(rejected ? AdaColors.navy : AdaColors.secondaryInk)
                        .frame(width: 24, height: 24)
                        .background(AdaColors.surfaceMuted, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(isSavingCandidateReview || isLoadingMoreCandidates)
                .help(rejected ? "Restore candidate" : "Not this turtle")
                .accessibilityLabel("\(rejected ? "Restore" : "Reject") \(candidate.name)")
            }
        }
        .padding(9)
        .background(
            selected ? AdaColors.accentSoft : AdaColors.canvas,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(selected ? AdaColors.navy.opacity(0.45) : .clear, lineWidth: 1.5)
        )
    }

    // MARK: - 4. Open-Set Verdict Bar

    private var verdictBar: some View {
        HStack(spacing: 10) {
            if isPending {
                if let cand = selectedCandidate {
                    HStack(spacing: 8) {
                        Text(cand.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AdaColors.ink)
                        if !cand.sideMatches {
                            NotSureMetaTag(title: "Opposite side", tint: AdaColors.red, background: AdaColors.red.opacity(0.11))
                        } else if !cand.location.isEmpty {
                            Text(cand.location)
                                .font(.system(size: 12))
                                .foregroundStyle(AdaColors.secondaryInk)
                        }
                    }
                } else {
                    Text(isSearching ? "Searching the gallery" : "No matching candidate left")
                        .font(.system(size: 12.5))
                        .foregroundStyle(AdaColors.secondaryInk)
                }
            } else {
                Text("\(item.decisionSummaryTitle) · \(item.updatedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(AdaColors.secondaryInk)
            }

            Spacer(minLength: 8)

            if isPending {
                Button {
                    openConfirmation(.needsPhoto)
                } label: {
                    Label("Needs photo", systemImage: "camera")
                }
                .buttonStyle(NotSurePillButtonStyle(.subtle, height: 38))
                .disabled(isSearching || isCropResearching || isSavingVerdict)

                Button {
                    openConfirmation(.newTurtle)
                } label: {
                    Label("New turtle", systemImage: "plus")
                }
                .buttonStyle(NotSurePillButtonStyle(.secondary, height: 38))
                .disabled(isSearching || isCropResearching || isSavingVerdict || isSavingCandidateReview ||
                    (item.sourceLogID != nil && !store.isDemoBypassActive && item.desktopReview?.canCreateNew != true))
                .help(item.desktopReview?.canCreateNew == true ? "Create a turtle from the reviewed sighting" : "Search all and rule out every candidate; both photo sides must be available")

                Button {
                    if let cand = selectedCandidate {
                        openConfirmation(.sameTurtle(id: cand.id, name: cand.name, image: cand.image))
                    }
                } label: {
                    Label("Same turtle", systemImage: "checkmark")
                }
                .buttonStyle(NotSurePillButtonStyle(.primary, height: 38))
                .disabled(!canConfirmSameTurtle || isCropResearching || isSavingCandidateReview || isLoadingMoreCandidates)
            } else if !item.hasDurableIdentityDecision || store.isDemoBypassActive {
                Button("Reopen review") {
                    if perform(.reopen) {
                        patchSession = NotSurePatchSession()
                        updatePatchSources()
                        showsPatchTool = false
                    }
                }
                    .buttonStyle(NotSurePillButtonStyle(.secondary, height: 38))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(AdaColors.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AdaColors.line, lineWidth: 1))
    }

    // MARK: - Compact 1-Step Confirmation Sheet (+ Live Backend Sync for Mobile Logs)

    private func openConfirmation(_ outcome: DecisionOutcome) {
        inlineError = nil
        let defaultReason = outcome.reasonChips.first ?? ""
        selectedChip = defaultReason
        confirmationNote = defaultReason
        confirmation = outcome
    }

    private func verdictSheet(for outcome: DecisionOutcome) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                if case .sameTurtle(_, _, let image) = outcome {
                    NotSureThumbnail(image: image, size: 46, radius: 12)
                } else {
                    Image(systemName: outcome.symbolName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(outcome.accentColor)
                        .frame(width: 44, height: 44)
                        .background(outcome.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(outcome.title)
                        .font(.system(size: 17, weight: .semibold))
                    Text(item.isFromMobileQueue && outcome.id.hasPrefix("same-")
                         ? "Same turtle · Syncs to mobile sighting log"
                         : outcome.badgeTitle)
                        .font(.system(size: 12))
                        .foregroundStyle(AdaColors.secondaryInk)
                }
                Spacer()
            }

            HStack(spacing: 6) {
                ForEach(outcome.reasonChips, id: \.self) { chip in
                    let active = selectedChip == chip
                    Button {
                        selectedChip = chip
                        confirmationNote = chip
                    } label: {
                        Text(chip)
                            .font(.system(size: 11.5, weight: active ? .semibold : .medium))
                            .foregroundStyle(active ? .white : AdaColors.ink)
                            .padding(.horizontal, 11)
                            .frame(height: 28)
                            .background(active ? AdaColors.navy : AdaColors.surfaceMuted, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            if case .newTurtle = outcome, item.sourceLogID != nil, !store.isDemoBypassActive {
                ReviewNewTurtleFields(name: $newTurtleName, profileCode: $newTurtleCode,
                    species: $newTurtleSpecies, photosAdequate: $newTurtlePhotosAdequate)
            }

            if let inlineError {
                Text(inlineError).font(.caption).foregroundStyle(AdaColors.red)
            }
            TextField("Decision reason (required)", text: $confirmationNote)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(AdaColors.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AdaColors.line, lineWidth: 1))

            HStack(spacing: 10) {
                Spacer()
                Button("Cancel") { confirmation = nil }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(NotSurePillButtonStyle(.subtle, height: 34))
                    .disabled(isSavingVerdict)
                Button {
                    let finalNote = confirmationNote.trimmingCharacters(in: .whitespacesAndNewlines)
                    Task {
                        isSavingVerdict = true
                        defer { isSavingVerdict = false }
                        do {
                            if case .newTurtle = outcome, item.sourceLogID != nil, !store.isDemoBypassActive {
                                guard let species = newTurtleSpecies else { throw APIError.validation("Select the turtle species.") }
                                let draft = IndividualDraft(id: newTurtleID, profileCode: newTurtleCode,
                                    name: newTurtleName.trimmingCharacters(in: .whitespacesAndNewlines),
                                    species: species.apiValue, sex: "unknown", firstSeenAt: item.createdAt)
                                try await store.createNotSureTurtle(caseID: item.id, draft: draft,
                                    photosAdequate: newTurtlePhotosAdequate, note: finalNote)
                            } else {
                                try await store.resolveNotSureCaseAndSyncBackend(item.id, action: outcome.action(note: finalNote))
                            }
                            guard viewIsActive else { return }
                            inlineError = nil
                            confirmation = nil
                            if let onNext { onNext() }
                        } catch {
                            guard viewIsActive else { return }
                            inlineError = error.localizedDescription
                        }
                    }
                } label: {
                    if isSavingVerdict {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(outcome.confirmTitle)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(NotSurePillButtonStyle(.primary, height: 34))
                .disabled(confirmationNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSavingVerdict ||
                    (outcome.id == "new-turtle" && item.sourceLogID != nil && !store.isDemoBypassActive &&
                     (!newTurtlePhotosAdequate || newTurtleSpecies == nil || newTurtleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                      newTurtleCode.count != 6 || !newTurtleCode.utf8.allSatisfy { (48...57).contains($0) })))
            }
        }
        .padding(22)
        .frame(width: 430)
        .background(AdaColors.card)
        .foregroundStyle(AdaColors.ink)
    }

    // MARK: - Interactive Scale Editing, Precision Pinning & Draggable Registration

    private func handleQueryScaleTap(_ number: Int) {
        if stageMode == .contours {
            selectedQueryScale = (selectedQueryScale == number) ? nil : number
            return
        }
        guard stageMode == .align,
              let pat = visibleQueryPatterns.first(where: { $0.number == number }) else { return }
        pendingQueryPin = (pat.centroid, number)
    }

    private func handleCandidateScaleTap(_ number: Int) {
        if stageMode == .contours {
            selectedCandidateScale = (selectedCandidateScale == number) ? nil : number
            return
        }
        guard stageMode == .align,
              let pending = pendingQueryPin,
              let pat = visibleCandidatePatterns.first(where: { $0.number == number }) else { return }
        addAnchorPair(
            queryPoint: pending.point,
            candidatePoint: pat.centroid,
            queryScale: pending.scaleNumber,
            candidateScale: number,
            source: .manual
        )
    }

    private func handleQueryFreeTap(_ point: ScalePoint) {
        if stageMode == .contours && isAddingManualLandmark && isPending && !showingCompanionSide {
            let nextIndex = customQueryLandmarks.count + 1
            let landmark = ManualScaleLandmark(label: "M\(nextIndex)", point: point)
            _ = perform(.addCustomQueryLandmark(landmark))
            isAddingManualLandmark = false
            return
        }
        guard stageMode == .align else { return }
        // Gently snap to a detected scale or manual landmark if tapped right on its center;
        // otherwise place an exact raw-pixel pin on any keratin junction, eye corner, or notch.
        if let snapped = nearestScale(to: point, in: visibleQueryPatterns, maxDist: 0.022) {
            pendingQueryPin = (snapped.centroid, snapped.number)
        } else if let lm = customQueryLandmarks.min(by: {
            hypot($0.point.x - point.x, $0.point.y - point.y) < hypot($1.point.x - point.x, $1.point.y - point.y)
        }), hypot(lm.point.x - point.x, lm.point.y - point.y) <= 0.024 {
            pendingQueryPin = (lm.point, nil)
        } else {
            pendingQueryPin = (point, nil)
        }
    }

    private func handleCandidateFreeTap(_ point: ScalePoint) {
        guard stageMode == .align, let pending = pendingQueryPin else { return }
        if let snapped = nearestScale(to: point, in: visibleCandidatePatterns, maxDist: 0.022) {
            addAnchorPair(
                queryPoint: pending.point,
                candidatePoint: snapped.centroid,
                queryScale: pending.scaleNumber,
                candidateScale: snapped.number,
                source: .manual
            )
        } else {
            addAnchorPair(
                queryPoint: pending.point,
                candidatePoint: point,
                queryScale: pending.scaleNumber,
                candidateScale: nil,
                source: .manual
            )
        }
    }

    private func nearestScale(to pt: ScalePoint, in patterns: [DetectedScalePattern], maxDist: Double) -> DetectedScalePattern? {
        guard let nearest = patterns.min(by: {
            hypot($0.centroid.x - pt.x, $0.centroid.y - pt.y) < hypot($1.centroid.x - pt.x, $1.centroid.y - pt.y)
        }) else { return nil }
        return hypot(nearest.centroid.x - pt.x, nearest.centroid.y - pt.y) <= maxDist ? nearest : nil
    }

    private func excludeQueryScale(_ scaleNumber: Int) {
        if selectedQueryScale == scaleNumber { selectedQueryScale = nil }
        _ = perform(.toggleExcludedQueryScale(scaleNumber))
    }

    private func addAnchorPair(
        queryPoint: ScalePoint,
        candidatePoint: ScalePoint,
        queryScale: Int?,
        candidateScale: Int?,
        source: ManualAnchorPair.Source
    ) {
        guard let cand = selectedCandidate else { return }
        var anchors = anchorsByCandidateID[cand.id] ?? []
        let label = nextPinLabel(existing: anchors)
        anchors.append(ManualAnchorPair(
            label: label,
            queryPoint: queryPoint,
            candidatePoint: candidatePoint,
            queryScaleNumber: queryScale,
            candidateScaleNumber: candidateScale,
            source: source
        ))
        anchorsByCandidateID[cand.id] = anchors
        pendingQueryPin = nil
        persistAnchorsIfPending(candidateID: cand.id, anchors: anchors)
        if anchors.count == 3 || anchors.count == 4 {
            withAnimation(.easeOut(duration: 0.16)) { alignPresentation = .curtain }
        }
    }

    private func moveAnchor(id: UUID, isQuery: Bool, to point: ScalePoint) {
        guard let cand = selectedCandidate,
              var anchors = anchorsByCandidateID[cand.id],
              let idx = anchors.firstIndex(where: { $0.id == id }) else { return }
        let clamped = ScalePoint(x: min(0.99, max(0.01, point.x)), y: min(0.99, max(0.01, point.y)))
        if isQuery {
            anchors[idx].queryPoint = clamped
            anchors[idx].queryScaleNumber = nil
        } else {
            anchors[idx].candidatePoint = clamped
            anchors[idx].candidateScaleNumber = nil
        }
        anchors[idx].source = .manual
        anchorsByCandidateID[cand.id] = anchors
        persistAnchorsIfPending(candidateID: cand.id, anchors: anchors)
    }

    private func deleteAnchor(id: UUID) {
        guard let cand = selectedCandidate else { return }
        var anchors = anchorsByCandidateID[cand.id] ?? []
        anchors.removeAll { $0.id == id }
        anchorsByCandidateID[cand.id] = anchors
        if anchors.count < 3 { alignPresentation = .pins; isBlinking = false }
        persistAnchorsIfPending(candidateID: cand.id, anchors: anchors)
    }

    private func undoLastAnchor() {
        guard let cand = selectedCandidate else { return }
        var anchors = anchorsByCandidateID[cand.id] ?? []
        guard !anchors.isEmpty else { return }
        anchors.removeLast()
        anchorsByCandidateID[cand.id] = anchors
        if anchors.count < 3 { alignPresentation = .pins; isBlinking = false }
        persistAnchorsIfPending(candidateID: cand.id, anchors: anchors)
    }

    private func clearAnchors() {
        guard let cand = selectedCandidate else { return }
        anchorsByCandidateID[cand.id] = []
        pendingQueryPin = nil
        alignPresentation = .pins
        isBlinking = false
        persistAnchorsIfPending(candidateID: cand.id, anchors: [])
    }

    private func nextPinLabel(existing: [ManualAnchorPair]) -> String {
        let alphabet = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L"]
        let used = Set(existing.map(\.label))
        if let letter = alphabet.first(where: { !used.contains($0) }) { return letter }
        return "P\(existing.count + 1)"
    }

    private func persistAnchorsIfPending(candidateID: String, anchors: [ManualAnchorPair]) {
        guard isPending else { return }
        _ = perform(.saveManualAnchors(candidateID: candidateID, anchors: anchors))
    }

    /// Seamlessly promotes any legacy `verifiedPairsByCandidateID` saved before manual pins existed.
    private func migrateLegacyPairsIntoAnchorsIfNeeded() {
        guard let cand = selectedCandidate else { return }
        guard (anchorsByCandidateID[cand.id] ?? []).isEmpty else { return }
        let legacyPairs = item.verifiedPairs(for: cand.id)
        guard !legacyPairs.isEmpty,
              let qPats = queryAnalysis?.patterns,
              let cPats = candidateAnalysis?.patterns else { return }
        let qByNum = Dictionary(uniqueKeysWithValues: qPats.map { ($0.number, $0) })
        let cByNum = Dictionary(uniqueKeysWithValues: cPats.map { ($0.number, $0) })
        let alphabet = ["A", "B", "C", "D", "E", "F", "G", "H"]
        let converted: [ManualAnchorPair] = legacyPairs.enumerated().compactMap { idx, link in
            guard let q = qByNum[link.queryNumber], let c = cByNum[link.candidateNumber] else { return nil }
            return ManualAnchorPair(
                label: idx < alphabet.count ? alphabet[idx] : "P\(idx + 1)",
                queryPoint: q.centroid,
                candidatePoint: c.centroid,
                queryScaleNumber: q.number,
                candidateScaleNumber: c.number,
                source: .manual
            )
        }
        if !converted.isEmpty {
            anchorsByCandidateID[cand.id] = converted
        }
    }

    private func seedAlignmentFromConsensus(_ consensus: GeometricConsensusReport, switchToCurtain: Bool) {
        guard let cand = selectedCandidate, consensus.canAutoSeedWarp else { return }
        anchorsByCandidateID[cand.id] = consensus.suggestedAnchors
        pendingQueryPin = nil
        persistAnchorsIfPending(candidateID: cand.id, anchors: consensus.suggestedAnchors)
        withAnimation(.easeOut(duration: 0.16)) {
            stageMode = .align
            alignPresentation = switchToCurtain ? .curtain : .pins
        }
    }

    private func autoAlignCurrentCandidate() async {
        guard let cand = selectedCandidate else { return }
        if aiAnnotationsAvailable {
            await loadAIAnnotationsForActiveCandidate()
            if let consensus = activeConsensus, consensus.canAutoSeedWarp {
                seedAlignmentFromConsensus(consensus, switchToCurtain: true)
                return
            }
        }
        // Fallback: upgraded 2-point similarity RANSAC over ocean-masked scale constellations.
        await extractVisibleContours()
        guard let q = queryAnalysis, let c = candidateAnalysis else { return }
        let pairs = PatternMatchCalculator.autoSuggestPairs(
            query: visibleQueryPatterns,
            candidate: visibleCandidatePatterns,
            queryROI: q.roi,
            candidateROI: c.roi,
            annotations: activeAIAnnotations
        )
        let qByNum = Dictionary(uniqueKeysWithValues: visibleQueryPatterns.map { ($0.number, $0) })
        let cByNum = Dictionary(uniqueKeysWithValues: visibleCandidatePatterns.map { ($0.number, $0) })
        let labels = ["A", "B", "C", "D", "E", "F"]
        let seeded: [ManualAnchorPair] = pairs.prefix(4).enumerated().compactMap { idx, link in
            guard let qPat = qByNum[link.queryNumber], let cPat = cByNum[link.candidateNumber] else { return nil }
            return ManualAnchorPair(
                label: idx < labels.count ? labels[idx] : "P\(idx + 1)",
                queryPoint: qPat.centroid,
                candidatePoint: cPat.centroid,
                queryScaleNumber: qPat.number,
                candidateScaleNumber: cPat.number,
                source: .aiInlier
            )
        }
        guard seeded.count >= 3 else {
            inlineError = "Not enough automatic consensus — click 3+ matching scale corners directly to warp."
            return
        }
        anchorsByCandidateID[cand.id] = seeded
        persistAnchorsIfPending(candidateID: cand.id, anchors: seeded)
        withAnimation(.easeOut(duration: 0.16)) { alignPresentation = .curtain }
    }

    private func setCandidateRejected(_ candidate: EscalatedNotSureCandidate, rejected: Bool) {
        isSavingCandidateReview = true
        Task {
            defer { isSavingCandidateReview = false }
            do {
                try await store.setNotSureCandidateRejected(caseID: item.id, candidateID: candidate.id, rejected: rejected)
                guard viewIsActive else { return }
                inlineError = nil
                if rejected {
                    selectedCandidateID = availableCandidates.first(where: { $0.id != candidate.id })?.id ?? ""
                } else if rejectedCandidates.count <= 1 { showsRejected = false }
            } catch is CancellationError { }
            catch { inlineError = error.localizedDescription }
        }
    }

    // MARK: - Live Backend XFeat/LighterGlue + RANSAC Geometric Consensus

    private func loadAIAnnotationsForActiveCandidate() async {
        guard let key = activeAIKey,
              let cand = selectedCandidate,
              let candUUID = UUID(uuidString: cand.id),
              store.canLoadRecords else { return }
        if aiAnnotationsCache[key] != nil { return }

        isLoadingAIAnnotations = true
        defer { isLoadingAIAnnotations = false }

        do {
            let annotations = try await store.fetchOverlayAnnotations(
                imageData: displayedQueryPhotoData,
                side: activeSightingSide,
                candidateID: candUUID,
                candidateSide: cand.side,
                maxThreads: 60
            )
            guard !Task.isCancelled else { return }
            let consensus = await Task.detached(priority: .userInitiated) {
                GeometricConsensusRANSAC.evaluate(annotations: annotations)
            }.value
            guard !Task.isCancelled else { return }
            aiAnnotationsCache[key] = annotations
            aiConsensusCache[key] = consensus
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            inlineError = "AI matches unavailable: \(error.localizedDescription)"
            showsAIMatches = false
        }
    }

    // MARK: - CoreImage Pixel-Registered Photographic Warp Renderer

    private func renderWarpedPhotoIfNeeded() async {
        guard let key = activeWarpKey,
              warpedPhotoCache[key] == nil,
              let transform = alignmentResult.transform,
              let qCG = displayedQueryImage?.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let cImg = selectedCandidate?.image else { return }

        let candSize: CGSize
        if let cCG = cImg.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            candSize = CGSize(width: cCG.width, height: cCG.height)
        } else {
            candSize = cImg.size
        }

        isRenderingWarp = true
        defer { isRenderingWarp = false }

        let warpedCG: CGImage? = await Task.detached(priority: .userInitiated) {
            PhotoWarpRenderer.renderWarpedQueryImage(
                queryCGImage: qCG,
                candidatePixelSize: candSize,
                transform: transform,
                maxDimension: 1100
            )
        }.value

        guard !Task.isCancelled, let warpedCG else { return }
        warpedPhotoCache[key] = NSImage(cgImage: warpedCG, size: NSSize(width: warpedCG.width, height: warpedCG.height))
    }

    // MARK: - Upgraded Ocean-Masked + Eyeball-Free Off-Main-Thread Contour Extraction

    private func extractVisibleContours() async {
        let qKey = queryCacheKey
        let cKey = candidateCacheKey
        let needsQuery = qKey.map { contourCache[$0] == nil } ?? false
        let needsCand = cKey.map { contourCache[$0] == nil } ?? false
        guard needsQuery || needsCand else { return }

        isExtractingContours = true
        defer { isExtractingContours = false }

        let config = PatternExtractionConfig(sensitivity: detailSensitivity)
        let qOverrideROI = showingCompanionSide ? nil : customQueryROI

        let qCG = needsQuery ? displayedQueryImage?.cgImage(forProposedRect: nil, context: nil, hints: nil) : nil
        let cCG = needsCand ? selectedCandidate?.image?.cgImage(forProposedRect: nil, context: nil, hints: nil) : nil
        let qSide = activeSightingSide
        let cSide = selectedCandidate?.side ?? item.side

        async let qDone: (ContourCacheKey, ExtractedScaleAnalysis)? = {
            guard let key = qKey, let cg = qCG else { return nil }
            let result = await Task.detached(priority: .userInitiated) {
                guard let raster = PatternContourEngine.underwaterLuminanceRaster(from: cg, maxDimension: 420) else {
                    return ExtractedScaleAnalysis.empty
                }
                return PatternContourEngine.extractAnalysis(from: raster, side: qSide, config: config, explicitROI: qOverrideROI)
            }.value
            return (key, result)
        }()

        async let cDone: (ContourCacheKey, ExtractedScaleAnalysis)? = {
            guard let key = cKey, let cg = cCG else { return nil }
            let result = await Task.detached(priority: .userInitiated) {
                guard let raster = PatternContourEngine.underwaterLuminanceRaster(from: cg, maxDimension: 420) else {
                    return ExtractedScaleAnalysis.empty
                }
                return PatternContourEngine.extractAnalysis(from: raster, side: cSide, config: config, explicitROI: nil)
            }.value
            return (key, result)
        }()

        let (qr, cr) = await (qDone, cDone)
        guard !Task.isCancelled else { return }
        if let (k, v) = qr { contourCache[k] = v }
        if let (k, v) = cr { contourCache[k] = v }
        migrateLegacyPairsIntoAnchorsIfNeeded()
    }

    // MARK: - Head Crop, Tilt-Level & Live Open-Set Re-Match

    private func initialCropRect() -> CGRect {
        if let roi = customQueryROI ?? queryAnalysis?.roi, roi.count >= 3 {
            let minX = max(0.02, roi.map(\.x).min() ?? 0.2)
            let minY = max(0.02, roi.map(\.y).min() ?? 0.2)
            let maxX = min(0.98, roi.map(\.x).max() ?? 0.8)
            let maxY = min(0.98, roi.map(\.y).max() ?? 0.8)
            return CGRect(x: minX, y: minY, width: max(0.15, maxX - minX), height: max(0.15, maxY - minY))
        }
        return CGRect(x: 0.20, y: 0.18, width: 0.60, height: 0.62)
    }

    private func applyLocalCropROI(_ rect: CGRect) {
        customQueryROI = [
            ScalePoint(x: rect.minX, y: rect.minY),
            ScalePoint(x: rect.maxX, y: rect.minY),
            ScalePoint(x: rect.maxX, y: rect.maxY),
            ScalePoint(x: rect.minX, y: rect.maxY),
        ]
        if stageMode == .compare { stageMode = .contours }
    }

    private func runCroppedLiveSearch(rect: CGRect, rotationDegrees: Double, usePairedSide: Bool) async {
        applyLocalCropROI(rect)
        guard liveSearchAvailable, let image = item.queryImage,
              let preparedJPEG = SquareOverlayMapper.prepareReMatchJPEG(
                  from: image,
                  normalizedRect: rect,
                  rotationDegrees: rotationDegrees
              ) else {
            showsCropSheet = false
            return
        }
        isCropResearching = true
        defer { isCropResearching = false; showsCropSheet = false }
        await runLiveSearch(overridePhotoData: preparedJPEG, usePairedSide: usePairedSide)
    }

    private func runLiveSearch(overridePhotoData: Data?, usePairedSide: Bool, retryPreviousAttempt: Bool = false, coverage: Int = 70) async {
        guard liveSearchAvailable, !isSearching else { return }
        isSearching = true
        inlineError = nil
        defer { isSearching = false }
        do {
            try await store.findNotSureCandidates(
                for: item.id,
                overridePhotoData: overridePhotoData,
                usePairedSide: usePairedSide,
                retryPreviousAttempt: retryPreviousAttempt,
                reviewCoverage: coverage
            )
            guard !Task.isCancelled else { return }
            showsRejected = false
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            inlineError = error.localizedDescription
        }
    }

    @discardableResult
    private func perform(_ action: NotSureReviewAction) -> Bool {
        do {
            try store.updateNotSureCase(item.id, action: action)
            inlineError = nil
            return true
        } catch {
            inlineError = error.localizedDescription
            return false
        }
    }

    // MARK: Geometry Helpers

    fileprivate static func screenPoint(
        from normalized: ScalePoint,
        fitted: CGRect,
        container: CGSize,
        zoom: CGFloat,
        pan: CGSize
    ) -> CGPoint {
        let ux = fitted.minX + CGFloat(normalized.x) * fitted.width
        let uy = fitted.minY + CGFloat(normalized.y) * fitted.height
        let cx = container.width * 0.5
        let cy = container.height * 0.5
        return CGPoint(
            x: cx + (ux - cx) * zoom + pan.width,
            y: cy + (uy - cy) * zoom + pan.height
        )
    }
}

// MARK: - Interactive Synced Photo + Numbered Contours + Suture Mesh + Draggable Precision Pins

private struct NotSurePanePin: Identifiable {
    let id: UUID
    let label: String
    let point: ScalePoint
    let source: ManualAnchorPair.Source
}

private struct NotSurePhotoPane: View {
    let image: NSImage?
    let badge: String
    var warningBadge: String? = nil
    let emptyLabel: String
    let accent: Color
    let showContours: Bool
    let showScaleBadges: Bool
    let showsSutureMesh: Bool
    let linesOnly: Bool
    let patterns: [DetectedScalePattern]
    let mesh: ScaleSutureMesh
    let customLandmarks: [ManualScaleLandmark]
    let highlightedScale: Int?
    let pairedNumbers: Set<Int>
    let anchors: [NotSurePanePin]
    let pendingPoint: ScalePoint?
    let allowsFreeTap: Bool
    let zoomScale: CGFloat
    let panOffset: CGSize
    let onPanChanged: (CGSize) -> Void
    let onPanEnded: (CGSize) -> Void
    let onTapScale: (Int) -> Void
    let onExcludeScale: ((Int) -> Void)?
    let onTapNormalizedPoint: (ScalePoint) -> Void
    let onDragAnchor: (UUID, ScalePoint) -> Void
    let onDeleteAnchor: (UUID) -> Void
    let onDeleteLandmark: ((UUID) -> Void)?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let image {
                    let fitted = NotSurePhotoGeometry.aspectFitRect(imageSize: image.size, in: geo.size)
                    ZStack {
                        if !linesOnly {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(width: geo.size.width, height: geo.size.height)
                        }

                        // Keratin suture mesh layer (optional progressive disclosure)
                        if showsSutureMesh && !mesh.edges.isEmpty {
                            let lookup = Dictionary(uniqueKeysWithValues: mesh.vertices.map { ($0.id, $0.point) })
                            Canvas { ctx, _ in
                                for edge in mesh.edges {
                                    let pts = edge.vertexIDs.compactMap { lookup[$0] }
                                    guard pts.count >= 2 else { continue }
                                    var path = Path()
                                    for (i, pt) in pts.enumerated() {
                                        let p = CGPoint(x: fitted.minX + pt.x * fitted.width, y: fitted.minY + pt.y * fitted.height)
                                        if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                                    }
                                    ctx.stroke(
                                        path,
                                        with: .color(Color.white.opacity(edge.isBoundary ? 0.55 : 0.85)),
                                        lineWidth: edge.isBoundary ? 1.1 : 1.5
                                    )
                                }
                            }
                            .allowsHitTesting(false)
                        }

                        // Numbered ocean-masked facial scale contours
                        if showContours && !patterns.isEmpty {
                            Canvas { ctx, _ in
                                for pat in patterns {
                                    let isSelected = highlightedScale == pat.number
                                    let isPaired = pairedNumbers.contains(pat.number)
                                    let path = NotSurePhotoGeometry.polygonPath(pat.polygon, in: fitted)
                                    if isSelected {
                                        ctx.fill(path, with: .color(accent.opacity(0.30)))
                                        ctx.stroke(path, with: .color(.white), lineWidth: 2.3)
                                    } else if isPaired {
                                        ctx.fill(path, with: .color(AdaColors.green.opacity(0.20)))
                                        ctx.stroke(path, with: .color(AdaColors.green), lineWidth: 1.8)
                                    } else {
                                        ctx.fill(path, with: .color(accent.opacity(showScaleBadges ? 0.10 : 0.04)))
                                        ctx.stroke(path, with: .color(accent.opacity(showScaleBadges ? 0.82 : 0.35)), lineWidth: showScaleBadges ? 1.4 : 1.0)
                                    }
                                }
                            }
                            .allowsHitTesting(false)

                            if showScaleBadges {
                                ForEach(patterns) { pat in
                                    let isSelected = highlightedScale == pat.number
                                    let isPaired = pairedNumbers.contains(pat.number)
                                    let pos = CGPoint(
                                        x: fitted.minX + pat.centroid.x * fitted.width,
                                        y: fitted.minY + pat.centroid.y * fitted.height
                                    )
                                    Button { onTapScale(pat.number) } label: {
                                        Text("\(pat.number)")
                                            .font(.system(size: isSelected ? 10 : 9, weight: .bold).monospacedDigit())
                                            .foregroundStyle(isSelected ? Color.black : .white)
                                            .frame(width: isSelected ? 21 : 18, height: isSelected ? 21 : 18)
                                            .background(
                                                isSelected ? Color.white : (isPaired ? AdaColors.green : Color.black.opacity(0.68)),
                                                in: Circle()
                                            )
                                            .overlay(
                                                Circle().stroke(isSelected ? accent : accent.opacity(0.8), lineWidth: 1.2)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                    .position(pos)
                                    .contextMenu {
                                        if let onExcludeScale {
                                            Button(role: .destructive) {
                                                onExcludeScale(pat.number)
                                            } label: {
                                                Label("Exclude false scale #\(pat.number)", systemImage: "eye.slash")
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Scientist-added manual scale landmarks (M1, M2...)
                        if showContours {
                            ForEach(customLandmarks) { lm in
                                let pos = CGPoint(
                                    x: fitted.minX + lm.point.x * fitted.width,
                                    y: fitted.minY + lm.point.y * fitted.height
                                )
                                Text(lm.label)
                                    .font(.system(size: 9, weight: .bold).monospacedDigit())
                                    .foregroundStyle(Color.black)
                                    .padding(.horizontal, 5)
                                    .frame(height: 18)
                                    .background(Color.yellow, in: Capsule())
                                    .overlay(Capsule().stroke(Color.black.opacity(0.55), lineWidth: 1))
                                    .position(pos)
                                    .contextMenu {
                                        if let onDeleteLandmark {
                                            Button(role: .destructive) {
                                                onDeleteLandmark(lm.id)
                                            } label: {
                                                Label("Delete \(lm.label)", systemImage: "trash")
                                            }
                                        }
                                    }
                            }
                        }

                        // Free-tap capture surface (placed BEFORE draggable pins so pins win hit-testing)
                        if allowsFreeTap {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture { location in
                                    guard fitted.width > 10, fitted.height > 10 else { return }
                                    let nx = (location.x - fitted.minX) / fitted.width
                                    let ny = (location.y - fitted.minY) / fitted.height
                                    guard nx >= 0, nx <= 1, ny >= 0, ny <= 1 else { return }
                                    onTapNormalizedPoint(ScalePoint(x: nx, y: ny))
                                }
                        }

                        // Pending first-click crosshair pin on Sighting
                        if let pendingPoint {
                            let pos = CGPoint(
                                x: fitted.minX + pendingPoint.x * fitted.width,
                                y: fitted.minY + pendingPoint.y * fitted.height
                            )
                            ZStack {
                                Circle()
                                    .stroke(Color.cyan, style: StrokeStyle(lineWidth: 2, dash: [3, 2]))
                                    .frame(width: 24, height: 24)
                                Circle()
                                    .fill(Color.cyan)
                                    .frame(width: 6, height: 6)
                            }
                            .position(pos)
                            .allowsHitTesting(false)
                        }

                        // Draggable precision registration pins (A, B, C, D...)
                        ForEach(anchors, id: \.id) { anchor in
                            let pos = CGPoint(
                                x: fitted.minX + anchor.point.x * fitted.width,
                                y: fitted.minY + anchor.point.y * fitted.height
                            )
                            let pinColor: Color = anchor.source == .aiInlier ? AdaColors.green : Color.cyan
                            ZStack {
                                Circle()
                                    .fill(pinColor)
                                    .frame(width: 22, height: 22)
                                    .overlay(Circle().stroke(Color.white, lineWidth: 1.8))
                                    .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                                Text(anchor.label)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color.black)
                            }
                            .frame(width: 32, height: 32)
                            .contentShape(Circle())
                            .position(pos)
                            .gesture(
                                DragGesture(minimumDistance: 1)
                                    .onChanged { value in
                                        guard fitted.width > 10, fitted.height > 10 else { return }
                                        let nx = (value.location.x - fitted.minX) / fitted.width
                                        let ny = (value.location.y - fitted.minY) / fitted.height
                                        onDragAnchor(anchor.id, ScalePoint(x: nx, y: ny))
                                    }
                            )
                            .contextMenu {
                                Button(role: .destructive) {
                                    onDeleteAnchor(anchor.id)
                                } label: {
                                    Label("Remove Pin \(anchor.label)", systemImage: "trash")
                                }
                            }
                            .help("Drag Pin \(anchor.label) to refine pixel warp · Right-click to remove")
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .scaleEffect(zoomScale)
                    .offset(panOffset)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "photo")
                            .font(.system(size: 24, weight: .light))
                            .foregroundStyle(Color.white.opacity(0.4))
                        Text(emptyLabel)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.white.opacity(0.5))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        guard image != nil, zoomScale > 1 else { return }
                        onPanChanged(value.translation)
                    }
                    .onEnded { value in
                        onPanEnded(value.translation)
                    }
            )
            .overlay(alignment: .topLeading) {
                HStack(spacing: 6) {
                    Text(badge)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.58), in: Capsule())

                    if let warningBadge {
                        Text(warningBadge)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(AdaColors.red.opacity(0.88), in: Capsule())
                    }
                }
                .padding(10)
            }
        }
    }
}

// MARK: - Human-Assisted Head Crop, Tilt-Level & Paired Re-Match Sheet

private struct NotSureHeadCropSheet: View {
    let image: NSImage?
    let hasCompanionSide: Bool
    let initialRect: CGRect
    let liveSearchAvailable: Bool
    let isSearching: Bool
    let onApplyLocal: (CGRect) -> Void
    let onCropAndResearch: (CGRect, Double, Bool) -> Void
    let onCancel: () -> Void

    @State private var cropRect: CGRect
    @State private var rotationDegrees: Double = 0
    @State private var usePairedSide: Bool

    init(
        image: NSImage?,
        hasCompanionSide: Bool,
        initialRect: CGRect,
        liveSearchAvailable: Bool,
        isSearching: Bool,
        onApplyLocal: @escaping (CGRect) -> Void,
        onCropAndResearch: @escaping (CGRect, Double, Bool) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.image = image
        self.hasCompanionSide = hasCompanionSide
        self.initialRect = initialRect
        self.liveSearchAvailable = liveSearchAvailable
        self.isSearching = isSearching
        self.onApplyLocal = onApplyLocal
        self.onCropAndResearch = onCropAndResearch
        self.onCancel = onCancel
        self._cropRect = State(initialValue: initialRect)
        self._usePairedSide = State(initialValue: hasCompanionSide)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Crop & level head")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button("Reset") {
                    cropRect = CGRect(x: 0.20, y: 0.18, width: 0.60, height: 0.62)
                    rotationDegrees = 0
                }
                .buttonStyle(NotSurePillButtonStyle(.subtle, height: 28))
            }

            GeometryReader { geo in
                ZStack {
                    Color(red: 10 / 255, green: 21 / 255, blue: 33 / 255)
                    if let image {
                        let fitted = NotSurePhotoGeometry.aspectFitRect(imageSize: image.size, in: geo.size)
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .rotationEffect(.degrees(rotationDegrees))

                        let box = CGRect(
                            x: fitted.minX + cropRect.minX * fitted.width,
                            y: fitted.minY + cropRect.minY * fitted.height,
                            width: cropRect.width * fitted.width,
                            height: cropRect.height * fitted.height
                        )
                        // Subtle horizon reference line inside crop box for head leveling
                        Path { path in
                            path.move(to: CGPoint(x: box.minX, y: box.midY))
                            path.addLine(to: CGPoint(x: box.maxX, y: box.midY))
                        }
                        .stroke(Color.cyan.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                        Rectangle()
                            .stroke(Color.cyan, lineWidth: 2)
                            .background(Color.cyan.opacity(0.08))
                            .frame(width: box.width, height: box.height)
                            .position(x: box.midX, y: box.midY)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { value in
                            guard let image else { return }
                            let fitted = NotSurePhotoGeometry.aspectFitRect(imageSize: image.size, in: geo.size)
                            guard fitted.width > 10, fitted.height > 10 else { return }
                            let x1 = min(max((value.startLocation.x - fitted.minX) / fitted.width, 0.02), 0.96)
                            let y1 = min(max((value.startLocation.y - fitted.minY) / fitted.height, 0.02), 0.96)
                            let x2 = min(max((value.location.x - fitted.minX) / fitted.width, 0.02), 0.98)
                            let y2 = min(max((value.location.y - fitted.minY) / fitted.height, 0.02), 0.98)
                            let minX = min(x1, x2), maxX = max(x1, x2)
                            let minY = min(y1, y2), maxY = max(y1, y2)
                            if maxX - minX >= 0.12 && maxY - minY >= 0.12 {
                                cropRect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
                            }
                        }
                )
            }
            .frame(height: 300)

            HStack(spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "rotate.right")
                        .font(.system(size: 12))
                        .foregroundStyle(AdaColors.secondaryInk)
                    Text("Level tilt")
                        .font(.system(size: 12, weight: .medium))
                    Slider(value: $rotationDegrees, in: -30...30, step: 1)
                        .tint(AdaColors.navy)
                        .frame(width: 150)
                    Text("\(Int(rotationDegrees.rounded()))°")
                        .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(AdaColors.secondaryInk)
                        .frame(width: 34, alignment: .trailing)
                }

                Spacer()

                if hasCompanionSide && liveSearchAvailable {
                    Toggle("Paired L+R", isOn: $usePairedSide)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12, weight: .medium))
                }
            }

            HStack(spacing: 10) {
                Text("Drag to exclude water or glare")
                    .font(.system(size: 11.5))
                    .foregroundStyle(AdaColors.secondaryInk)
                Spacer()
                Button(isSearching ? "Stop waiting" : "Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(NotSurePillButtonStyle(.subtle, height: 34))
                Button("Apply contours") { onApplyLocal(cropRect) }
                    .buttonStyle(NotSurePillButtonStyle(.secondary, height: 34))
                    .disabled(isSearching)
                if liveSearchAvailable {
                    Button {
                        onCropAndResearch(cropRect, rotationDegrees, usePairedSide)
                    } label: {
                        if isSearching {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Re-match")
                        }
                    }
                    .buttonStyle(NotSurePillButtonStyle(.primary, height: 34))
                    .disabled(isSearching)
                }
            }
        }
        .padding(20)
        .frame(width: 560)
        .background(AdaColors.card)
        .foregroundStyle(AdaColors.ink)
    }
}

// MARK: - Shared FigCraft Primitives

private struct NotSureThumbnail: View {
    let image: NSImage?
    let size: CGFloat
    var radius: CGFloat = 10

    var body: some View {
        ZStack {
            AdaColors.surfaceMuted
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "photo").foregroundStyle(AdaColors.secondaryInk)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .accessibilityHidden(true)
    }
}

private struct NotSureMetaTag: View {
    let title: String
    let tint: Color
    var background: Color = AdaColors.surfaceMuted

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(background, in: Capsule())
            .lineLimit(1)
            .fixedSize()
    }
}

private struct NotSureStatusPill: View {
    let item: EscalatedNotSureCase

    private var tint: Color {
        switch item.decision {
        case .pending: AdaColors.ink
        case .recommendedMatch: AdaColors.green
        case .reviewedUnknown:
            item.unknownOutcome == .needsBetterPhoto ? AdaColors.orange : AdaColors.accent
        }
    }

    private var background: Color {
        switch item.decision {
        case .pending: AdaColors.surfaceMuted
        case .recommendedMatch: AdaColors.green.opacity(0.12)
        case .reviewedUnknown:
            item.unknownOutcome == .needsBetterPhoto ? AdaColors.orange.opacity(0.16) : AdaColors.accentSoft
        }
    }

    var body: some View {
        Text(item.decisionSummaryTitle)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(background, in: Capsule())
            .fixedSize()
    }
}

private struct NotSurePillButtonStyle: ButtonStyle {
    enum Tone { case primary, secondary, subtle }
    let tone: Tone
    var height: CGFloat = 36
    var bold: Bool = false

    init(_ tone: Tone, height: CGFloat = 36, bold: Bool = false) {
        self.tone = tone
        self.height = height
        self.bold = bold
    }

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: (tone == .primary || bold) ? .semibold : .medium))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 15)
            .frame(height: height)
            .background(backgroundColor(pressed: configuration.isPressed), in: Capsule())
            .overlay(Capsule().stroke(borderColor, lineWidth: tone == .primary ? 0 : 1))
            .opacity(isEnabled ? 1 : 0.42)
            .contentShape(Capsule())
    }

    private var foregroundColor: Color {
        switch tone {
        case .primary: .white
        case .secondary: AdaColors.navy
        case .subtle: AdaColors.ink
        }
    }

    private func backgroundColor(pressed: Bool) -> Color {
        switch tone {
        case .primary: AdaColors.navy.opacity(pressed ? 0.85 : 1)
        case .secondary: AdaColors.accentSoft.opacity(pressed ? 1.0 : 0.72)
        case .subtle: pressed ? AdaColors.surfaceMuted : AdaColors.card
        }
    }

    private var borderColor: Color {
        switch tone {
        case .primary: .clear
        case .secondary: AdaColors.accent.opacity(0.28)
        case .subtle: AdaColors.line
        }
    }
}

private extension TurtlePhotoSide {
    var shortLabel: String {
        switch self {
        case .left: "Left"
        case .right: "Right"
        }
    }

    var opposite: TurtlePhotoSide {
        switch self {
        case .left: .right
        case .right: .left
        }
    }
}

#if DEBUG
#Preview("Not Sure · Inbox (+ Mobile Sync)") {
    NotSureWorkspaceView(
        store: PreviewFixtures.makeDemoStore(persona: .worldSuperNetwork, section: .scientistReview, withNotSureCases: true),
        onOpenPractice: {}
    )
    .frame(width: 1320, height: 840)
    .preferredColorScheme(.light)
}

#Preview("Not Sure · Compare + AI RANSAC") {
    NotSureWorkspaceView(
        store: PreviewFixtures.makeDemoStore(persona: .worldSuperNetwork, section: .scientistReview, withNotSureCases: true, openFirstNotSureCase: true),
        onOpenPractice: {},
        initialStageMode: .compare
    )
    .frame(width: 1320, height: 840)
    .preferredColorScheme(.light)
}

#Preview("Not Sure · Contours # (Ocean-Masked + Manual Mark)") {
    NotSureWorkspaceView(
        store: PreviewFixtures.makeDemoStore(persona: .worldSuperNetwork, section: .scientistReview, withNotSureCases: true, openFirstNotSureCase: true),
        onOpenPractice: {},
        initialStageMode: .contours
    )
    .frame(width: 1320, height: 840)
    .preferredColorScheme(.light)
}

#Preview("Not Sure · Align (Pixel-Warped Curtain + Pins)") {
    NotSureWorkspaceView(
        store: PreviewFixtures.makeDemoStore(persona: .worldSuperNetwork, section: .scientistReview, withNotSureCases: true, openFirstNotSureCase: true),
        onOpenPractice: {},
        initialStageMode: .align
    )
    .frame(width: 1320, height: 840)
    .preferredColorScheme(.light)
}
#endif


private struct ReviewQueueThumbnail: View {
    @ObservedObject var store: AppStore
    let sightingID: UUID
    let photo: MobileReviewPhoto?
    @State private var image: NSImage?
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFill() }
            else { Image(systemName: "photo").font(.system(size: 24)).frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .frame(width: 68, height: 68).clipped()
        .background(AdaColors.surfaceMuted, in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task(id: "\(photo?.id.uuidString ?? "")-\(photo?.revision ?? "legacy")") {
            image = nil
            if let photo { image = await store.loadQueueThumbnail(sightingID: sightingID, photo: photo) }
        }
    }
}
