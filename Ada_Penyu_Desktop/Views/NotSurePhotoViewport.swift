import CoreGraphics

struct NotSureComparisonViewports {
    var sighting = NotSurePhotoViewport()
    var candidate = NotSurePhotoViewport()
    var overlay = NotSurePhotoViewport()
}

struct NotSurePhotoViewport {
    static let maximumScale: CGFloat = 4

    private(set) var scale: CGFloat = 1
    private var pan: CGSize = .zero
    var dragDelta: CGSize = .zero

    var isZoomed: Bool { scale > 1 }

    var offset: CGSize {
        CGSize(width: pan.width + dragDelta.width, height: pan.height + dragDelta.height)
    }

    func magnified(by factor: CGFloat) -> Self {
        var viewport = self
        viewport.setScale(scale * factor)
        return viewport
    }

    mutating func stepZoom(by delta: CGFloat) {
        setScale(scale + delta)
    }

    mutating func commitPan(_ translation: CGSize) {
        if isZoomed {
            pan.width += translation.width
            pan.height += translation.height
        }
        dragDelta = .zero
    }

    private mutating func setScale(_ newScale: CGFloat) {
        scale = min(Self.maximumScale, max(1, newScale))
        if !isZoomed {
            pan = .zero
            dragDelta = .zero
        }
    }
}
