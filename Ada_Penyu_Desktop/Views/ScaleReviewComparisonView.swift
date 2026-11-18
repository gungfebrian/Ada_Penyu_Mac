import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ScaleReviewComparisonView: View {
    let queryImage: NSImage?
    let galleryImage: NSImage?
    @ObservedObject var store: ScaleReviewStore
    var querySampleName: String? = nil
    var gallerySampleName: String? = nil
    @State private var showsNumbers = true
    @State private var queryColor = Color.cyan
    @State private var galleryColor = AdaColors.orange
    @State private var exportMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Numbered scale review").font(.system(size: 13, weight: .semibold))
                    Text("Click any numbered scale on the photo or list to inspect, confirm, reject, or redraw.")
                        .font(.system(size: 11)).foregroundStyle(AdaColors.secondaryInk)
                }
                Spacer()
                Toggle("Numbers", isOn: $showsNumbers).toggleStyle(.checkbox)
                Button("Export workspace reviews…", action: exportReview).disabled(store.documents.isEmpty)
            }.font(.system(size: 11)).controlSize(.small).padding(12).background(AdaColors.card)
            HStack(spacing: 1) {
                ScalePhotoReviewPane(
                    image: queryImage,
                    title: "QUERY",
                    sampleName: querySampleName,
                    store: store,
                    showsNumbers: showsNumbers,
                    tint: $queryColor
                )
                ScalePhotoReviewPane(
                    image: galleryImage,
                    title: "GALLERY",
                    sampleName: gallerySampleName,
                    store: store,
                    showsNumbers: showsNumbers,
                    tint: $galleryColor
                )
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(AdaColors.line)
            VStack(alignment: .leading, spacing: 4) {
                Text("Counts include confirmed scales only. Proposals can include eyes, glare or merged scales. Numbers are local to each photo; matching numbers do not establish correspondence.")
                Text("Manual head region · drafts stay in this workspace until you leave or sign out. Export to keep a copy.")
                if let exportMessage { Text(exportMessage).foregroundStyle(AdaColors.navy).textSelection(.enabled) }
            }.font(.system(size: 10)).foregroundStyle(AdaColors.secondaryInk).frame(maxWidth: .infinity, alignment: .leading)
                .padding(10).background(AdaColors.card)
        }
    }

    private func exportReview() {
        struct Export: Encodable {
            let schemaVersion = 1
            let coordinateSystem = "normalized-top-left"
            let photoHashMethod = "SHA-256 of NSImage TIFF representation"
            let method = "Manual head ROI; heuristic enclosed-region proposals; scientist-confirmed polygons"
            let generatedAt = Date()
            let photos: [ScalePhotoReview]
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "ada-penyu-scale-review.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(Export(photos: store.documents.values.sorted { $0.photoHash < $1.photoHash })).write(to: url, options: .atomic)
            exportMessage = "Exported \(store.documents.count) photo review(s) to \(url.lastPathComponent)."
        } catch { exportMessage = "Export failed: \(error.localizedDescription)" }
    }
}

private struct ScalePhotoReviewPane: View {
    let image: NSImage?
    let title: String
    var sampleName: String? = nil
    @ObservedObject var store: ScaleReviewStore
    let showsNumbers: Bool
    @Binding var tint: Color
    private enum EditMode: String, CaseIterable { case inspect = "Review", head = "Head ROI", draw = "Draw scale" }
    @State private var mode: EditMode = .inspect
    @State private var hash: String?
    @State private var raster: (pixels: [Float], width: Int, height: Int)?
    @State private var draft: [ScalePoint] = []
    @State private var selected: UUID?
    @State private var redrawing: UUID?
    @State private var redrawLease: UUID?
    @State private var pendingROI: ScaleRect?
    @State private var confirmROIChange = false
    @State private var message = "Select a numbered scale on the photo or list below to confirm, reject, or redraw."
    @State private var threshold = 0.08
    @State private var processing = false
    @State private var requestID = UUID()
    @State private var worker: Task<Void, Never>?
    @State private var dragPosition: (CGPoint, CGPoint)?
    @State private var zoom = 1.0
    private var document: ScalePhotoReview? { hash.flatMap { store.documents[$0] } }
    private var selectedScale: ReviewedScale? { document?.scales.first { $0.id == selected } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.system(size: 11, weight: .bold)).foregroundStyle(AdaColors.navy)
                Spacer()
                Text("\(document?.confirmedCount ?? 0) confirmed").foregroundStyle(AdaColors.green)
                Text("\(document?.pendingCount ?? 0) pending").foregroundStyle(AdaColors.secondaryInk)
            }.font(.system(size: 11, weight: .semibold)).padding(10)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Picker("Tool", selection: $mode) {
                        ForEach(EditMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.labelsHidden().frame(maxWidth: 180)
                    ColorPicker("Lines", selection: $tint, supportsOpacity: false).labelsHidden().frame(width: 28).accessibilityLabel("\(title) scale outline color")
                    Menu("\(Int(zoom * 100))%") {
                        ForEach([1.0, 1.5, 2.0], id: \.self) { value in Button("\(Int(value * 100))%") { zoom = value } }
                    }.frame(width: 72)
                    Button("Detect Scales", action: seedMockScales)
                }
                HStack(spacing: 6) {
                    Text("Edges")
                    Slider(value: $threshold, in: 0.02...0.3, step: 0.01).frame(minWidth: 50, maxWidth: 105)
                        .accessibilityLabel("\(title) proposal boundary threshold")
                    Button(processing ? "Proposing…" : "Propose regions", action: propose)
                        .disabled(document?.headROI == nil || processing || raster == nil)
                    if processing { ProgressView().controlSize(.mini) }
                }
                HStack(spacing: 6) {
                    Button(redrawing == nil ? "Finish scale" : "Finish redraw", action: finishPolygon).disabled(mode != .draw || draft.count < 3)
                    Button("Undo point") { if !draft.isEmpty { draft.removeLast() } }.disabled(draft.isEmpty)
                    Button("Cancel") { endRedraw(); draft = []; mode = .inspect }.disabled(draft.isEmpty && mode == .inspect)
                }
                Text(message).font(.system(size: 10)).foregroundStyle(AdaColors.secondaryInk).lineLimit(2).frame(height: 28, alignment: .topLeading)
            }.font(.system(size: 11)).controlSize(.small).padding(.horizontal, 10).padding(.bottom, 8)
            GeometryReader { geometry in
                let rect = fittedRect(size: geometry.size)
                ZStack {
                    Color(red: 0.05, green: 0.07, blue: 0.08)
                    if let image {
                        Image(nsImage: image).resizable().scaledToFit().frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                        Canvas { context, _ in draw(context: &context, rect: rect) }
                    } else {
                        ContentUnavailableView("Photo unavailable", systemImage: "photo")
                    }
                }.contentShape(Rectangle()).clipped()
                    .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                        if mode == .head { dragPosition = (value.startLocation, value.location) }
                    }.onEnded { value in
                        dragPosition = nil
                        handle(start: value.startLocation, end: value.location, rect: rect)
                    })
            }.frame(minHeight: 130)
            reviewControls
        }.background(AdaColors.card)
            .task(id: image.map(ObjectIdentifier.init)) { loadPhoto() }
            .onChange(of: mode) { _, value in
                if value == .head { message = "Drag a rectangle around the visible head scales." }
                if value == .draw { message = "Click vertices around ONE scale, then Finish scale. Only confirmed scales are counted." }
                if value != .draw { endRedraw(); draft = [] }
                if value == .inspect { message = "Select a numbered region, check its boundary, then confirm or reject." }
            }
            .onDisappear { worker?.cancel(); requestID = UUID(); processing = false; endRedraw() }
            .onChange(of: document?.headRevision) { _, _ in
                worker?.cancel(); requestID = UUID(); processing = false
                endRedraw(); draft = []; selected = nil
            }
            .confirmationDialog("Change head region?", isPresented: $confirmROIChange, titleVisibility: .visible) {
                Button("Replace region and clear its scales", role: .destructive) { if let pendingROI { applyROI(pendingROI) } }
                Button("Cancel", role: .cancel) { pendingROI = nil }
            } message: { Text("This photograph already has scale annotations. Changing its head region clears those annotations and restarts numbering.") }
    }

    private var reviewControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal) {
                HStack(spacing: 5) {
                    ForEach(document?.scales ?? []) { scale in
                        Button {
                            selected = scale.id; mode = .inspect
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: scale.status == .confirmed ? "checkmark.circle.fill" : scale.status == .rejected ? "xmark.circle" : "circle.dashed")
                                Text("\(scale.number)")
                            }.padding(.horizontal, 7).padding(.vertical, 5)
                                .background(selected == scale.id ? AdaColors.accentSoft : AdaColors.canvas, in: RoundedRectangle(cornerRadius: 6))
                        }.buttonStyle(.plain).help("Scale \(scale.number) · \(scale.status.rawValue) · \(scale.source.rawValue)")
                    }
                }
            }.frame(height: 28)
            if let scale = selectedScale {
                Text("#\(scale.number) · \(scale.status.rawValue.capitalized) · \(scale.source == .manual ? "Scientist drawn" : "Region proposal")")
                HStack(spacing: 8) {
                    Button("Confirm") { update { $0.setStatus(scale.id, .confirmed) } }.tint(AdaColors.green)
                    Button("Reject") { update { $0.setStatus(scale.id, .rejected) } }
                    Button("Redraw") {
                        endRedraw()
                        guard let hash, let lease = store.beginRedraw(hash, scaleID: scale.id) else { return }
                        redrawLease = lease; mode = .draw; redrawing = scale.id; draft = []
                    }
                    Button("Delete", role: .destructive) { update { $0.remove(scale.id) }; selected = nil }
                }.disabled(processing)
            } else {
                Text(document?.scales.isEmpty == false ? "Select a number to review its boundary." : "No scales reviewed yet.")
                    .foregroundStyle(AdaColors.secondaryInk)
            }
        }.font(.system(size: 10)).controlSize(.small).frame(maxWidth: .infinity, alignment: .leading).padding(10).frame(height: 100, alignment: .top)
    }

    private func loadPhoto() {
        worker?.cancel(); requestID = UUID(); processing = false
        endRedraw()
        hash = nil; raster = nil; draft = []; selected = nil; redrawing = nil; zoom = 1
        guard let image, let data = image.tiffRepresentation, let raster = ContourRasterizer.luminance(from: image, maxDimension: 900) else { return }
        let photoHash = ScaleReviewStore.photoHash(data)
        self.raster = raster; hash = photoHash
        let pxW = image.cgImage(forProposedRect: nil, context: nil, hints: nil)?.width ?? raster.width
        let pxH = image.cgImage(forProposedRect: nil, context: nil, hints: nil)?.height ?? raster.height
        store.ensurePhoto(hash: photoHash, width: pxW, height: pxH)
        if document?.headROI == nil, document?.scales.isEmpty != false {
            seedMockScales()
        } else {
            mode = document?.headROI == nil ? .head : .inspect
            selected = document?.scales.first?.id
        }
    }

    private func seedMockScales() {
        guard let hash else { return }
        let matchedSample = sampleName.flatMap { I3SSampleLibrary.sample(forFilenameOrID: $0) }
        store.seedMockAnnotations(for: hash, sample: matchedSample, image: image)
        mode = .inspect
        selected = store.documents[hash]?.scales.first?.id
        let count = store.documents[hash]?.scales.count ?? 0
        message = count > 0
            ? "Extracted \(count) scale pattern contours inside the cheek ROI. Click any number to confirm, reject, or redraw."
            : "Set Head ROI or click Propose regions."
    }
    private func fittedRect(size: CGSize) -> CGRect {
        guard let image, image.size.width > 0, image.size.height > 0 else { return .zero }
        let factor = min(size.width / image.size.width, size.height / image.size.height) * zoom
        let width = image.size.width * factor, height = image.size.height * factor
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }
    private func point(_ location: CGPoint, rect: CGRect) -> ScalePoint? {
        guard rect.width > 0, rect.height > 0, rect.contains(location) else { return nil }
        return ScalePoint(x: (location.x - rect.minX) / rect.width, y: (location.y - rect.minY) / rect.height)
    }
    private func handle(start: CGPoint, end: CGPoint, rect: CGRect) {
        guard let a = point(start, rect: rect), let b = point(end, rect: rect), hash != nil else { return }
        switch mode {
        case .head:
            let roi = ScaleRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
            guard roi.isValid else { message = "Drag a larger region inside the photograph."; return }
            if document?.scales.isEmpty == false { pendingROI = roi; confirmROIChange = true } else { applyROI(roi) }
        case .draw:
            guard let roi = document?.headROI, roi.contains(b) else { message = "Set a head region first; every scale vertex must be inside it."; return }
            draft.append(b)
        case .inspect:
            selected = document?.scales.last(where: { ScalePhotoReview.contains(b, polygon: $0.polygon) })?.id
        }
    }
    private func applyROI(_ roi: ScaleRect) {
        worker?.cancel(); requestID = UUID(); processing = false
        update { $0.setHeadROI(roi) }; pendingROI = nil; selected = nil; draft = []; mode = .inspect
        message = "Head region set. Propose regions or draw one scale at a time."
    }
    private func finishPolygon() {
        var changed = false
        if let redrawing { update { changed = $0.redraw(redrawing, polygon: draft) } }
        else { update { selected = $0.add(polygon: draft, source: .manual); changed = selected != nil } }
        guard changed else { message = "Use a simple closed boundary with at least 3 distinct points inside the head region."; return }
        endRedraw(); draft = []; mode = .inspect
        message = "Boundary saved as pending. Confirm it only after visual review."
    }
    private func endRedraw() {
        if let hash, let redrawLease { store.endRedraw(hash, lease: redrawLease) }
        redrawLease = nil; redrawing = nil
    }
    private func update(_ edit: (inout ScalePhotoReview) -> Void) { if let hash { store.update(hash, edit) } }
    private func propose() {
        guard let raster, let roi = document?.headROI, let hash else { return }
        worker?.cancel(); let token = UUID(); requestID = token; processing = true
        let threshold = threshold
        let headRevision = document?.headRevision
        worker = Task { @MainActor in
            let task = Task.detached(priority: .userInitiated) {
                guard let field = ContourEngine.detect(luminance: raster.pixels, width: raster.width, height: raster.height, smooth: true) else { return [[ScalePoint]]() }
                let mask = field.mask(threshold: threshold, lineWeight: 2)
                return ScaleRegionProposalEngine.closedRegions(edges: mask, width: raster.width, height: raster.height, roi: roi)
            }
            let regions = await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
            guard !Task.isCancelled, requestID == token, self.hash == hash, document?.headROI == roi, document?.headRevision == headRevision else { return }
            store.replaceProposals(hash, polygons: regions)
            processing = false; selected = nil
            message = regions.isEmpty ? "No enclosed regions at this threshold. Try a lower value or draw scales manually." : "Region proposals are pending; inspect each one. Up to 80 regions per run. Reviewed and manual work was preserved."
        }
    }
    private func draw(context: inout GraphicsContext, rect: CGRect) {
        func map(_ p: ScalePoint) -> CGPoint { CGPoint(x: rect.minX + p.x * rect.width, y: rect.minY + p.y * rect.height) }
        func path(_ points: [ScalePoint], close: Bool) -> Path {
            Path { p in
                guard let first = points.first else { return }
                p.move(to: map(first)); for v in points.dropFirst() { p.addLine(to: map(v)) }
                if close { p.closeSubpath() }
            }
        }
        if let roi = document?.headROI {
            let box = CGRect(x: rect.minX + roi.x * rect.width, y: rect.minY + roi.y * rect.height, width: roi.width * rect.width, height: roi.height * rect.height)
            context.stroke(Path(box), with: .color(.white.opacity(0.8)), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }
        for scale in document?.scales ?? [] {
            let outline = path(scale.polygon, close: true)
            let color = scale.status == .rejected ? Color.gray : tint
            context.fill(outline, with: .color(color.opacity(scale.status == .rejected ? 0.04 : 0.12)))
            context.stroke(outline, with: .color(color), style: StrokeStyle(lineWidth: selected == scale.id ? 3 : 1.4, dash: scale.status == .pending ? [4, 3] : []))
            if showsNumbers {
                let c = map(scale.center)
                context.fill(Path(ellipseIn: CGRect(x: c.x - 10, y: c.y - 10, width: 20, height: 20)), with: .color(.black.opacity(0.8)))
                context.draw(Text("\(scale.number)").font(.system(size: 11, weight: .bold)).foregroundColor(.white), at: c)
            }
        }
        context.stroke(path(draft, close: false), with: .color(.white), lineWidth: 2)
        for p in draft { let c = map(p); context.fill(Path(ellipseIn: CGRect(x: c.x - 3, y: c.y - 3, width: 6, height: 6)), with: .color(.white)) }
        if let (a, b) = dragPosition {
            context.stroke(Path(CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))), with: .color(.white), lineWidth: 2)
        }
    }
}
