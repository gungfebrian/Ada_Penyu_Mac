import SwiftUI

/// Route inside the Settings workspace detail pane.
enum SettingsDetailRoute: Hashable, Identifiable {
    case passwordSecurity
    case organisationProfile
    case manageRangers
    case addRanger
    case rangerDetails(UUID)
    case language
    case appPermissions
    case contourReview
    case helpSupport
    case developerAPIKey

    var id: String {
        switch self {
        case .passwordSecurity: "passwordSecurity"
        case .organisationProfile: "organisationProfile"
        case .manageRangers: "manageRangers"
        case .addRanger: "addRanger"
        case .rangerDetails(let memberID): "rangerDetails.\(memberID.uuidString)"
        case .language: "language"
        case .appPermissions: "appPermissions"
        case .contourReview: "contourReview"
        case .helpSupport: "helpSupport"
        case .developerAPIKey: "developerAPIKey"
        }
    }
}

private struct SettingsSplitModeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var settingsSplitMode: Bool {
        get { self[SettingsSplitModeKey.self] }
        set { self[SettingsSplitModeKey.self] = newValue }
    }
}

/// Shared Settings section with an external title and a grouped white FigCraft card.
struct SettingsSectionGroup<Content: View>: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey? = nil
    var secondary: Bool = false
    var compact: Bool = false
    @ViewBuilder let content: Content

    private var radius: CGFloat {
        compact ? 18 : AdaLayout.cardRadius
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 7 : 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: secondary ? 12.5 : (compact ? 13 : 14), weight: .semibold))
                    .foregroundStyle(secondary ? AdaColors.secondaryInk : AdaColors.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: compact ? 11 : 12))
                        .foregroundStyle(AdaColors.secondaryInk)
                }
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content
            }
            .background(AdaColors.card)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(AdaColors.line, lineWidth: 1)
            )
        }
    }
}

struct SettingsRowDivider: View {
    var inset: CGFloat = 56
    var body: some View {
        Divider()
            .overlay(AdaColors.line)
            .padding(.leading, inset)
    }
}

/// Clickable drill-down row styled to match the iPhone Settings hierarchy on macOS.
struct SettingsNavigationRow: View {
    let icon: String
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey? = nil
    var trailingValue: String? = nil
    var showsChevron: Bool = true
    var isSelected: Bool = false
    var isSecondary: Bool = false
    var isDisabled: Bool = false
    var compact: Bool = false
    var accessibilityID: String? = nil
    let action: () -> Void

    @State private var isHovered = false

    private var rowBackground: Color {
        guard !isDisabled else { return .clear }
        if isSelected {
            return AdaColors.navy.opacity(0.08)
        }
        if isHovered {
            return AdaColors.canvas.opacity(0.75)
        }
        return .clear
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: compact ? 11 : 14) {
                Image(systemName: icon)
                    .font(.system(size: compact ? 14.5 : 16, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? AdaColors.navy : (isSecondary ? AdaColors.secondaryInk : AdaColors.navy))
                    .frame(width: compact ? 22 : 24, height: compact ? 22 : 24)

                VStack(alignment: .leading, spacing: 1.5) {
                    Text(title)
                        .font(.system(size: compact ? 13.5 : 14, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isDisabled ? AdaColors.secondaryInk : (isSelected ? AdaColors.navy : AdaColors.ink))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: compact ? 11 : 12))
                            .foregroundStyle(AdaColors.secondaryInk)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 10)

                if let trailingValue, !trailingValue.isEmpty {
                    Text(trailingValue)
                        .font(.system(size: compact ? 12 : 13, weight: isSelected ? .medium : .regular))
                        .foregroundStyle(isSelected ? AdaColors.navy : AdaColors.secondaryInk)
                        .lineLimit(1)
                }

                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: compact ? 10.5 : 12, weight: .semibold))
                        .foregroundStyle(isSelected ? AdaColors.navy : AdaColors.secondaryInk.opacity(0.6))
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, compact ? 14 : 18)
            .padding(.vertical, compact ? 10.5 : 14)
            .frame(maxWidth: .infinity, minHeight: compact ? 44 : 52, alignment: .leading)
            .background(rowBackground)
            .overlay(alignment: .leading) {
                if isSelected {
                    Capsule()
                        .fill(AdaColors.navy)
                        .frame(width: 3, height: 22)
                        .padding(.leading, 4)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { isHovered = $0 }
        .accessibilityValue(trailingValue ?? "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .modifier(OptionalAccessibilityIdentifier(id: accessibilityID))
    }
}

/// Non-interactive informational row inside a Settings card (e.g., Software version).
struct SettingsInfoRow: View {
    let icon: String
    let title: LocalizedStringKey
    let value: String
    var compact: Bool = false
    var accessibilityID: String? = nil

    var body: some View {
        HStack(spacing: compact ? 11 : 14) {
            Image(systemName: icon)
                .font(.system(size: compact ? 14.5 : 16, weight: .medium))
                .foregroundStyle(AdaColors.navy)
                .frame(width: compact ? 22 : 24, height: compact ? 22 : 24)

            Text(title)
                .font(.system(size: compact ? 13.5 : 14, weight: .medium))
                .foregroundStyle(AdaColors.ink)

            Spacer(minLength: 10)

            Text(value)
                .font(.system(size: compact ? 12 : 13))
                .foregroundStyle(AdaColors.secondaryInk)
                .textSelection(.enabled)
        }
        .padding(.horizontal, compact ? 14 : 18)
        .padding(.vertical, compact ? 10.5 : 14)
        .frame(maxWidth: .infinity, minHeight: compact ? 44 : 52, alignment: .leading)
        .accessibilityElement(children: .combine)
        .modifier(OptionalAccessibilityIdentifier(id: accessibilityID))
    }
}

/// Detail screen container with a clear Mac back affordance and scrollable FigCraft column.
struct SettingsDetailScaffold<Trailing: View, Content: View>: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey? = nil
    var backLabel: LocalizedStringKey = "Settings"
    var isBackDisabled: Bool = false
    var isNestedRoute: Bool = false
    let onBack: () -> Void
    @ViewBuilder let trailing: Trailing
    @ViewBuilder let content: Content

    @Environment(\.settingsSplitMode) private var isSplitMode

    init(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        backLabel: LocalizedStringKey = "Settings",
        isBackDisabled: Bool = false,
        isNestedRoute: Bool = false,
        onBack: @escaping () -> Void,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.backLabel = backLabel
        self.isBackDisabled = isBackDisabled
        self.isNestedRoute = isNestedRoute
        self.onBack = onBack
        self.trailing = trailing()
        self.content = content()
    }

    private var showsBackButton: Bool {
        !isSplitMode || isNestedRoute
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .center, spacing: 14) {
                    if showsBackButton {
                        Button(action: onBack) {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 12, weight: .semibold))
                                Text(backLabel)
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundStyle(isBackDisabled ? AdaColors.secondaryInk : AdaColors.navy)
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .background(AdaColors.card, in: Capsule())
                            .overlay(Capsule().stroke(AdaColors.line, lineWidth: 1))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(isBackDisabled)
                        .help("Back")
                        .accessibilityLabel("Back")
                        .accessibilityIdentifier("settings.detail.backButton")
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(AdaColors.ink)
                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: 12))
                                .foregroundStyle(AdaColors.secondaryInk)
                        }
                    }

                    Spacer(minLength: 12)
                    trailing
                }

                content
            }
            .frame(maxWidth: isSplitMode ? 720 : 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, isSplitMode ? 0 : AdaLayout.pagePadding)
            .padding(.bottom, 32)
        }
    }
}

struct SettingsStatusBanner: View {
    enum Style {
        case error, success, info, warning

        var icon: String {
            switch self {
            case .error: "exclamationmark.triangle.fill"
            case .success: "checkmark.circle.fill"
            case .info: "info.circle.fill"
            case .warning: "exclamationmark.circle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .error: AdaColors.red
            case .success: AdaColors.green
            case .info: AdaColors.navy
            case .warning: AdaColors.orange
            }
        }

        var background: Color {
            switch self {
            case .error: AdaColors.red.opacity(0.08)
            case .success: AdaColors.green.opacity(0.09)
            case .info: AdaColors.navy.opacity(0.06)
            case .warning: AdaColors.orange.opacity(0.14)
            }
        }
    }

    let style: Style
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: style.icon)
                .font(.system(size: 14))
                .foregroundStyle(style.tint)
                .padding(.top, 1)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(AdaColors.ink)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct OptionalAccessibilityIdentifier: ViewModifier {
    let id: String?
    func body(content: Content) -> some View {
        if let id {
            content.accessibilityIdentifier(id)
        } else {
            content
        }
    }
}

/// Shared bundle version formatting for Settings Support.
enum AppVersionInfo {
    static func displayString(bundle: Bundle = .main) -> String {
        let short = (bundle.infoDictionary?["CFBundleShortVersionString"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let build = (bundle.infoDictionary?["CFBundleVersion"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let version = (short?.isEmpty == false ? short! : "1.0")
        if let build, !build.isEmpty {
            return "AdaPenyu v\(version) (\(build))"
        }
        return "AdaPenyu v\(version)"
    }
}
