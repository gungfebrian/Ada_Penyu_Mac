import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: AppStore
    @ObservedObject var model: OrganizationAPIKeySettings

    var body: some View {
        Group {
            if let detail = store.settingsDetail {
                detailView(for: detail)
            } else {
                overview
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .alert(item: Binding(get: { model.pendingDestination }, set: { if $0 == nil { model.cancelNavigation() } })) { destination in
            Alert(
                title: Text("Leave without saving your API key?"),
                message: Text("This is the only time the full key is available. Leaving discards it from this screen. You would need to rotate again to get another key."),
                primaryButton: .destructive(Text("Discard and Leave")) { store.discardKeyAndNavigate(to: destination) },
                secondaryButton: .cancel(Text("Stay")) { model.cancelNavigation() }
            )
        }
        .alert(item: Binding(get: { store.pendingSettingsDetailTarget }, set: { if $0 == nil { store.cancelPendingSettingsDetailNavigation() } })) { _ in
            Alert(
                title: Text("Leave without saving your API key?"),
                message: Text("This is the only time the full key is available. Leaving discards it from this screen. You would need to rotate again to get another key."),
                primaryButton: .destructive(Text("Discard and Leave")) { store.discardKeyAndCompleteSettingsDetailNavigation() },
                secondaryButton: .cancel(Text("Stay")) { store.cancelPendingSettingsDetailNavigation() }
            )
        }
    }

    // MARK: - Overview

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                accountSummaryHeader

                // Account section
                SettingsSectionGroup(title: "Account") {
                    SettingsNavigationRow(
                        icon: "lock",
                        title: "Password & Security",
                        trailingValue: store.isDemoBypassActive ? "Demo" : nil,
                        accessibilityID: "settings.row.passwordSecurity"
                    ) {
                        store.requestSettingsDetail(.passwordSecurity)
                    }
                }

                // Support section
                SettingsSectionGroup(title: "Support") {
                    SettingsInfoRow(
                        icon: "info.circle",
                        title: "Software version",
                        value: AppVersionInfo.displayString(),
                        accessibilityID: "settings.row.softwareVersion"
                    )
                    SettingsRowDivider()
                    SettingsNavigationRow(
                        icon: "questionmark.circle",
                        title: "Help & Support",
                        accessibilityID: "settings.row.helpSupport"
                    ) {
                        store.requestSettingsDetail(.helpSupport)
                    }
                }

                // Developer Options section (visually secondary, preserving PR #14 API key controls)
                SettingsSectionGroup(
                    title: "Developer Options",
                    subtitle: "Connect external tools to your organization's data.",
                    secondary: true
                ) {
                    SettingsNavigationRow(
                        icon: "key.horizontal",
                        title: "Organization API Key",
                        subtitle: "Read-only credentials for external scripts and dashboards",
                        trailingValue: apiKeyRowStatus,
                        isSecondary: true,
                        accessibilityID: "settings.row.organizationAPIKey"
                    ) {
                        store.requestSettingsDetail(.developerAPIKey)
                    }
                }

                logoutButton
            }
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AdaLayout.pagePadding)
            .padding(.bottom, 36)
        }
    }

    private var accountSummaryHeader: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(AdaColors.navy)
                .frame(width: 44, height: 44)
                .overlay {
                    Text(accountInitial)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(store.accountName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AdaColors.ink)
                HStack(spacing: 6) {
                    if !store.authEmail.isEmpty {
                        Text(store.authEmail)
                            .font(.system(size: 12))
                            .foregroundStyle(AdaColors.secondaryInk)
                    }
                    if !store.accountOrganization.isEmpty {
                        Text("·")
                            .font(.system(size: 12))
                            .foregroundStyle(AdaColors.secondaryInk)
                        Text(store.accountOrganization)
                            .font(.system(size: 12))
                            .foregroundStyle(AdaColors.secondaryInk)
                    }
                }
                .lineLimit(1)
            }

            Spacer(minLength: 12)

            Text(accountBadgeText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AdaColors.navy)
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background(AdaColors.canvas, in: Capsule())
                .overlay(Capsule().stroke(AdaColors.line, lineWidth: 1))
        }
        .padding(18)
        .background(AdaColors.card, in: RoundedRectangle(cornerRadius: AdaLayout.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdaLayout.cardRadius, style: .continuous)
                .stroke(AdaColors.line, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settings.accountSummary")
    }

    private var accountInitial: String {
        let trimmed = store.accountName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "?" }
        return String(first).uppercased()
    }

    private var accountBadgeText: String {
        if store.isDemoBypassActive { return "Demo" }
        if store.isLiveOwner { return "Owner" }
        if store.isLiveRanger { return "Ranger" }
        return store.accountRoleLabel
    }

    private var apiKeyRowStatus: String? {
        if store.isDemoBypassActive { return "Demo" }
        if !store.isLiveOwner { return "Owner only" }
        if let metadata = model.metadata {
            return metadata.configured ? "Active" : "Not configured"
        }
        return nil
    }

    private var logoutButton: some View {
        Button {
            store.signOut()
        } label: {
            Text("Log out")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(AdaColors.navy, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
        .accessibilityIdentifier("settings.logoutButton")
    }

    // MARK: - Detail Routing

    @ViewBuilder
    private func detailView(for detail: SettingsDetailRoute) -> some View {
        switch detail {
        case .passwordSecurity:
            PasswordSecurityView(store: store, model: store.passwordSecurity, onBack: { store.requestSettingsBack() })
        case .helpSupport:
            HelpSupportDetailView(store: store, onBack: { store.requestSettingsBack() })
        case .developerAPIKey:
            DeveloperAPIKeyDetailView(store: store, model: model, onBack: { store.requestSettingsBack() })
        default:
            overview
        }
    }
}

// MARK: - Help & Support Detail

private struct HelpSupportDetailView: View {
    @ObservedObject var store: AppStore
    let onBack: () -> Void

    var body: some View {
        SettingsDetailScaffold(title: "Help & Support", onBack: onBack) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "lifepreserver")
                        .font(.system(size: 20))
                        .foregroundStyle(AdaColors.navy)
                        .frame(width: 44, height: 44)
                        .background(AdaColors.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Organisation Administrator Support")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AdaColors.ink)
                        Text("For assistance with AdaPenyu or your organisation account, please contact your organisation administrator.")
                            .font(.system(size: 13))
                            .foregroundStyle(AdaColors.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Divider().overlay(AdaColors.line)

                VStack(alignment: .leading, spacing: 10) {
                    supportField("Software version", value: AppVersionInfo.displayString())
                    if !store.accountOrganization.isEmpty {
                        supportField("Organisation", value: store.accountOrganization)
                    }
                    if !store.authEmail.isEmpty {
                        supportField("Signed-in account", value: store.authEmail)
                    }
                }
            }
            .padding(24)
            .background(AdaColors.card, in: RoundedRectangle(cornerRadius: AdaLayout.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AdaLayout.cardRadius, style: .continuous)
                    .stroke(AdaColors.line, lineWidth: 1)
            )
        }
    }

    private func supportField(_ title: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AdaColors.secondaryInk)
            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(AdaColors.ink)
                .textSelection(.enabled)
        }
    }
}

// MARK: - Developer Options: Organization API Key Detail (Preserved PR #14 Lifecycle)

private struct DeveloperAPIKeyDetailView: View {
    @ObservedObject var store: AppStore
    @ObservedObject var model: OrganizationAPIKeySettings
    let onBack: () -> Void
    @State private var confirmation: KeyConfirmation?
    @State private var surfaceID = UUID()

    private enum KeyConfirmation: String, Identifiable {
        case rotate, revoke
        var id: String { rawValue }
    }

    var body: some View {
        SettingsDetailScaffold(
            title: "Developer Options",
            subtitle: "Connect external tools to your organization's data.",
            isBackDisabled: model.isChanging,
            onBack: onBack
        ) {
            keyCard
                .alert(item: $confirmation, content: mutationAlert)
        }
        .task(id: model.contextVersion) { await model.enter(surfaceID: surfaceID) }
        .onDisappear { model.leave(surfaceID: surfaceID) }
    }

    private var keyCard: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "key.horizontal")
                    .font(.system(size: 20))
                    .foregroundStyle(AdaColors.navy)
                    .frame(width: 44, height: 44)
                    .background(AdaColors.canvas, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 5) {
                    Text("Organization API Key")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AdaColors.ink)
                    Text(store.accountOrganization.isEmpty ? "Your organization" : store.accountOrganization)
                        .font(.system(size: 12))
                        .foregroundStyle(AdaColors.secondaryInk)
                }
                Spacer(minLength: 8)
            }

            Text("Give scripts and dashboards read-only access to this organization's turtles, sightings, and photos. Your Mac app continues to use account sign-in.")
                .font(.system(size: 13))
                .foregroundStyle(AdaColors.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            if let message = model.accessMessage {
                Label(message, systemImage: "lock")
                    .font(.system(size: 13))
                    .foregroundStyle(AdaColors.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ownerContent
            }
        }
        .padding(24)
        .background(AdaColors.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(AdaColors.line, lineWidth: 1))
    }

    @ViewBuilder private var ownerContent: some View {
        if model.isLoading {
            ProgressView("Loading key status…").controlSize(.small)
        }

        if let metadata = model.metadata {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Circle().fill(metadata.configured ? AdaColors.green : AdaColors.secondaryInk).frame(width: 7, height: 7)
                    Text(metadata.configured ? "Active key" : "No API key configured")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AdaColors.ink)
                }
                if metadata.configured {
                    if let prefix = metadata.prefix {
                        metadataRow("Key prefix", value: prefix + "…", monospaced: true)
                    }
                    if let issuedAt = metadata.issuedAt {
                        metadataRow("Issued", value: issuedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                    if model.newSecret == nil {
                        Text("The full key cannot be retrieved. Rotate it if you need a new secret.")
                            .font(.system(size: 12)).foregroundStyle(AdaColors.secondaryInk)
                    }
                }
            }
        }

        if let secret = model.newSecret {
            secretPanel(secret)
        }

        if let error = model.errorMessage {
            VStack(alignment: .leading, spacing: 10) {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12))
                    .foregroundStyle(AdaColors.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Reload key status") { Task { await model.load() } }
                    .disabled(model.isLoading || model.isChanging)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AdaColors.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        }

        if model.isChanging {
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(model.operation == .rotate ? "Issuing API key…" : "Revoking API key…")
                    .controlSize(.small)
                Text("Navigation will resume when the request finishes or times out.")
                    .font(.system(size: 12)).foregroundStyle(AdaColors.secondaryInk)
            }
        } else if let metadata = model.metadata {
            HStack(spacing: 12) {
                if metadata.configured {
                    Button("Rotate Key") { confirmation = .rotate }
                        .buttonStyle(.bordered)
                    Button("Revoke Key", role: .destructive) { confirmation = .revoke }
                        .buttonStyle(.bordered)
                } else {
                    Button("Generate API Key") { Task { await model.rotate() } }
                        .buttonStyle(.borderedProminent)
                        .tint(AdaColors.navy)
                }
            }
            .disabled(!model.canChange)
        }
    }

    private func metadataRow(_ title: LocalizedStringKey, value: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11)).foregroundStyle(AdaColors.secondaryInk)
            Text(value).font(.system(size: 13, design: monospaced ? .monospaced : .default))
                .foregroundStyle(AdaColors.ink).textSelection(.enabled)
        }
    }

    private func secretPanel(_ secret: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Save your new API key", systemImage: "checkmark.circle")
                .font(.system(size: 14, weight: .semibold))
            Text("Save this key now. It cannot be retrieved later.")
                .font(.system(size: 12))

            Group {
                if model.isSecretRevealed {
                    Text(secret).textSelection(.enabled)
                } else {
                    Text("••••••••••••••••••••••••").accessibilityLabel("API key hidden")
                }
            }
            .font(.system(size: 13, design: .monospaced))
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 12) {
                Button {
                    model.isSecretRevealed.toggle()
                } label: {
                    Label(model.isSecretRevealed ? "Hide" : "Reveal", systemImage: model.isSecretRevealed ? "eye.slash" : "eye")
                }
                Button(action: model.copySecret) {
                    Label(model.didCopy ? "Copied · Copy again" : "Copy", systemImage: model.didCopy ? "checkmark" : "doc.on.doc")
                }
            }
            .buttonStyle(.bordered)

            Text("Copied keys clear from the clipboard after 60 seconds if nothing else is copied. Other apps' clipboard history cannot be cleared.")
                .font(.system(size: 11)).foregroundStyle(AdaColors.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            Button(model.hasSavedSecret ? "Saved" : "I've saved it", action: model.acknowledgeSaved)
                .buttonStyle(.borderedProminent)
                .tint(AdaColors.navy)
                .disabled(model.hasSavedSecret)
        }
        .foregroundStyle(AdaColors.ink)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AdaColors.green.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
    }

    private func mutationAlert(_ action: KeyConfirmation) -> Alert {
        let rotating = action == .rotate
        return Alert(
            title: Text(rotating ? "Rotate organization API key?" : "Revoke organization API key?"),
            message: Text(rotating
                ? "The current key stops working immediately. Every integration using it will need the replacement. The new secret is available only once."
                : "The key stops working immediately. Every integration using it will lose access until you generate and configure a new key."),
            primaryButton: .destructive(Text(rotating ? "Rotate Key" : "Revoke Key")) {
                Task {
                    if rotating { await model.rotate() }
                    else { await model.revoke() }
                }
            },
            secondaryButton: .cancel()
        )
    }
}
