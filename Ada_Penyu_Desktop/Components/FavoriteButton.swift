import SwiftUI

struct FavoriteButton: View {
    let isFavorite: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isFavorite ? AdaColors.accent : AdaColors.secondaryInk)
                .frame(width: 28, height: 28)
                .background(
                    isFavorite ? AdaColors.accent.opacity(0.14) : Color.black.opacity(0.045),
                    in: Circle()
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isFavorite)
        .help(isFavorite ? "Remove from favorites" : "Add to favorites")
        .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
    }
}
