import SwiftUI

enum AdaColors {
    // Sampled from the approved 1512 x 982 desktop compositions.
    static let canvas = Color(red: 245 / 255, green: 245 / 255, blue: 247 / 255)
    static let sidebar = Color(red: 239 / 255, green: 240 / 255, blue: 241 / 255)
    static let card = Color.white
    static let ink = Color(red: 0.08, green: 0.09, blue: 0.11)
    static let secondaryInk = Color(red: 0.43, green: 0.46, blue: 0.51)
    static let tertiaryInk = Color(red: 0.61, green: 0.64, blue: 0.69)
    static let navy = Color(red: 12 / 255, green: 42 / 255, blue: 62 / 255)
    static let navySoft = Color(red: 24 / 255, green: 58 / 255, blue: 82 / 255)
    static let brandBlue = Color(red: 22 / 255, green: 60 / 255, blue: 96 / 255)
    static let line = Color.black.opacity(0.08)
    static let green = Color(red: 0.09, green: 0.48, blue: 0.31)
    static let orange = Color(red: 230 / 255, green: 172 / 255, blue: 62 / 255)
    static let red = Color(red: 214 / 255, green: 40 / 255, blue: 40 / 255)
    static let accent = Color(red: 74 / 255, green: 144 / 255, blue: 205 / 255)
}

enum AdaLayout {
    static let defaultWindowSize = CGSize(width: 1_512, height: 900)
    static let minimumWindowSize = CGSize(width: 1_100, height: 680)
    static let sidebarWidth: CGFloat = 253
    static let mapFilterWidth: CGFloat = 287
    static let tableMinimumWidth: CGFloat = 760
    static let tableSpeciesWidth: CGFloat = 220
    static let tableLocationWidth: CGFloat = 180
    static let tableLastSeenWidth: CGFloat = 192
    static let tableSightingsWidth: CGFloat = 55
    static let tableConditionWidth: CGFloat = 82
    static let tableActionWidth: CGFloat = 28
    static let pagePadding: CGFloat = 22
    static let cardRadius: CGFloat = 11
    static let containerRadius: CGFloat = 20
    static let windowChromeTopPadding: CGFloat = 28
}

extension View {
    func adaCard(padding: CGFloat = 20, radius: CGFloat = AdaLayout.cardRadius) -> some View {
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
    var horizontalPadding: CGFloat = 13
    var unselectedBackground: Color = AdaColors.card
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(isSelected ? Color.white : AdaColors.secondaryInk)
                .padding(.horizontal, horizontalPadding)
                .frame(height: 28)
                .background(isSelected ? AdaColors.navy : unselectedBackground)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
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
