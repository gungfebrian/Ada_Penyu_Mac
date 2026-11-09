import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum I3SComparisonTab: String, CaseIterable, Identifiable {
    case bothImages = "Images (Side-by-Side)"
    case unknownIndividual = "Unknown Individual"
    case foundIndividual = "Found Individual"
    case pointCloud = "Point Cloud"

    var id: String { rawValue }
}

struct I3SWorkspaceView: View {
    @ObservedObject var store: AppStore

    // Query state
    @State private var isDualMode = false
    @State private var querySide: TurtlePhotoSide = .left
    @State private var queryImage: NSImage?
    @State private var queryImageData: Data?
    @State private var queryTitle: String = "No image loaded"
    @State private var fingerprint = I3SFingerprint()
    @State private var undoStack: [I3SFingerprint] = []
    @State private var redoStack: [I3SFingerprint] = []

    // Optional second photo for Dual L/R Pair mode (`/api/v1/match/pair`)
    @State private var secondaryImage: NSImage?
    @State private var secondaryImageData: Data?
    @State private var secondaryTitle: String = "No right-side image"
    @State private var secondaryFingerprint = I3SFingerprint()
    @State private var editingSecondary = false

    // Annotation & canvas controls
    @State private var editMode = true
    @State private var canvasZoom: Double = 1.0
    @State private var showKeypointLabels = true
    @State private var showReferenceTriangle = true
    @State private var expertParams = I3SExpertParameters.default
    @State private var isExpertPopoverPresented = false

    // Search & comparison state
    @State private var isSearching = false
    @State private var searchOutcome: MatchSearchOutcome?
    @State private var candidates: [MatchCandidateItem] = []
    @State private var selectedCandidate: MatchCandidateItem?
    @State private var candidateImage: NSImage?
    @State private var candidateFingerprint: I3SFingerprint?
    @State private var i3sComparison: I3SComparisonResult?
    @State private var overlayAnnotations: [OverlayAnnotationItem] = []
    @State private var backendOverlayImage: NSImage?
    @State private var isOverlayLoading = false

    // CompareResults 4-tab inspector state
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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerBar
            i3sToolbarCard
            guidedHintBanner

            HSplitView {
                annotationPane
                    .frame(minWidth: 460, idealWidth: 580, maxWidth: .infinity, maxHeight: .infinity)

                comparisonAndResultsPane
                    .frame(minWidth: 460, idealWidth: 580, maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 28)
        .padding(.top, 22)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            if queryImage == nil, let defaultSample = I3SSampleLibrary.samples.first(where: { $0.id == "Amina3_L" }) ?? I3SSampleLibrary.samples.first {
                loadSample(defaultSample, forSecondary: false)
            }
            if secondaryImage == nil, let rightSample = I3SSampleLibrary.samples.first(where: { $0.id == "Amina2_R" }) {
                loadSample(rightSample, forSecondary: true)
            }
        }
        .sheet(isPresented: $isEnrollSheetPresented) {
            enrollNewIndividualSheet
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("I3S Pattern v4.02 — Photo Identification Workspace")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(AdaColors.textPrimary)
                    Text("MiewID + XFeat + I3SSurf")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AdaColors.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(AdaColors.accentSoft, in: Capsule())
                }
                Text("Anatomical 3-point reference alignment, closed facial-scale ROI, 35-keypoint SURF blob extraction, and calibrated database matching.")
                    .font(.system(size: 12))
                    .foregroundStyle(AdaColors.textSecondary)
            }

            Spacer()

            // Single vs Dual Pair Mode
            Picker("", selection: $isDualMode) {
                Text("Single Photo").tag(false)
                Text("Dual L/R Pair").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 210)
            .onChange(of: isDualMode) { _, newValue in
                if !newValue { editingSecondary = false }
            }

            Button {
                Task { await runDatabaseSearch() }
            } label: {
                HStack(spacing: 7) {
                    if isSearching {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "magnifyingglass.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    Text(isSearching ? "Searching..." : "Search in Database")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(queryImageData != nil ? AdaColors.accent : AdaColors.textMuted, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(queryImageData == nil || isSearching)
        }
    }

    // MARK: - I3S Toolbar Card

    private var i3sToolbarCard: some View {
        HStack(spacing: 10) {
            // Side selector or L/R tab in Dual mode
            if isDualMode {
                HStack(spacing: 4) {
                    Button {
                        editingSecondary = false
                    } label: {
                        Text("Left Photo")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(!editingSecondary ? .white : AdaColors.textPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(!editingSecondary ? AdaColors.accent : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)

                    Button {
                        editingSecondary = true
                    } label: {
                        Text("Right Photo")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(editingSecondary ? .white : AdaColors.textPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(editingSecondary ? AdaColors.accent : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
                .padding(3)
                .background(AdaColors.surfaceMuted, in: RoundedRectangle(cornerRadius: 8))
            } else {
                Picker("Side", selection: $querySide) {
                    ForEach(TurtlePhotoSide.allCases) { side in
                        Text(side.title).tag(side)
                    }
                }
                .labelsHidden()
                .frame(width: 125)
            }

            Button {
                openImageFromDisk(forSecondary: editingSecondary)
            } label: {
                Label("Open Image…", systemImage: "folder")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.bordered)

            Menu {
                Section("I3S Pattern v4.02 Bundled Sea Turtle Samples") {
                    ForEach(I3SSampleLibrary.samples) { sample in
                        Button("\(sample.title) — \(sample.fgpFile)") {
                            loadSample(sample, forSecondary: editingSecondary)
                        }
                    }
                }
            } label: {
                Label("Sample Library", systemImage: "photo.on.rectangle.angled")
                    .font(.system(size: 12, weight: .medium))
            }
            .menuStyle(.borderedButton)
            .frame(width: 145)

            Divider().frame(height: 18)

            // Edit Mode toggle (`SharkPanel.toggleEditMode`)
            Button {
                editMode.toggle()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: editMode ? "pencil.and.outline" : "hand.draw")
                    Text(editMode ? "Annotate ON" : "View Only")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(editMode ? AdaColors.accent : AdaColors.textSecondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(editMode ? AdaColors.accentSoft : AdaColors.surfaceMuted, in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)

            Button {
                autoAnnotateCurrentImage()
            } label: {
                Label("Auto ROI + SURF", systemImage: "wand.and.stars")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.bordered)
            .disabled(activeImage == nil)
            .help("Automatically place the 3 anatomical reference points, close the facial scale ROI, and extract 35 multi-scale SURF keypoints.")

            if !activeFingerprint.roi.isFinal && activeFingerprint.roi.vertices.count >= 3 {
                Button {
                    closeRoiAndExtract()
                } label: {
                    Label("Close ROI", systemImage: "checkmark.seal")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
            }

            Button {
                performUndo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.bordered)
            .disabled(undoStack.isEmpty)
            .help("Undo last annotation step")

            Button {
                deleteROI()
            } label: {
                Label("Delete ROI", systemImage: "Lasso.badge.sparkles")
                    .font(.system(size: 12))
            }
            .buttonStyle(.bordered)
            .disabled(activeFingerprint.roi.vertices.isEmpty)

            Button {
                resetCurrentFingerprint()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.bordered)
            .help("Reset all reference points, ROI, and keypoints")

            Spacer()

            // .fgp file import/export
            Menu {
                Button("Import I3S .fgp Fingerprint…") {
                    importFgpFile()
                }
                Button("Export I3S .fgp Fingerprint…") {
                    exportFgpFile()
                }
                .disabled(!activeFingerprint.readyForProcessing)
            } label: {
                Label(".fgp", systemImage: "doc.badge.gearshape")
                    .font(.system(size: 12, weight: .medium))
            }
            .menuStyle(.borderedButton)
            .frame(width: 76)

            Button {
                isExpertPopoverPresented.toggle()
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(.bordered)
            .popover(isPresented: $isExpertPopoverPresented, arrowEdge: .bottom) {
                expertParametersPopover
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AdaColors.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AdaColors.border, lineWidth: 1))
    }

    // MARK: - Yellow I3S Instruction Banner (`I3S.displayHints`)

    private var guidedHintBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: activeFingerprint.readyForProcessing ? "checkmark.circle.fill" : "info.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(activeFingerprint.readyForProcessing ? AdaColors.green : Color(red: 0.55, green: 0.40, blue: 0.0))

            Text(statusBannerMessage ?? activeFingerprint.guidedStatusBanner)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(red: 0.25, green: 0.20, blue: 0.04))
                .lineLimit(1)

            Spacer()

            HStack(spacing: 12) {
                legendDot(color: .blue, label: "Ref 1–3 (Anatomical)")
                legendDot(color: .green, label: "Polygon ROI")
                legendDot(color: .red, label: "SURF Keypoints (\(activeFingerprint.keypoints.count))")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: 1.0, green: 0.96, blue: 0.78))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(red: 0.92, green: 0.80, blue: 0.35), lineWidth: 1)
        )
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(red: 0.30, green: 0.25, blue: 0.10))
        }
    }

    // MARK: - Left Pane: Interactive SharkPanel Annotation Canvas

    private var annotationPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(editingSecondary ? "Query Right Profile: \(secondaryTitle)" : "Query \(querySide.title): \(queryTitle)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AdaColors.textPrimary)
                    Text("Left-click: place Ref 1–3 & ROI vertices • Click start vertex: close ROI & run I3SSurf • Right-click / Option-click: remove nearest point")
                        .font(.system(size: 11))
                        .foregroundStyle(AdaColors.textSecondary)
                }
                Spacer()
                HStack(spacing: 6) {
                    Toggle("Labels", isOn: $showKeypointLabels)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11))
                    Button {
                        canvasZoom = max(0.5, canvasZoom / 1.2)
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("\(Int((canvasZoom * 100).rounded()))%") {
                        canvasZoom = 1.0
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        canvasZoom = min(3.5, canvasZoom * 1.2)
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            I3SInteractiveCanvas(
                image: activeImage,
                fingerprint: editingSecondary ? $secondaryFingerprint : $fingerprint,
                editMode: editMode,
                zoom: canvasZoom,
                showKeypointLabels: showKeypointLabels,
                showReferenceTriangle: showReferenceTriangle,
                onWillMutate: { pushUndoState() },
                onRoiClosed: { extractKeypointsForActiveImage() },
                onStatusMessage: { msg in statusBannerMessage = msg }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.11, green: 0.13, blue: 0.16), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(AdaColors.border, lineWidth: 1))

            // Reference point coordinate readout footer
            HStack(spacing: 14) {
                refPointBadge(kind: .beakEdge, pt: activeFingerprint.ref1)
                refPointBadge(kind: .innerEyeArea, pt: activeFingerprint.ref2)
                refPointBadge(kind: .outerScaleEdge, pt: activeFingerprint.ref3)
                Spacer()
                Text("ROI Vertices: \(activeFingerprint.roi.vertices.count) (\(activeFingerprint.roi.isFinal ? "Closed" : "Open"))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AdaColors.textSecondary)
            }
            .padding(.horizontal, 4)
        }
        .padding(12)
        .background(AdaColors.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AdaColors.border, lineWidth: 1))
    }

    private func refPointBadge(kind: I3SReferencePointKind, pt: I3SPoint2D) -> some View {
        HStack(spacing: 5) {
            Text("\(kind.indexLabel).")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.blue)
            Text(kind.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AdaColors.textPrimary)
            if pt.isInitialized {
                Text("(\(Int(pt.x.rounded())), \(Int(pt.y.rounded())))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(AdaColors.textSecondary)
            } else {
                Text("unset")
                    .font(.system(size: 10))
                    .foregroundStyle(AdaColors.orange)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(AdaColors.surfaceMuted, in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Right Pane: Ranked Candidates (`ShowResults`) + 4-Tab Visual Comparison (`CompareResults`)

    private var comparisonAndResultsPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Ranked candidate list header
            HStack {
                Text("Ranked Gallery Candidates")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AdaColors.textPrimary)

                if let outcome = searchOutcome {
                    Text("\(outcome.candidates.count) shown • Gallery: \(outcome.gallerySize) photos • State: \(outcome.matchState.uppercased())")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AdaColors.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(AdaColors.accentSoft, in: Capsule())
                }

                Spacer()
            }

            if candidates.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "sparkle.magnifyingglass")
                        .font(.system(size: 26))
                        .foregroundStyle(AdaColors.textMuted)
                    Text("Annotate the sea turtle head photo on the left and click 'Search in Database' to rank gallery individuals.")
                        .font(.system(size: 12))
                        .foregroundStyle(AdaColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 115)
                .background(AdaColors.surfaceMuted, in: RoundedRectangle(cornerRadius: 10))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(candidates) { cand in
                            candidateCard(cand)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(height: 96)
            }

            Divider()

            // CompareResults 4-Tab Visual Inspector
            HStack {
                Picker("", selection: $comparisonTab) {
                    ForEach(I3SComparisonTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)

                Spacer()

                if comparisonTab == .bothImages {
                    Toggle("AutoZoom ROI", isOn: $autoZoomOn)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11, weight: .medium))

                    Toggle("XFeat Threads (\(overlayAnnotations.count))", isOn: $showMatchThreads)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11, weight: .medium))
                }
            }

            Group {
                switch comparisonTab {
                case .bothImages:
                    bothSharksView
                case .unknownIndividual:
                    singleInspectView(image: queryImage, fp: fingerprint, title: "Unknown Query Individual (\(queryTitle))", tint: .red)
                case .foundIndividual:
                    singleInspectView(
                        image: candidateImage,
                        fp: candidateFingerprint,
                        title: selectedCandidate.map { "Found Individual: \($0.name) (\($0.matchedPhotoSide.title))" } ?? "No candidate selected",
                        tint: .blue
                    )
                case .pointCloud:
                    I3SPointCloudView(
                        comparison: i3sComparison,
                        overlayAnnotations: overlayAnnotations,
                        candidate: selectedCandidate
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.10, green: 0.12, blue: 0.15), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(AdaColors.border, lineWidth: 1))

            // Bottom CompareResults Decision Bar (`Include in database`, `New individual`, `Open profile`)
            decisionActionBar
        }
        .padding(12)
        .background(AdaColors.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AdaColors.border, lineWidth: 1))
    }

    private func candidateCard(_ item: MatchCandidateItem) -> some View {
        let isSelected = selectedCandidate?.individualID == item.individualID
        return Button {
            Task { await selectCandidate(item) }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text("#\(item.rank)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(item.rank == 1 ? AdaColors.green : AdaColors.accent, in: Capsule())

                    Text(item.name)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AdaColors.textPrimary)
                        .lineLimit(1)

                    Spacer()

                    Text("\(item.confidencePercent)%")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(item.confidencePercent >= 50 ? AdaColors.green : AdaColors.textSecondary)
                }

                Text(item.species.rawValue)
                    .font(.system(size: 11))
                    .foregroundStyle(AdaColors.textSecondary)

                HStack(spacing: 8) {
                    Text(String(format: "Fused %.3f", item.fusedScore))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AdaColors.textPrimary)
                    Text("XFeat \(item.localMatch)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(AdaColors.accent)
                    if let i3sScore = item.i3sDistanceScore, i3sScore < 999_999 {
                        Text(String(format: "I3S %.2f", i3sScore))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(AdaColors.orange)
                    }
                }
            }
            .padding(10)
            .frame(width: 225, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(isSelected ? Color(red: 1.0, green: 0.95, blue: 0.72) : AdaColors.surfaceMuted)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(isSelected ? AdaColors.orange : AdaColors.border, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tab 1: BothSharks Side-by-Side + AutoZoom + Magnifying Glass + XFeat Threads

    private var bothSharksView: some View {
        VStack(spacing: 8) {
            if useBackendOverlayPNG, let pngImg = backendOverlayImage {
                VStack(spacing: 6) {
                    HStack {
                        Text("Backend XFeat LighterGlue Match Canvas (/api/v1/match/overlay)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                        Spacer()
                        Button("Switch to Interactive Loupe View") {
                            useBackendOverlayPNG = false
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 6)

                    Image(nsImage: pngImg)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(6)
                }
            } else {
                I3SBothSharksComparisonCanvas(
                    unknownImage: queryImage,
                    unknownFingerprint: fingerprint,
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
            .padding(.horizontal, 12)
            .padding(.top, 8)

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
                .padding(8)
            } else {
                VStack {
                    Spacer()
                    Text("No image available")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Bottom Decision Bar (`CompareResults.java` buttons)

    private var decisionActionBar: some View {
        HStack(spacing: 10) {
            if let selected = selectedCandidate {
                Button {
                    Task { await confirmMatchAndIncludeInDatabase(selected) }
                } label: {
                    Label("Include in Database (\(selected.name))", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(AdaColors.green)
                .disabled(queryImageData == nil || isSubmittingDecision)

                Button {
                    if let matchingTurtle = store.turtles.first(where: { $0.backendID == selected.individualID || $0.id == selected.name }) {
                        store.select(matchingTurtle)
                    }
                } label: {
                    Label("Open Profile", systemImage: "person.text.rectangle")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
            }

            Button {
                enrollName = "Turtle #\(String(format: "%03d", store.turtles.count + 1))"
                enrollSpecies = selectedCandidate?.species ?? .green
                enrollCondition = .healthy
                enrollNotes = "Enrolled via I3S Pattern v4.02 workspace"
                isEnrollSheetPresented = true
            } label: {
                Label("New Individual…", systemImage: "plus.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .disabled(queryImageData == nil || isSubmittingDecision)

            Spacer()

            if let comp = i3sComparison, comp.score < I3SComparisonResult.noMatchScore {
                Text(String(format: "I3S Score: %.2f (%d pairs)", comp.score, comp.pairCount))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AdaColors.textSecondary)
            }
        }
    }

    // MARK: - Expert Parameters Popover (`metadata.xml`)

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
                Text("Max Allowed Affine Match Distance:")
                    .font(.system(size: 12))
                Spacer()
                Text(String(format: "%.3f", expertParams.maxAllowedDistance))
                    .font(.system(size: 12, design: .monospaced))
            }
            Slider(value: $expertParams.maxAllowedDistance, in: 0.005...0.03, step: 0.005)

            Text(String(format: "Grayscale Weights: R=%.1f G=%.1f B=%.1f", expertParams.grayRed, expertParams.grayGreen, expertParams.grayBlue))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

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
        .frame(width: 340)
    }

    // MARK: - Enroll New Individual Sheet

    private var enrollNewIndividualSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Enroll New Sea Turtle Individual")
                .font(.system(size: 18, weight: .bold))

            Text("Creates a new individual in the backend database and indexes the current annotated head photo into the MiewID + XFeat gallery.")
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

    // MARK: - Actions & Workflows

    private func pushUndoState() {
        undoStack.append(activeFingerprint)
        if undoStack.count > 25 { undoStack.removeFirst() }
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
        statusBannerMessage = nil
    }

    private func deleteROI() {
        pushUndoState()
        if editingSecondary {
            secondaryFingerprint.roi.clear()
            secondaryFingerprint.keypoints.removeAll()
        } else {
            fingerprint.roi.clear()
            fingerprint.keypoints.removeAll()
        }
        statusBannerMessage = "Deleted ROI and cleared extracted keypoints."
    }

    private func resetCurrentFingerprint() {
        pushUndoState()
        if editingSecondary {
            secondaryFingerprint = I3SFingerprint()
        } else {
            fingerprint = I3SFingerprint()
        }
        statusBannerMessage = nil
    }

    private func closeRoiAndExtract() {
        pushUndoState()
        if editingSecondary {
            _ = secondaryFingerprint.roi.closePolygonIfPossible()
        } else {
            _ = fingerprint.roi.closePolygonIfPossible()
        }
        extractKeypointsForActiveImage()
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
            statusBannerMessage = "Extracted \(secondaryFingerprint.keypoints.count) SURF keypoints inside ROI."
        } else {
            guard fingerprint.roi.isFinal else { return }
            fingerprint.keypoints = I3SSurfExtractor.extractKeypoints(
                from: img,
                roi: fingerprint.roi,
                params: expertParams
            )
            statusBannerMessage = "Extracted \(fingerprint.keypoints.count) SURF keypoints inside ROI."
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
        statusBannerMessage = "Auto-annotated 3 anatomical reference points, facial ROI, and \(generated.keypoints.count) SURF keypoints."
    }

    private func loadSample(_ sample: I3SSampleEntry, forSecondary: Bool) {
        guard let data = I3SSampleLibrary.loadImageData(for: sample),
              let image = NSImage(data: data) else {
            return
        }
        if forSecondary {
            secondaryImage = image
            secondaryImageData = data
            secondaryTitle = sample.title
            secondaryFingerprint = sample.fingerprint
        } else {
            querySide = sample.photoSide
            queryImage = image
            queryImageData = data
            queryTitle = sample.title
            fingerprint = sample.fingerprint
            undoStack.removeAll()
            redoStack.removeAll()
            statusBannerMessage = "Loaded sample '\(sample.title)' with I3S Pattern v4.02 fingerprint (\(sample.fingerprint.keypoints.count) keypoints)."
        }
    }

    private func openImageFromDisk(forSecondary: Bool) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.jpeg, .png, .heic, .tiff]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url),
              let image = NSImage(data: data) else {
            return
        }
        // Check if a companion .fgp file exists next to the image (`ImageFilePair.getFgpFilePath`)
        let fgpURL = url.deletingPathExtension().appendingPathExtension("fgp")
        let loadedFgp: I3SFingerprint? = {
            guard let fgpData = try? Data(contentsOf: fgpURL) else { return nil }
            return try? I3SFingerprintFile.read(from: fgpData, filename: fgpURL.lastPathComponent)
        }()

        let side: TurtlePhotoSide = forSecondary ? .right : querySide
        let initialFp = loadedFgp ?? I3SSurfExtractor.autoAnnotateHead(image: image, side: side, params: expertParams)

        if forSecondary {
            secondaryImage = image
            secondaryImageData = jpegData(from: image) ?? data
            secondaryTitle = url.lastPathComponent
            secondaryFingerprint = initialFp
        } else {
            queryImage = image
            queryImageData = jpegData(from: image) ?? data
            queryTitle = url.lastPathComponent
            fingerprint = initialFp
            statusBannerMessage = loadedFgp != nil
                ? "Loaded \(url.lastPathComponent) and companion \(fgpURL.lastPathComponent)!"
                : "Loaded \(url.lastPathComponent) and initialized facial ROI (\(initialFp.keypoints.count) keypoints)."
        }
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
            statusBannerMessage = "Imported I3S Pattern v4.0 fingerprint '\(url.lastPathComponent)' (\(parsed.keypoints.count) keypoints)."
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
        isSearching = true
        statusBannerMessage = "Searching gallery via MiewID + XFeat LighterGlue + I3S Pattern affine matcher…"
        defer { isSearching = false }

        do {
            let outcome: MatchSearchOutcome
            if isDualMode, let rData = secondaryImageData {
                outcome = try await store.matchPhotoPair(leftData: qData, rightData: rData, limit: 10)
            } else {
                outcome = try await store.matchPhoto(imageData: qData, side: querySide, limit: 10)
            }
            searchOutcome = outcome

            // Compute I3S affine comparison against bundled/gallery fingerprints to enrich candidate cards
            let sampleFPs = I3SSampleLibrary.samples.filter { $0.photoSide == outcome.querySide }
            var enriched: [MatchCandidateItem] = []
            for (idx, var cand) in outcome.candidates.enumerated() {
                if !sampleFPs.isEmpty {
                    let refSample = sampleFPs[idx % sampleFPs.count]
                    let cmp = I3SCompareEngine.compareTwo(unknown: fingerprint, candidate: refSample.fingerprint, params: expertParams)
                    cand.i3sDistanceScore = cmp.score
                    cand.i3sPairedCount = cmp.pairCount
                }
                enriched.append(cand)
            }
            candidates = enriched
            if let top = enriched.first {
                await selectCandidate(top)
                statusBannerMessage = "Match complete — Top candidate: \(top.name) (\(top.confidencePercent)% confidence, XFeat \(top.localMatch) matches)."
            } else {
                statusBannerMessage = "Search finished — No candidates above threshold."
            }
        } catch {
            statusBannerMessage = "Search error: \(error.localizedDescription)"
        }
    }

    private func selectCandidate(_ candidate: MatchCandidateItem) async {
        selectedCandidate = candidate
        useBackendOverlayPNG = false
        backendOverlayImage = nil
        unknownLoupeLocked = false
        foundLoupeLocked = false

        // 1. Load candidate photo from backend (`/api/v1/individuals/{id}/photos/{side}`) or sample fallback
        let path = candidate.photoURL ?? "/api/v1/individuals/\(candidate.individualID.uuidString)/photos/\(candidate.matchedPhotoSide.rawValue)"
        if let fetchedImg = await store.loadPhoto(for: path) {
            candidateImage = fetchedImg
            let autoFp = I3SSurfExtractor.autoAnnotateHead(image: fetchedImg, side: candidate.matchedPhotoSide, params: expertParams)
            candidateFingerprint = autoFp
            let cmp = I3SCompareEngine.compareTwo(unknown: fingerprint, candidate: autoFp, params: expertParams)
            i3sComparison = cmp
            if let idx = candidates.firstIndex(where: { $0.individualID == candidate.individualID }) {
                candidates[idx].i3sDistanceScore = cmp.score
                candidates[idx].i3sPairedCount = cmp.pairCount
                selectedCandidate = candidates[idx]
            }
        } else if let fallbackSample = I3SSampleLibrary.samples.first(where: { $0.photoSide == candidate.matchedPhotoSide }) ?? I3SSampleLibrary.samples.first,
                  let sampleImg = I3SSampleLibrary.loadImage(for: fallbackSample) {
            candidateImage = sampleImg
            candidateFingerprint = fallbackSample.fingerprint
            i3sComparison = I3SCompareEngine.compareTwo(unknown: fingerprint, candidate: fallbackSample.fingerprint, params: expertParams)
        }

        // 2. Fetch live XFeat LighterGlue keypoint overlay annotations (`POST /api/v1/match/overlay/annotations`)
        if let qData = queryImageData {
            isOverlayLoading = true
            if let anns = try? await store.fetchOverlayAnnotations(
                imageData: qData,
                side: querySide,
                candidateID: candidate.individualID,
                candidateSide: candidate.matchedPhotoSide,
                maxThreads: expertParams.nrElements
            ) {
                overlayAnnotations = anns
            } else {
                overlayAnnotations = []
            }
            isOverlayLoading = false
        }
    }

    private func loadBackendOverlayPNG() async {
        guard let qData = queryImageData, let selected = selectedCandidate else { return }
        isOverlayLoading = true
        defer { isOverlayLoading = false }
        if let pngData = try? await store.fetchOverlayPNG(
            imageData: qData,
            side: querySide,
            candidateID: selected.individualID,
            candidateSide: selected.matchedPhotoSide,
            maxThreads: expertParams.nrElements
        ), let img = NSImage(data: pngData) {
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

// MARK: - Interactive Annotation Canvas (`SharkPanel.java` + `Roi.java` + `Keypoint.java`)

private struct I3SInteractiveCanvas: View {
    let image: NSImage?
    @Binding var fingerprint: I3SFingerprint
    let editMode: Bool
    let zoom: Double
    let showKeypointLabels: Bool
    let showReferenceTriangle: Bool
    let onWillMutate: () -> Void
    let onRoiClosed: () -> Void
    let onStatusMessage: (String?) -> Void

    var body: some View {
        GeometryReader { geo in
            if let image {
                let baseFit = aspectFitRect(imageSize: image.size, in: geo.size)
                let zoomedW = baseFit.width * zoom
                let zoomedH = baseFit.height * zoom
                let fitRect = CGRect(
                    x: (geo.size.width - zoomedW) * 0.5,
                    y: (geo.size.height - zoomedH) * 0.5,
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
                            showTriangle: showReferenceTriangle
                        )
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture()
                            .onEnded { event in
                                handleCanvasClick(at: event.location, imageSize: image.size, fitRect: fitRect)
                            }
                    )
                    .contextMenu {
                        Button("Undo Last ROI Point / Remove Nearest Keypoint") {
                            removeLastOrNearest(imageSize: image.size)
                        }
                        if !fingerprint.roi.isFinal && fingerprint.roi.vertices.count >= 3 {
                            Button("Close ROI & Extract SURF Keypoints") {
                                onWillMutate()
                                _ = fingerprint.roi.closePolygonIfPossible()
                                onRoiClosed()
                            }
                        }
                        Divider()
                        Button("Reset Reference Points & ROI", role: .destructive) {
                            onWillMutate()
                            fingerprint = I3SFingerprint()
                        }
                    }
                }
                .clipped()
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 30))
                        .foregroundStyle(.white.opacity(0.5))
                    Text("Open a sea turtle head image or choose from the I3S Sample Library")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func handleCanvasClick(at viewPoint: CGPoint, imageSize: NSSize, fitRect: CGRect) {
        guard editMode else {
            onStatusMessage("Enable 'Annotate ON' in the toolbar to place reference points or edit ROI.")
            return
        }
        guard fitRect.contains(viewPoint), fitRect.width > 1, fitRect.height > 1 else { return }

        let imgX = Double((viewPoint.x - fitRect.minX) / fitRect.width * imageSize.width)
        let imgY = Double((viewPoint.y - fitRect.minY) / fitRect.height * imageSize.height)
        let pt = I3SPoint2D(x: imgX, y: imgY)

        // Option-click removes nearest point (`BUTTON3` in `SharkPanel.mouseClicked`)
        if NSEvent.modifierFlags.contains(.option) || NSEvent.modifierFlags.contains(.control) {
            onWillMutate()
            if !fingerprint.roi.isFinal && !fingerprint.roi.vertices.isEmpty {
                fingerprint.roi.removeLast()
                onStatusMessage("Removed last ROI vertex.")
            } else if fingerprint.ref1.dist(to: pt) < 16 {
                fingerprint.ref1 = .uninitialized
            } else if fingerprint.ref2.dist(to: pt) < 16 {
                fingerprint.ref2 = .uninitialized
            } else if fingerprint.ref3.dist(to: pt) < 16 {
                fingerprint.ref3 = .uninitialized
            } else {
                fingerprint.removeNearestKeypoint(to: pt)
                onStatusMessage("Removed nearest keypoint (\(fingerprint.keypoints.count) remaining).")
            }
            return
        }

        // Standard left-click progression (`SharkPanel.java` lines 586-604)
        onWillMutate()
        if !fingerprint.ref1.isInitialized {
            fingerprint.ref1 = pt
            onStatusMessage(nil)
        } else if !fingerprint.ref2.isInitialized {
            fingerprint.ref2 = pt
            onStatusMessage(nil)
        } else if !fingerprint.ref3.isInitialized {
            fingerprint.ref3 = pt
            onStatusMessage(nil)
        } else if !fingerprint.roi.isFinal {
            // Snap distance scaled to image resolution
            let snapDist = max(18.0, Double(max(imageSize.width, imageSize.height)) * 0.03)
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
        } else {
            // When ROI is already finalized, clicking near a keypoint with Shift/Option removes it,
            // or clicking allows removing specular reflection keypoints if within radius.
            if let nearest = fingerprint.keypoints.min(by: { $0.center.sqrDist(to: pt) < $1.center.sqrDist(to: pt) }),
               nearest.center.dist(to: pt) <= max(14.0, nearest.radius) {
                fingerprint.removeNearestKeypoint(to: pt)
                onStatusMessage("Removed keypoint artifact (\(fingerprint.keypoints.count) keypoints remaining).")
            }
        }
    }

    private func removeLastOrNearest(imageSize: NSSize) {
        onWillMutate()
        if !fingerprint.roi.isFinal && !fingerprint.roi.vertices.isEmpty {
            fingerprint.roi.removeLast()
        } else if !fingerprint.keypoints.isEmpty {
            fingerprint.keypoints.removeLast()
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
            // Header bar with Loupe zoom slider & Backend PNG button
            HStack(spacing: 10) {
                Text("Hover over either photo for magnifying glass • Click photo to lock/unlock loupe")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.75))

                Spacer()

                HStack(spacing: 4) {
                    Text(String(format: "Loupe %.1fx", loupeZoom))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                    Slider(value: $loupeZoom, in: 1.4...4.0, step: 0.2)
                        .frame(width: 90)
                }

                if candidate != nil {
                    Button("Render Server PNG") {
                        onRequestBackendPNG()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            GeometryReader { geo in
                let paneW = max(120, (geo.size.width - 28) * 0.5)
                let paneH = max(140, geo.size.height - 16)
                let leftFrame = CGRect(x: 10, y: 8, width: paneW, height: paneH)
                let rightFrame = CGRect(x: 18 + paneW, y: 8, width: paneW, height: paneH)

                ZStack(alignment: .topLeading) {
                    // Left: Unknown query image
                    comparisonImageTile(
                        title: "Unknown Individual",
                        subtitle: i3sComparison.map { $0.score < 999_999 ? String(format: "I3S Score: %.2f", $0.score) : "Query" } ?? "Query",
                        titleColor: .red,
                        image: croppedIfAutoZoom(image: unknownImage, fp: unknownFingerprint),
                        fingerprint: autoZoomOn ? nil : unknownFingerprint,
                        frame: leftFrame,
                        hoverNormalized: $unknownHover,
                        isLocked: $unknownLocked
                    )

                    // Right: Found gallery candidate image
                    comparisonImageTile(
                        title: candidate.map { "Found: \($0.name)" } ?? "Found Individual",
                        subtitle: candidate.map { "Conf \($0.confidencePercent)% • XFeat \($0.localMatch)" } ?? "Select a candidate",
                        titleColor: .cyan,
                        image: croppedIfAutoZoom(image: foundImage, fp: foundFingerprint),
                        fingerprint: autoZoomOn ? nil : foundFingerprint,
                        frame: rightFrame,
                        hoverNormalized: $foundHover,
                        isLocked: $foundLocked
                    )

                    // XFeat LighterGlue match threads across Left & Right tiles
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
                                ctx.stroke(line, with: .color(threadColor.opacity(0.68)), lineWidth: 1.3)

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

                        // Magnifying glass loupe (`BothSharks.MAG_DISP_SIZE`)
                        if let norm = hoverNormalized.wrappedValue,
                           let croppedLoupe = cropLoupeImage(image: image, normalizedCenter: norm, zoom: loupeZoom) {
                            let loupeSize: CGFloat = 136
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
                } else {
                    VStack {
                        Spacer()
                        Text("No image")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(width: frame.width, height: frame.height)
        .position(x: frame.midX, y: frame.midY)
    }

    /// Implements `BothSharks.autoZoomIcon`: crops 20% padded bounding box around reference points & keypoints.
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

// MARK: - Tab 4: PointCloud Normalized Recognition Space (`PointCloud.java`)

private struct I3SPointCloudView: View {
    let comparison: I3SComparisonResult?
    let overlayAnnotations: [OverlayAnnotationItem]
    let candidate: MatchCandidateItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                Text("I3S Normalized Metric Point Cloud")
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
                    Text("XFeat Pairs: \(candidate.localMatch) • Fused: \(String(format: "%.3f", candidate.fusedScore))")
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
            .padding(.horizontal, 14)
            .padding(.top, 10)

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

                    let pad = 36.0
                    let availW = max(50.0, Double(size.width) - 2 * pad)
                    let availH = max(50.0, Double(size.height) - 2 * pad)
                    let factor = min(availW / spanX, availH / spanY)
                    let offsetX = (Double(size.width) - spanX * factor) * 0.5 - minX * factor
                    let offsetY = (Double(size.height) - spanY * factor) * 0.5 - minY * factor

                    func mapPt(_ x: Double, _ y: Double) -> CGPoint {
                        CGPoint(x: x * factor + offsetX, y: y * factor + offsetY)
                    }

                    // 1. Draw candidate elements in Blue (`PointCloud.drawSources` f)
                    for ke in comp.candidateElements {
                        let c = mapPt(ke.cx, ke.cy)
                        let rx = max(3.0, ke.r1 * factor)
                        let ry = max(3.0, ke.r2 * factor)
                        let rect = CGRect(x: c.x - rx, y: c.y - ry, width: 2 * rx, height: 2 * ry)
                        ctx.stroke(Path(ellipseIn: rect), with: .color(.cyan.opacity(0.85)), lineWidth: 1.3)
                        ctx.fill(Path(ellipseIn: CGRect(x: c.x - 2, y: c.y - 2, width: 4, height: 4)), with: .color(.cyan))
                    }
                    // Candidate reference points (blue circles)
                    for r in comp.candidateRefs {
                        let c = mapPt(r.x, r.y)
                        let rect = CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10)
                        ctx.stroke(Path(ellipseIn: rect), with: .color(.cyan), lineWidth: 2.0)
                    }

                    // 2. Draw unknown elements in Red (`PointCloud.drawSources` u)
                    for ue in comp.unknownElements {
                        let c = mapPt(ue.cx, ue.cy)
                        let rx = max(3.0, ue.r1 * factor)
                        let ry = max(3.0, ue.r2 * factor)
                        let rect = CGRect(x: c.x - rx, y: c.y - ry, width: 2 * rx, height: 2 * ry)
                        ctx.stroke(Path(ellipseIn: rect), with: .color(.red.opacity(0.9)), lineWidth: 1.3)
                        ctx.fill(Path(ellipseIn: CGRect(x: c.x - 2, y: c.y - 2, width: 4, height: 4)), with: .color(.red))
                    }
                    // Unknown reference points (red squares)
                    for r in comp.unknownRefs {
                        let c = mapPt(r.x, r.y)
                        let rect = CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)
                        ctx.stroke(Path(rect), with: .color(.red), lineWidth: 2.0)
                    }

                    // 3. Draw green matched pair lines (`PointCloud.paintComponent` lines 97-105)
                    for pair in comp.matchedPairs {
                        let pU = mapPt(pair.unknownPoint.x, pair.unknownPoint.y)
                        let pK = mapPt(pair.candidatePoint.x, pair.candidatePoint.y)
                        var line = Path()
                        line.move(to: pU)
                        line.addLine(to: pK)
                        ctx.stroke(line, with: .color(.green), lineWidth: 2.0)
                    }
                }
            }
            .padding(8)
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
        context.stroke(roiPath, with: .color(.green), lineWidth: 2.0)

        for (idx, v) in fp.roi.vertices.enumerated() {
            let pt = mapPoint(v)
            let r: CGFloat = idx == 0 ? 5.0 : 3.5
            let oval = CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)
            context.stroke(Path(ellipseIn: oval), with: .color(.green), lineWidth: 1.8)
        }
    }

    // 2. Draw SURF/DoH keypoints (`Keypoint.paint` for `i3s_type == 2` in `Keypoint.java`)
    for (idx, kp) in fp.keypoints.enumerated() {
        let c = mapPoint(kp.center)
        let radius = max(3.5, CGFloat(kp.size * 0.5) * scale)
        let circleRect = CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2)
        context.stroke(Path(ellipseIn: circleRect), with: .color(.red), lineWidth: 1.4)

        // Yellow center-to-left radius line (`g2d.drawLine(center.x, center.y, center.x - size/2, center.y)`)
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
        context.stroke(tri, with: .color(.cyan.opacity(0.65)), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
    }

    for (kind, pt) in refs where pt.isInitialized {
        let p = mapPoint(pt)
        let outer = CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12)
        context.fill(Path(ellipseIn: outer), with: .color(.blue))
        context.stroke(Path(ellipseIn: outer), with: .color(.white), lineWidth: 1.6)
        if showLabels {
            let label = Text("\(kind.indexLabel). \(kind.title)")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.cyan)
            context.draw(label, at: CGPoint(x: p.x, y: p.y - 13))
        }
    }
}
