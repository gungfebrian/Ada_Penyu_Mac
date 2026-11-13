import AppKit
import SwiftUI

private struct TurtlePhotoLoaderKey: EnvironmentKey {
    static let defaultValue: @MainActor (String?) async -> NSImage? = { _ in nil }
}

extension EnvironmentValues {
    var turtlePhotoLoader: @MainActor (String?) async -> NSImage? {
        get { self[TurtlePhotoLoaderKey.self] }
        set { self[TurtlePhotoLoaderKey.self] = newValue }
    }
}

/// Uses the shared authenticated transport and cache supplied by the app shell.
struct TurtlePhoto: View {
    let paths: [String]
    let size: CGFloat
    @Environment(\.turtlePhotoLoader) private var loadPhoto
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                PlaceholderImage(size: size)
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityLabel(image == nil ? "Photo unavailable" : "Turtle identity photo")
        .task(id: paths) {
            image = nil
            for path in paths where !path.isEmpty {
                let loaded = await loadPhoto(path)
                guard !Task.isCancelled else { return }
                if let loaded { image = loaded; return }
            }
        }
    }
}

extension Turtle {
    var identityPhotoPaths: [String] { [leftPhotoURL, rightPhotoURL].compactMap { $0 }.filter { !$0.isEmpty } }
}
