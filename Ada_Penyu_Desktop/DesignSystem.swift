import SwiftUI

enum AdaColors {
    // Shared with the mobile app's turtle design system.
    static let canvas = Color(red: 232 / 255, green: 232 / 255, blue: 232 / 255)
    static let sidebar = Color(red: 242 / 255, green: 242 / 255, blue: 242 / 255)
    static let card = Color.white
    static let ink = Color(red: 0.08, green: 0.09, blue: 0.11)
    static let secondaryInk = Color(red: 0.43, green: 0.46, blue: 0.51)
    static let tertiaryInk = Color(red: 0.61, green: 0.64, blue: 0.69)
    static let navy = Color(red: 12 / 255, green: 42 / 255, blue: 62 / 255)
    static let navySoft = Color(red: 24 / 255, green: 58 / 255, blue: 82 / 255)
    static let line = Color.black.opacity(0.08)
    static let green = Color(red: 0.09, green: 0.48, blue: 0.31)
    static let orange = Color(red: 230 / 255, green: 172 / 255, blue: 62 / 255)
    static let red = Color(red: 214 / 255, green: 40 / 255, blue: 40 / 255)
    static let accent = Color(red: 74 / 255, green: 144 / 255, blue: 205 / 255)
}

extension View {
    func adaCard(padding: CGFloat = 20, radius: CGFloat = 12) -> some View {
        self
            .padding(padding)
            .background(AdaColors.card)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

}

struct ConditionPill: View {
    let condition: TurtleCondition

    var body: some View {
        Text(condition.rawValue)
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1)
            .foregroundStyle(condition.tint)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(condition.background)
            .clipShape(Capsule())
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(isSelected ? Color.white : AdaColors.secondaryInk)
                .padding(.horizontal, 14)
                .frame(height: 29)
                .background(isSelected ? AdaColors.navy : AdaColors.card)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

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

/// Brand mark shared with the mobile app. The image is the same template asset
/// used by `TurtleMapPinView`, so the desktop shell and map speak the same
/// visual language instead of falling back to an SF Symbol.
struct TurtleBrandMark: View {
    let size: CGFloat
    var background: Color = AdaColors.navy

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(background)
            .frame(width: size, height: size)
            .overlay {
                Image("Turtle")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.18)
                    .foregroundStyle(.white)
            }
    }
}

/// Compact annotation pin copied from the mobile app's `TurtleMapPinView`.
struct TurtleMapPin: View {
    let isSelected: Bool

    var body: some View {
        VStack(spacing: -1) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white)
                .frame(width: 44, height: 44)
                .overlay {
                    Image("TurtleMapPinIcon")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .padding(9)
                        .foregroundStyle(AdaColors.navy)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(isSelected ? AdaColors.accent : Color.clear, lineWidth: 2)
                }

            PinPointerTriangle()
                .fill(Color.white)
                .frame(width: 14, height: 8)
        }
        .shadow(color: .black.opacity(0.22), radius: 4, y: 2)
    }
}

struct PinPointerTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct PlaceholderImage: View {
    var size: CGFloat = 32
    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.black.opacity(0.07))
            .frame(width: size, height: size)
    }
}

struct SectionTitle: View {
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AdaColors.ink)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(AdaColors.tertiaryInk)
            }
        }
    }
}
