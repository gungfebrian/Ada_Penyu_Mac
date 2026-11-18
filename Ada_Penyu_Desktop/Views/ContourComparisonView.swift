import AppKit
import SwiftUI

struct ContourSettings {
    var enabled = false
    var queryColor = Color.cyan
    var galleryColor = AdaColors.orange
    var threshold = 0.08
    var opacity = 0.95
    var lineWeight = 2
    var reduceNoise = true
    var linesOnly = false
    var patternOnly = true
    var showNumbers = true
    var querySide: TurtlePhotoSide = .left
    var gallerySide: TurtlePhotoSide = .left
}

/// Photo comparison only: no fingerprint, network call or identity write.
struct ContourComparisonView: View {
    let queryImage: NSImage?
    let galleryImage: NSImage?
    @Binding var settings: ContourSettings
    var queryTitle = "Query photograph"
    var galleryTitle = "Gallery photograph"
    var showsVisibilityControl = true
    @State private var zoom = 1.0
    @State private var pan: CGSize = .zero

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    if showsVisibilityControl {
                        Toggle("Contours", isOn: $settings.enabled).toggleStyle(.checkbox)
                            .accessibilityLabel("Show photo contours")
                    }
                    if settings.enabled {
                        Picker("Mode", selection: $settings.patternOnly) {
                            Text("Pattern Only").tag(true)
                            Text("Raw Edges").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 170)

                        ContourColorMenu(title: "Query", color: $settings.queryColor)
                        ContourColorMenu(title: "Candidate", color: $settings.galleryColor)
                        if settings.patternOnly {
                            Toggle("#", isOn: $settings.showNumbers).toggleStyle(.checkbox)
                                .help("Show numbered scale pattern labels (1, 2, 3...)")
                        }
                        Toggle("Lines only", isOn: $settings.linesOnly).toggleStyle(.checkbox)
                        Toggle("Smooth", isOn: $settings.reduceNoise).toggleStyle(.checkbox)
                    } else {
                        Text("Original photos · enable Contours to trace pattern")
                            .foregroundStyle(AdaColors.secondaryInk).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Menu("\(Int(zoom * 100))%") {
                        ForEach([1.0, 1.5, 2.0, 3.0, 4.0], id: \.self) { value in
                            Button("\(Int(value * 100))%") { zoom = value; pan = .zero }
                        }
                    }.frame(width: 72).help("Synchronized zoom. Drag either photograph to pan both.")
                    Button("1:1") { zoom = 1; pan = .zero }
                }.fixedSize(horizontal: true, vertical: false).frame(height: 26)
                }.scrollIndicators(.hidden)
                if settings.enabled {
                    ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        Text(settings.patternOnly ? "Pattern detail" : "Edge threshold")
                        Slider(value: $settings.threshold, in: 0.01...0.5, step: 0.01)
                            .frame(width: 140)
                            .accessibilityLabel("Edge strength threshold for both photographs")
                            .accessibilityValue(String(format: "%.2f", settings.threshold))
                        Text(settings.threshold, format: .number.precision(.fractionLength(2))).monospacedDigit().frame(width: 30)
                        Menu("Presets") {
                            Button("Fine · 0.04") { settings.threshold = 0.04 }
                            Button("Balanced · 0.08") { settings.threshold = 0.08 }
                            Button("Strong · 0.15") { settings.threshold = 0.15 }
                        }
                        Text("Opacity")
                        Slider(value: $settings.opacity, in: 0.2...1, step: 0.05)
                            .frame(width: 68).accessibilityLabel("Contour overlay opacity")
                            .disabled(settings.linesOnly)
                        Picker("Weight", selection: $settings.lineWeight) {
                            Text("Thin").tag(1); Text("Med").tag(2); Text("Bold").tag(3)
                        }.frame(width: 120)
                        Button("Reset") {
                            settings = ContourSettings(enabled: true, querySide: settings.querySide, gallerySide: settings.gallerySide)
                            zoom = 1; pan = .zero
                        }
                        Spacer(minLength: 0)
                    }.fixedSize(horizontal: true, vertical: false).frame(height: 22)
                    }.scrollIndicators(.hidden)
                }
            }
            .font(.system(size: 11)).controlSize(.small)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(AdaColors.card)
            Divider().overlay(AdaColors.line)
            HStack(spacing: 2) {
                ContourPhotoPane(image: queryImage, title: queryTitle, settings: settings,
                    side: settings.querySide, tint: settings.queryColor, zoom: zoom, pan: $pan)
                ContourPhotoPane(image: galleryImage, title: galleryTitle, settings: settings,
                    side: settings.gallerySide, tint: settings.galleryColor, zoom: zoom, pan: $pan)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(.black)
            HStack(spacing: 8) {
                Image(systemName: settings.patternOnly ? "viewfinder.circle" : "waveform.path.ecg")
                Text(settings.patternOnly
                     ? "Pattern-only smooth scale contours · numbered top-to-bottom for manual comparison"
                     : "Raw edge overlay · switch to Pattern Only to remove water & seagrass noise")
                    .lineLimit(1)
                Spacer(minLength: 0)
            }.font(.system(size: 10.5)).foregroundStyle(AdaColors.secondaryInk)
                .padding(.horizontal, 12).padding(.vertical, 6).background(AdaColors.card)
        }
    }
}

private struct ContourFieldKey: Equatable {
    let imageID: ObjectIdentifier?
    let smooth: Bool
    let patternOnly: Bool
    let side: TurtlePhotoSide
}

private struct ContourRenderKey: Equatable {
    let field: ContourFieldKey
    let threshold: Double
    let lineWeight: Int
    let enabled: Bool
}

private struct ContourPhotoPane: View {
    let image: NSImage?
    let title: String
    let settings: ContourSettings
    let side: TurtlePhotoSide
    let tint: Color
    let zoom: Double
    @Binding var pan: CGSize
    @State private var overlay: NSImage?
    @State private var patternROI: [ScalePoint] = []
    @State private var detectedPatterns: [DetectedScalePattern] = []
    @State private var cachedField: ContourField?
    @State private var cachedFieldKey: ContourFieldKey?
    @State private var cachedROI: [ScalePoint] = []
    @State private var cachedPatternFieldKey: ContourFieldKey?
    @State private var renderedKey: ContourRenderKey?
    @State private var processing = false
    @State private var error: String?
    @State private var coverage: Double?
    @State private var dragStart: CGSize?

    private var request: ContourRenderKey {
        ContourRenderKey(
            field: ContourFieldKey(
                imageID: image.map(ObjectIdentifier.init),
                smooth: settings.reduceNoise,
                patternOnly: settings.patternOnly,
                side: side
            ),
            threshold: settings.threshold,
            lineWeight: settings.lineWeight,
            enabled: settings.enabled
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).lineLimit(1)
                Spacer()
                if processing { ProgressView().controlSize(.mini) }
                if settings.enabled, renderedKey == request {
                    if settings.patternOnly {
                        Text("\(detectedPatterns.count) scales")
                            .foregroundStyle(tint)
                            .monospacedDigit()
                    } else if let coverage {
                        Text(String(format: "%.1f%% edges", coverage * 100)).foregroundStyle(.white.opacity(0.65))
                    }
                }
            }.font(.system(size: 11, weight: .semibold)).padding(.horizontal, 10).padding(.vertical, 7).background(.white.opacity(0.06))
            GeometryReader { geometry in
                ZStack {
                    Color.black
                    if let image {
                        let imageRect = fittedRect(for: image.size, in: geometry.size)
                        ZStack {
                            Image(nsImage: image).resizable().scaledToFit()
                                .opacity(settings.enabled && settings.linesOnly ? 0 : 1)
                            if settings.enabled, renderedKey == request {
                                if settings.patternOnly {
                                    patternOverlay(in: imageRect)
                                } else if let overlay {
                                    Image(nsImage: overlay).resizable().interpolation(.none).scaledToFit()
                                        .colorMultiply(tint)
                                        .opacity(settings.linesOnly ? 1 : settings.opacity)
                                }
                            }
                        }
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .scaleEffect(zoom).offset(pan)
                    } else {
                        ContentUnavailableView("Photo unavailable", systemImage: "photo",
                            description: Text("The actual reference photograph is required. No substitute image is used."))
                    }
                }.clipped().contentShape(Rectangle())
                    .gesture(DragGesture().onChanged { value in
                        if dragStart == nil { dragStart = pan }
                        let base = dragStart ?? .zero
                        pan = CGSize(width: base.width + value.translation.width, height: base.height + value.translation.height)
                    }.onEnded { _ in dragStart = nil })
            }
            if let error { Text(error).font(.caption).foregroundStyle(.orange).padding(8) }
        }.foregroundStyle(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: request) { await render() }
    }

    @ViewBuilder
    private func patternOverlay(in imageRect: CGRect) -> some View {
        ZStack {
            if !settings.linesOnly && patternROI.count >= 3 {
                // Dim non-pattern surroundings cleanly so scientists focus only on the facial scale cluster
                Canvas { context, size in
                    var maskPath = Path(CGRect(origin: .zero, size: size))
                    var roiPath = Path()
                    for (idx, pt) in patternROI.enumerated() {
                        let p = CGPoint(
                            x: imageRect.minX + pt.x * imageRect.width,
                            y: imageRect.minY + pt.y * imageRect.height
                        )
                        if idx == 0 { roiPath.move(to: p) } else { roiPath.addLine(to: p) }
                    }
                    roiPath.closeSubpath()
                    maskPath.addPath(roiPath)
                    context.fill(maskPath, with: .color(.black.opacity(0.46)), style: FillStyle(eoFill: true))
                }
                .allowsHitTesting(false)
            }

            Canvas { context, _ in
                if patternROI.count >= 3 {
                    var roiPath = Path()
                    for (idx, pt) in patternROI.enumerated() {
                        let p = CGPoint(
                            x: imageRect.minX + pt.x * imageRect.width,
                            y: imageRect.minY + pt.y * imageRect.height
                        )
                        if idx == 0 { roiPath.move(to: p) } else { roiPath.addLine(to: p) }
                    }
                    roiPath.closeSubpath()
                    context.stroke(
                        roiPath,
                        with: .color(tint.opacity(0.45)),
                        style: StrokeStyle(lineWidth: 1.1, dash: [5, 4])
                    )
                }

                let lineW = Double(max(1, settings.lineWeight)) * (settings.linesOnly ? 1.15 : 1.0)
                let strokeOpacity = settings.linesOnly ? 1.0 : settings.opacity
                for scale in detectedPatterns {
                    guard scale.polygon.count >= 3 else { continue }
                    var polyPath = Path()
                    for (idx, pt) in scale.polygon.enumerated() {
                        let p = CGPoint(
                            x: imageRect.minX + pt.x * imageRect.width,
                            y: imageRect.minY + pt.y * imageRect.height
                        )
                        if idx == 0 { polyPath.move(to: p) } else { polyPath.addLine(to: p) }
                    }
                    polyPath.closeSubpath()
                    context.fill(polyPath, with: .color(tint.opacity(settings.linesOnly ? 0.14 : 0.10)))
                    context.stroke(
                        polyPath,
                        with: .color(tint.opacity(strokeOpacity)),
                        style: StrokeStyle(lineWidth: lineW, lineCap: .round, lineJoin: .round)
                    )
                }
            }
            .allowsHitTesting(false)

            if settings.showNumbers {
                ForEach(detectedPatterns) { scale in
                    let cx = imageRect.minX + scale.centroid.x * imageRect.width
                    let cy = imageRect.minY + scale.centroid.y * imageRect.height
                    Text("\(scale.number)")
                        .font(.system(size: zoom >= 1.8 ? 10 : 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(tint.opacity(0.92), in: Capsule())
                        .position(x: cx, y: cy)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private func fittedRect(for imageSize: CGSize, in containerSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              containerSize.width > 0, containerSize.height > 0 else {
            return CGRect(origin: .zero, size: containerSize)
        }
        let scale = min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        let w = imageSize.width * scale
        let h = imageSize.height * scale
        return CGRect(x: (containerSize.width - w) / 2, y: (containerSize.height - h) / 2, width: w, height: h)
    }

    @MainActor
    private func render() async {
        let key = request
        processing = false; error = nil
        guard key.enabled, let image else { return }
        processing = true
        do {
            try await Task.sleep(for: .milliseconds(80))
            if key.field.patternOnly {
                guard let raster = PatternContourEngine.underwaterLuminance(from: image, maxDimension: 380) else {
                    error = "Unable to read this photograph."; processing = false; return
                }
                let roi: [ScalePoint]
                if cachedPatternFieldKey == key.field, cachedROI.count >= 3 {
                    roi = cachedROI
                } else {
                    let sideVal = key.field.side
                    let roiWorker = Task.detached(priority: .userInitiated) {
                        PatternContourEngine.detectFacialPatternROI(from: raster, side: sideVal).roi
                    }
                    roi = await withTaskCancellationHandler { await roiWorker.value } onCancel: { roiWorker.cancel() }
                    try Task.checkCancellation()
                    cachedROI = roi
                    cachedPatternFieldKey = key.field
                }

                let sensitivity = max(0.20, min(0.85, 0.72 - key.threshold * 2.7))
                let smoothness = key.field.smooth ? 0.72 : 0.35
                let config = PatternExtractionConfig(sensitivity: sensitivity, smoothness: smoothness)
                let patWorker = Task.detached(priority: .userInitiated) {
                    PatternContourEngine.extractPatterns(from: raster, roiPolygon: roi, config: config)
                }
                let patterns = await withTaskCancellationHandler { await patWorker.value } onCancel: { patWorker.cancel() }
                try Task.checkCancellation()
                patternROI = roi
                detectedPatterns = patterns
                renderedKey = key
                processing = false
                return
            }

            let field: ContourField
            if cachedFieldKey == key.field, let cachedField { field = cachedField }
            else {
                guard let raster = ContourRasterizer.luminance(from: image) else {
                    error = "Unable to read this photograph."; processing = false; return
                }
                let worker = Task.detached(priority: .userInitiated) {
                    ContourEngine.detect(luminance: raster.pixels, width: raster.width, height: raster.height, smooth: key.field.smooth)
                }
                let result = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
                try Task.checkCancellation()
                guard let result else { error = "Could not extract photo edges."; processing = false; return }
                field = result; cachedField = result; cachedFieldKey = key.field
            }
            let worker = Task.detached(priority: .userInitiated) {
                field.mask(threshold: key.threshold, lineWeight: key.lineWeight)
            }
            let mask = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            try Task.checkCancellation()
            guard let image = ContourRasterizer.overlay(field: field, mask: mask) else {
                error = "Could not render photo edges."; processing = false; return
            }
            overlay = image; renderedKey = key
            coverage = Double(mask.filter { $0 > 0 }.count) / Double(mask.count)
            processing = false
        } catch {
            // A newer photograph or setting owns the state; never publish old work.
        }
    }
}

private struct ContourColorMenu: View {
    let title: String
    @Binding var color: Color
    private let choices: [(String, Color)] = [
        ("Cyan", .cyan), ("Amber", AdaColors.orange), ("White", .white),
        ("Magenta", .pink), ("Lime", .green)
    ]
    var body: some View {
        Menu {
            ForEach(choices, id: \.0) { name, value in
                Button { color = value } label: {
                    Label(name, systemImage: color == value ? "checkmark.circle.fill" : "circle")
                }
            }
        } label: {
            Label { Text(title) } icon: { Circle().fill(color).frame(width: 10, height: 10) }
        }.accessibilityLabel(title).help("Choose a high-contrast contour color")
    }
}
