import AppKit
import SwiftUI

// MARK: - Studio Inputs & Modes

struct PatternComparisonTarget: Identifiable {
    let id: String
    let rank: Int
    let title: String
    let subtitle: String
    let side: TurtlePhotoSide
    let sideMatches: Bool
    let image: NSImage?
    let sampleEntry: I3SSampleEntry?
    let fingerprint: I3SFingerprint?
    let customROI: [ScalePoint]?
}

enum PatternStudioMode: String, CaseIterable, Identifiable {
    case oneVsThree = "1 vs 3"
    case oneToOne = "1 : 1"
    case overlay = "Overlay"

    var id: String { rawValue }
}

enum PatternOneVsThreeArrangement: String, CaseIterable, Identifiable {
    case quad = "2×2 Grid"
    case row = "1 + 3 Row"

    var id: String { rawValue }
}

enum PatternContourDisplayStyle: String, CaseIterable, Identifiable {
    case scaleMesh = "Scale Mesh"
    case inkContours = "Ink"
    case combined = "Both"

    var id: String { rawValue }
}

private struct PatternExtractionCacheKey: Equatable {
    let targetID: String
    let imageID: ObjectIdentifier?
    let sensitivityBucket: Int
    let smoothnessBucket: Int
    let roiSignature: Int
}

private struct ExtractedTargetData: Equatable {
    let cacheKey: PatternExtractionCacheKey
    let roi: [ScalePoint]
    let patterns: [DetectedScalePattern]
    let mesh: ScaleSutureMesh
    let autoRefs: (ref1: ScalePoint, ref2: ScalePoint, ref3: ScalePoint)?

    static func == (lhs: ExtractedTargetData, rhs: ExtractedTargetData) -> Bool {
        lhs.cacheKey == rhs.cacheKey && lhs.roi == rhs.roi && lhs.patterns == rhs.patterns && lhs.mesh == rhs.mesh
    }
}

// MARK: - Reusable Pattern-Only Contour & Manual Pair Calculator Studio

/// Visual-first sea turtle scale pattern studio supporting polygonal scale suture mesh
/// (Watershed suture tessellation), smooth melanin contours, 1-vs-3 comparison,
/// interactive junction editing, and manual numbered pair calculation.
struct PatternContourStudioView: View {
    let query: PatternComparisonTarget
    let candidates: [PatternComparisonTarget]
    @Binding var selectedCandidateID: String
    @Binding var mode: PatternStudioMode
    var linesOnlyInitial: Bool = false
    var initialShowNumbers: Bool = true
    var onSelectCandidateID: ((String) -> Void)? = nil
    var onConfirmCandidate: ((PatternComparisonTarget) -> Void)? = nil
    var onRejectCandidate: ((PatternComparisonTarget) -> Void)? = nil

    @State private var arrangement: PatternOneVsThreeArrangement = .quad
    @State private var displayStyle: PatternContourDisplayStyle = .scaleMesh
    @State private var linesOnly: Bool
    @State private var patternOnlyMask = false
    @State private var showNumbers: Bool
    @State private var showMatchThreads = true
    @State private var config = PatternExtractionConfig()
    @State private var meshColor: Color = Color(red: 0.94, green: 0.16, blue: 0.14)
    @State private var contourColor: Color = .cyan
    @State private var candidateColor: Color = AdaColors.orange
    @State private var fillOpacity: Double = 0.16
    @State private var overlayBlend: Double = 0.50

    @State private var zoom: Double = 1.0
    @State private var pan: CGSize = .zero
    @State private var isEditingROI = false
    @State private var isEditingMesh = false
    @State private var roiEditingTargetID: String? = nil
    @State private var showSettingsPopover = false

    @State private var extractedByID: [String: ExtractedTargetData] = [:]
    @State private var editedROIs: [String: [ScalePoint]] = [:]
    @State private var editedMeshes: [String: ScaleSutureMesh] = [:]

    // Manual & assisted scale pairing state
    @State private var activeQueryNumber: Int? = nil
    @State private var activePairFeedback: PatternPairDetail? = nil
    @State private var pairsByCandidateID: [String: [PatternPairLink]] = [:]
    @State private var isSyncing = false

    init(
        query: PatternComparisonTarget,
        candidates: [PatternComparisonTarget],
        selectedCandidateID: Binding<String>,
        mode: Binding<PatternStudioMode>,
        linesOnlyInitial: Bool = false,
        initialShowNumbers: Bool = true,
        onSelectCandidateID: ((String) -> Void)? = nil,
        onConfirmCandidate: ((PatternComparisonTarget) -> Void)? = nil,
        onRejectCandidate: ((PatternComparisonTarget) -> Void)? = nil
    ) {
        self.query = query
        self.candidates = candidates
        self._selectedCandidateID = selectedCandidateID
        self._mode = mode
        self.linesOnlyInitial = linesOnlyInitial
        self.initialShowNumbers = initialShowNumbers
        self.onSelectCandidateID = onSelectCandidateID
        self.onConfirmCandidate = onConfirmCandidate
        self.onRejectCandidate = onRejectCandidate
        self._linesOnly = State(initialValue: linesOnlyInitial)
        self._showNumbers = State(initialValue: initialShowNumbers)
    }

    private var selectedCandidate: PatternComparisonTarget? {
        candidates.first { $0.id == selectedCandidateID } ?? candidates.first
    }

    /// Up to 3 top candidates displayed alongside the Query in 1-vs-3 mode.
    private var topThreeCandidates: [PatternComparisonTarget] {
        var top = Array(candidates.prefix(3))
        if let sel = selectedCandidate, !top.contains(where: { $0.id == sel.id }), top.count == 3 {
            top[2] = sel
        }
        return top
    }

    private var extractionSignature: String {
        let qKey = "\(query.id):\(query.image.map { ObjectIdentifier($0).hashValue } ?? 0)"
        let cKeys = candidates.prefix(4).map { "\($0.id):\($0.image.map { ObjectIdentifier($0).hashValue } ?? 0)" }.joined(separator: "|")
        let s = Int((config.sensitivity * 100).rounded())
        let sm = Int((config.smoothness * 100).rounded())
        let roiHash = editedROIs.keys.sorted().map { "\($0):\(editedROIs[$0]?.count ?? 0)" }.joined(separator: ",")
        return "\(qKey)|\(cKeys)|\(s)|\(sm)|\(roiHash)"
    }

    var body: some View {
        VStack(spacing: 0) {
            compactToolbar
            Divider().overlay(Color.white.opacity(0.08))

            ZStack {
                Color(red: 13 / 255, green: 26 / 255, blue: 40 / 255)

                switch mode {
                case .oneVsThree:
                    oneVsThreeCanvas
                case .oneToOne:
                    oneToOneCanvas
                case .overlay:
                    overlayWarpCanvas
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().overlay(Color.white.opacity(0.08))
            calculatorStrip
        }
        .task(id: extractionSignature) {
            await extractAllTargets()
        }
        .onAppear {
            if linesOnlyInitial { linesOnly = true }
        }
    }

    // MARK: - Single Slim Control Strip (Zero Paragraph Clutter)

    private var compactToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Picker("Mode", selection: $mode) {
                    ForEach(PatternStudioMode.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 224)

                if mode == .oneVsThree {
                    Picker("Grid", selection: $arrangement) {
                        ForEach(PatternOneVsThreeArrangement.allCases) { arr in
                            Text(arr.rawValue).tag(arr)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 138)
                }

                Picker("Style", selection: $displayStyle) {
                    ForEach(PatternContourDisplayStyle.allCases) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 196)
                .help("Scale Mesh traces the polygonal sutures between scales; Ink traces dark spots")

                Divider().frame(height: 18)

                chipToggle("ROI Mask", icon: "viewfinder", isOn: $patternOnlyMask)
                chipToggle("Lines", icon: "scribble.variable", isOn: $linesOnly)
                chipToggle("#", icon: "number", isOn: $showNumbers)

                if mode == .oneToOne {
                    chipToggle("Threads", icon: "point.topleft.down.to.point.bottomright.curvepath", isOn: $showMatchThreads)
                }

                Divider().frame(height: 18)

                // Edit scale mesh vertices directly
                Button {
                    isEditingMesh.toggle()
                    if isEditingMesh { isEditingROI = false; roiEditingTargetID = nil }
                } label: {
                    Label(isEditingMesh ? "Done Mesh" : "Edit Mesh", systemImage: isEditingMesh ? "checkmark.circle.fill" : "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isEditingMesh ? .white : AdaColors.navy)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(isEditingMesh ? AdaColors.navy : AdaColors.canvas, in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Drag any shared suture junction point directly on the photo")

                // Direct ROI adjustment toggle
                Button {
                    isEditingMesh = false
                    if isEditingROI {
                        isEditingROI = false
                        roiEditingTargetID = nil
                    } else {
                        isEditingROI = true
                        roiEditingTargetID = query.id
                    }
                } label: {
                    Label(isEditingROI ? "Done ROI" : "Set ROI", systemImage: isEditingROI ? "checkmark.circle.fill" : "crop")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isEditingROI ? .white : AdaColors.navy)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(isEditingROI ? AdaColors.navy : AdaColors.canvas, in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Drag a new pattern region box directly over any turtle photo")

                // Compact tuning popover (keeps main view unobstructed!)
                Button {
                    showSettingsPopover.toggle()
                } label: {
                    Label("Tune", systemImage: "slider.horizontal.3")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AdaColors.ink)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(AdaColors.canvas, in: Capsule())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showSettingsPopover, arrowEdge: .bottom) {
                    tuningPopover
                }

                Spacer(minLength: 8)

                if isSyncing {
                    ProgressView().controlSize(.mini)
                }

                // Synced zoom & focus
                HStack(spacing: 4) {
                    Button { zoom = max(1.0, zoom - 0.25); if zoom == 1.0 { pan = .zero } } label: {
                        Image(systemName: "minus.magnifyingglass").frame(width: 22, height: 22)
                    }.buttonStyle(.plain)

                    Button {
                        zoom = 1.0; pan = .zero
                    } label: {
                        Text("\(Int((zoom * 100).rounded()))%")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .frame(width: 40)
                    }.buttonStyle(.plain)

                    Button { zoom = min(3.5, zoom + 0.25) } label: {
                        Image(systemName: "plus.magnifyingglass").frame(width: 22, height: 22)
                    }.buttonStyle(.plain)
                }
                .font(.system(size: 11))
                .foregroundStyle(AdaColors.ink)
                .padding(.horizontal, 6)
                .frame(height: 26)
                .background(AdaColors.canvas, in: Capsule())

                Button {
                    focusOnQueryPattern()
                } label: {
                    Text("Focus ROI")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AdaColors.ink)
                        .padding(.horizontal, 9)
                        .frame(height: 26)
                        .background(AdaColors.canvas, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
        }
        .background(AdaColors.card)
    }

    private func chipToggle(_ label: String, icon: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10, weight: .semibold))
                Text(label).font(.system(size: 11, weight: isOn.wrappedValue ? .semibold : .medium))
            }
            .foregroundStyle(isOn.wrappedValue ? .white : AdaColors.ink)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(isOn.wrappedValue ? AdaColors.navy : AdaColors.canvas, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var tuningPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pattern Contour Extraction")
                .font(.system(size: 12, weight: .bold))

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Scale Sensitivity").font(.system(size: 11))
                    Spacer()
                    Text("\(Int((config.sensitivity * 100).rounded()))%")
                        .font(.system(size: 11, design: .monospaced))
                }
                Slider(value: $config.sensitivity, in: 0.15...0.85, step: 0.05)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Contour Smoothness").font(.system(size: 11))
                    Spacer()
                    Text("\(Int((config.smoothness * 100).rounded()))%")
                        .font(.system(size: 11, design: .monospaced))
                }
                Slider(value: $config.smoothness, in: 0.0...1.0, step: 0.05)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Pattern Fill").font(.system(size: 11))
                    Spacer()
                    Text("\(Int((fillOpacity * 100).rounded()))%")
                        .font(.system(size: 11, design: .monospaced))
                }
                Slider(value: $fillOpacity, in: 0.0...0.45, step: 0.05)
            }

            HStack(spacing: 10) {
                ColorPicker("Mesh", selection: $meshColor, supportsOpacity: false)
                ColorPicker("Query", selection: $contourColor, supportsOpacity: false)
                ColorPicker("Cand", selection: $candidateColor, supportsOpacity: false)
            }
            .font(.system(size: 11))

            HStack {
                Button("Reset Defaults") {
                    editedROIs.removeAll()
                    editedMeshes.removeAll()
                    config = PatternExtractionConfig()
                    fillOpacity = 0.16
                    meshColor = Color(red: 0.94, green: 0.16, blue: 0.14)
                    contourColor = .cyan
                    candidateColor = AdaColors.orange
                }
                .controlSize(.small)
                Spacer()
                Button("Done") { showSettingsPopover = false }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .frame(width: 260)
    }

    // MARK: - 1 vs 3 Contour Canvas (Compare 1 Photo Pattern to 3 Candidate Patterns)

    private var oneVsThreeCanvas: some View {
        let three = topThreeCandidates
        return GeometryReader { geo in
            let spacing: CGFloat = 6
            if arrangement == .quad {
                let tileW = max(160, (geo.size.width - spacing * 3) / 2)
                let tileH = max(140, (geo.size.height - spacing * 3) / 2)
                VStack(spacing: spacing) {
                    HStack(spacing: spacing) {
                        queryPatternTile
                            .frame(width: tileW, height: tileH)

                        if three.indices.contains(0) {
                            candidatePatternTile(three[0])
                                .frame(width: tileW, height: tileH)
                        } else {
                            emptySlotCard(rank: 1).frame(width: tileW, height: tileH)
                        }
                    }
                    HStack(spacing: spacing) {
                        if three.indices.contains(1) {
                            candidatePatternTile(three[1])
                                .frame(width: tileW, height: tileH)
                        } else {
                            emptySlotCard(rank: 2).frame(width: tileW, height: tileH)
                        }
                        if three.indices.contains(2) {
                            candidatePatternTile(three[2])
                                .frame(width: tileW, height: tileH)
                        } else {
                            emptySlotCard(rank: 3).frame(width: tileW, height: tileH)
                        }
                    }
                }
                .padding(spacing)
            } else {
                // 1 Query on Left (34%) + 3 Candidates Side-by-Side on Right
                let leftW = max(240, (geo.size.width - spacing * 5) * 0.34)
                let candW = max(150, (geo.size.width - leftW - spacing * 5) / 3)
                let tileH = max(180, geo.size.height - spacing * 2)
                HStack(spacing: spacing) {
                    queryPatternTile
                        .frame(width: leftW, height: tileH)
                    ForEach(0..<3, id: \.self) { idx in
                        if three.indices.contains(idx) {
                            candidatePatternTile(three[idx])
                                .frame(width: candW, height: tileH)
                        } else {
                            emptySlotCard(rank: idx + 1)
                                .frame(width: candW, height: tileH)
                        }
                    }
                }
                .padding(spacing)
            }
        }
    }

    // MARK: - 1 : 1 Interactive Pattern Contour + Cross-Photo Thread Canvas

    private var oneToOneCanvas: some View {
        let sel = selectedCandidate
        let activePairs = sel.flatMap { pairsByCandidateID[$0.id] } ?? []
        let qPatterns = activePatterns(for: query.id)
        let cPatterns = sel.map { activePatterns(for: $0.id) } ?? []

        return GeometryReader { geo in
            ZStack {
                HStack(spacing: 4) {
                    queryPatternTile
                    if let sel {
                        candidatePatternTile(sel)
                    } else {
                        emptySlotCard(rank: 1)
                    }
                }
                .padding(6)

                if showMatchThreads,
                   let qImg = query.image,
                   let cImg = sel?.image,
                   !qPatterns.isEmpty,
                   !cPatterns.isEmpty,
                   !activePairs.isEmpty {
                    let halfW = (geo.size.width - 16) * 0.5
                    let tileSize = CGSize(width: halfW, height: geo.size.height - 12)
                    let qFit = zoomedAspectFitRect(imageSize: qImg.size, container: tileSize)
                    let cFit = zoomedAspectFitRect(imageSize: cImg.size, container: tileSize)
                    let qByNum = Dictionary(uniqueKeysWithValues: qPatterns.map { ($0.number, $0) })
                    let cByNum = Dictionary(uniqueKeysWithValues: cPatterns.map { ($0.number, $0) })

                    Canvas { ctx, _ in
                        for pair in activePairs {
                            guard let qp = qByNum[pair.queryNumber], let cp = cByNum[pair.candidateNumber] else { continue }
                            let p1 = CGPoint(x: 6 + qFit.minX + qp.centroid.x * qFit.width, y: 6 + qFit.minY + qp.centroid.y * qFit.height)
                            let p2 = CGPoint(x: 10 + halfW + cFit.minX + cp.centroid.x * cFit.width, y: 6 + cFit.minY + cp.centroid.y * cFit.height)
                            var line = Path()
                            line.move(to: p1)
                            line.addLine(to: p2)
                            let highlighted = activeQueryNumber == pair.queryNumber || activePairFeedback?.queryNumber == pair.queryNumber
                            ctx.stroke(
                                line,
                                with: .color((highlighted ? Color.yellow : Color.green).opacity(highlighted ? 0.95 : 0.65)),
                                lineWidth: highlighted ? 2.4 : 1.5
                            )
                        }
                    }
                    .allowsHitTesting(false)
                }
            }
        }
    }

    // MARK: - Affine Warped Query Pattern Overlay & Blink Canvas

    private var overlayWarpCanvas: some View {
        let sel = selectedCandidate
        let calc = sel.map { calculation(for: $0) }
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Overlay / Affine Warp:")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.cyan)
                Slider(value: $overlayBlend, in: 0...1, step: 0.05)
                    .frame(width: 210)
                Text("\(Int((overlayBlend * 100).rounded()))% Candidate")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                Button("0% Query") { overlayBlend = 0 }
                    .buttonStyle(.bordered).controlSize(.mini)
                Button("50/50") { overlayBlend = 0.5 }
                    .buttonStyle(.bordered).controlSize(.mini)
                Button("100% Cand + Warped Contours") { overlayBlend = 1.0 }
                    .buttonStyle(.bordered).controlSize(.mini)
                Spacer()
                if let calc, let res = calc.affineResidualPercent {
                    Text(String(format: "Warped %d Q-patterns · Mean Err %.1f%%", calc.warpedQueryContours.count, res))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.green)
                } else {
                    Text("Pair 3+ numbered scales to warp Query contours onto Candidate")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.75))

            if let sel {
                ZStack {
                    PatternInteractiveTile(
                        title: query.title,
                        badgeText: "BASE · \(query.title)",
                        side: query.side,
                        sideMatches: true,
                        image: query.image,
                        roi: extractedByID[query.id]?.roi ?? [],
                        patterns: activePatterns(for: query.id),
                        mesh: displayStyle == .inkContours ? nil : activeMesh(for: query.id),
                        displayStyle: displayStyle,
                        meshColor: contourColor,
                        warpedContours: [],
                        pairedNumbers: [:],
                        activeQueryNumber: activeQueryNumber,
                        accentColor: contourColor,
                        isSelectedTile: true,
                        linesOnly: linesOnly,
                        patternOnlyMask: patternOnlyMask,
                        showNumbers: showNumbers,
                        isROIEditMode: false,
                        isMeshEditMode: false,
                        zoom: zoom,
                        pan: $pan,
                        onSelectTile: {},
                        onTapPattern: { _ in },
                        onDrawNewROI: { _ in },
                        onMoveMeshVertex: { _, _ in }
                    )
                    .opacity(1.0 - overlayBlend * 0.88)

                    PatternInteractiveTile(
                        title: sel.title,
                        badgeText: "#\(sel.rank) \(sel.title) + Warped Q",
                        side: sel.side,
                        sideMatches: sel.sideMatches,
                        image: sel.image,
                        roi: extractedByID[sel.id]?.roi ?? [],
                        patterns: activePatterns(for: sel.id),
                        mesh: displayStyle == .inkContours ? nil : activeMesh(for: sel.id),
                        displayStyle: displayStyle,
                        meshColor: meshColor,
                        warpedContours: calc?.warpedQueryContours ?? [],
                        pairedNumbers: candidatePairLookup(for: sel.id),
                        activeQueryNumber: nil,
                        accentColor: candidateColor,
                        isSelectedTile: true,
                        linesOnly: linesOnly,
                        patternOnlyMask: patternOnlyMask,
                        showNumbers: showNumbers,
                        isROIEditMode: false,
                        isMeshEditMode: false,
                        zoom: zoom,
                        pan: $pan,
                        onSelectTile: {},
                        onTapPattern: { cNum in handleCandidatePatternTap(cNum, candidate: sel) },
                        onDrawNewROI: { _ in },
                        onMoveMeshVertex: { _, _ in }
                    )
                    .opacity(max(0.12, overlayBlend))
                }
                .padding(6)
            } else {
                emptySlotCard(rank: 1)
            }
        }
    }

    // MARK: - Tile Builders

    private func activeMesh(for targetID: String) -> ScaleSutureMesh {
        editedMeshes[targetID] ?? extractedByID[targetID]?.mesh ?? ScaleSutureMesh(vertices: [], edges: [], cells: [])
    }

    private func activePatterns(for targetID: String) -> [DetectedScalePattern] {
        if displayStyle != .inkContours {
            let mesh = activeMesh(for: targetID)
            if !mesh.cells.isEmpty {
                return mesh.cells.map { $0.asDetectedPattern() }
            }
        }
        return extractedByID[targetID]?.patterns ?? []
    }

    private var queryPatternTile: some View {
        let qData = extractedByID[query.id]
        let patterns = activePatterns(for: query.id)
        let mesh = activeMesh(for: query.id)
        let selPairs = selectedCandidate.flatMap { pairsByCandidateID[$0.id] } ?? []
        let lookup = Dictionary(uniqueKeysWithValues: selPairs.map { ($0.queryNumber, $0.candidateNumber) })

        return PatternInteractiveTile(
            title: query.title,
            badgeText: displayStyle == .scaleMesh ? "QUERY · \(mesh.cells.count) scales" : "QUERY · \(patterns.count) patterns",
            side: query.side,
            sideMatches: true,
            image: query.image,
            roi: qData?.roi ?? [],
            patterns: qData?.patterns ?? [],
            mesh: displayStyle == .inkContours ? nil : mesh,
            displayStyle: displayStyle,
            meshColor: meshColor,
            warpedContours: [],
            pairedNumbers: lookup,
            activeQueryNumber: activeQueryNumber,
            accentColor: contourColor,
            isSelectedTile: true,
            linesOnly: linesOnly,
            patternOnlyMask: patternOnlyMask,
            showNumbers: showNumbers,
            isROIEditMode: isEditingROI && roiEditingTargetID == query.id,
            isMeshEditMode: isEditingMesh,
            zoom: zoom,
            pan: $pan,
            onSelectTile: {
                if isEditingROI { roiEditingTargetID = query.id }
            },
            onTapPattern: { num in
                if activeQueryNumber == num {
                    activeQueryNumber = nil
                } else {
                    activeQueryNumber = num
                    activePairFeedback = selectedCandidate.flatMap { cand in
                        calculation(for: cand).pairDetails.first { $0.queryNumber == num }
                    }
                }
            },
            onDrawNewROI: { rectPoly in
                editedROIs[query.id] = rectPoly
                editedMeshes.removeValue(forKey: query.id)
                isEditingROI = false
                roiEditingTargetID = nil
            },
            onMoveMeshVertex: { vid, pt in
                editedMeshes[query.id] = activeMesh(for: query.id).movingVertex(id: vid, to: pt)
            }
        )
    }

    private func candidatePatternTile(_ cand: PatternComparisonTarget) -> some View {
        let cData = extractedByID[cand.id]
        let patterns = activePatterns(for: cand.id)
        let mesh = activeMesh(for: cand.id)
        let calc = calculation(for: cand)
        let isSelected = cand.id == selectedCandidate?.id
        let lookup = candidatePairLookup(for: cand.id)

        let badge = calc.pairCount > 0
            ? "#\(cand.rank) \(cand.title) · \(calc.combinedScorePercent)% (\(calc.pairCount) pairs)"
            : "#\(cand.rank) \(cand.title) · \(patterns.count) scales"

        return PatternInteractiveTile(
            title: cand.title,
            badgeText: badge,
            side: cand.side,
            sideMatches: cand.sideMatches,
            image: cand.image,
            roi: cData?.roi ?? [],
            patterns: cData?.patterns ?? [],
            mesh: displayStyle == .inkContours ? nil : mesh,
            displayStyle: displayStyle,
            meshColor: meshColor,
            warpedContours: calc.warpedQueryContours,
            pairedNumbers: lookup,
            activeQueryNumber: nil,
            accentColor: candidateColor,
            isSelectedTile: isSelected,
            linesOnly: linesOnly,
            patternOnlyMask: patternOnlyMask,
            showNumbers: showNumbers,
            isROIEditMode: isEditingROI && roiEditingTargetID == cand.id,
            isMeshEditMode: isEditingMesh && isSelected,
            zoom: zoom,
            pan: $pan,
            onSelectTile: {
                selectCandidate(cand.id)
                if isEditingROI { roiEditingTargetID = cand.id }
            },
            onTapPattern: { cNum in
                selectCandidate(cand.id)
                handleCandidatePatternTap(cNum, candidate: cand)
            },
            onDrawNewROI: { rectPoly in
                editedROIs[cand.id] = rectPoly
                editedMeshes.removeValue(forKey: cand.id)
                isEditingROI = false
                roiEditingTargetID = nil
            },
            onMoveMeshVertex: { vid, pt in
                editedMeshes[cand.id] = activeMesh(for: cand.id).movingVertex(id: vid, to: pt)
            },
            onExpandOneToOne: mode == .oneVsThree ? {
                selectCandidate(cand.id)
                mode = .oneToOne
            } : nil,
            onQuickConfirm: onConfirmCandidate != nil ? {
                selectCandidate(cand.id)
                onConfirmCandidate?(cand)
            } : nil,
            onQuickReject: onRejectCandidate != nil ? {
                selectCandidate(cand.id)
                onRejectCandidate?(cand)
            } : nil
        )
    }

    private func emptySlotCard(rank: Int) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "photo")
                .font(.system(size: 20))
                .foregroundStyle(.white.opacity(0.35))
            Text("Candidate #\(rank) unavailable")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Compact Bottom Manual Pattern Calculator Bar

    private var calculatorStrip: some View {
        let cand = selectedCandidate
        let calc = cand.map { calculation(for: $0) }
        let score = calc?.combinedScorePercent ?? 0
        let scoreTint: Color = score >= 78 ? AdaColors.green : (score >= 52 ? AdaColors.orange : AdaColors.red)

        return HStack(spacing: 12) {
            if let qNum = activeQueryNumber {
                HStack(spacing: 6) {
                    Circle().fill(contourColor).frame(width: 8, height: 8)
                    Text("Click matching # on Candidate for Q#\(qNum)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AdaColors.navy)
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(contourColor.opacity(0.16), in: Capsule())
            } else {
                Text("Click Q# then Candidate# to pair")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AdaColors.secondaryInk)
            }

            if let cand, let calc {
                Divider().frame(height: 18)

                metricPill("Paired", value: "\(calc.pairCount)/\(min(calc.totalQueryPatterns, calc.totalCandidatePatterns))")
                metricPill("Shape", value: "\(calc.shapeMatchPercent)%")

                if let err = calc.affineResidualPercent, let fit = calc.affineFitPercent {
                    metricPill("Affine", value: String(format: "%d%% (err %.1f%%)", fit, err))
                } else {
                    metricPill("Affine", value: "Pair 3+")
                }

                if let i3sEq = calc.i3sEquivalentDistance {
                    metricPill("Pattern Dist", value: String(format: "%.1f", i3sEq))
                }

                HStack(spacing: 5) {
                    Text("Calc:")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AdaColors.secondaryInk)
                    Text("\(calc.combinedScorePercent)%")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(scoreTint)
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(scoreTint.opacity(0.12), in: Capsule())

                if let detail = activePairFeedback {
                    Text("Q#\(detail.queryNumber)↔C#\(detail.candidateNumber) shape \(detail.shapeAgreementPercent)%"
                         + (detail.normalizedResidualPercent.map { String(format: " · err %.1f%%", $0) } ?? ""))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(AdaColors.navy)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    autoPairCandidate(cand)
                } label: {
                    Label("Auto-Pair", systemImage: "wand.and.stars")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(AdaColors.navy, in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    pairsByCandidateID[cand.id] = []
                    activePairFeedback = nil
                } label: {
                    Text("Clear")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AdaColors.secondaryInk)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(AdaColors.canvas, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled((pairsByCandidateID[cand.id] ?? []).isEmpty)
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(AdaColors.card)
    }

    private func metricPill(_ label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(AdaColors.secondaryInk)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(AdaColors.ink)
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(AdaColors.canvas, in: Capsule())
    }

    // MARK: - Pairing & Real Calculation Logic

    private func selectCandidate(_ id: String) {
        selectedCandidateID = id
        onSelectCandidateID?(id)
        if let qNum = activeQueryNumber {
            activePairFeedback = candidates.first { $0.id == id }.flatMap { cand in
                calculation(for: cand).pairDetails.first { $0.queryNumber == qNum }
            }
        } else {
            activePairFeedback = nil
        }
    }

    private func candidatePairLookup(for candidateID: String) -> [Int: Int] {
        let pairs = pairsByCandidateID[candidateID] ?? []
        return Dictionary(uniqueKeysWithValues: pairs.map { ($0.candidateNumber, $0.queryNumber) })
    }

    private func handleCandidatePatternTap(_ cNum: Int, candidate: PatternComparisonTarget) {
        var links = pairsByCandidateID[candidate.id] ?? []

        if let qNum = activeQueryNumber {
            // If exact pair already exists, remove it; otherwise link Q#qNum <-> C#cNum
            if let existingExact = links.firstIndex(where: { $0.queryNumber == qNum && $0.candidateNumber == cNum }) {
                links.remove(at: existingExact)
                activePairFeedback = nil
            } else {
                links.removeAll { $0.queryNumber == qNum || $0.candidateNumber == cNum }
                links.append(PatternPairLink(queryNumber: qNum, candidateNumber: cNum))
                links.sort { $0.queryNumber < $1.queryNumber }
                pairsByCandidateID[candidate.id] = links
                activePairFeedback = calculation(for: candidate).pairDetails.first { $0.queryNumber == qNum }
                // Advance activeQueryNumber to the next unpaired Query scale for fast manual workflow!
                let activeQ = activePatterns(for: query.id)
                let pairedQs = Set(links.map(\.queryNumber))
                activeQueryNumber = activeQ.first { !pairedQs.contains($0.number) && $0.number > qNum }?.number
                    ?? activeQ.first { !pairedQs.contains($0.number) }?.number
                return
            }
        } else if let idx = links.firstIndex(where: { $0.candidateNumber == cNum }) {
            let removedQ = links[idx].queryNumber
            links.remove(at: idx)
            activeQueryNumber = removedQ
            activePairFeedback = nil
        }

        pairsByCandidateID[candidate.id] = links
    }

    private func calculation(for candidate: PatternComparisonTarget) -> PatternMatchCalculation {
        let qData = extractedByID[query.id]
        let cData = extractedByID[candidate.id]
        let pairs = pairsByCandidateID[candidate.id] ?? []
        return PatternMatchCalculator.calculate(
            query: activePatterns(for: query.id),
            candidate: activePatterns(for: candidate.id),
            pairs: pairs,
            queryROI: qData?.roi ?? [],
            candidateROI: cData?.roi ?? []
        )
    }

    private func autoPairCandidate(_ candidate: PatternComparisonTarget) {
        guard let qData = extractedByID[query.id], let cData = extractedByID[candidate.id] else { return }
        let qFP = effectiveFingerprint(for: query, data: qData)
        let cFP = effectiveFingerprint(for: candidate, data: cData)
        let suggested = PatternMatchCalculator.autoSuggestPairs(
            query: activePatterns(for: query.id),
            candidate: activePatterns(for: candidate.id),
            queryFP: qFP,
            candidateFP: cFP,
            queryImageSize: query.image?.size,
            candidateImageSize: candidate.image?.size,
            queryROI: qData.roi,
            candidateROI: cData.roi
        )
        pairsByCandidateID[candidate.id] = suggested
        activePairFeedback = calculation(for: candidate).pairDetails.first
    }

    private func effectiveFingerprint(for target: PatternComparisonTarget, data: ExtractedTargetData) -> I3SFingerprint? {
        if let fp = target.fingerprint, fp.allReferencesInitialized { return fp }
        if let sample = target.sampleEntry { return sample.fingerprint }
        if let refs = data.autoRefs, let img = target.image {
            let w = Double(max(1, img.size.width))
            let h = Double(max(1, img.size.height))
            return I3SFingerprint(
                ref1: I3SPoint2D(x: refs.ref1.x * w, y: refs.ref1.y * h),
                ref2: I3SPoint2D(x: refs.ref2.x * w, y: refs.ref2.y * h),
                ref3: I3SPoint2D(x: refs.ref3.x * w, y: refs.ref3.y * h)
            )
        }
        return nil
    }

    // MARK: - Background Pattern Extraction

    private func extractAllTargets() async {
        isSyncing = true
        defer { isSyncing = false }

        var targets: [PatternComparisonTarget] = [query]
        targets.append(contentsOf: candidates.prefix(4))

        let currentConfig = config
        let sensBucket = Int((currentConfig.sensitivity * 100).rounded())
        let smoothBucket = Int((currentConfig.smoothness * 100).rounded())

        for target in targets {
            if Task.isCancelled { return }
            let overrideROI = editedROIs[target.id]
            let roiSig = (overrideROI?.count ?? 0) * 31 + (target.customROI?.count ?? 0)
            let key = PatternExtractionCacheKey(
                targetID: target.id,
                imageID: target.image.map(ObjectIdentifier.init),
                sensitivityBucket: sensBucket,
                smoothnessBucket: smoothBucket,
                roiSignature: roiSig
            )
            if extractedByID[target.id]?.cacheKey == key { continue }
            guard let img = target.image,
                  let fullRaster = PatternContourEngine.underwaterLuminance(from: img, maxDimension: 420) else {
                continue
            }

            let explicitROI = resolveExplicitROI(for: target, overrideROI: overrideROI, imageSize: img.size)
            let side = target.side

            let worker = Task.detached(priority: .userInitiated) { () -> (roi: [ScalePoint], patterns: [DetectedScalePattern], mesh: ScaleSutureMesh, refs: (ScalePoint, ScalePoint, ScalePoint)?) in
                let roi: [ScalePoint]
                let refs: (ScalePoint, ScalePoint, ScalePoint)?
                if let explicitROI, explicitROI.count >= 3 {
                    roi = explicitROI
                    refs = nil
                } else {
                    let detected = PatternContourEngine.detectFacialPatternROI(from: fullRaster, side: side)
                    roi = detected.roi
                    refs = (detected.ref1, detected.ref2, detected.ref3)
                }
                let patterns = PatternContourEngine.extractPatterns(from: fullRaster, roiPolygon: roi, config: currentConfig)
                let mesh = PatternContourEngine.extractScaleSutureMesh(
                    from: fullRaster,
                    roiPolygon: roi,
                    patterns: patterns,
                    config: currentConfig
                )
                return (roi, patterns, mesh, refs)
            }

            let result = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            if Task.isCancelled { return }

            let data = ExtractedTargetData(
                cacheKey: key,
                roi: result.roi,
                patterns: result.patterns,
                mesh: result.mesh,
                autoRefs: result.refs
            )
            extractedByID[target.id] = data
        }

        // Seed initial auto-pair calculation for any candidate that doesn't yet have manual pairs
        for cand in candidates.prefix(4) where pairsByCandidateID[cand.id] == nil {
            autoPairCandidate(cand)
        }
    }

    private func resolveExplicitROI(
        for target: PatternComparisonTarget,
        overrideROI: [ScalePoint]?,
        imageSize: NSSize
    ) -> [ScalePoint]? {
        if let overrideROI, overrideROI.count >= 3 {
            return overrideROI
        }
        if let custom = target.customROI, custom.count >= 3 {
            return custom
        }
        if let fp = target.fingerprint, fp.roi.isFinal, fp.roi.vertices.count >= 3,
           imageSize.width > 1, imageSize.height > 1 {
            let w = Double(target.sampleEntry?.imageWidth ?? Int(imageSize.width))
            let h = Double(target.sampleEntry?.imageHeight ?? Int(imageSize.height))
            return fp.roi.vertices.map { ScalePoint(x: min(0.98, max(0.02, $0.x / w)), y: min(0.98, max(0.02, $0.y / h))) }
        }
        if let sample = target.sampleEntry, !sample.roi.isEmpty, sample.imageWidth > 0, sample.imageHeight > 0 {
            let w = Double(sample.imageWidth), h = Double(sample.imageHeight)
            return sample.roi.compactMap { pair in
                guard pair.count >= 2 else { return nil }
                return ScalePoint(x: min(0.98, max(0.02, pair[0] / w)), y: min(0.98, max(0.02, pair[1] / h)))
            }
        }
        return nil
    }

    private func focusOnQueryPattern() {
        let qROI = extractedByID[query.id]?.roi ?? []
        guard !qROI.isEmpty else {
            zoom = 1.65; pan = .zero
            return
        }
        let cx = (qROI.map(\.x).min()! + qROI.map(\.x).max()!) * 0.5
        let cy = (qROI.map(\.y).min()! + qROI.map(\.y).max()!) * 0.5
        zoom = 1.75
        pan = CGSize(width: (0.5 - cx) * 320, height: (0.5 - cy) * 260)
    }

    private func zoomedAspectFitRect(imageSize: NSSize, container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, container.width > 0, container.height > 0 else { return .zero }
        let baseScale = min(container.width / imageSize.width, container.height / imageSize.height)
        let w = imageSize.width * baseScale * zoom
        let h = imageSize.height * baseScale * zoom
        return CGRect(
            x: (container.width - w) * 0.5 + pan.width,
            y: (container.height - h) * 0.5 + pan.height,
            width: w,
            height: h
        )
    }
}

// MARK: - Interactive Single Tile (Smooth Pattern Contour + Number Badges + ROI Drag)

private struct PatternInteractiveTile: View {
    let title: String
    let badgeText: String
    let side: TurtlePhotoSide
    let sideMatches: Bool
    let image: NSImage?
    let roi: [ScalePoint]
    let patterns: [DetectedScalePattern]
    let mesh: ScaleSutureMesh?
    let displayStyle: PatternContourDisplayStyle
    let meshColor: Color
    let warpedContours: [WarpedPatternContour]
    /// Map of `localPatternNumber -> pairedOtherNumber`
    let pairedNumbers: [Int: Int]
    let activeQueryNumber: Int?
    let accentColor: Color
    let isSelectedTile: Bool
    let linesOnly: Bool
    let patternOnlyMask: Bool
    let showNumbers: Bool
    let isROIEditMode: Bool
    let isMeshEditMode: Bool
    let zoom: Double
    @Binding var pan: CGSize
    let onSelectTile: () -> Void
    let onTapPattern: (Int) -> Void
    let onDrawNewROI: ([ScalePoint]) -> Void
    let onMoveMeshVertex: (Int, ScalePoint) -> Void
    var onExpandOneToOne: (() -> Void)? = nil
    var onQuickConfirm: (() -> Void)? = nil
    var onQuickReject: (() -> Void)? = nil

    @State private var dragStartPan: CGSize? = nil
    @State private var draggedVertexID: Int? = nil
    @State private var roiDragBox: (start: CGPoint, current: CGPoint)? = nil

    private var activeHitPatterns: [DetectedScalePattern] {
        if displayStyle != .inkContours, let mesh, !mesh.cells.isEmpty {
            return mesh.cells.map { $0.asDetectedPattern() }
        }
        return patterns
    }

    var body: some View {
        GeometryReader { geo in
            let fit = tileFitRect(in: geo.size)
            ZStack(alignment: .topLeading) {
                Color(red: 0.05, green: 0.07, blue: 0.10)

                if let image {
                    if !linesOnly {
                        Image(nsImage: image)
                            .resizable()
                            .frame(width: fit.width, height: fit.height)
                            .position(x: fit.midX, y: fit.midY)
                    }

                    Canvas { context, size in
                        drawPatternOverlay(in: &context, canvasSize: size, fit: fit)
                    }
                    .allowsHitTesting(false)
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "photo")
                            .font(.system(size: 20))
                            .foregroundStyle(.white.opacity(0.4))
                        Text("No photograph")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                // Minimal floating corner badge — leaves 96% of photo & contours crystal clear!
                HStack(spacing: 6) {
                    Text(badgeText)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(side.title.prefix(1).uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(sideMatches ? Color.green : Color.red)
                        .padding(.horizontal, 5)
                        .frame(height: 15)
                        .background(Color.white.opacity(0.14), in: Capsule())

                    Spacer(minLength: 4)

                    if let onExpandOneToOne {
                        Button(action: onExpandOneToOne) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 20, height: 20)
                                .background(Color.white.opacity(0.16), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Focus 1:1")
                    }
                    if let onQuickConfirm {
                        Button(action: onQuickConfirm) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 20, height: 20)
                                .background(AdaColors.green, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Same turtle")
                    }
                    if let onQuickReject {
                        Button(action: onQuickReject) {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 20, height: 20)
                                .background(AdaColors.red, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Different turtle")
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.62), in: Capsule())
                .padding(8)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let dragDist = hypot(value.translation.width, value.translation.height)
                        if isROIEditMode {
                            if dragDist > 3 { roiDragBox = (value.startLocation, value.location) }
                        } else if isMeshEditMode, let mesh, fit.width > 4, fit.height > 4 {
                            if draggedVertexID == nil {
                                let best = mesh.vertices.min { a, b in
                                    let pa = CGPoint(x: fit.minX + a.point.x * fit.width, y: fit.minY + a.point.y * fit.height)
                                    let pb = CGPoint(x: fit.minX + b.point.x * fit.width, y: fit.minY + b.point.y * fit.height)
                                    return hypot(pa.x - value.startLocation.x, pa.y - value.startLocation.y)
                                        < hypot(pb.x - value.startLocation.x, pb.y - value.startLocation.y)
                                }
                                if let best {
                                    let pBest = CGPoint(x: fit.minX + best.point.x * fit.width, y: fit.minY + best.point.y * fit.height)
                                    if hypot(pBest.x - value.startLocation.x, pBest.y - value.startLocation.y) <= 18 {
                                        draggedVertexID = best.id
                                    }
                                }
                            }
                            if let vid = draggedVertexID {
                                let norm = ScalePoint(
                                    x: min(max((value.location.x - fit.minX) / fit.width, 0.01), 0.99),
                                    y: min(max((value.location.y - fit.minY) / fit.height, 0.01), 0.99)
                                )
                                onMoveMeshVertex(vid, norm)
                                return
                            }
                            if dragDist > 4 {
                                if dragStartPan == nil { dragStartPan = pan }
                                let base = dragStartPan ?? .zero
                                pan = CGSize(width: base.width + value.translation.width, height: base.height + value.translation.height)
                            }
                        } else if dragDist > 4 {
                            if dragStartPan == nil { dragStartPan = pan }
                            let base = dragStartPan ?? .zero
                            pan = CGSize(width: base.width + value.translation.width, height: base.height + value.translation.height)
                        }
                    }
                    .onEnded { value in
                        let wasVertexDrag = draggedVertexID != nil
                        defer {
                            dragStartPan = nil
                            draggedVertexID = nil
                            roiDragBox = nil
                        }
                        if wasVertexDrag { return }
                        let dragDist = hypot(value.translation.width, value.translation.height)
                        if isROIEditMode, dragDist > 12, fit.width > 4, fit.height > 4 {
                            let x0 = min(max((min(value.startLocation.x, value.location.x) - fit.minX) / fit.width, 0.02), 0.96)
                            let y0 = min(max((min(value.startLocation.y, value.location.y) - fit.minY) / fit.height, 0.02), 0.96)
                            let x1 = min(max((max(value.startLocation.x, value.location.x) - fit.minX) / fit.width, x0 + 0.08), 0.98)
                            let y1 = min(max((max(value.startLocation.y, value.location.y) - fit.minY) / fit.height, y0 + 0.08), 0.98)
                            onDrawNewROI([
                                ScalePoint(x: x0, y: y0),
                                ScalePoint(x: x1, y: y0),
                                ScalePoint(x: x1, y: y1),
                                ScalePoint(x: x0, y: y1),
                            ])
                            return
                        }
                        guard dragDist <= 4 else { return }
                        onSelectTile()

                        guard fit.width > 1, fit.height > 1 else { return }
                        let normPt = ScalePoint(
                            x: (value.location.x - fit.minX) / fit.width,
                            y: (value.location.y - fit.minY) / fit.height
                        )
                        let pool = activeHitPatterns
                        if let hit = pool.last(where: { ScalePhotoReview.contains(normPt, polygon: $0.polygon) })
                            ?? pool.min(by: { hypot($0.centroid.x - normPt.x, $0.centroid.y - normPt.y) < hypot($1.centroid.x - normPt.x, $1.centroid.y - normPt.y) }) {
                            let viewDist = hypot((hit.centroid.x - normPt.x) * fit.width, (hit.centroid.y - normPt.y) * fit.height)
                            if ScalePhotoReview.contains(normPt, polygon: hit.polygon) || viewDist <= 22 {
                                onTapPattern(hit.number)
                            }
                        }
                    }
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isROIEditMode ? Color.yellow : (isMeshEditMode ? meshColor : (isSelectedTile ? accentColor : Color.white.opacity(0.14))), lineWidth: isSelectedTile ? 2.0 : 1.0)
        )
    }

    private func tileFitRect(in container: CGSize) -> CGRect {
        let imgSize = image?.size ?? NSSize(width: 640, height: 640)
        guard imgSize.width > 0, imgSize.height > 0, container.width > 0, container.height > 0 else { return .zero }
        let baseScale = min(container.width / imgSize.width, container.height / imgSize.height)
        let w = imgSize.width * baseScale * zoom
        let h = imgSize.height * baseScale * zoom
        return CGRect(
            x: (container.width - w) * 0.5 + pan.width,
            y: (container.height - h) * 0.5 + pan.height,
            width: w,
            height: h
        )
    }

    private func drawPatternOverlay(in context: inout GraphicsContext, canvasSize: CGSize, fit: CGRect) {
        func mapPt(_ p: ScalePoint) -> CGPoint {
            CGPoint(x: fit.minX + p.x * fit.width, y: fit.minY + p.y * fit.height)
        }

        // 1. Pattern Spotlight scrim: isolates ONLY the cheek pattern region!
        if roi.count >= 3 {
            var roiPath = Path()
            for (i, pt) in roi.enumerated() {
                let p = mapPt(pt)
                if i == 0 { roiPath.move(to: p) } else { roiPath.addLine(to: p) }
            }
            roiPath.closeSubpath()

            if patternOnlyMask && !linesOnly {
                var outer = Path(CGRect(origin: .zero, size: canvasSize))
                outer.addPath(roiPath)
                context.fill(outer, with: .color(Color.black.opacity(0.66)), style: FillStyle(eoFill: true))
            }

            context.stroke(
                roiPath,
                with: .color(accentColor.opacity(0.55)),
                style: StrokeStyle(lineWidth: 1.4, dash: [6, 4])
            )
        }

        // 2A. Optional Ink Blobs (when Ink or Both style is chosen)
        if displayStyle == .inkContours || displayStyle == .combined {
            for pat in patterns {
                guard pat.polygon.count >= 3 else { continue }
                var polyPath = Path()
                for (i, v) in pat.polygon.enumerated() {
                    let p = mapPt(v)
                    if i == 0 { polyPath.move(to: p) } else { polyPath.addLine(to: p) }
                }
                polyPath.closeSubpath()

                let isActiveQ = activeQueryNumber == pat.number
                let isPaired = pairedNumbers[pat.number] != nil
                let strokeColor: Color = displayStyle == .combined
                    ? accentColor.opacity(0.65)
                    : (isActiveQ ? .yellow : (isPaired ? .green : accentColor))
                let fillColor: Color = isActiveQ ? Color.yellow.opacity(0.26) : (isPaired ? Color.green.opacity(0.18) : accentColor.opacity(displayStyle == .combined ? 0.08 : 0.14))

                context.fill(polyPath, with: .color(fillColor))
                context.stroke(
                    polyPath,
                    with: .color(strokeColor.opacity(0.95)),
                    style: StrokeStyle(lineWidth: displayStyle == .combined ? 1.2 : (isActiveQ ? 2.8 : (isPaired ? 2.2 : 1.7)), lineCap: .round, lineJoin: .round)
                )

                if displayStyle == .inkContours && showNumbers {
                    drawNumberBadge(num: pat.number, at: mapPt(pat.centroid), in: &context)
                }
            }
        }

        // 2B. Polygonal Scale Suture Mesh (Picture 1 style — crisp shared lines along pale sutures!)
        if displayStyle != .inkContours, let mesh, !mesh.edges.isEmpty {
            let vertMap = Dictionary(uniqueKeysWithValues: mesh.vertices.map { ($0.id, $0.point) })

            // Highlight paired or active scute cell softly
            for cell in mesh.cells where cell.polygon.count >= 3 {
                let isActiveQ = activeQueryNumber == cell.number
                let isPaired = pairedNumbers[cell.number] != nil
                if isActiveQ || isPaired {
                    var cp = Path()
                    for (i, v) in cell.polygon.enumerated() {
                        let p = mapPt(v)
                        if i == 0 { cp.move(to: p) } else { cp.addLine(to: p) }
                    }
                    cp.closeSubpath()
                    context.fill(cp, with: .color((isActiveQ ? Color.yellow : Color.green).opacity(0.24)))
                }
            }

            // Draw deduplicated suture edges cleanly once
            var meshPath = Path()
            for edge in mesh.edges {
                let pts = edge.vertexIDs.compactMap { vertMap[$0] }.map { mapPt($0) }
                guard let first = pts.first, pts.count >= 2 else { continue }
                meshPath.move(to: first)
                for pt in pts.dropFirst() {
                    meshPath.addLine(to: pt)
                }
            }
            context.stroke(
                meshPath,
                with: .color(meshColor.opacity(0.96)),
                style: StrokeStyle(lineWidth: linesOnly ? 2.5 : 2.1, lineCap: .round, lineJoin: .round)
            )

            // Draw draggable junction vertices when Edit Mesh mode is on
            if isMeshEditMode {
                for v in mesh.vertices {
                    let pt = mapPt(v.point)
                    let rect = CGRect(x: pt.x - 4.5, y: pt.y - 4.5, width: 9, height: 9)
                    context.fill(Path(ellipseIn: rect), with: .color(.white))
                    context.stroke(Path(ellipseIn: rect), with: .color(meshColor), lineWidth: 1.6)
                }
            }

            if showNumbers {
                for cell in mesh.cells {
                    drawNumberBadge(num: cell.number, at: mapPt(cell.center), in: &context)
                }
            }
        }

        // 3. Affine-warped Query contours overlaid directly on Candidate in Overlay / Warp mode
        for warped in warpedContours where warped.polygon.count >= 3 {
            var wp = Path()
            for (i, v) in warped.polygon.enumerated() {
                let p = mapPt(v)
                if i == 0 { wp.move(to: p) } else { wp.addLine(to: p) }
            }
            wp.closeSubpath()
            context.stroke(
                wp,
                with: .color(Color.cyan.opacity(0.90)),
                style: StrokeStyle(lineWidth: 1.6, dash: [4, 3])
            )
        }

        // 4. Interactive ROI drag preview box
        if let (a, b) = roiDragBox {
            let box = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
            context.fill(Path(box), with: .color(Color.yellow.opacity(0.12)))
            context.stroke(Path(box), with: .color(.yellow), lineWidth: 2.0)
        }
    }

    private func drawNumberBadge(num: Int, at c: CGPoint, in context: inout GraphicsContext) {
        let isActiveQ = activeQueryNumber == num
        let isPaired = pairedNumbers[num] != nil
        let labelText = pairedNumbers[num].map { "\(num)↔\($0)" } ?? "\(num)"
        let pillW: CGFloat = labelText.count > 2 ? 32 : 18
        let pillRect = CGRect(x: c.x - pillW * 0.5, y: c.y - 9, width: pillW, height: 18)
        context.fill(
            Path(roundedRect: pillRect, cornerRadius: 9),
            with: .color((isActiveQ ? Color.yellow : (isPaired ? AdaColors.green : Color.black)).opacity(0.84))
        )
        context.stroke(
            Path(roundedRect: pillRect, cornerRadius: 9),
            with: .color(.white.opacity(0.75)),
            lineWidth: 0.9
        )
        context.draw(
            Text(labelText)
                .font(.system(size: labelText.count > 2 ? 9 : 10, weight: .bold, design: .monospaced))
                .foregroundColor(isActiveQ ? .black : .white),
            at: c
        )
    }
}
