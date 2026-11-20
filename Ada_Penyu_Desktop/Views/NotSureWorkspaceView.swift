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

    private var pendingCount: Int { store.pendingNotSureCases.count }
    private var reviewedCount: Int { store.escalatedNotSureCases.count - pendingCount }

    private var visibleCases: [EscalatedNotSureCase] {
        store.escalatedNotSureCases
            .filter { ($0.decision != .pending) == showsReviewed }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var activeQueueIDs: [UUID] {
        let existingIDs = Set(store.escalatedNotSureCases.map(\.id))
        let validSession = sessionCaseIDs.filter { existingIDs.contains($0) }
        if let selectedCaseID, validSession.contains(selectedCaseID) { return validSession }
        return visibleCases.map(\.id)
    }

    var body: some View {
        Group {
            if let item = store.escalatedNotSureCases.first(where: { $0.id == selectedCaseID }) {
                let queueIDs = activeQueueIDs
                let index = queueIDs.firstIndex(of: item.id) ?? 0
                NotSureCaseDetail(
                    store: store,
                    item: item,
                    initialStageMode: initialStageMode,
                    queueIndex: index,
                    queueCount: max(queueIDs.count, 1),
                    onPrevious: index > 0 ? { selectedCaseID = queueIDs[index - 1] } : nil,
                    onNext: index + 1 < queueIDs.count ? { selectedCaseID = queueIDs[index + 1] } : nil,
                    onBack: {
                        showsReviewed = item.decision != .pending
                        selectedCaseID = nil
                        sessionCaseIDs = []
                    }
                )
                .id(item.id)
            } else {
                inbox
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AdaColors.canvas)
        .foregroundStyle(AdaColors.ink)
        .onAppear(perform: openRequestedCase)
        .onChange(of: store.reviewNavigationTrigger) { _, _ in
            selectedCaseID = nil
            sessionCaseIDs = []
            openRequestedCase()
        }
    }

    // MARK: - Inbox (Direct, Minimal Text, FigCraft Cards)

    private var inbox: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                HStack(spacing: 3) {
                    queuePill("Pending", count: pendingCount, reviewed: false)
                    queuePill("Reviewed", count: reviewedCount, reviewed: true)
                }
                .padding(3)
                .background(AdaColors.card, in: Capsule())
                .overlay(Capsule().stroke(AdaColors.line, lineWidth: 1))

                Spacer(minLength: 0)

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
                    Button("Retry", action: store.reloadNotSureQueue)
                        .buttonStyle(AdaPillButtonStyle(secondary: true))
                }
                .adaCard(padding: 14, radius: 18)
            }

            if visibleCases.isEmpty {
                emptyQueue
            } else {
                ScrollView {
                    caseList
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
            Image(systemName: showsReviewed ? "checkmark.circle" : "tray")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(AdaColors.secondaryInk)
            Text(showsReviewed ? "No reviewed cases" : "No pending cases")
                .font(.system(size: 16, weight: .semibold))
            if !showsReviewed {
                Button("Open Photo ID") { store.activeSection = .identification }
                    .buttonStyle(AdaPillButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .adaCard(padding: 24, radius: AdaLayout.cardRadius)
    }

    private var caseList: some View {
        let cases = visibleCases
        return LazyVStack(spacing: 0) {
            ForEach(cases) { item in
                let savedAnchors = item.verifiedPairsByCandidateID?.values.map(\.count).max() ?? 0
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
                                        title: "\(savedAnchors) anchors",
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

// MARK: - Case Detail (Obvious · Easy · Possible | Zero Page Scroll)

private struct NotSureCaseDetail: View {
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
                ["Scales match", "Overlay aligned", "Both sides match"]
            case .newTurtle:
                ["Different pattern", "Contours diverge", "Not in gallery"]
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

    private struct ExtractedContours: Equatable {
        let roi: [ScalePoint]
        let patterns: [DetectedScalePattern]
        let mesh: ScaleSutureMesh
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
    @State private var showsRejected = false
    @State private var showingCompanionSide = false

    // Visual Compare / Overlay & Synced Zoom-Pan
    @State private var isOverlayActive = false
    @State private var overlayOpacity: Double = 0.55
    @State private var isBlinking = false
    @State private var blinkShowsCandidate = false
    @State private var zoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var dragDelta: CGSize = .zero

    // Zero-.fgp Numbered Contours & 3-Tap Human Alignment
    @State private var contourCache: [ContourCacheKey: ExtractedContours] = [:]
    @State private var isExtractingContours = false
    @State private var selectedQueryScale: Int?
    @State private var selectedCandidateScale: Int?
    @State private var pendingQueryAnchor: Int?
    @State private var pairsByCandidateID: [String: [PatternPairLink]]
    @State private var alignShowsOverlay = false

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
        self._pairsByCandidateID = State(initialValue: item.verifiedPairsByCandidateID ?? [:])
        self._customQueryROI = State(initialValue: item.queryROI.count >= 3 ? item.queryROI : nil)
    }

    // MARK: Derived Properties

    private var isPending: Bool { item.decision == .pending }
    private var liveSearchAvailable: Bool {
        isPending && store.isAuthenticated && !store.isDemoBypassActive && !item.isExample
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

    private var activeSightingSide: TurtlePhotoSide {
        showingCompanionSide && item.companionImage != nil ? item.side.opposite : item.side
    }

    private var displayedQueryImage: NSImage? {
        showingCompanionSide && item.companionImage != nil ? item.companionImage : item.queryImage
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

    private var queryContours: ExtractedContours? { queryCacheKey.flatMap { contourCache[$0] } }
    private var candidateContours: ExtractedContours? { candidateCacheKey.flatMap { contourCache[$0] } }

    private var activePairs: [PatternPairLink] {
        guard let cand = selectedCandidate else { return [] }
        return pairsByCandidateID[cand.id] ?? []
    }

    private var alignmentCheck: NotSureAlignmentCheck? {
        guard let q = queryContours, let c = candidateContours else { return nil }
        return NotSureAlignmentEvaluator.evaluate(
            query: q.patterns,
            candidate: c.patterns,
            pairs: activePairs,
            queryROI: q.roi,
            candidateROI: c.roi
        )
    }

    private var contourExtractionTrigger: String {
        guard stageMode != .compare else { return "compare" }
        return "\(stageMode.rawValue)|\(queryCacheKey?.hashValue ?? 0)|\(candidateCacheKey?.hashValue ?? 0)"
    }

    private var canConfirmSameTurtle: Bool {
        guard isPending, !isSearching, let selectedCandidate else { return false }
        return item.canRecommend(selectedCandidate)
    }

    private var hasAdvancedOverrides: Bool {
        linesOnly || detailBucket != 48 || customQueryROI != nil
    }

    private var effectiveOverlayAlpha: Double {
        isBlinking ? (blinkShowsCandidate ? 1.0 : 0.0) : overlayOpacity
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 12) {
            topBar
            HStack(spacing: 14) {
                stageContainer
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                candidateRail
                    .frame(width: 268)
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
                    Button("Dismiss") { self.inlineError = nil }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AdaColors.secondaryInk)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(AdaColors.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            verdictBar
        }
        .padding(.horizontal, AdaLayout.pagePadding)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: contourExtractionTrigger) {
            guard stageMode != .compare else { return }
            await extractVisibleContours()
        }
        .task(id: searchRequest) {
            guard searchRequest != nil else { return }
            await runLiveSearch(overridePhotoData: nil)
        }
        .task(id: isBlinking) {
            guard isBlinking else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(620))
                guard !Task.isCancelled else { break }
                withAnimation(.easeInOut(duration: 0.12)) { blinkShowsCandidate.toggle() }
            }
        }
        .onChange(of: selectedCandidate?.id) { _, _ in
            selectedCandidateScale = nil
            pendingQueryAnchor = nil
            if activePairs.count < 3 { alignShowsOverlay = false }
            if selectedCandidate?.image == nil { isBlinking = false }
        }
        .onChange(of: stageMode) { _, mode in
            isBlinking = false
            pendingQueryAnchor = nil
            if mode == .align, activePairs.count >= 3 {
                alignShowsOverlay = true
            } else if mode != .align {
                alignShowsOverlay = false
            }
        }
        .sheet(item: $confirmation) { verdictSheet(for: $0) }
        .sheet(isPresented: $showsCropSheet) {
            NotSureHeadCropSheet(
                image: item.queryImage,
                initialRect: initialCropRect(),
                liveSearchAvailable: liveSearchAvailable,
                isSearching: isCropResearching,
                onApplyLocal: { rect in
                    applyLocalCropROI(rect)
                    showsCropSheet = false
                },
                onCropAndResearch: { rect in
                    Task { await runCroppedLiveSearch(rect: rect) }
                },
                onCancel: { showsCropSheet = false }
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
                        pendingQueryAnchor = nil
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
        AdaPopupCardSurface(width: 248, padding: 10) {
            AdaPopupRow(
                title: "Lines only",
                icon: "scribble.variable",
                badge: linesOnly ? "On" : "Off",
                isSelected: linesOnly
            ) {
                linesOnly.toggle()
                if linesOnly && stageMode == .compare { stageMode = .contours }
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
                title: liveSearchAvailable ? "Crop head & Re-search" : "Crop head area",
                icon: "crop",
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
        HStack(spacing: 10) {
            switch stageMode {
            case .compare:
                compareControls
            case .contours:
                contourControls
            case .align:
                alignControls
            }

            Spacer(minLength: 6)

            if isExtractingContours {
                ProgressView()
                    .controlSize(.mini)
                    .tint(.white)
                    .accessibilityLabel("Extracting scale contours")
            }

            zoomControls
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
    }

    @ViewBuilder
    private var compareControls: some View {
        HStack(spacing: 2) {
            darkModeChip("Side by side", active: !isOverlayActive) {
                withAnimation(.easeOut(duration: 0.14)) {
                    isOverlayActive = false
                    isBlinking = false
                }
            }
            darkModeChip("Blink / Overlay", active: isOverlayActive) {
                withAnimation(.easeOut(duration: 0.14)) {
                    isOverlayActive = true
                }
            }
        }
        .padding(3)
        .background(Self.stageChipBg, in: Capsule())

        if isOverlayActive, selectedCandidate?.image != nil {
            blinkButton
            opacitySlider(leftLabel: "S", rightLabel: "C")
        }
    }

    @ViewBuilder
    private var contourControls: some View {
        if let qNum = selectedQueryScale,
           let qPat = queryContours?.patterns.first(where: { $0.number == qNum }) {
            darkInfoPill("S #\(qPat.number) · \(qPat.vertexCount)-sided", accent: .cyan)
        }
        if let cNum = selectedCandidateScale,
           let cPat = candidateContours?.patterns.first(where: { $0.number == cNum }) {
            darkInfoPill("C #\(cPat.number) · \(cPat.vertexCount)-sided", accent: AdaColors.orange)
        }
        if selectedQueryScale == nil && selectedCandidateScale == nil {
            Text("Tap any numbered scale to inspect shape")
                .font(.system(size: 11.5))
                .foregroundStyle(Color.white.opacity(0.64))
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var alignControls: some View {
        let count = activePairs.count
        let check = alignmentCheck

        // 3 progress dots + concise status (NEVER a fake centroid "Strong fit %" score!)
        HStack(spacing: 7) {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { idx in
                    Circle()
                        .fill(idx < count ? Color.cyan : Color.white.opacity(0.24))
                        .frame(width: 7, height: 7)
                }
            }
            Text(check?.pillText ?? "Tap 3 matching scales")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(check?.isWarning == true ? AdaColors.orange : .white)
        }
        .padding(.horizontal, 11)
        .frame(height: 28)
        .background(
            check?.isWarning == true ? AdaColors.orange.opacity(0.20) : Self.stageChipBg,
            in: Capsule()
        )

        if let qNum = pendingQueryAnchor {
            darkInfoPill("Pick match for #\(qNum)", accent: .cyan)
        }

        if check?.isReadyForOverlay == true {
            HStack(spacing: 2) {
                darkModeChip("Pairs", active: !alignShowsOverlay) {
                    withAnimation(.easeOut(duration: 0.14)) {
                        alignShowsOverlay = false
                        isBlinking = false
                    }
                }
                darkModeChip("Warped overlay", active: alignShowsOverlay) {
                    withAnimation(.easeOut(duration: 0.14)) {
                        alignShowsOverlay = true
                    }
                }
            }
            .padding(3)
            .background(Self.stageChipBg, in: Capsule())

            if alignShowsOverlay {
                blinkButton
            }
        }

        if !activePairs.isEmpty {
            Button { undoLastAnchor() } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.84))
                    .frame(width: 28, height: 28)
                    .background(Self.stageChipBg, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Undo last pair")

            Button { clearAnchors() } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.76))
                    .frame(width: 28, height: 28)
                    .background(Self.stageChipBg, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Clear pairs")
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
            .frame(minWidth: 72, maxWidth: 116)
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
                .padding(.horizontal, 11)
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
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(Self.stageChipBg, in: Capsule())
    }

    private var zoomControls: some View {
        HStack(spacing: 2) {
            zoomStepButton("minus", label: "Zoom out", disabled: zoomScale <= 1.01) { stepZoom(by: -0.5) }
            Button(action: resetZoom) {
                Text("\(Int((zoomScale * 100).rounded()))%")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(minWidth: 40, minHeight: 24)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Reset zoom")
            zoomStepButton("plus", label: "Zoom in", disabled: zoomScale >= 3.99) { stepZoom(by: 0.5) }
        }
        .padding(.horizontal, 5)
        .frame(height: 28)
        .background(Self.stageChipBg, in: Capsule())
        .fixedSize()
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

    // MARK: Stage Body

    @ViewBuilder
    private var stageBody: some View {
        if stageMode == .compare && isOverlayActive {
            rawBlinkOverlayCanvas
        } else if stageMode == .align && alignShowsOverlay, let check = alignmentCheck, check.isReadyForOverlay {
            warpedAlignmentOverlayCanvas(check: check)
        } else {
            sideBySideStage
        }
    }

    private var sideBySideStage: some View {
        let queryBadge = "SIGHTING · \(activeSightingSide.shortLabel.uppercased())"
        let candBadge: String = {
            guard let cand = selectedCandidate else { return "CANDIDATE" }
            let score = cand.isBundledExample ? "SAMPLE" : "\(cand.confidencePercent)%"
            return "#\(cand.rank) \(cand.name) · \(score)"
        }()

        return HStack(spacing: 0) {
            NotSurePhotoPane(
                image: displayedQueryImage,
                badge: queryBadge,
                emptyLabel: "No photo",
                accent: .cyan,
                showContours: stageMode != .compare,
                linesOnly: linesOnly && stageMode != .compare,
                patterns: queryContours?.patterns ?? [],
                highlightedScale: stageMode == .align ? pendingQueryAnchor : selectedQueryScale,
                pairedNumbers: Set(activePairs.map(\.queryNumber)),
                zoomScale: zoomScale,
                panOffset: currentPanOffset,
                onPanChanged: { dragDelta = $0 },
                onPanEnded: commitPan,
                onTapScale: handleQueryScaleTap
            )

            Rectangle().fill(Color.white.opacity(0.10)).frame(width: 1)

            NotSurePhotoPane(
                image: selectedCandidate?.image,
                badge: candBadge,
                warningBadge: selectedCandidate.flatMap { $0.sideMatches ? nil : "Opposite side" },
                emptyLabel: selectedCandidate == nil ? "No candidate" : "No photo",
                accent: AdaColors.orange,
                showContours: stageMode != .compare,
                linesOnly: linesOnly && stageMode != .compare,
                patterns: candidateContours?.patterns ?? [],
                highlightedScale: selectedCandidateScale,
                pairedNumbers: Set(activePairs.map(\.candidateNumber)),
                zoomScale: zoomScale,
                panOffset: currentPanOffset,
                onPanChanged: { dragDelta = $0 },
                onPanEnded: commitPan,
                onTapScale: handleCandidateScaleTap
            )
        }
    }

    private var rawBlinkOverlayCanvas: some View {
        GeometryReader { geo in
            ZStack {
                if let query = displayedQueryImage {
                    Image(nsImage: query)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .scaleEffect(zoomScale)
                        .offset(currentPanOffset)
                }
                if let candImg = selectedCandidate?.image {
                    Image(nsImage: candImg)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .scaleEffect(zoomScale)
                        .offset(currentPanOffset)
                        .opacity(effectiveOverlayAlpha)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .contentShape(Rectangle())
            .gesture(panGesture)
            .overlay(alignment: .topLeading) {
                stageCornerBadge(
                    isBlinking
                        ? (blinkShowsCandidate ? (selectedCandidate?.name ?? "Candidate") : "Sighting")
                        : "Overlay · \(Int((overlayOpacity * 100).rounded()))%"
                )
                .padding(12)
            }
        }
    }

    private func warpedAlignmentOverlayCanvas(check: NotSureAlignmentCheck) -> some View {
        GeometryReader { geo in
            ZStack {
                if let candImg = selectedCandidate?.image {
                    let fitted = Self.aspectFitRect(imageSize: candImg.size, in: geo.size)
                    ZStack {
                        if !linesOnly {
                            Image(nsImage: candImg)
                                .resizable()
                                .scaledToFit()
                                .frame(width: geo.size.width, height: geo.size.height)
                        }

                        // Candidate native contours (subtle orange)
                        if let cContours = candidateContours {
                            Canvas { ctx, _ in
                                for pat in cContours.patterns {
                                    let path = Self.polygonPath(pat.polygon, in: fitted)
                                    ctx.stroke(path, with: .color(AdaColors.orange.opacity(0.65)), lineWidth: 1.5)
                                }
                            }
                        }

                        // Warped Sighting contours projected onto Candidate frame (crisp cyan — blinks when Blink is active)
                        if !isBlinking || !blinkShowsCandidate {
                            Canvas { ctx, _ in
                                for warped in check.warpedContours {
                                    let path = Self.polygonPath(warped.polygon, in: fitted)
                                    ctx.fill(path, with: .color(Color.cyan.opacity(0.14)))
                                    ctx.stroke(path, with: .color(Color.cyan.opacity(0.95)), lineWidth: 2.0)
                                }
                            }
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .scaleEffect(zoomScale)
                    .offset(currentPanOffset)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .contentShape(Rectangle())
            .gesture(panGesture)
            .overlay(alignment: .topLeading) {
                HStack(spacing: 6) {
                    stageCornerBadge("Cyan = Sighting warped onto \(selectedCandidate?.name ?? "Candidate")")
                }
                .padding(12)
            }
        }
    }

    private func stageCornerBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.55), in: Capsule())
    }

    private var currentPanOffset: CGSize {
        CGSize(width: panOffset.width + dragDelta.width, height: panOffset.height + dragDelta.height)
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                guard zoomScale > 1.01 else { return }
                dragDelta = value.translation
            }
            .onEnded { value in
                guard zoomScale > 1.01 else { dragDelta = .zero; return }
                commitPan(value.translation)
            }
    }

    private func commitPan(_ translation: CGSize) {
        panOffset = CGSize(width: panOffset.width + translation.width, height: panOffset.height + translation.height)
        dragDelta = .zero
    }

    private func stepZoom(by delta: CGFloat) {
        withAnimation(.easeOut(duration: 0.14)) {
            zoomScale = min(4.0, max(1.0, zoomScale + delta))
            if zoomScale <= 1.01 { panOffset = .zero; dragDelta = .zero }
        }
    }

    private func resetZoom() {
        withAnimation(.easeOut(duration: 0.14)) {
            zoomScale = 1.0
            panOffset = .zero
            dragDelta = .zero
        }
    }

    // MARK: - 3. Slim Right Candidate Rail (Always Visible, 1-Click Reject & Advance)

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

                if liveSearchAvailable {
                    Button { searchRequest = UUID() } label: {
                        if isSearching {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AdaColors.secondaryInk)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isSearching)
                    .help("Search gallery again")
                }
            }

            if displayedCandidates.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: showsRejected ? "arrow.uturn.backward.circle" : "person.crop.circle.badge.questionmark")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(AdaColors.secondaryInk)
                    Text(showsRejected ? "No rejected candidates" : "All candidates ruled out")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AdaColors.secondaryInk)
                        .multilineTextAlignment(.center)
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
        let pairCount = pairsByCandidateID[candidate.id]?.count ?? 0

        return HStack(spacing: 10) {
            Button {
                selectedCandidateID = candidate.id
            } label: {
                HStack(spacing: 10) {
                    NotSureThumbnail(image: candidate.image, size: 46, radius: 10)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(candidate.name)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(AdaColors.ink)
                            .lineLimit(1)
                        HStack(spacing: 5) {
                            NotSureMetaTag(
                                title: candidate.evidenceLabel,
                                tint: selected ? AdaColors.navy : AdaColors.secondaryInk,
                                background: selected ? AdaColors.navy.opacity(0.10) : AdaColors.surfaceMuted
                            )
                            if !candidate.sideMatches {
                                NotSureMetaTag(
                                    title: "Wrong side",
                                    tint: AdaColors.red,
                                    background: AdaColors.red.opacity(0.11)
                                )
                            } else if pairCount >= 3 {
                                NotSureMetaTag(
                                    title: "\(pairCount) pts",
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
                    if rejected {
                        perform(.restoreCandidate(candidate.id))
                        if rejectedCandidates.isEmpty { showsRejected = false }
                    } else {
                        rejectAndAdvance(candidate)
                    }
                } label: {
                    Image(systemName: rejected ? "arrow.uturn.backward" : "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(rejected ? AdaColors.navy : AdaColors.secondaryInk)
                        .frame(width: 24, height: 24)
                        .background(AdaColors.surfaceMuted, in: Circle())
                }
                .buttonStyle(.plain)
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

    // MARK: - 4. Open-Set Verdict Bar (Mirrors Mobile: Match / New turtle / Needs photo)

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
                    Text("No matching candidate left")
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
                .disabled(isSearching || isCropResearching)

                Button {
                    openConfirmation(.newTurtle)
                } label: {
                    Label("New turtle", systemImage: "plus")
                }
                .buttonStyle(NotSurePillButtonStyle(.secondary, height: 38))
                .disabled(isSearching || isCropResearching)

                Button {
                    if let cand = selectedCandidate {
                        openConfirmation(.sameTurtle(id: cand.id, name: cand.name, image: cand.image))
                    }
                } label: {
                    Label("Same turtle", systemImage: "checkmark")
                }
                .buttonStyle(NotSurePillButtonStyle(.primary, height: 38))
                .disabled(!canConfirmSameTurtle || isCropResearching)
            } else {
                Button("Reopen review") { perform(.reopen) }
                    .buttonStyle(NotSurePillButtonStyle(.secondary, height: 38))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(AdaColors.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AdaColors.line, lineWidth: 1))
    }

    // MARK: - Compact 1-Step Confirmation Sheet (1-Tap Reason Chips)

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
                    Text(outcome.badgeTitle)
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

            TextField("Optional note", text: $confirmationNote)
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
                Button(outcome.confirmTitle) {
                    let finalNote = confirmationNote.trimmingCharacters(in: .whitespacesAndNewlines)
                    if perform(outcome.action(note: finalNote)) {
                        confirmation = nil
                        if let onNext { onNext() }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(NotSurePillButtonStyle(.primary, height: 34))
                .disabled(confirmationNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 420)
        .background(AdaColors.card)
        .foregroundStyle(AdaColors.ink)
    }

    // MARK: - Interactive Scale Tap & 3-Anchor Alignment

    private func handleQueryScaleTap(_ number: Int) {
        if stageMode == .contours {
            selectedQueryScale = (selectedQueryScale == number) ? nil : number
            return
        }
        guard stageMode == .align else { return }
        pendingQueryAnchor = (pendingQueryAnchor == number) ? nil : number
    }

    private func handleCandidateScaleTap(_ number: Int) {
        if stageMode == .contours {
            selectedCandidateScale = (selectedCandidateScale == number) ? nil : number
            return
        }
        guard stageMode == .align, let cand = selectedCandidate, let qNum = pendingQueryAnchor else { return }
        var pairs = pairsByCandidateID[cand.id] ?? []
        pairs.removeAll { $0.queryNumber == qNum || $0.candidateNumber == number }
        pairs.append(PatternPairLink(queryNumber: qNum, candidateNumber: number))
        pairs.sort { $0.queryNumber < $1.queryNumber }
        pairsByCandidateID[cand.id] = pairs
        pendingQueryAnchor = nil
        persistPairsIfPending(candidateID: cand.id, pairs: pairs)
        if pairs.count == 3 {
            withAnimation(.easeOut(duration: 0.16)) { alignShowsOverlay = true }
        }
    }

    private func undoLastAnchor() {
        guard let cand = selectedCandidate else { return }
        var pairs = pairsByCandidateID[cand.id] ?? []
        guard !pairs.isEmpty else { return }
        pairs.removeLast()
        pairsByCandidateID[cand.id] = pairs
        if pairs.count < 3 { alignShowsOverlay = false; isBlinking = false }
        persistPairsIfPending(candidateID: cand.id, pairs: pairs)
    }

    private func clearAnchors() {
        guard let cand = selectedCandidate else { return }
        pairsByCandidateID[cand.id] = []
        pendingQueryAnchor = nil
        alignShowsOverlay = false
        isBlinking = false
        persistPairsIfPending(candidateID: cand.id, pairs: [])
    }

    private func persistPairsIfPending(candidateID: String, pairs: [PatternPairLink]) {
        guard isPending else { return }
        _ = perform(.saveVerifiedPairs(candidateID: candidateID, pairs: pairs))
    }

    private func rejectAndAdvance(_ candidate: EscalatedNotSureCandidate) {
        let remainingAfter = availableCandidates.filter { $0.id != candidate.id }
        if perform(.rejectCandidate(candidate.id)) {
            if selectedCandidateID == candidate.id || selectedCandidate?.id == candidate.id {
                selectedCandidateID = remainingAfter.first?.id ?? ""
            }
        }
    }

    // MARK: - Zero-.fgp Off-Main-Thread Contour Extraction

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

        let qRasters: (key: ContourCacheKey, roiR: (pixels: [Float], width: Int, height: Int), patR: (pixels: [Float], width: Int, height: Int), side: TurtlePhotoSide, overrideROI: [ScalePoint]?)? = {
            guard needsQuery, let key = qKey, let img = displayedQueryImage,
                  let r360 = PatternContourEngine.underwaterLuminance(from: img, maxDimension: 360),
                  let r420 = PatternContourEngine.underwaterLuminance(from: img, maxDimension: 420) else { return nil }
            return (key, r360, r420, activeSightingSide, qOverrideROI)
        }()

        let cRasters: (key: ContourCacheKey, roiR: (pixels: [Float], width: Int, height: Int), patR: (pixels: [Float], width: Int, height: Int), side: TurtlePhotoSide)? = {
            guard needsCand, let key = cKey, let cand = selectedCandidate, let img = cand.image,
                  let r360 = PatternContourEngine.underwaterLuminance(from: img, maxDimension: 360),
                  let r420 = PatternContourEngine.underwaterLuminance(from: img, maxDimension: 420) else { return nil }
            return (key, r360, r420, cand.side)
        }()

        async let qDone: (ContourCacheKey, ExtractedContours)? = {
            guard let job = qRasters else { return nil }
            let result = await Task.detached(priority: .userInitiated) {
                let roi = job.overrideROI ?? PatternContourEngine.detectFacialPatternROI(from: job.roiR, side: job.side).roi
                let patterns = PatternContourEngine.extractPatterns(from: job.patR, roiPolygon: roi, config: config)
                let mesh = PatternContourEngine.extractScaleSutureMesh(from: job.patR, roiPolygon: roi, config: config)
                return ExtractedContours(roi: roi, patterns: patterns, mesh: mesh)
            }.value
            return (job.key, result)
        }()

        async let cDone: (ContourCacheKey, ExtractedContours)? = {
            guard let job = cRasters else { return nil }
            let result = await Task.detached(priority: .userInitiated) {
                let roi = PatternContourEngine.detectFacialPatternROI(from: job.roiR, side: job.side).roi
                let patterns = PatternContourEngine.extractPatterns(from: job.patR, roiPolygon: roi, config: config)
                let mesh = PatternContourEngine.extractScaleSutureMesh(from: job.patR, roiPolygon: roi, config: config)
                return ExtractedContours(roi: roi, patterns: patterns, mesh: mesh)
            }.value
            return (job.key, result)
        }()

        let (qr, cr) = await (qDone, cDone)
        guard !Task.isCancelled else { return }
        if let (k, v) = qr { contourCache[k] = v }
        if let (k, v) = cr { contourCache[k] = v }
    }

    // MARK: - Head Crop & Live Open-Set Re-Search

    private func initialCropRect() -> CGRect {
        if let roi = customQueryROI ?? queryContours?.roi, roi.count >= 3 {
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

    private func runCroppedLiveSearch(rect: CGRect) async {
        applyLocalCropROI(rect)
        guard liveSearchAvailable, let image = item.queryImage,
              let croppedJPEG = NotSureHeadCropper.croppedJPEGData(from: image, normalizedRect: rect) else {
            showsCropSheet = false
            return
        }
        isCropResearching = true
        defer { isCropResearching = false; showsCropSheet = false }
        await runLiveSearch(overridePhotoData: croppedJPEG)
    }

    private func runLiveSearch(overridePhotoData: Data?) async {
        guard liveSearchAvailable, !isSearching else { return }
        isSearching = true
        inlineError = nil
        defer { isSearching = false }
        do {
            try await store.findNotSureCandidates(for: item.id, overridePhotoData: overridePhotoData)
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

    fileprivate static func aspectFitRect(imageSize: NSSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, container.width > 0, container.height > 0 else {
            return CGRect(origin: .zero, size: container)
        }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let w = imageSize.width * scale
        let h = imageSize.height * scale
        return CGRect(x: (container.width - w) * 0.5, y: (container.height - h) * 0.5, width: w, height: h)
    }

    fileprivate static func polygonPath(_ polygon: [ScalePoint], in rect: CGRect) -> Path {
        var path = Path()
        for (idx, pt) in polygon.enumerated() {
            let p = CGPoint(x: rect.minX + pt.x * rect.width, y: rect.minY + pt.y * rect.height)
            if idx == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Interactive Synced Photo + Numbered Contour Pane

private struct NotSurePhotoPane: View {
    let image: NSImage?
    let badge: String
    var warningBadge: String? = nil
    let emptyLabel: String
    let accent: Color
    let showContours: Bool
    let linesOnly: Bool
    let patterns: [DetectedScalePattern]
    let highlightedScale: Int?
    let pairedNumbers: Set<Int>
    let zoomScale: CGFloat
    let panOffset: CGSize
    let onPanChanged: (CGSize) -> Void
    let onPanEnded: (CGSize) -> Void
    let onTapScale: (Int) -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let image {
                    let fitted = NotSureCaseDetail.aspectFitRect(imageSize: image.size, in: geo.size)
                    ZStack {
                        if !linesOnly {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(width: geo.size.width, height: geo.size.height)
                        }

                        if showContours && !patterns.isEmpty {
                            Canvas { ctx, _ in
                                for pat in patterns {
                                    let isSelected = highlightedScale == pat.number
                                    let isPaired = pairedNumbers.contains(pat.number)
                                    let path = NotSureCaseDetail.polygonPath(pat.polygon, in: fitted)
                                    if isSelected {
                                        ctx.fill(path, with: .color(accent.opacity(0.32)))
                                        ctx.stroke(path, with: .color(.white), lineWidth: 2.4)
                                    } else if isPaired {
                                        ctx.fill(path, with: .color(AdaColors.green.opacity(0.24)))
                                        ctx.stroke(path, with: .color(AdaColors.green), lineWidth: 2.0)
                                    } else {
                                        ctx.fill(path, with: .color(accent.opacity(0.10)))
                                        ctx.stroke(path, with: .color(accent.opacity(0.85)), lineWidth: 1.4)
                                    }
                                }
                            }
                            .allowsHitTesting(false)

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
                            }
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
                        guard zoomScale > 1.01 else { return }
                        onPanChanged(value.translation)
                    }
                    .onEnded { value in
                        guard zoomScale > 1.01 else { onPanChanged(.zero); return }
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

// MARK: - Head Crop & Open-Set Re-Search Sheet

private struct NotSureHeadCropSheet: View {
    let image: NSImage?
    let initialRect: CGRect
    let liveSearchAvailable: Bool
    let isSearching: Bool
    let onApplyLocal: (CGRect) -> Void
    let onCropAndResearch: (CGRect) -> Void
    let onCancel: () -> Void

    @State private var cropRect: CGRect

    init(
        image: NSImage?,
        initialRect: CGRect,
        liveSearchAvailable: Bool,
        isSearching: Bool,
        onApplyLocal: @escaping (CGRect) -> Void,
        onCropAndResearch: @escaping (CGRect) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.image = image
        self.initialRect = initialRect
        self.liveSearchAvailable = liveSearchAvailable
        self.isSearching = isSearching
        self.onApplyLocal = onApplyLocal
        self.onCropAndResearch = onCropAndResearch
        self.onCancel = onCancel
        self._cropRect = State(initialValue: initialRect)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Crop head region")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button("Reset") { cropRect = CGRect(x: 0.20, y: 0.18, width: 0.60, height: 0.62) }
                    .buttonStyle(NotSurePillButtonStyle(.subtle, height: 28))
            }

            GeometryReader { geo in
                ZStack {
                    Color(red: 10 / 255, green: 21 / 255, blue: 33 / 255)
                    if let image {
                        let fitted = NotSureCaseDetail.aspectFitRect(imageSize: image.size, in: geo.size)
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: geo.size.width, height: geo.size.height)

                        let box = CGRect(
                            x: fitted.minX + cropRect.minX * fitted.width,
                            y: fitted.minY + cropRect.minY * fitted.height,
                            width: cropRect.width * fitted.width,
                            height: cropRect.height * fitted.height
                        )
                        Rectangle()
                            .stroke(Color.cyan, lineWidth: 2)
                            .background(Color.cyan.opacity(0.10))
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
                            let fitted = NotSureCaseDetail.aspectFitRect(imageSize: image.size, in: geo.size)
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

            HStack(spacing: 10) {
                Text("Drag across the head scales")
                    .font(.system(size: 11.5))
                    .foregroundStyle(AdaColors.secondaryInk)
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(NotSurePillButtonStyle(.subtle, height: 34))
                Button("Apply contours") { onApplyLocal(cropRect) }
                    .buttonStyle(NotSurePillButtonStyle(.secondary, height: 34))
                if liveSearchAvailable {
                    Button {
                        onCropAndResearch(cropRect)
                    } label: {
                        if isSearching {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Re-search")
                        }
                    }
                    .buttonStyle(NotSurePillButtonStyle(.primary, height: 34))
                    .disabled(isSearching)
                }
            }
        }
        .padding(20)
        .frame(width: 540)
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
#Preview("Not Sure · Inbox") {
    NotSureWorkspaceView(
        store: PreviewFixtures.makeDemoStore(persona: .worldSuperNetwork, section: .scientistReview, withNotSureCases: true),
        onOpenPractice: {}
    )
    .frame(width: 1320, height: 840)
    .preferredColorScheme(.light)
}

#Preview("Not Sure · Compare (Clean + Paired L/R)") {
    NotSureWorkspaceView(
        store: PreviewFixtures.makeDemoStore(persona: .worldSuperNetwork, section: .scientistReview, withNotSureCases: true, openFirstNotSureCase: true),
        onOpenPractice: {},
        initialStageMode: .compare
    )
    .frame(width: 1320, height: 840)
    .preferredColorScheme(.light)
}

#Preview("Not Sure · Contours # (Zero .fgp)") {
    NotSureWorkspaceView(
        store: PreviewFixtures.makeDemoStore(persona: .worldSuperNetwork, section: .scientistReview, withNotSureCases: true, openFirstNotSureCase: true),
        onOpenPractice: {},
        initialStageMode: .contours
    )
    .frame(width: 1320, height: 840)
    .preferredColorScheme(.light)
}

#Preview("Not Sure · Align (3-Tap Warped Overlay)") {
    NotSureWorkspaceView(
        store: PreviewFixtures.makeDemoStore(persona: .worldSuperNetwork, section: .scientistReview, withNotSureCases: true, openFirstNotSureCase: true),
        onOpenPractice: {},
        initialStageMode: .align
    )
    .frame(width: 1320, height: 840)
    .preferredColorScheme(.light)
}
#endif
