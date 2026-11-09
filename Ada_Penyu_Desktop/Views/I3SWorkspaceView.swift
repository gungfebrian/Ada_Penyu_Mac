import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum I3SComparisonTab: String, CaseIterable, Identifiable {
    case bothImages = "Side-by-Side"
    case pointCloud = "Point Cloud"
    case unknownIndividual = "Query Photo"
    case foundIndividual = "Gallery Photo"

    var id: String { rawValue }
}

/// Interactive step mode so the user always knows what clicking the canvas will do,
/// and can click any step pill to jump back and re-pick a specific point.
enum I3SAnnotationStep: Int, CaseIterable, Identifiable {
    case ref1 = 0
    case ref2 = 1
    case ref3 = 2
    case roi = 3
    case keypoints = 4

    var id: Int { rawValue }

    var shortTitle: String {
        switch self {
        case .ref1: "1. Beak Edge"
        case .ref2: "2. Eye Area"
        case .ref3: "3. Outer Scale"
        case .roi: "4. Draw ROI"
        case .keypoints: "5. Keypoints"
        }
    }

    var instructionText: String {
        switch self {
        case .ref1:
            "Click on the photo to place Reference Point 1: Beak edge (tip of upper beak)."
        case .ref2:
            "Click on the photo to place Reference Point 2: Inner edge of eye area (nasal corner of orbit)."
        case .ref3:
            "Click on the photo to place Reference Point 3: Edge of outer postorbital scale."
        case .roi:
            "Click around the cheek scales to draw a polygon ROI. Click the first green point (or 'Finish ROI') to extract keypoints."
        case .keypoints:
            "ROI finalized! Click any red keypoint circle to remove glare artifacts, or click inside the ROI to add a keypoint."
        }
    }
}

struct I3SWorkspaceView: View {
    @ObservedObject var store: AppStore

    // Query state — starts clean & unannotated!
    @State private var isDualMode = false
    @State private var querySide: TurtlePhotoSide = .left
    @State private var queryImage: NSImage?
    @State private var queryImageData: Data?
    @State private var queryTitle: String = "No photo loaded"
    @State private var fingerprint = I3SFingerprint()
    @State private var companionFgp: I3SFingerprint?
    @State private var undoStack: [I3SFingerprint] = []
    @State private var redoStack: [I3SFingerprint] = []

    // Optional second photo for Dual L/R Pair mode (`/api/v1/match/pair`)
    @State private var secondaryImage: NSImage?
    @State private var secondaryImageData: Data?
    @State private var secondaryTitle: String = "No right photo"
    @State private var secondaryFingerprint = I3SFingerprint()
    @State private var editingSecondary = false

    // Active step & canvas controls
    @State private var activeStep: I3SAnnotationStep = .ref1
    @State private var canvasZoom: Double = 1.0
    @State private var canvasPan: CGSize = .zero
    @State private var showKeypointLabels = false
    @State private var expertParams = I3SExpertParameters.default
    @State private var isExpertPopoverPresented = false
    @State private var isDropTargeted = false

    // Search & candidate state
    @State private var isSearching = false
    @State private var queryRevision = 0
    @State private var candidateRevision = 0
    @State private var searchOutcome: MatchSearchOutcome?
    @State private var candidates: [MatchCandidateItem] = []
    @State private var selectedCandidate: MatchCandidateItem?
    @State private var candidateImage: NSImage?
    @State private var candidateFingerprint: I3SFingerprint?
    @State private var i3sComparison: I3SComparisonResult?
    @State private var overlayAnnotations: [OverlayAnnotationItem] = []
    @State private var backendOverlayImage: NSImage?
    @State private var isOverlayLoading = false

    // Visual Comparison Modal (`CompareResults.java`)
    @State private var isComparisonModalPresented = false
    @State private var comparisonTab: I3SComparisonTab = .bothImages
    @State private var autoZoomOn = false
    @State private var showMatchThreads = true
    @State private var useBackendOverlayPNG = false
    @State private var loupeZoom: Double = 2.2
    @State private var unknownHoverNormalized: CGPoint?
    @State private var foundHoverNormalized: CGPoint?
    @State private var unknownLoupeLocked = false
    @State private var foundLoupeLocked = false

    // Enrollment & status feedback
    @State private var statusBannerMessage: String?
    @State private var isEnrollSheetPresented = false
    @State private var enrollName = ""
    @State private var enrollSpecies: TurtleSpecies = .green
    @State private var enrollCondition: TurtleCondition = .healthy
    @State private var enrollNotes = ""
    @State private var isSubmittingDecision = false

    private var activeFingerprint: I3SFingerprint {
        editingSecondary ? secondaryFingerprint : fingerprint
    }

    private var activeImage: NSImage? {
        editingSecondary ? secondaryImage : queryImage
    }

    private var comparisonUsesSecondary: Bool {
        isDualMode && selectedCandidate?.matchedPhotoSide == .right
    }

    private var comparisonFingerprint: I3SFingerprint {
        comparisonUsesSecondary ? secondaryFingerprint : fingerprint
    }

    private var comparisonImage: NSImage? {
        comparisonUsesSecondary ? secondaryImage : queryImage
    }

    private var comparisonImageData: Data? {
        comparisonUsesSecondary ? secondaryImageData : queryImageData
    }

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                mainWorkspaceArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider().overlay(AdaColors.line)

                rightInspectorPanel
                    .frame(width: 348)
                    .background(AdaColors.card)
            }
            .background(AdaColors.canvas)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Full-size CompareResults Visual Comparison Modal
            if isComparisonModalPresented, let selected = selectedCandidate {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Color.black.opacity(0.28))
                    .ignoresSafeArea()
                    .onTapGesture { isComparisonModalPresented = false }

                GeometryReader { proxy in
                    visualComparisonModal(for: selected)
                        .frame(
                            width: min(max(proxy.size.width - 64, 860), 1_180),
                            height: min(max(proxy.size.height - 64, 620), 820)
                        )
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .sheet(isPresented: $isEnrollSheetPresented) {
            enrollNewIndividualSheet
        }
        .onChange(of: fingerprint) { _, _ in invalidateI3SScores() }
        .onChange(of: secondaryFingerprint) { _, _ in invalidateI3SScores() }
        .onChange(of: expertParams) { _, _ in invalidateI3SScores() }
        .onChange(of: querySide) { _, _ in invalidateI3SScores() }
        .onChange(of: isDualMode) { _, _ in invalidateI3SScores() }
        .onChange(of: queryImageData) { _, _ in invalidateI3SScores() }
        .onChange(of: secondaryImageData) { _, _ in invalidateI3SScores() }
    }

    // MARK: - Left / Center Main Workspace Area

    private var mainWorkspaceArea: some View {
        VStack(alignment: .leading, spacing: 12) {
            topActionToolbar
            stepProgressBanner

            ZStack {
                if activeImage == nil {
                    emptyImportDropZone
                } else {
                    interactiveCanvasCard
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onDrop(of: [.fileURL, .image], isTargeted: $isDropTargeted) { providers in
                handleDrop(providers: providers)
            }
        }
        .padding(18)
    }

    // MARK: - Clean Top Action Toolbar

    private var topActionToolbar: some View {
        HStack(spacing: 8) {
            // Primary Import Photo button
            Button {
                openImageFromDisk(forSecondary: editingSecondary)
            } label: {
                Label("Import Photo…", systemImage: "photo.badge.plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 13)
                    .frame(height: 30)
                    .background(AdaColors.navy, in: Capsule())
            }
            .buttonStyle(.plain)

            // Sample Photos menu (loads UNANNOTATED photo by default!)
            Menu {
                Section("Load Unannotated Sample Photo (Annotate Yourself)") {
                    ForEach(I3SSampleLibrary.samples) { sample in
                        Button("\(sample.title) (\(sample.photoSide.title))") {
                            loadSample(sample, includeAnnotations: false, forSecondary: editingSecondary)
                        }
                    }
                }
                Divider()
                Section("Load Sample with Pre-Saved .fgp Annotations") {
                    ForEach(I3SSampleLibrary.samples) { sample in
                        Button("\(sample.title) + .fgp (35 keypoints)") {
                            loadSample(sample, includeAnnotations: true, forSecondary: editingSecondary)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 11, weight: .medium))
                    Text("Sample Photos")
                        .font(.system(size: 12, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
                .foregroundStyle(AdaColors.ink)
                .padding(.horizontal, 11)
                .frame(height: 30)
                .background(AdaColors.card, in: Capsule())
                .overlay(Capsule().stroke(AdaColors.line, lineWidth: 1))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            // Side selector
            if isDualMode {
                HStack(spacing: 2) {
                    FilterChip(title: "Left Photo", isSelected: !editingSecondary, horizontalPadding: 10) {
                        editingSecondary = false
                        syncActiveStepToFingerprint()
                    }
                    FilterChip(title: "Right Photo", isSelected: editingSecondary, horizontalPadding: 10) {
                        editingSecondary = true
                        syncActiveStepToFingerprint()
                    }
                }
            } else {
                HStack(spacing: 4) {
                    ForEach(TurtlePhotoSide.allCases) { side in
                        FilterChip(title: side.title, isSelected: querySide == side, horizontalPadding: 10) {
                            querySide = side
                        }
                    }
                }
            }

            Spacer(minLength: 8)

            if activeImage != nil {
                // Zoom controls
                HStack(spacing: 4) {
                    Button {
                        canvasZoom = max(0.5, canvasZoom / 1.2)
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                            .font(.system(size: 11, weight: .medium))
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)

                    Button {
                        canvasZoom = 1.0
                        canvasPan = .zero
                    } label: {
                        Text("\(Int((canvasZoom * 100).rounded()))%")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 6)
                            .frame(height: 26)
                    }
                    .buttonStyle(.plain)

                    Button {
                        canvasZoom = min(4.0, canvasZoom * 1.2)
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                            .font(.system(size: 11, weight: .medium))
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(AdaColors.ink)
                .padding(.horizontal, 4)
                .background(AdaColors.card, in: Capsule())
                .overlay(Capsule().stroke(AdaColors.line, lineWidth: 1))

                Button {
                    performUndo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(undoStack.isEmpty ? AdaColors.tertiaryInk : AdaColors.ink)
                        .frame(width: 28, height: 28)
                        .background(AdaColors.card, in: Circle())
                        .overlay(Circle().stroke(AdaColors.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(undoStack.isEmpty)
                .help("Undo last step")

                Button {
                    resetCurrentFingerprint()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 11, weight: .medium))
                        Text("Clear")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(AdaColors.ink)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(AdaColors.card, in: Capsule())
                    .overlay(Capsule().stroke(AdaColors.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Clear all reference points and ROI to annotate from scratch")
            }

            // .fgp & Expert settings menu
            Menu {
                Button("Import .fgp Fingerprint File…") {
                    importFgpFile()
                }
                .disabled(activeImage == nil)

                Button("Export .fgp Fingerprint File…") {
                    exportFgpFile()
                }
                .disabled(!activeFingerprint.readyForProcessing)

                if let companion = companionFgp {
                    Divider()
                    Button("Load Companion .fgp (\(companion.keypoints.count) keypoints)") {
                        pushUndoState()
                        if editingSecondary {
                            secondaryFingerprint = companion
                        } else {
                            fingerprint = companion
                        }
                        syncActiveStepToFingerprint()
                        statusBannerMessage = "Loaded companion .fgp annotations."
                    }
                }

                Divider()
                Button("Auto-Place Head ROI & Extract 35 Keypoints") {
                    autoAnnotateCurrentImage()
                }
                .disabled(activeImage == nil)

                Button("Expert I3S Parameters…") {
                    isExpertPopoverPresented = true
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AdaColors.ink)
                    .frame(width: 30, height: 30)
                    .background(AdaColors.card, in: Circle())
                    .overlay(Circle().stroke(AdaColors.line, lineWidth: 1))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .popover(isPresented: $isExpertPopoverPresented, arrowEdge: .bottom) {
                expertParametersPopover
            }
        }
    }

    // MARK: - Interactive Step-by-Step Progress Bar

    private var stepProgressBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(I3SAnnotationStep.allCases) { step in
                    let isDone = isStepCompleted(step)
                    let isCurrent = activeStep == step
                    Button {
                        activeStep = step
                        statusBannerMessage = nil
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: isDone ? "checkmark.circle.fill" : (isCurrent ? "record.circle" : "circle"))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(isCurrent ? .white : (isDone ? AdaColors.green : AdaColors.tertiaryInk))
                            Text(step.shortTitle)
                                .font(.system(size: 11, weight: isCurrent ? .semibold : .medium))
                                .foregroundStyle(isCurrent ? .white : AdaColors.ink)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(
                            isCurrent ? AdaColors.navy : (isDone ? AdaColors.green.opacity(0.10) : AdaColors.canvas),
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                if !activeFingerprint.roi.isFinal && activeFingerprint.roi.vertices.count >= 3 {
                    Button {
                        closeRoiAndExtract()
                    } label: {
                        Label("Finish ROI & Extract Keypoints", systemImage: "sparkles")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .frame(height: 26)
                            .background(AdaColors.green, in: Capsule())
                    }
                    .buttonStyle(.plain)
                } else if activeImage != nil && !activeFingerprint.readyForProcessing {
                    Button {
                        autoAnnotateCurrentImage()
                    } label: {
                        Label("Use Head Template", systemImage: "wand.and.stars")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AdaColors.navy)
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(AdaColors.accentSoft, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "hand.point.up.left.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(AdaColors.navy)
                Text(statusBannerMessage ?? (activeImage == nil ? "Import or drag-and-drop a sea turtle head photo to start step-by-step I3S annotation." : activeStep.instructionText))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AdaColors.ink)
                    .lineLimit(1)
                Spacer()
                if activeImage != nil {
                    Text("Tip: Drag any point to adjust • Right-click to undo point")
                        .font(.system(size: 11))
                        .foregroundStyle(AdaColors.tertiaryInk)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(AdaColors.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AdaColors.line, lineWidth: 1)
        )
    }

    // MARK: - Empty Import / Drag-and-Drop Zone

    private var emptyImportDropZone: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(AdaColors.navy.opacity(0.07))
                    .frame(width: 72, height: 72)
                Image(systemName: "viewfinder.circle")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(AdaColors.navy)
            }

            VStack(spacing: 6) {
                Text("Import or Drop a Sea Turtle Head Photo")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AdaColors.ink)
                Text("Photos open unannotated so you can mark Reference Points 1–3 and trace the facial scale ROI yourself.")
                    .font(.system(size: 12))
                    .foregroundStyle(AdaColors.secondaryInk)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }

            HStack(spacing: 10) {
                Button {
                    openImageFromDisk(forSecondary: editingSecondary)
                } label: {
                    Label("Choose Photo from Mac…", systemImage: "folder.badge.plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .frame(height: 36)
                        .background(AdaColors.navy, in: Capsule())
                }
                .buttonStyle(.plain)

                if let defaultSample = I3SSampleLibrary.samples.first(where: { $0.id == "Amina3_L" }) ?? I3SSampleLibrary.samples.first {
                    Button {
                        loadSample(defaultSample, includeAnnotations: false, forSecondary: editingSecondary)
                    } label: {
                        Label("Try Sample Photo (Unannotated)", systemImage: "photo")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AdaColors.ink)
                            .padding(.horizontal, 16)
                            .frame(height: 36)
                            .background(AdaColors.canvas, in: Capsule())
                            .overlay(Capsule().stroke(AdaColors.line, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            // Quick thumbnail strip of bundled raw sea turtle head photos
            VStack(spacing: 8) {
                Text("Or pick a sea turtle head photo to annotate:")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AdaColors.tertiaryInk)

                HStack(spacing: 10) {
                    ForEach(I3SSampleLibrary.samples.prefix(5)) { sample in
                        Button {
                            loadSample(sample, includeAnnotations: false, forSecondary: editingSecondary)
                        } label: {
                            VStack(spacing: 5) {
                                if let img = I3SSampleLibrary.loadImage(for: sample) {
                                    Image(nsImage: img)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 68, height: 68)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                                Text(sample.id)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(AdaColors.secondaryInk)
                            }
                            .padding(6)
                            .background(AdaColors.canvas, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AdaColors.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    isDropTargeted ? AdaColors.accent : AdaColors.line,
                    style: StrokeStyle(lineWidth: isDropTargeted ? 2.5 : 1.5, dash: [8, 6])
                )
        )
    }

    // MARK: - Interactive Canvas Card

    private var interactiveCanvasCard: some View {
        VStack(spacing: 0) {
            I3SInteractiveCanvas(
                image: activeImage,
                fingerprint: editingSecondary ? $secondaryFingerprint : $fingerprint,
                activeStep: $activeStep,
                zoom: canvasZoom,
                panOffset: $canvasPan,
                showKeypointLabels: showKeypointLabels,
                onWillMutate: { pushUndoState() },
                onRoiClosed: {
                    extractKeypointsForActiveImage()
                    activeStep = .keypoints
                },
                onStatusMessage: { msg in statusBannerMessage = msg }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.11, green: 0.13, blue: 0.16))

            // Subtle canvas footer bar
            HStack(spacing: 14) {
                Text(editingSecondary ? secondaryTitle : queryTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AdaColors.ink)

                if let companion = companionFgp, !activeFingerprint.readyForProcessing {
                    Button("Load Saved .fgp (\(companion.keypoints.count) pts)") {
                        pushUndoState()
                        if editingSecondary {
                            secondaryFingerprint = companion
                        } else {
                            fingerprint = companion
                        }
                        syncActiveStepToFingerprint()
                        statusBannerMessage = "Loaded saved I3S fingerprint annotations."
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AdaColors.accent)
                    .buttonStyle(.plain)
                }

                Spacer()

                Toggle("Show Keypoint Numbers", isOn: $showKeypointLabels)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                    .foregroundStyle(AdaColors.secondaryInk)
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(AdaColors.card)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AdaColors.line, lineWidth: 1)
        )
    }

    // MARK: - Right Inspector Sidebar (`width: 348`, matching `MapFilterPanel`)

    private var rightInspectorPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 1. Annotation Checklist & Re-pick Controls
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("I3S Annotation Steps")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AdaColors.ink)
                    Spacer()
                    Toggle("Dual L/R", isOn: $isDualMode)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .font(.system(size: 11))
                        .onChange(of: isDualMode) { _, newValue in
                            if !newValue { editingSecondary = false }
                        }
                }

                stepCheckRow(
                    step: .ref1,
                    title: "1. Beak edge",
                    detail: coordinateString(activeFingerprint.ref1),
                    isComplete: activeFingerprint.ref1.isInitialized,
                    dotColor: .blue
                )
                stepCheckRow(
                    step: .ref2,
                    title: "2. Inner eye area",
                    detail: coordinateString(activeFingerprint.ref2),
                    isComplete: activeFingerprint.ref2.isInitialized,
                    dotColor: .blue
                )
                stepCheckRow(
                    step: .ref3,
                    title: "3. Outer scale edge",
                    detail: coordinateString(activeFingerprint.ref3),
                    isComplete: activeFingerprint.ref3.isInitialized,
                    dotColor: .blue
                )
                stepCheckRow(
                    step: .roi,
                    title: "4. Facial scale ROI",
                    detail: activeFingerprint.roi.isFinal
                        ? "Closed (\(activeFingerprint.roi.vertices.count - 1) pts)"
                        : "\(activeFingerprint.roi.vertices.count) vertices",
                    isComplete: activeFingerprint.roi.isFinal,
                    dotColor: .green
                )
                stepCheckRow(
                    step: .keypoints,
                    title: "5. Blob keypoints",
                    detail: "\(activeFingerprint.keypoints.count) / \(expertParams.nrElements) blobs",
                    isComplete: !activeFingerprint.keypoints.isEmpty,
                    dotColor: .red
                )
            }

            // Primary Search Button
            Button {
                Task { await runDatabaseSearch() }
            } label: {
                HStack(spacing: 8) {
                    if isSearching {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    Text(isSearching ? "Matching Gallery…" : "Search in Database")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(queryImageData != nil ? AdaColors.navy : AdaColors.tertiaryInk, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(queryImageData == nil || isSearching)

            Divider().overlay(AdaColors.line)

            // 2. Ranked Gallery Candidates (`ShowResults.java`)
            HStack {
                Text("Gallery Matches")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AdaColors.ink)
                Spacer()
                if let outcome = searchOutcome {
                    Text("\(outcome.candidates.count) results")
                        .font(.system(size: 11))
                        .foregroundStyle(AdaColors.tertiaryInk)
                }
            }

            if candidates.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tortoise")
                        .font(.system(size: 24))
                        .foregroundStyle(AdaColors.tertiaryInk)
                    Text("No search results yet")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AdaColors.secondaryInk)
                    Text("Import a photo, mark the head or click 'Search in Database' to rank gallery individuals.")
                        .font(.system(size: 11))
                        .foregroundStyle(AdaColors.tertiaryInk)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .background(AdaColors.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(candidates) { cand in
                            candidateRow(cand)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            Spacer(minLength: 0)

            // Quick Enroll New Individual button at bottom of sidebar
            if queryImageData != nil {
                Button {
                    enrollName = "Turtle #\(String(format: "%03d", store.turtles.count + 1))"
                    enrollSpecies = selectedCandidate?.species ?? .green
                    enrollCondition = .healthy
                    enrollNotes = "Enrolled via I3S Pattern v4.02 workspace"
                    isEnrollSheetPresented = true
                } label: {
                    Label("Enroll as New Individual…", systemImage: "plus.circle")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AdaColors.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(AdaColors.canvas, in: Capsule())
                        .overlay(Capsule().stroke(AdaColors.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
    }

    private func stepCheckRow(
        step: I3SAnnotationStep,
        title: String,
        detail: String,
        isComplete: Bool,
        dotColor: Color
    ) -> some View {
        let isSelected = activeStep == step
        return Button {
            activeStep = step
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(isComplete ? AdaColors.green : dotColor.opacity(0.6))
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(AdaColors.ink)
                Spacer()
                Text(detail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(isComplete ? AdaColors.secondaryInk : AdaColors.tertiaryInk)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(isSelected ? AdaColors.canvas : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func candidateRow(_ item: MatchCandidateItem) -> some View {
        let isSelected = selectedCandidate?.individualID == item.individualID
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("#\(item.rank)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(item.rank == 1 ? AdaColors.green : AdaColors.navy, in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AdaColors.ink)
                    Text("\(item.species.rawValue) · \(item.matchedPhotoSide.title)")
                        .font(.system(size: 10))
                        .foregroundStyle(AdaColors.tertiaryInk)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(item.confidencePercent)%")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(item.confidencePercent >= 50 ? AdaColors.green : AdaColors.ink)
                    Text(String(format: "Fused %.2f", item.fusedScore))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(AdaColors.tertiaryInk)
                }
            }

            HStack(spacing: 8) {
                Text("XFeat \(item.localMatch)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(AdaColors.accent)
                if let i3sScore = item.i3sDistanceScore, i3sScore < 999_999 {
                    Text(String(format: "I3S Score %.2f", i3sScore))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(AdaColors.secondaryInk)
                }
                Spacer()
                Button {
                    Task {
                        await selectCandidate(item)
                        isComparisonModalPresented = true
                    }
                } label: {
                    Text("Compare Visually")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AdaColors.navy)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(AdaColors.card, in: Capsule())
                        .overlay(Capsule().stroke(AdaColors.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(11)
        .background(isSelected ? AdaColors.accentSoft : AdaColors.canvas, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? AdaColors.accent : Color.clear, lineWidth: 1.5)
        )
        .onTapGesture {
            Task {
                await selectCandidate(item)
                isComparisonModalPresented = true
            }
        }
    }

    // MARK: - Spacious Visual Comparison Modal (`CompareResults.java`)

    private func visualComparisonModal(for selected: MatchCandidateItem) -> some View {
        VStack(spacing: 0) {
            // Modal Header
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("Visual Match Comparison — \(selected.name)")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AdaColors.ink)
                        Text("Rank #\(selected.rank) · \(selected.confidencePercent)% Confidence")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AdaColors.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(AdaColors.green.opacity(0.12), in: Capsule())
                    }
                    Text("Inspect side-by-side scale patterns, XFeat LighterGlue threads, magnifying loupe, and aligned I3S point cloud.")
                        .font(.system(size: 11))
                        .foregroundStyle(AdaColors.tertiaryInk)
                }

                Spacer()

                Picker("", selection: $comparisonTab) {
                    ForEach(I3SComparisonTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 420)

                Button {
                    isComparisonModalPresented = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AdaColors.secondaryInk)
                        .frame(width: 30, height: 30)
                        .background(Color.black.opacity(0.045), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 22)
            .frame(height: 64)
            .background(AdaColors.card)

            Divider().overlay(AdaColors.line)

            // Modal Body
            HStack(spacing: 12) {
                Button("Load Gallery .fgp…") { importCandidateFgpFile() }
                    .disabled(candidateImage == nil)
                Text(i3sComparison == nil
                     ? "I3S needs query annotations and the fingerprint belonging to this gallery photo."
                     : "I3S compares the annotated photos. Lower distance scores are better.")
                    .font(.caption)
                    .foregroundStyle(AdaColors.secondaryInk)
                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 8)

            Group {
                switch comparisonTab {
                case .bothImages:
                    modalBothSharksBody
                case .pointCloud:
                    I3SPointCloudView(
                        comparison: i3sComparison,
                        overlayAnnotations: overlayAnnotations,
                        candidate: selected
                    )
                case .unknownIndividual:
                    singleInspectView(image: comparisonImage, fp: comparisonFingerprint, title: "Query Individual (\(comparisonUsesSecondary ? secondaryTitle : queryTitle))", tint: .red)
                case .foundIndividual:
                    singleInspectView(
                        image: candidateImage,
                        fp: candidateFingerprint,
                        title: "Gallery Individual: \(selected.name) (\(selected.matchedPhotoSide.title))",
                        tint: .cyan
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.10, green: 0.12, blue: 0.15))

            Divider().overlay(AdaColors.line)

            // Modal Footer (`CompareResults` actions)
            HStack(spacing: 12) {
                Toggle("AutoZoom ROI (20%)", isOn: $autoZoomOn)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12, weight: .medium))

                Toggle("XFeat Match Threads (\(overlayAnnotations.count))", isOn: $showMatchThreads)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12, weight: .medium))

                Spacer()

                Button {
                    if let matchingTurtle = store.turtles.first(where: { $0.backendID == selected.individualID || $0.id == selected.name }) {
                        isComparisonModalPresented = false
                        store.select(matchingTurtle)
                    }
                } label: {
                    Text("Open Profile")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AdaColors.ink)
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background(AdaColors.canvas, in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    isComparisonModalPresented = false
                    enrollName = "Turtle #\(String(format: "%03d", store.turtles.count + 1))"
                    enrollSpecies = selected.species
                    enrollCondition = .healthy
                    enrollNotes = "Enrolled via I3S Pattern v4.02 workspace"
                    isEnrollSheetPresented = true
                } label: {
                    Text("New Individual…")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AdaColors.ink)
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background(AdaColors.canvas, in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    Task {
                        await confirmMatchAndIncludeInDatabase(selected)
                        isComparisonModalPresented = false
                    }
                } label: {
                    Label("Include in Database (\(selected.name))", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 32)
                        .background(AdaColors.green, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(queryImageData == nil || isSubmittingDecision)
            }
            .padding(.horizontal, 22)
            .frame(height: 56)
            .background(AdaColors.card)
        }
        .background(AdaColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.75), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.24), radius: 30, y: 12)
    }

    private var modalBothSharksBody: some View {
        VStack(spacing: 0) {
            if useBackendOverlayPNG, let pngImg = backendOverlayImage {
                VStack(spacing: 8) {
                    HStack {
                        Text("Server-Rendered XFeat LighterGlue Canvas (/api/v1/match/overlay)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                        Spacer()
                        Button("Back to Interactive Loupe Comparison") {
                            useBackendOverlayPNG = false
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                    Image(nsImage: pngImg)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(12)
                }
            } else {
                I3SBothSharksComparisonCanvas(
                    unknownImage: comparisonImage,
                    unknownFingerprint: comparisonFingerprint,
                    foundImage: candidateImage,
                    foundFingerprint: candidateFingerprint,
                    candidate: selectedCandidate,
                    i3sComparison: i3sComparison,
                    overlayAnnotations: overlayAnnotations,
                    autoZoomOn: autoZoomOn,
                    showMatchThreads: showMatchThreads,
                    loupeZoom: $loupeZoom,
                    unknownHover: $unknownHoverNormalized,
                    foundHover: $foundHoverNormalized,
                    unknownLocked: $unknownLoupeLocked,
                    foundLocked: $foundLoupeLocked,
                    onRequestBackendPNG: {
                        Task { await loadBackendOverlayPNG() }
                    }
                )
            }
        }
    }

    private func singleInspectView(image: NSImage?, fp: I3SFingerprint?, title: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle().fill(tint).frame(width: 8, height: 8)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                if let fp {
                    Text("Keypoints: \(fp.keypoints.count)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

            if let image {
                GeometryReader { geo in
                    let fit = aspectFitRect(imageSize: image.size, in: geo.size)
                    ZStack(alignment: .topLeading) {
                        Image(nsImage: image)
                            .resizable()
                            .frame(width: fit.width, height: fit.height)
                            .position(x: fit.midX, y: fit.midY)

                        if let fp {
                            Canvas { ctx, _ in
                                drawFingerprintOverlay(
                                    context: &ctx,
                                    fp: fp,
                                    imageSize: image.size,
                                    fitRect: fit,
                                    showLabels: true,
                                    showTriangle: true
                                )
                            }
                        }
                    }
                }
                .padding(12)
            }
        }
    }

    // MARK: - Expert Settings Popover & Enrollment Sheet

    private var expertParametersPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("I3S Pattern v4.02 Expert Settings (metadata.xml)")
                .font(.system(size: 13, weight: .bold))

            Stepper("Target Keypoints (nrElements): \(expertParams.nrElements)", value: $expertParams.nrElements, in: 15...80, step: 5)
                .font(.system(size: 12))

            HStack {
                Text("ROI Warp Size:")
                    .font(.system(size: 12))
                Spacer()
                Text("\(Int(expertParams.warpSize)) px")
                    .font(.system(size: 12, design: .monospaced))
            }
            Slider(value: $expertParams.warpSize, in: 250...800, step: 50)

            HStack {
                Text("Min Keypoint Distance Ratio:")
                    .font(.system(size: 12))
                Spacer()
                Text(String(format: "%.2f", expertParams.relKeypointDist))
                    .font(.system(size: 12, design: .monospaced))
            }
            Slider(value: $expertParams.relKeypointDist, in: 0.02...0.12, step: 0.01)

            HStack {
                Button("Reset Defaults") {
                    expertParams = .default
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("Re-Extract Keypoints") {
                    extractKeypointsForActiveImage()
                    isExpertPopoverPresented = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    private var enrollNewIndividualSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Enroll New Sea Turtle Individual")
                .font(.system(size: 18, weight: .bold))

            Text("Creates a new individual in the backend database and indexes the current head photo into the MiewID + XFeat gallery.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            TextField("Individual Name / Code", text: $enrollName)
                .textFieldStyle(.roundedBorder)

            Picker("Species", selection: $enrollSpecies) {
                ForEach(TurtleSpecies.allCases) { sp in
                    Text(sp.rawValue).tag(sp)
                }
            }

            Picker("Health Condition", selection: $enrollCondition) {
                ForEach(TurtleCondition.allCases) { cond in
                    Text(cond.rawValue).tag(cond)
                }
            }

            TextField("Notes / Capture Location", text: $enrollNotes)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel") {
                    isEnrollSheetPresented = false
                }
                .buttonStyle(.bordered)

                Button {
                    Task { await submitNewIndividualEnrollment() }
                } label: {
                    Text(isSubmittingDecision ? "Enrolling…" : "Create & Index Gallery Photo")
                }
                .buttonStyle(.borderedProminent)
                .disabled(enrollName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmittingDecision)
            }
        }
        .padding(22)
        .frame(width: 420)
    }

    // MARK: - Helpers & State Transitions

    private func isStepCompleted(_ step: I3SAnnotationStep) -> Bool {
        let fp = activeFingerprint
        switch step {
        case .ref1: return fp.ref1.isInitialized
        case .ref2: return fp.ref2.isInitialized
        case .ref3: return fp.ref3.isInitialized
        case .roi: return fp.roi.isFinal
        case .keypoints: return !fp.keypoints.isEmpty
        }
    }

    private func syncActiveStepToFingerprint() {
        let fp = activeFingerprint
        if !fp.ref1.isInitialized {
            activeStep = .ref1
        } else if !fp.ref2.isInitialized {
            activeStep = .ref2
        } else if !fp.ref3.isInitialized {
            activeStep = .ref3
        } else if !fp.roi.isFinal {
            activeStep = .roi
        } else {
            activeStep = .keypoints
        }
    }

    private func coordinateString(_ pt: I3SPoint2D) -> String {
        guard pt.isInitialized else { return "Click to set" }
        return "(\(Int(pt.x.rounded())), \(Int(pt.y.rounded())))"
    }

    private func pushUndoState() {
        undoStack.append(activeFingerprint)
        if undoStack.count > 30 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    private func performUndo() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(activeFingerprint)
        if editingSecondary {
            secondaryFingerprint = prev
        } else {
            fingerprint = prev
        }
        syncActiveStepToFingerprint()
        statusBannerMessage = nil
    }

    private func resetCurrentFingerprint() {
        pushUndoState()
        if editingSecondary {
            secondaryFingerprint = I3SFingerprint()
        } else {
            fingerprint = I3SFingerprint()
        }
        activeStep = .ref1
        statusBannerMessage = "Cleared annotations — Click Reference Point 1 (Beak edge) to start."
    }

    private func closeRoiAndExtract() {
        pushUndoState()
        if editingSecondary {
            _ = secondaryFingerprint.roi.closePolygonIfPossible()
        } else {
            _ = fingerprint.roi.closePolygonIfPossible()
        }
        extractKeypointsForActiveImage()
        activeStep = .keypoints
    }

    private func extractKeypointsForActiveImage() {
        guard let img = activeImage else { return }
        if editingSecondary {
            guard secondaryFingerprint.roi.isFinal else { return }
            secondaryFingerprint.keypoints = I3SSurfExtractor.extractKeypoints(
                from: img,
                roi: secondaryFingerprint.roi,
                params: expertParams
            )
            statusBannerMessage = "Extracted \(secondaryFingerprint.keypoints.count) approximate blob keypoints inside ROI."
        } else {
            guard fingerprint.roi.isFinal else { return }
            fingerprint.keypoints = I3SSurfExtractor.extractKeypoints(
                from: img,
                roi: fingerprint.roi,
                params: expertParams
            )
            statusBannerMessage = "Extracted \(fingerprint.keypoints.count) approximate blob keypoints inside ROI."
        }
    }

    private func autoAnnotateCurrentImage() {
        guard let img = activeImage else { return }
        pushUndoState()
        let side: TurtlePhotoSide = editingSecondary ? .right : querySide
        let generated = I3SSurfExtractor.autoAnnotateHead(image: img, side: side, params: expertParams)
        if editingSecondary {
            secondaryFingerprint = generated
        } else {
            fingerprint = generated
        }
        activeStep = .keypoints
        statusBannerMessage = "Placed a fixed head template with \(generated.keypoints.count) approximate blob keypoints. Adjust the reference points and ROI to fit this photo."
    }

    private func loadSample(_ sample: I3SSampleEntry, includeAnnotations: Bool, forSecondary: Bool) {
        guard let data = I3SSampleLibrary.loadImageData(for: sample),
              let image = NSImage(data: data) else {
            return
        }
        canvasZoom = 1.0
        canvasPan = .zero
        companionFgp = sample.fingerprint
        let initialFp = includeAnnotations ? sample.fingerprint : I3SFingerprint()

        if forSecondary {
            secondaryImage = image
            secondaryImageData = data
            secondaryTitle = sample.title
            secondaryFingerprint = initialFp
        } else {
            querySide = sample.photoSide
            queryImage = image
            queryImageData = data
            queryTitle = sample.title
            fingerprint = initialFp
            undoStack.removeAll()
            redoStack.removeAll()
        }
        syncActiveStepToFingerprint()
        statusBannerMessage = includeAnnotations
            ? "Loaded '\(sample.title)' with saved .fgp annotations (\(sample.fingerprint.keypoints.count) keypoints)."
            : "Loaded '\(sample.title)' unannotated — Click Reference Point 1 (Beak edge) on the photo!"
    }

    private func openImageFromDisk(forSecondary: Bool) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .jpeg, .png, .heic, .tiff]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadImageFile(from: url, forSecondary: forSecondary)
    }

    private func loadImageFile(from url: URL, forSecondary: Bool) {
        guard let data = try? Data(contentsOf: url),
              let image = NSImage(data: data) else {
            statusBannerMessage = "Could not decode image file \(url.lastPathComponent)."
            return
        }
        canvasZoom = 1.0
        canvasPan = .zero

        // Check if a companion .fgp file exists next to the image, but do NOT auto-apply it so the user can annotate freely
        let fgpURL = url.deletingPathExtension().appendingPathExtension("fgp")
        if let fgpData = try? Data(contentsOf: fgpURL),
           let parsedFgp = try? I3SFingerprintFile.read(from: fgpData, filename: fgpURL.lastPathComponent) {
            companionFgp = parsedFgp
        } else {
            companionFgp = nil
        }

        if forSecondary {
            secondaryImage = image
            secondaryImageData = jpegData(from: image) ?? data
            secondaryTitle = url.lastPathComponent
            secondaryFingerprint = I3SFingerprint()
        } else {
            queryImage = image
            queryImageData = jpegData(from: image) ?? data
            queryTitle = url.lastPathComponent
            fingerprint = I3SFingerprint()
            undoStack.removeAll()
            redoStack.removeAll()
        }
        activeStep = .ref1
        statusBannerMessage = "Imported '\(url.lastPathComponent)' — Click Reference Point 1 (Beak edge) on the photo to begin."
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else {
                        return
                    }
                    Task { @MainActor in
                        if url.pathExtension.lowercased() == "fgp" {
                            if let fgpBytes = try? Data(contentsOf: url),
                               let parsed = try? I3SFingerprintFile.read(from: fgpBytes, filename: url.lastPathComponent) {
                                pushUndoState()
                                if editingSecondary { secondaryFingerprint = parsed } else { fingerprint = parsed }
                                syncActiveStepToFingerprint()
                                statusBannerMessage = "Loaded dropped .fgp file '\(url.lastPathComponent)'."
                            }
                        } else {
                            loadImageFile(from: url, forSecondary: editingSecondary)
                        }
                    }
                }
                return true
            }
        }
        return false
    }

    private func importFgpFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "fgp") ?? .data]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url) else {
            return
        }
        do {
            let parsed = try I3SFingerprintFile.read(from: data, filename: url.lastPathComponent)
            pushUndoState()
            if editingSecondary {
                secondaryFingerprint = parsed
            } else {
                fingerprint = parsed
            }
            syncActiveStepToFingerprint()
            statusBannerMessage = "Imported .fgp fingerprint '\(url.lastPathComponent)' (\(parsed.keypoints.count) keypoints)."
        } catch {
            statusBannerMessage = error.localizedDescription
        }
    }

    private func exportFgpFile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = (queryTitle as NSString).deletingPathExtension + ".fgp"
        panel.allowedContentTypes = [UTType(filenameExtension: "fgp") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let bytes = I3SFingerprintFile.write(activeFingerprint)
        try? bytes.write(to: url, options: .atomic)
        statusBannerMessage = "Exported binary I3S 'IP40' fingerprint to \(url.lastPathComponent)."
    }

    private func runDatabaseSearch() async {
        guard let qData = queryImageData else { return }
        let revision = queryRevision
        isSearching = true
        statusBannerMessage = "Searching gallery via MiewID + XFeat LighterGlue…"
        defer { isSearching = false }

        do {
            let outcome: MatchSearchOutcome
            if isDualMode, let rData = secondaryImageData {
                outcome = try await store.matchPhotoPair(leftData: qData, rightData: rData, limit: 10)
            } else {
                outcome = try await store.matchPhoto(imageData: qData, side: querySide, limit: 10)
            }
            guard queryRevision == revision else { return }
            searchOutcome = outcome

            candidates = outcome.candidates
            if let top = candidates.first {
                await selectCandidate(top)
                guard queryRevision == revision else { return }
                statusBannerMessage = "Found \(candidates.count) candidates — Top match: \(top.name) (\(top.confidencePercent)% confidence). Click 'Compare Visually' to inspect."
            } else {
                statusBannerMessage = "Search complete — No candidates above threshold."
            }
        } catch {
            guard queryRevision == revision else { return }
            statusBannerMessage = "Search error: \(error.localizedDescription)"
        }
    }

    private func selectCandidate(_ candidate: MatchCandidateItem) async {
        candidateRevision += 1
        let selectionRevision = candidateRevision
        let inputRevision = queryRevision
        selectedCandidate = candidate
        candidateImage = nil
        candidateFingerprint = nil
        i3sComparison = nil
        overlayAnnotations = []
        isOverlayLoading = false
        useBackendOverlayPNG = false
        backendOverlayImage = nil
        unknownLoupeLocked = false
        foundLoupeLocked = false

        let comparisonData = comparisonImageData
        let comparisonSide: TurtlePhotoSide = comparisonUsesSecondary ? .right : querySide
        let path = candidate.photoURL ?? "/api/v1/individuals/\(candidate.individualID.uuidString)/photos/\(candidate.matchedPhotoSide.rawValue)"
        let fetchedImage = await store.loadPhoto(for: path)
        guard candidateRevision == selectionRevision, queryRevision == inputRevision else { return }
        candidateImage = fetchedImage

        if let qData = comparisonData {
            isOverlayLoading = true
            let annotations = try? await store.fetchOverlayAnnotations(
                imageData: qData,
                side: comparisonSide,
                candidateID: candidate.individualID,
                candidateSide: candidate.matchedPhotoSide,
                maxThreads: expertParams.nrElements
            )
            guard candidateRevision == selectionRevision, queryRevision == inputRevision else { return }
            overlayAnnotations = annotations ?? []
            isOverlayLoading = false
        }
    }

    private func importCandidateFgpFile() {
        guard candidateImage != nil, let selected = selectedCandidate else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "fgp") ?? .data]
        panel.allowsMultipleSelection = false
        panel.message = "Choose the .fgp belonging to the displayed gallery photo of \(selected.name)."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let parsed = try I3SFingerprintFile.read(from: Data(contentsOf: url), filename: url.lastPathComponent)
            guard parsed.readyForProcessing, comparisonFingerprint.readyForProcessing else {
                statusBannerMessage = "Complete the query annotations and load a gallery .fgp with references, ROI, and keypoints."
                return
            }
            guard isDualMode || selected.matchedPhotoSide == querySide else {
                statusBannerMessage = "I3S requires both photos to show the same side."
                return
            }
            candidateFingerprint = parsed
            let comparison = I3SCompareEngine.compareTwo(unknown: comparisonFingerprint, candidate: parsed, params: expertParams)
            i3sComparison = comparison
            if let index = candidates.firstIndex(where: { $0.individualID == selected.individualID }) {
                candidates[index].i3sDistanceScore = comparison.score
                candidates[index].i3sPairedCount = comparison.pairCount
                selectedCandidate = candidates[index]
            }
        } catch {
            statusBannerMessage = error.localizedDescription
        }
    }

    private func invalidateI3SScores() {
        queryRevision += 1
        candidateRevision += 1
        i3sComparison = nil
        overlayAnnotations = []
        backendOverlayImage = nil
        useBackendOverlayPNG = false
        isOverlayLoading = false
        for index in candidates.indices {
            candidates[index].i3sDistanceScore = nil
            candidates[index].i3sPairedCount = nil
        }
        if var selected = selectedCandidate {
            selected.i3sDistanceScore = nil
            selected.i3sPairedCount = nil
            selectedCandidate = selected
        }
    }

    private func loadBackendOverlayPNG() async {
        guard let qData = comparisonImageData, let selected = selectedCandidate else { return }
        let selectionRevision = candidateRevision
        let inputRevision = queryRevision
        let side: TurtlePhotoSide = comparisonUsesSecondary ? .right : querySide
        isOverlayLoading = true
        defer {
            if candidateRevision == selectionRevision { isOverlayLoading = false }
        }
        if let pngData = try? await store.fetchOverlayPNG(
            imageData: qData,
            side: side,
            candidateID: selected.individualID,
            candidateSide: selected.matchedPhotoSide,
            maxThreads: expertParams.nrElements
        ), let img = NSImage(data: pngData),
           candidateRevision == selectionRevision, queryRevision == inputRevision {
            backendOverlayImage = img
            useBackendOverlayPNG = true
        }
    }

    private func confirmMatchAndIncludeInDatabase(_ candidate: MatchCandidateItem) async {
        guard let qData = queryImageData else { return }
        isSubmittingDecision = true
        defer { isSubmittingDecision = false }
        do {
            try await store.confirmMatchAndAttachPhoto(
                individualID: candidate.individualID,
                side: querySide,
                imageData: qData
            )
            statusBannerMessage = "Included photo in database for \(candidate.name) (\(querySide.title))."
        } catch {
            statusBannerMessage = "Failed to include photo: \(error.localizedDescription)"
        }
    }

    private func submitNewIndividualEnrollment() async {
        isSubmittingDecision = true
        defer { isSubmittingDecision = false }
        do {
            let leftBytes = isDualMode ? queryImageData : (querySide == .left ? queryImageData : nil)
            let rightBytes = isDualMode ? secondaryImageData : (querySide == .right ? queryImageData : nil)
            let created = try await store.enrollNewIndividual(
                name: enrollName.trimmingCharacters(in: .whitespacesAndNewlines),
                species: enrollSpecies,
                condition: enrollCondition,
                notes: enrollNotes.isEmpty ? nil : enrollNotes,
                leftPhoto: leftBytes,
                rightPhoto: rightBytes
            )
            isEnrollSheetPresented = false
            statusBannerMessage = "Enrolled new individual '\(created.id)' and indexed head photo(s) in backend."
        } catch {
            statusBannerMessage = "Enrollment failed: \(error.localizedDescription)"
        }
    }

    private func jpegData(from image: NSImage) -> Data? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.92])
    }
}

// MARK: - Interactive Annotation Canvas with Click, Drag-to-Adjust & Right-Click Support

private enum DraggedHandle: Equatable {
    case ref1
    case ref2
    case ref3
    case roiVertex(Int)
}

private struct I3SInteractiveCanvas: View {
    let image: NSImage?
    @Binding var fingerprint: I3SFingerprint
    @Binding var activeStep: I3SAnnotationStep
    let zoom: Double
    @Binding var panOffset: CGSize
    let showKeypointLabels: Bool
    let onWillMutate: () -> Void
    let onRoiClosed: () -> Void
    let onStatusMessage: (String?) -> Void

    @State private var activeDragHandle: DraggedHandle?
    @State private var didPushUndoForDrag = false

    var body: some View {
        GeometryReader { geo in
            if let image {
                let baseFit = aspectFitRect(imageSize: image.size, in: geo.size)
                let zoomedW = baseFit.width * zoom
                let zoomedH = baseFit.height * zoom
                let fitRect = CGRect(
                    x: (geo.size.width - zoomedW) * 0.5 + panOffset.width,
                    y: (geo.size.height - zoomedH) * 0.5 + panOffset.height,
                    width: zoomedW,
                    height: zoomedH
                )

                ZStack(alignment: .topLeading) {
                    Image(nsImage: image)
                        .resizable()
                        .frame(width: fitRect.width, height: fitRect.height)
                        .position(x: fitRect.midX, y: fitRect.midY)

                    Canvas { context, _ in
                        drawFingerprintOverlay(
                            context: &context,
                            fp: fingerprint,
                            imageSize: image.size,
                            fitRect: fitRect,
                            showLabels: showKeypointLabels,
                            showTriangle: true
                        )
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            handlePointerChanged(value: value, imageSize: image.size, fitRect: fitRect)
                        }
                        .onEnded { value in
                            handlePointerEnded(value: value, imageSize: image.size, fitRect: fitRect)
                        }
                )
                .contextMenu {
                    if !fingerprint.roi.isFinal && !fingerprint.roi.vertices.isEmpty {
                        Button("Undo Last ROI Point") {
                            onWillMutate()
                            fingerprint.roi.removeLast()
                        }
                    }
                    if !fingerprint.roi.isFinal && fingerprint.roi.vertices.count >= 3 {
                        Button("Finish ROI & Extract Blob Keypoints") {
                            onWillMutate()
                            _ = fingerprint.roi.closePolygonIfPossible()
                            onRoiClosed()
                        }
                    }
                    Divider()
                    Button("Re-pick 1. Beak Edge") { activeStep = .ref1 }
                    Button("Re-pick 2. Eye Area") { activeStep = .ref2 }
                    Button("Re-pick 3. Outer Scale") { activeStep = .ref3 }
                    Divider()
                    Button("Clear ROI Only") {
                        onWillMutate()
                        fingerprint.roi.clear()
                        fingerprint.keypoints.removeAll()
                        activeStep = .roi
                    }
                    Button("Clear All Annotations", role: .destructive) {
                        onWillMutate()
                        fingerprint = I3SFingerprint()
                        activeStep = .ref1
                    }
                }
                .clipped()
            }
        }
    }

    private func toImagePoint(_ viewPoint: CGPoint, imageSize: NSSize, fitRect: CGRect) -> I3SPoint2D? {
        guard fitRect.width > 1, fitRect.height > 1 else { return nil }
        let clampedX = min(max(viewPoint.x, fitRect.minX), fitRect.maxX)
        let clampedY = min(max(viewPoint.y, fitRect.minY), fitRect.maxY)
        let imgX = Double((clampedX - fitRect.minX) / fitRect.width * imageSize.width)
        let imgY = Double((clampedY - fitRect.minY) / fitRect.height * imageSize.height)
        return I3SPoint2D(x: imgX, y: imgY)
    }

    private func toViewPoint(_ pt: I3SPoint2D, imageSize: NSSize, fitRect: CGRect) -> CGPoint {
        CGPoint(
            x: fitRect.minX + CGFloat(pt.x) / imageSize.width * fitRect.width,
            y: fitRect.minY + CGFloat(pt.y) / imageSize.height * fitRect.height
        )
    }

    private func hitTestHandle(at viewPoint: CGPoint, imageSize: NSSize, fitRect: CGRect) -> DraggedHandle? {
        let hitRadius: CGFloat = 14.0
        if fingerprint.ref1.isInitialized, hypot(toViewPoint(fingerprint.ref1, imageSize: imageSize, fitRect: fitRect).x - viewPoint.x, toViewPoint(fingerprint.ref1, imageSize: imageSize, fitRect: fitRect).y - viewPoint.y) <= hitRadius {
            return .ref1
        }
        if fingerprint.ref2.isInitialized, hypot(toViewPoint(fingerprint.ref2, imageSize: imageSize, fitRect: fitRect).x - viewPoint.x, toViewPoint(fingerprint.ref2, imageSize: imageSize, fitRect: fitRect).y - viewPoint.y) <= hitRadius {
            return .ref2
        }
        if fingerprint.ref3.isInitialized, hypot(toViewPoint(fingerprint.ref3, imageSize: imageSize, fitRect: fitRect).x - viewPoint.x, toViewPoint(fingerprint.ref3, imageSize: imageSize, fitRect: fitRect).y - viewPoint.y) <= hitRadius {
            return .ref3
        }
        for (idx, v) in fingerprint.roi.vertices.enumerated() {
            let vp = toViewPoint(v, imageSize: imageSize, fitRect: fitRect)
            if hypot(vp.x - viewPoint.x, vp.y - viewPoint.y) <= hitRadius {
                return .roiVertex(idx)
            }
        }
        return nil
    }

    private func handlePointerChanged(value: DragGesture.Value, imageSize: NSSize, fitRect: CGRect) {
        let dragDist = hypot(value.translation.width, value.translation.height)
        guard dragDist > 3.0 else { return }

        if activeDragHandle == nil {
            activeDragHandle = hitTestHandle(at: value.startLocation, imageSize: imageSize, fitRect: fitRect)
        }

        guard let handle = activeDragHandle,
              let pt = toImagePoint(value.location, imageSize: imageSize, fitRect: fitRect) else {
            return
        }

        if !didPushUndoForDrag {
            onWillMutate()
            didPushUndoForDrag = true
        }

        switch handle {
        case .ref1:
            fingerprint.ref1 = pt
        case .ref2:
            fingerprint.ref2 = pt
        case .ref3:
            fingerprint.ref3 = pt
        case let .roiVertex(idx):
            guard idx < fingerprint.roi.vertices.count else { break }
            let wasFinal = fingerprint.roi.isFinal
            fingerprint.roi.vertices[idx] = pt
            if wasFinal {
                if idx == 0 {
                    fingerprint.roi.vertices[fingerprint.roi.vertices.count - 1] = pt
                } else if idx == fingerprint.roi.vertices.count - 1 {
                    fingerprint.roi.vertices[0] = pt
                }
            }
        }
    }

    private func handlePointerEnded(value: DragGesture.Value, imageSize: NSSize, fitRect: CGRect) {
        defer {
            activeDragHandle = nil
            didPushUndoForDrag = false
        }

        let dragDist = hypot(value.translation.width, value.translation.height)
        if dragDist > 3.0 {
            if case .roiVertex = activeDragHandle, fingerprint.roi.isFinal {
                onRoiClosed()
            }
            return
        }

        // Single click!
        guard fitRect.contains(value.location),
              let pt = toImagePoint(value.location, imageSize: imageSize, fitRect: fitRect) else {
            return
        }

        // Option-click or Control-click removes last ROI vertex or nearest keypoint
        if NSEvent.modifierFlags.contains(.option) || NSEvent.modifierFlags.contains(.control) {
            onWillMutate()
            if !fingerprint.roi.isFinal && !fingerprint.roi.vertices.isEmpty {
                fingerprint.roi.removeLast()
                onStatusMessage("Removed last ROI vertex.")
            } else {
                fingerprint.removeNearestKeypoint(to: pt)
                onStatusMessage("Removed nearest keypoint (\(fingerprint.keypoints.count) remaining).")
            }
            return
        }

        onWillMutate()
        switch activeStep {
        case .ref1:
            fingerprint.ref1 = pt
            if !fingerprint.ref2.isInitialized {
                activeStep = .ref2
            } else if !fingerprint.ref3.isInitialized {
                activeStep = .ref3
            } else if !fingerprint.roi.isFinal {
                activeStep = .roi
            } else {
                activeStep = .keypoints
            }
            onStatusMessage(nil)

        case .ref2:
            fingerprint.ref2 = pt
            if !fingerprint.ref3.isInitialized {
                activeStep = .ref3
            } else if !fingerprint.roi.isFinal {
                activeStep = .roi
            } else {
                activeStep = .keypoints
            }
            onStatusMessage(nil)

        case .ref3:
            fingerprint.ref3 = pt
            if !fingerprint.roi.isFinal {
                activeStep = .roi
            } else {
                activeStep = .keypoints
            }
            onStatusMessage(nil)

        case .roi:
            if fingerprint.roi.isFinal {
                // Allow starting a fresh ROI if the user explicitly selected Step 4: Draw ROI
                fingerprint.roi.clear()
                fingerprint.keypoints.removeAll()
            }
            let snapDist = max(20.0, Double(max(imageSize.width, imageSize.height)) * 0.035)
            do {
                let closed = try fingerprint.roi.add(pt, closeThresholdSquared: snapDist * snapDist)
                if closed {
                    onRoiClosed()
                } else {
                    onStatusMessage(nil)
                }
            } catch {
                onStatusMessage(error.localizedDescription)
            }

        case .keypoints:
            // If clicking on an existing keypoint, remove it; otherwise if inside ROI, add a keypoint
            if let nearest = fingerprint.keypoints.min(by: { $0.center.sqrDist(to: pt) < $1.center.sqrDist(to: pt) }),
               nearest.center.dist(to: pt) <= max(14.0, nearest.radius) {
                fingerprint.removeNearestKeypoint(to: pt)
                onStatusMessage("Removed keypoint artifact (\(fingerprint.keypoints.count) remaining).")
            } else if fingerprint.roi.contains(pt) {
                fingerprint.keypoints.append(I3SKeypoint(center: pt, size: 18.0))
                onStatusMessage("Added manual keypoint (\(fingerprint.keypoints.count) total).")
            }
        }
    }
}

// MARK: - BothSharks Side-by-Side Comparison + AutoZoom + Magnifying Glass (`BothSharks.java`)

private struct I3SBothSharksComparisonCanvas: View {
    let unknownImage: NSImage?
    let unknownFingerprint: I3SFingerprint
    let foundImage: NSImage?
    let foundFingerprint: I3SFingerprint?
    let candidate: MatchCandidateItem?
    let i3sComparison: I3SComparisonResult?
    let overlayAnnotations: [OverlayAnnotationItem]
    let autoZoomOn: Bool
    let showMatchThreads: Bool
    @Binding var loupeZoom: Double
    @Binding var unknownHover: CGPoint?
    @Binding var foundHover: CGPoint?
    @Binding var unknownLocked: Bool
    @Binding var foundLocked: Bool
    let onRequestBackendPNG: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Text("Hover over either photo to inspect scales with the magnifying glass • Click photo to lock/unlock loupe")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.75))

                Spacer()

                HStack(spacing: 6) {
                    Text(String(format: "Loupe %.1fx", loupeZoom))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                    Slider(value: $loupeZoom, in: 1.4...4.0, step: 0.2)
                        .frame(width: 90)
                }

                if candidate != nil {
                    Button("Server XFeat PNG") {
                        onRequestBackendPNG()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

            GeometryReader { geo in
                let paneW = max(140, (geo.size.width - 36) * 0.5)
                let paneH = max(160, geo.size.height - 20)
                let leftFrame = CGRect(x: 12, y: 8, width: paneW, height: paneH)
                let rightFrame = CGRect(x: 24 + paneW, y: 8, width: paneW, height: paneH)

                ZStack(alignment: .topLeading) {
                    comparisonImageTile(
                        title: "Unknown Individual (Query)",
                        subtitle: i3sComparison.map { $0.score < 999_999 ? String(format: "I3S Score: %.2f", $0.score) : "Query" } ?? "Query",
                        titleColor: .red,
                        image: croppedIfAutoZoom(image: unknownImage, fp: unknownFingerprint),
                        fingerprint: autoZoomOn ? nil : unknownFingerprint,
                        frame: leftFrame,
                        hoverNormalized: $unknownHover,
                        isLocked: $unknownLocked
                    )

                    comparisonImageTile(
                        title: candidate.map { "Found: \($0.name)" } ?? "Found Individual",
                        subtitle: candidate.map { "Conf \($0.confidencePercent)% · XFeat \($0.localMatch)" } ?? "",
                        titleColor: .cyan,
                        image: croppedIfAutoZoom(image: foundImage, fp: foundFingerprint),
                        fingerprint: autoZoomOn ? nil : foundFingerprint,
                        frame: rightFrame,
                        hoverNormalized: $foundHover,
                        isLocked: $foundLocked
                    )

                    if showMatchThreads,
                       let uImg = unknownImage,
                       let fImg = foundImage,
                       !overlayAnnotations.isEmpty {
                        let uFit = aspectFitRect(imageSize: uImg.size, in: CGSize(width: leftFrame.width, height: leftFrame.height - 26))
                            .offsetBy(dx: leftFrame.minX, dy: leftFrame.minY + 26)
                        let fFit = aspectFitRect(imageSize: fImg.size, in: CGSize(width: rightFrame.width, height: rightFrame.height - 26))
                            .offsetBy(dx: rightFrame.minX, dy: rightFrame.minY + 26)

                        Canvas { ctx, _ in
                            for (idx, ann) in overlayAnnotations.prefix(35).enumerated() {
                                let p1 = CGPoint(
                                    x: uFit.minX + CGFloat(ann.query.x) * uFit.width,
                                    y: uFit.minY + CGFloat(ann.query.y) * uFit.height
                                )
                                let p2 = CGPoint(
                                    x: fFit.minX + CGFloat(ann.candidate.x) * fFit.width,
                                    y: fFit.minY + CGFloat(ann.candidate.y) * fFit.height
                                )
                                var line = Path()
                                line.move(to: p1)
                                line.addLine(to: p2)
                                let hue = Double(idx % 12) / 12.0
                                let threadColor = Color(hue: hue, saturation: 0.85, brightness: 0.98)
                                ctx.stroke(line, with: .color(threadColor.opacity(0.68)), lineWidth: 1.4)

                                let dot1 = CGRect(x: p1.x - 3, y: p1.y - 3, width: 6, height: 6)
                                let dot2 = CGRect(x: p2.x - 3, y: p2.y - 3, width: 6, height: 6)
                                ctx.fill(Path(ellipseIn: dot1), with: .color(.red))
                                ctx.fill(Path(ellipseIn: dot2), with: .color(.cyan))
                            }
                        }
                        .allowsHitTesting(false)
                    }
                }
            }
        }
    }

    private func comparisonImageTile(
        title: String,
        subtitle: String,
        titleColor: Color,
        image: NSImage?,
        fingerprint: I3SFingerprint?,
        frame: CGRect,
        hoverNormalized: Binding<CGPoint?>,
        isLocked: Binding<Bool>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(titleColor)
                Spacer()
                if isLocked.wrappedValue {
                    Label("Loupe Locked", systemImage: "lock.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.yellow)
                }
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .frame(height: 20)

            GeometryReader { innerGeo in
                if let image {
                    let fit = aspectFitRect(imageSize: image.size, in: innerGeo.size)
                    ZStack(alignment: .topLeading) {
                        Image(nsImage: image)
                            .resizable()
                            .frame(width: fit.width, height: fit.height)
                            .position(x: fit.midX, y: fit.midY)

                        if let fingerprint {
                            Canvas { ctx, _ in
                                drawFingerprintOverlay(
                                    context: &ctx,
                                    fp: fingerprint,
                                    imageSize: image.size,
                                    fitRect: fit,
                                    showLabels: false,
                                    showTriangle: true
                                )
                            }
                            .allowsHitTesting(false)
                        }

                        if let norm = hoverNormalized.wrappedValue,
                           let croppedLoupe = cropLoupeImage(image: image, normalizedCenter: norm, zoom: loupeZoom) {
                            let loupeSize: CGFloat = 150
                            let viewX = min(max(fit.minX + loupeSize * 0.5, fit.minX + norm.x * fit.width), fit.maxX - loupeSize * 0.5)
                            let viewY = min(max(fit.minY + loupeSize * 0.5, fit.minY + norm.y * fit.height), fit.maxY - loupeSize * 0.5)

                            Image(nsImage: croppedLoupe)
                                .resizable()
                                .frame(width: loupeSize, height: loupeSize)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(isLocked.wrappedValue ? Color.yellow : titleColor, lineWidth: 2.2)
                                )
                                .shadow(color: .black.opacity(0.55), radius: 8)
                                .position(x: viewX, y: viewY)
                                .allowsHitTesting(false)
                        }
                    }
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        guard !isLocked.wrappedValue else { return }
                        switch phase {
                        case let .active(loc):
                            if fit.contains(loc), fit.width > 1, fit.height > 1 {
                                let nx = (loc.x - fit.minX) / fit.width
                                let ny = (loc.y - fit.minY) / fit.height
                                hoverNormalized.wrappedValue = CGPoint(x: nx, y: ny)
                            } else {
                                hoverNormalized.wrappedValue = nil
                            }
                        case .ended:
                            hoverNormalized.wrappedValue = nil
                        }
                    }
                    .onTapGesture { loc in
                        if fit.contains(loc), fit.width > 1, fit.height > 1 {
                            isLocked.wrappedValue.toggle()
                            if isLocked.wrappedValue {
                                let nx = (loc.x - fit.minX) / fit.width
                                let ny = (loc.y - fit.minY) / fit.height
                                hoverNormalized.wrappedValue = CGPoint(x: nx, y: ny)
                            }
                        }
                    }
                }
            }
        }
        .frame(width: frame.width, height: frame.height)
        .position(x: frame.midX, y: frame.midY)
    }

    private func croppedIfAutoZoom(image: NSImage?, fp: I3SFingerprint?) -> NSImage? {
        guard autoZoomOn, let image, let fp, let bbox = fp.boundingBox(marginPercent: 20.0),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return image
        }
        let w = CGFloat(cg.width)
        let h = CGFloat(cg.height)
        let clamped = bbox.intersection(CGRect(x: 0, y: 0, width: w, height: h))
        guard clamped.width > 24, clamped.height > 24,
              let sub = cg.cropping(to: clamped) else {
            return image
        }
        return NSImage(cgImage: sub, size: NSSize(width: clamped.width, height: clamped.height))
    }

    private func cropLoupeImage(image: NSImage, normalizedCenter: CGPoint, zoom: Double) -> NSImage? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = Double(cg.width)
        let h = Double(cg.height)
        let patchSide = max(32.0, min(w, h) / max(1.2, zoom * 1.4))
        let cx = Double(normalizedCenter.x) * w
        let cy = Double(normalizedCenter.y) * h
        let x = max(0.0, min(w - patchSide, cx - patchSide * 0.5))
        let y = max(0.0, min(h - patchSide, cy - patchSide * 0.5))
        let rect = CGRect(x: x, y: y, width: patchSide, height: patchSide)
        guard let sub = cg.cropping(to: rect) else { return nil }
        return NSImage(cgImage: sub, size: NSSize(width: patchSide, height: patchSide))
    }
}

// MARK: - PointCloud Normalized Recognition Space (`PointCloud.java`)

private struct I3SPointCloudView: View {
    let comparison: I3SComparisonResult?
    let overlayAnnotations: [OverlayAnnotationItem]
    let candidate: MatchCandidateItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                Text("I3S Aligned Point Cloud")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)

                if let comparison {
                    Text("Nr of I3S feature pairs: \(comparison.pairCount)")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.green)

                    Text(comparison.score < I3SComparisonResult.noMatchScore
                         ? String(format: "I3S Distance Score: %.2f", comparison.score)
                         : "I3S Score: No affine lock")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.yellow)
                }

                if let candidate {
                    Text("XFeat Pairs: \(candidate.localMatch) · Fused: \(String(format: "%.3f", candidate.fusedScore))")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.cyan)
                }

                Spacer()

                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Circle().stroke(.red, lineWidth: 2).frame(width: 8, height: 8)
                        Text("Unknown (Red)")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    HStack(spacing: 4) {
                        Circle().stroke(.cyan, lineWidth: 2).frame(width: 8, height: 8)
                        Text("Affine Warped Candidate (Blue)")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    HStack(spacing: 4) {
                        Rectangle().fill(.green).frame(width: 12, height: 2)
                        Text("Matched Pair Vector")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            GeometryReader { geo in
                Canvas { ctx, size in
                    guard let comp = comparison, !comp.unknownElements.isEmpty else { return }

                    var allPts: [I3SPoint2D] = []
                    allPts.append(contentsOf: comp.unknownRefs)
                    allPts.append(contentsOf: comp.candidateRefs)
                    allPts.append(contentsOf: comp.unknownElements.map { I3SPoint2D(x: $0.cx, y: $0.cy) })
                    allPts.append(contentsOf: comp.candidateElements.map { I3SPoint2D(x: $0.cx, y: $0.cy) })
                    guard !allPts.isEmpty else { return }

                    let minX = allPts.map(\.x).min() ?? 0
                    let maxX = allPts.map(\.x).max() ?? 100
                    let minY = allPts.map(\.y).min() ?? 0
                    let maxY = allPts.map(\.y).max() ?? 100
                    let spanX = max(10.0, maxX - minX)
                    let spanY = max(10.0, maxY - minY)

                    let pad = 40.0
                    let availW = max(50.0, Double(size.width) - 2 * pad)
                    let availH = max(50.0, Double(size.height) - 2 * pad)
                    let factor = min(availW / spanX, availH / spanY)
                    let offsetX = (Double(size.width) - spanX * factor) * 0.5 - minX * factor
                    let offsetY = (Double(size.height) - spanY * factor) * 0.5 - minY * factor

                    func mapPt(_ x: Double, _ y: Double) -> CGPoint {
                        CGPoint(x: x * factor + offsetX, y: y * factor + offsetY)
                    }

                    for ke in comp.candidateElements {
                        let c = mapPt(ke.cx, ke.cy)
                        let rx = max(3.0, ke.r1 * factor)
                        let ry = max(3.0, ke.r2 * factor)
                        let rect = CGRect(x: c.x - rx, y: c.y - ry, width: 2 * rx, height: 2 * ry)
                        ctx.stroke(Path(ellipseIn: rect), with: .color(.cyan.opacity(0.85)), lineWidth: 1.4)
                        ctx.fill(Path(ellipseIn: CGRect(x: c.x - 2, y: c.y - 2, width: 4, height: 4)), with: .color(.cyan))
                    }
                    for r in comp.candidateRefs {
                        let c = mapPt(r.x, r.y)
                        let rect = CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10)
                        ctx.stroke(Path(ellipseIn: rect), with: .color(.cyan), lineWidth: 2.0)
                    }

                    for ue in comp.unknownElements {
                        let c = mapPt(ue.cx, ue.cy)
                        let rx = max(3.0, ue.r1 * factor)
                        let ry = max(3.0, ue.r2 * factor)
                        let rect = CGRect(x: c.x - rx, y: c.y - ry, width: 2 * rx, height: 2 * ry)
                        ctx.stroke(Path(ellipseIn: rect), with: .color(.red.opacity(0.9)), lineWidth: 1.4)
                        ctx.fill(Path(ellipseIn: CGRect(x: c.x - 2, y: c.y - 2, width: 4, height: 4)), with: .color(.red))
                    }
                    for r in comp.unknownRefs {
                        let c = mapPt(r.x, r.y)
                        let rect = CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)
                        ctx.stroke(Path(rect), with: .color(.red), lineWidth: 2.0)
                    }

                    for pair in comp.matchedPairs {
                        let pU = mapPt(pair.unknownPoint.x, pair.unknownPoint.y)
                        let pK = mapPt(pair.candidatePoint.x, pair.candidatePoint.y)
                        var line = Path()
                        line.move(to: pU)
                        line.addLine(to: pK)
                        ctx.stroke(line, with: .color(.green), lineWidth: 2.2)
                    }
                }
            }
            .padding(12)
        }
    }
}

// MARK: - Shared Drawing Helpers (`FingerPrint.paint`, `Roi.paint`, `Keypoint.paint`)

private func aspectFitRect(imageSize: NSSize, in containerSize: CGSize) -> CGRect {
    guard imageSize.width > 0, imageSize.height > 0, containerSize.width > 0, containerSize.height > 0 else {
        return .zero
    }
    let scale = min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
    let w = imageSize.width * scale
    let h = imageSize.height * scale
    let x = (containerSize.width - w) * 0.5
    let y = (containerSize.height - h) * 0.5
    return CGRect(x: x, y: y, width: w, height: h)
}

private func drawFingerprintOverlay(
    context: inout GraphicsContext,
    fp: I3SFingerprint,
    imageSize: NSSize,
    fitRect: CGRect,
    showLabels: Bool,
    showTriangle: Bool
) {
    guard imageSize.width > 0, imageSize.height > 0 else { return }
    let scaleX = fitRect.width / imageSize.width
    let scaleY = fitRect.height / imageSize.height
    let scale = (scaleX + scaleY) * 0.5

    func mapPoint(_ p: I3SPoint2D) -> CGPoint {
        CGPoint(
            x: fitRect.minX + CGFloat(p.x) * scaleX,
            y: fitRect.minY + CGFloat(p.y) * scaleY
        )
    }

    // 1. Draw green ROI polygon (`Roi.paint` in `Roi.java`)
    if !fp.roi.vertices.isEmpty {
        var roiPath = Path()
        for (idx, v) in fp.roi.vertices.enumerated() {
            let pt = mapPoint(v)
            if idx == 0 {
                roiPath.move(to: pt)
            } else {
                roiPath.addLine(to: pt)
            }
        }
        if fp.roi.isFinal {
            context.fill(roiPath, with: .color(.green.opacity(0.08)))
        }
        context.stroke(roiPath, with: .color(.green), lineWidth: 2.2)

        for (idx, v) in fp.roi.vertices.enumerated() {
            let pt = mapPoint(v)
            let isFirst = idx == 0
            let r: CGFloat = isFirst ? 6.5 : 4.5
            let oval = CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)
            context.fill(Path(ellipseIn: oval), with: .color(isFirst && !fp.roi.isFinal ? .yellow : .green))
            context.stroke(Path(ellipseIn: oval), with: .color(.white), lineWidth: 1.5)
        }
    }

    // 2. Draw SURF/DoH keypoints (`Keypoint.paint` for `i3s_type == 2` in `Keypoint.java`)
    for (idx, kp) in fp.keypoints.enumerated() {
        let c = mapPoint(kp.center)
        let radius = max(3.5, CGFloat(kp.size * 0.5) * scale)
        let circleRect = CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2)
        context.stroke(Path(ellipseIn: circleRect), with: .color(.red), lineWidth: 1.5)

        var radLine = Path()
        radLine.move(to: c)
        radLine.addLine(to: CGPoint(x: c.x - radius, y: c.y))
        context.stroke(radLine, with: .color(.yellow), lineWidth: 1.2)

        if showLabels {
            let text = Text("\(idx)").font(.system(size: 9, weight: .bold)).foregroundColor(.yellow)
            context.draw(text, at: CGPoint(x: c.x, y: c.y - radius - 6))
        }
    }

    // 3. Draw 3 anatomical reference points (`FingerPrint.paint` in `FingerPrint.java`)
    let refs: [(I3SReferencePointKind, I3SPoint2D)] = [
        (.beakEdge, fp.ref1),
        (.innerEyeArea, fp.ref2),
        (.outerScaleEdge, fp.ref3),
    ]
    let validRefPoints = refs.filter { $0.1.isInitialized }.map { mapPoint($0.1) }
    if showTriangle && validRefPoints.count == 3 {
        var tri = Path()
        tri.move(to: validRefPoints[0])
        tri.addLine(to: validRefPoints[1])
        tri.addLine(to: validRefPoints[2])
        tri.closeSubpath()
        context.stroke(tri, with: .color(.cyan.opacity(0.7)), style: StrokeStyle(lineWidth: 1.3, dash: [5, 4]))
    }

    for (kind, pt) in refs where pt.isInitialized {
        let p = mapPoint(pt)
        let outer = CGRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14)
        context.fill(Path(ellipseIn: outer), with: .color(.blue))
        context.stroke(Path(ellipseIn: outer), with: .color(.white), lineWidth: 2.0)

        let numText = Text("\(kind.indexLabel)")
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(.white)
        context.draw(numText, at: p)

        let label = Text("\(kind.indexLabel). \(kind.title)")
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.cyan)
        context.draw(label, at: CGPoint(x: p.x, y: p.y - 15))
    }
}
