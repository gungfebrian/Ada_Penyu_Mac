import AppKit
import SwiftUI

struct NotSurePatchSource: Hashable {
    private let photoID: ObjectIdentifier
    let side: TurtlePhotoSide
    private let candidateID: String?

    init(photo: NSImage, side: TurtlePhotoSide, candidateID: String? = nil) {
        photoID = ObjectIdentifier(photo)
        self.side = side
        self.candidateID = candidateID
    }
}

struct NotSurePatchSession {
    private var sightingSource: NotSurePatchSource?
    private var candidateSource: NotSurePatchSource?
    var sighting: CGRect?
    var candidate: CGRect?

    mutating func updateSources(sighting: NotSurePatchSource?, candidate: NotSurePatchSource?) {
        if sightingSource != sighting { self.sighting = nil }
        if candidateSource != candidate { self.candidate = nil }
        sightingSource = sighting
        candidateSource = candidate
    }
}

enum NotSurePhotoGeometry {
    static func aspectFitRect(imageSize: NSSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, container.width > 0, container.height > 0 else {
            return CGRect(origin: .zero, size: container)
        }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let w = imageSize.width * scale
        let h = imageSize.height * scale
        return CGRect(x: (container.width - w) * 0.5, y: (container.height - h) * 0.5, width: w, height: h)
    }

    static func polygonPath(_ polygon: [ScalePoint], in rect: CGRect) -> Path {
        var path = Path()
        for (idx, pt) in polygon.enumerated() {
            let p = CGPoint(x: rect.minX + pt.x * rect.width, y: rect.minY + pt.y * rect.height)
            if idx == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }
}

enum NotSurePatchGeometry {
    static func selection(from start: CGPoint, to end: CGPoint, in photo: CGRect) -> CGRect? {
        guard photo.contains(start) else { return nil }
        let endX = min(photo.maxX, max(photo.minX, end.x))
        let endY = min(photo.maxY, max(photo.minY, end.y))
        let width = abs(endX - start.x)
        let height = abs(endY - start.y)
        guard width >= 4, height >= 4 else { return nil }
        return CGRect(
            x: (min(start.x, endX) - photo.minX) / photo.width,
            y: (min(start.y, endY) - photo.minY) / photo.height,
            width: width / photo.width,
            height: height / photo.height
        )
    }

    static func frame(of patch: CGRect, in photo: CGRect) -> CGRect {
        CGRect(
            x: photo.minX + patch.minX * photo.width,
            y: photo.minY + patch.minY * photo.height,
            width: patch.width * photo.width,
            height: patch.height * photo.height
        )
    }

    static func preview(patch: CGRect, photoSize: CGSize, in viewport: CGSize) -> (clip: CGRect, photo: CGRect) {
        let patchSize = CGSize(width: patch.width * photoSize.width, height: patch.height * photoSize.height)
        let clip = NotSurePhotoGeometry.aspectFitRect(imageSize: patchSize, in: viewport)
        let width = clip.width / patch.width
        let height = clip.height / patch.height
        return (clip, CGRect(
            x: clip.minX - patch.minX * width,
            y: clip.minY - patch.minY * height,
            width: width,
            height: height
        ))
    }
}

struct NotSurePatchPicker: View {
    let image: NSImage
    let accent: Color
    @Binding var patch: CGRect?
    @GestureState private var provisionalPatch: CGRect?

    var body: some View {
        GeometryReader { geometry in
            let photo = NotSurePhotoGeometry.aspectFitRect(imageSize: image.size, in: geometry.size)

            ZStack(alignment: .topLeading) {
                Image(nsImage: image)
                    .resizable()
                    .frame(width: photo.width, height: photo.height)
                    .position(x: photo.midX, y: photo.midY)

                if let selection = provisionalPatch ?? patch {
                    let box = NotSurePatchGeometry.frame(of: selection, in: photo)
                    Rectangle()
                        .fill(accent.opacity(0.12))
                        .overlay(Rectangle().strokeBorder(accent, lineWidth: 2))
                        .frame(width: box.width, height: box.height)
                        .position(x: box.midX, y: box.midY)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4)
                    .updating($provisionalPatch) { drag, state, _ in
                        state = NotSurePatchGeometry.selection(from: drag.startLocation, to: drag.location, in: photo)
                    }
                    .onEnded { drag in
                        if let selection = NotSurePatchGeometry.selection(from: drag.startLocation, to: drag.location, in: photo) {
                            patch = selection
                        }
                    }
            )
        }
    }
}

struct NotSurePatchPreview: View {
    let image: NSImage
    let patch: CGRect
    let outlines: [DetectedScalePattern]
    let accent: Color
    let viewport: NotSurePhotoViewport
    let onPanChanged: (CGSize) -> Void
    let onPanEnded: (CGSize) -> Void

    var body: some View {
        Canvas { context, size in
            let frames = NotSurePatchGeometry.preview(patch: patch, photoSize: image.size, in: size)
            context.clip(to: Path(frames.clip))
            context.draw(context.resolve(Image(nsImage: image)), in: frames.photo)
            for scale in outlines {
                context.stroke(
                    NotSurePhotoGeometry.polygonPath(scale.polygon, in: frames.photo),
                    with: .color(accent),
                    lineWidth: 1.5
                )
            }
        }
        .scaleEffect(viewport.scale)
        .offset(viewport.offset)
        .clipped()
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    if viewport.isZoomed { onPanChanged(value.translation) }
                }
                .onEnded { onPanEnded($0.translation) }
        )
    }
}
