import SwiftUI

/// Toggles whether an individual sea turtle is tracked on the account's watchlist.
struct FavoriteButton: View {
    let isFavorite: Bool
    var isVisible: Bool = true
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: isFavorite ? "bookmark.fill" : "bookmark")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(isFavorite ? AdaColors.navy : (isHovered ? AdaColors.ink : AdaColors.secondaryInk))
                .frame(width: 30, height: 30)
                .background(
                    isFavorite
                        ? AdaColors.navy.opacity(isHovered ? 0.14 : 0.09)
                        : (isHovered ? Color.black.opacity(0.06) : Color.clear),
                    in: Circle()
                )
                .overlay(
                    Circle()
                        .stroke(isFavorite ? AdaColors.navy.opacity(0.16) : (isHovered ? AdaColors.line : .clear), lineWidth: 1)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(isFavorite || isVisible || isHovered ? 1 : 0.35)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.14), value: isFavorite)
        .animation(.easeInOut(duration: 0.14), value: isHovered)
        .help(isFavorite ? "Remove from watchlist" : "Add to watchlist")
        .accessibilityLabel(isFavorite ? "Remove from watchlist" : "Add to watchlist")
    }
}
