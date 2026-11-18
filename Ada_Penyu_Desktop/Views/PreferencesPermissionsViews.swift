import AppKit
import SwiftUI

// MARK: - Language Picker

struct LanguageSettingsView: View {
    @ObservedObject var localization: LocalizationManager
    let onBack: () -> Void

    var body: some View {
        SettingsDetailScaffold(
            title: "Language",
            subtitle: "Choose the display language for AdaPenyu on this Mac.",
            onBack: onBack
        ) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(spacing: 0) {
                    ForEach(Array(AppLanguage.allCases.enumerated()), id: \.element.id) { index, option in
                        if index > 0 {
                            SettingsRowDivider(inset: 18)
                        }
                        languageRow(option)
                    }
                }
                .background(AdaColors.card)
                .clipShape(RoundedRectangle(cornerRadius: AdaLayout.cardRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AdaLayout.cardRadius, style: .continuous)
                        .stroke(AdaColors.line, lineWidth: 1)
                )

                Text("Language changes apply immediately and are saved on this Mac.")
                    .font(.system(size: 12))
                    .foregroundStyle(AdaColors.secondaryInk)
                    .padding(.horizontal, 4)
            }
        }
    }

    private func languageRow(_ option: AppLanguage) -> some View {
        let isSelected = localization.language == option
        return Button {
            localization.language = option
        } label: {
            HStack(spacing: 14) {
                Text(option.displayName)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(AdaColors.ink)
                Spacer(minLength: 12)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AdaColors.navy)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("settings.language.\(option.rawValue)")
    }
}

// MARK: - macOS App Permissions Help

enum MacSystemSettingsPanel {
    static let filesAndFoldersURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")!
}

struct AppPermissionsView: View {
    @ObservedObject var store: AppStore
    let onBack: () -> Void
    var openSystemURL: (URL) -> Bool = { NSWorkspace.shared.open($0) }

    @State private var systemSettingsError: String?

    var body: some View {
        SettingsDetailScaffold(
            title: "App Permissions",
            subtitle: "How AdaPenyu Mac uses macOS sandbox and file permissions.",
            onBack: onBack
        ) {
            VStack(alignment: .leading, spacing: 18) {
                if let systemSettingsError {
                    SettingsStatusBanner(style: .warning, message: systemSettingsError)
                }

                VStack(alignment: .leading, spacing: 18) {
                    permissionSection(
                        icon: "folder",
                        title: "Selected Files & Folders",
                        description: "AdaPenyu Mac imports turtle photos and exports reports only for files and folders you explicitly choose through the macOS file picker."
                    )

                    Button {
                        if !openSystemURL(MacSystemSettingsPanel.filesAndFoldersURL) {
                            systemSettingsError = "Could not open macOS System Settings."
                        } else {
                            systemSettingsError = nil
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up.forward.app")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Open Files & Folders in System Settings")
                                .font(.system(size: 13, weight: .semibold))
                        }
                    }
                    .buttonStyle(AdaPillButtonStyle(secondary: true))
                    .accessibilityIdentifier("settings.permissions.openFilesPanel")

                    Divider().overlay(AdaColors.line)

                    permissionSection(
                        icon: "network",
                        title: "Network Access",
                        description: "Used to sign in and sync organisation records with your configured AdaPenyu backend.",
                        footnote: store.apiBaseURLString
                    )

                    Divider().overlay(AdaColors.line)

                    permissionSection(
                        icon: "info.circle",
                        title: "Phone-Only Permissions Not Used",
                        description: "AdaPenyu Mac does not request Camera, Photos Library, Location, or Push Notification permissions."
                    )
                }
                .padding(24)
                .background(AdaColors.card, in: RoundedRectangle(cornerRadius: AdaLayout.cardRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AdaLayout.cardRadius, style: .continuous)
                        .stroke(AdaColors.line, lineWidth: 1)
                )
            }
        }
    }

    private func permissionSection(
        icon: String,
        title: LocalizedStringKey,
        description: LocalizedStringKey,
        footnote: String? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(AdaColors.navy)
                .frame(width: 36, height: 36)
                .background(AdaColors.canvas, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AdaColors.ink)
                Text(description)
                    .font(.system(size: 13))
                    .foregroundStyle(AdaColors.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                if let footnote, !footnote.isEmpty {
                    Text(footnote)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(AdaColors.secondaryInk)
                        .textSelection(.enabled)
                }
            }
        }
    }
}
