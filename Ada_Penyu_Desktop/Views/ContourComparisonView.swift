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
            VStack(alignment: .leading, spacing: 8) {
                ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    if showsVisibilityControl {
                        Toggle("Contours", isOn: $settings.enabled).toggleStyle(.checkbox)
                            .accessibilityLabel("Show photo contours")
                    }
                    if settings.enabled {
                        ContourColorMenu(title: "Query color", color: $settings.queryColor)
                        ContourColorMenu(title: "Gallery color", color: $settings.galleryColor)
                        Toggle("Lines only", isOn: $settings.linesOnly).toggleStyle(.checkbox)
                        Toggle("Reduce noise", isOn: $settings.reduceNoise).toggleStyle(.checkbox)
                    } else {
                        Text("Original photographs · turn on Contours to inspect scale edges")
                            .foregroundStyle(AdaColors.secondaryInk).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    Menu("\(Int(zoom * 100))%") {
                        ForEach([1.0, 1.5, 2.0, 3.0, 4.0], id: \.self) { value in
                            Button("\(Int(value * 100))%") { zoom = value; pan = .zero }
                        }
                    }.frame(width: 78).help("Synchronized zoom. Drag either photograph to pan both.")
                    Button("Recenter") { zoom = 1; pan = .zero }
                }.fixedSize(horizontal: true, vertical: false).frame(height: 26)
                }.scrollIndicators(.hidden)
                if settings.enabled {
                    ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        Text("Edge threshold")
                        Slider(value: $settings.threshold, in: 0.01...0.5, step: 0.01)
                            .frame(width: 150)
                            .accessibilityLabel("Edge strength threshold for both photographs")
                            .accessibilityValue(String(format: "%.2f", settings.threshold))
                            .help("Lower shows faint detail. Higher keeps stronger connected edges. Same cutoff for both photographs.")
                        Text(settings.threshold, format: .number.precision(.fractionLength(2))).monospacedDigit().frame(width: 30)
                        Menu("Presets") {
                            Button("Fine detail · 0.04") { settings.threshold = 0.04 }
                            Button("Balanced · 0.08") { settings.threshold = 0.08 }
                            Button("Strong edges · 0.15") { settings.threshold = 0.15 }
                        }
                        Text("Opacity")
                        Slider(value: $settings.opacity, in: 0.2...1, step: 0.05)
                            .frame(width: 70).accessibilityLabel("Contour overlay opacity")
                            .disabled(settings.linesOnly)
                        Picker("Line weight", selection: $settings.lineWeight) {
                            Text("Thin").tag(1); Text("Medium").tag(2); Text("Bold").tag(3)
                        }.frame(width: 140)
                        Button("Reset") {
                            settings = ContourSettings(enabled: true)
                            zoom = 1; pan = .zero
                        }
                        Spacer(minLength: 0)
                    }.fixedSize(horizontal: true, vertical: false).frame(height: 24)
                    }.scrollIndicators(.visible)
                }
            }
            .font(.system(size: 11)).controlSize(.small)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(AdaColors.card)
            Divider().overlay(AdaColors.line)
            HStack(spacing: 2) {
                ContourPhotoPane(image: queryImage, title: queryTitle, settings: settings,
                    tint: settings.queryColor, zoom: zoom, pan: $pan)
                ContourPhotoPane(image: galleryImage, title: galleryTitle, settings: settings,
                    tint: settings.galleryColor, zoom: zoom, pan: $pan)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(.black)
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                Text("Visual edge aid · includes glare and background edges. Edge threshold is not identity confidence. Photographs are not geometrically aligned.")
                Spacer(minLength: 0)
            }.font(.system(size: 11)).foregroundStyle(AdaColors.secondaryInk)
                .padding(10).background(AdaColors.card)
        }
    }
}

private struct ContourFieldKey: Equatable {
    let imageID: ObjectIdentifier?
    let smooth: Bool
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
    let tint: Color
    let zoom: Double
    @Binding var pan: CGSize
    @State private var overlay: NSImage?
    @State private var cachedField: ContourField?
    @State private var cachedFieldKey: ContourFieldKey?
    @State private var renderedKey: ContourRenderKey?
    @State private var processing = false
    @State private var error: String?
    @State private var coverage: Double?
    @State private var dragStart: CGSize?

    private var request: ContourRenderKey {
        ContourRenderKey(field: ContourFieldKey(imageID: image.map(ObjectIdentifier.init), smooth: settings.reduceNoise),
            threshold: settings.threshold, lineWeight: settings.lineWeight, enabled: settings.enabled)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).lineLimit(1)
                Spacer()
                if processing { ProgressView().controlSize(.mini) }
                if settings.enabled, renderedKey == request, let coverage {
                    Text(String(format: "%.1f%% edge pixels", coverage * 100)).foregroundStyle(.white.opacity(0.65))
                }
            }.font(.system(size: 11, weight: .semibold)).padding(10).background(.white.opacity(0.06))
            GeometryReader { geometry in
                ZStack {
                    Color.black
                    if let image {
                        ZStack {
                            Image(nsImage: image).resizable().scaledToFit()
                                .opacity(settings.enabled && settings.linesOnly ? 0 : 1)
                            if settings.enabled, renderedKey == request, let overlay {
                                Image(nsImage: overlay).resizable().interpolation(.none).scaledToFit()
                                    .colorMultiply(tint)
                                    .opacity(settings.linesOnly ? 1 : settings.opacity)
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

    @MainActor
    private func render() async {
        let key = request
        processing = false; error = nil
        guard key.enabled, let image else { return }
        processing = true
        do {
            try await Task.sleep(for: .milliseconds(100))
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
