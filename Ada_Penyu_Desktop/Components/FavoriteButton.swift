import SwiftUI

/// Toggles whether an individual sea turtle is saved for quick follow-up.
struct FavoriteButton: View {
    let isFavorite: Bool
    var isVisible: Bool = true
    let action: () -> Void
    @State private var isHovered = false

    private var iconOpacity: Double {
        if isFavorite || isHovered { return 1.0 }
        return isVisible ? 0.85 : 0.32
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: isFavorite ? "bookmark.fill" : "bookmark")
                .font(.system(size: 12.5, weight: isFavorite ? .semibold : .medium))
                .foregroundStyle(isFavorite ? AdaColors.navy : (isHovered ? AdaColors.ink : AdaColors.secondaryInk))
                .frame(width: 30, height: 30)
                .background(
                    isFavorite
                        ? AdaColors.navy.opacity(isHovered ? 0.14 : 0.09)
                        : (isHovered ? AdaColors.navy.opacity(0.06) : Color.clear),
                    in: Circle()
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(iconOpacity)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.14), value: isFavorite)
        .animation(.easeInOut(duration: 0.14), value: isHovered)
        .help(isFavorite ? "Remove from Saved" : "Save sea turtle")
        .accessibilityLabel(isFavorite ? "Remove from Saved" : "Save sea turtle")
    }
}
