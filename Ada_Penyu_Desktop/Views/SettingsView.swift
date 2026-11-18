import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: AppStore
    @ObservedObject var model: OrganizationAPIKeySettings
    @ObservedObject var organisation: OrganisationSettingsModel

    init(store: AppStore, model: OrganizationAPIKeySettings) {
        self.store = store
        self.model = model
        self.organisation = store.organisationSettings
    }

    var body: some View {
        GeometryReader { geometry in
            let isSplit = geometry.size.width >= 820

            Group {
                if isSplit {
                    splitLayout(availableWidth: geometry.size.width)
                } else if let detail = store.settingsDetail {
                    detailView(for: detail)
                        .environment(\.settingsSplitMode, false)
                } else {
                    compactSingleColumnOverview
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .task(id: store.sessionGeneration) {
            if organisation.canViewProfile && organisation.profile == nil {
                await organisation.loadProfile()
            }
        }
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

    // MARK: - Adaptive Split & Compact Layouts

    private func splitLayout(availableWidth: CGFloat) -> some View {
        let railWidth: CGFloat = availableWidth >= 1120 ? 352 : 302
        return HStack(alignment: .top, spacing: 28) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    sectionList(compact: true)
                    logoutButton(compact: true)
                }
                .padding(.bottom, 32)
            }
            .frame(width: railWidth)

            Group {
                if let detail = store.settingsDetail {
                    detailView(for: detail)
                } else {
                    overviewSummaryPane
                }
            }
            .environment(\.settingsSplitMode, true)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, AdaLayout.pagePadding)
    }

    private var compactSingleColumnOverview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                accountSummaryHeader
                sectionList(compact: false)
                logoutButton(compact: false)
            }
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AdaLayout.pagePadding)
            .padding(.bottom, 36)
        }
    }

    private func isRowSelected(_ route: SettingsDetailRoute) -> Bool {
        guard let current = store.settingsDetail else { return false }
        if route == .manageRangers {
            switch current {
            case .manageRangers, .addRanger, .rangerDetails: return true
            default: return false
            }
        }
        return current == route
    }

    @ViewBuilder
    private func sectionList(compact: Bool) -> some View {
        let dividerInset: CGFloat = compact ? 47 : 56

        // Account section
        SettingsSectionGroup(title: "Account", compact: compact) {
            SettingsNavigationRow(
                icon: "lock",
                title: "Password & Security",
                trailingValue: store.isDemoBypassActive ? store.localization.localized("Demo") : nil,
                isSelected: isRowSelected(.passwordSecurity),
                compact: compact,
                accessibilityID: "settings.row.passwordSecurity"
            ) {
                store.requestSettingsDetail(.passwordSecurity)
            }
        }

        // Organisation section
        SettingsSectionGroup(title: "Organisation", compact: compact) {
            SettingsNavigationRow(
                icon: "building.2",
                title: "Organisation Profile",
                trailingValue: store.isDemoBypassActive ? store.localization.localized("Demo") : nil,
                isSelected: isRowSelected(.organisationProfile),
                compact: compact,
                accessibilityID: "settings.row.organisationProfile"
            ) {
                store.requestSettingsDetail(.organisationProfile)
            }

            if organisation.canManageRangers {
                SettingsRowDivider(inset: dividerInset)
                SettingsNavigationRow(
                    icon: "person.2",
                    title: "Manage Rangers",
                    trailingValue: localizedMemberCount,
                    isSelected: isRowSelected(.manageRangers),
                    compact: compact,
                    accessibilityID: "settings.row.manageRangers"
                ) {
                    store.requestSettingsDetail(.manageRangers)
                }
            }
        }

        // Preferences & Permissions section
        SettingsSectionGroup(title: "Preferences & Permissions", compact: compact) {
            SettingsNavigationRow(
                icon: "globe",
                title: "Language",
                trailingValue: store.localization.language.displayName,
                isSelected: isRowSelected(.language),
                compact: compact,
                accessibilityID: "settings.row.language"
            ) {
                store.requestSettingsDetail(.language)
            }
            SettingsRowDivider(inset: dividerInset)
            SettingsNavigationRow(
                icon: "hand.raised",
                title: "App Permissions",
                isSelected: isRowSelected(.appPermissions),
                compact: compact,
                accessibilityID: "settings.row.appPermissions"
            ) {
                store.requestSettingsDetail(.appPermissions)
            }
        }

        // Contour Review section (Mac-only defaults)
        SettingsSectionGroup(
            title: "Contour Review",
            subtitle: compact ? nil : "Defaults for new photo comparisons",
            compact: compact
        ) {
            SettingsNavigationRow(
                icon: "viewfinder.circle",
                title: "Contour Review",
                subtitle: compact ? nil : "Scale numbers, edge threshold, opacity, line weight, and noise reduction",
                trailingValue: store.contourPreferences.summaryText,
                isSelected: isRowSelected(.contourReview),
                compact: compact,
                accessibilityID: "settings.row.contourReview"
            ) {
                store.requestSettingsDetail(.contourReview)
            }
        }

        // Support section
        SettingsSectionGroup(title: "Support", compact: compact) {
            SettingsInfoRow(
                icon: "info.circle",
                title: "Software version",
                value: AppVersionInfo.displayString(),
                compact: compact,
                accessibilityID: "settings.row.softwareVersion"
            )
            SettingsRowDivider(inset: dividerInset)
            SettingsNavigationRow(
                icon: "questionmark.circle",
                title: "Help & Support",
                isSelected: isRowSelected(.helpSupport),
                compact: compact,
                accessibilityID: "settings.row.helpSupport"
            ) {
                store.requestSettingsDetail(.helpSupport)
            }
        }

        // Developer Options section (visually secondary, preserving PR #14 API key controls)
        SettingsSectionGroup(
            title: "Developer Options",
            subtitle: compact ? nil : "Connect external tools to your organization's data.",
            secondary: true,
            compact: compact
        ) {
            SettingsNavigationRow(
                icon: "key.horizontal",
                title: "Organization API Key",
                subtitle: compact ? nil : "Read-only credentials for external scripts and dashboards",
                trailingValue: apiKeyRowStatus,
                isSelected: isRowSelected(.developerAPIKey),
                isSecondary: true,
                compact: compact,
                accessibilityID: "settings.row.organizationAPIKey"
            ) {
                store.requestSettingsDetail(.developerAPIKey)
            }
        }
    }

    // MARK: - Split Desktop Overview Panel (Right Column when no detail is selected)

    private var overviewSummaryPane: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                // FigCraft deep-navy hero summary card matching Dashboard identity
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .center, spacing: 14) {
                        Circle()
                            .fill(.white.opacity(0.14))
                            .frame(width: 50, height: 50)
                            .overlay {
                                Text(accountInitial)
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(.white)
                            }

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text(store.accountName)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.white)
                                Text(accountBadgeText)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(AdaColors.navy)
                                    .padding(.horizontal, 10)
                                    .frame(height: 22)
                                    .background(.white.opacity(0.92), in: Capsule())
                            }
                            HStack(spacing: 6) {
                                if !store.authEmail.isEmpty {
                                    Text(store.authEmail)
                                }
                                if !store.accountOrganization.isEmpty {
                                    Text("·")
                                    Text(store.accountOrganization)
                                }
                            }
                            .font(.system(size: 12.5))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                    }

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            heroActionPill(icon: "lock", title: "Password & Security") {
                                store.requestSettingsDetail(.passwordSecurity)
                            }
                            heroActionPill(icon: "building.2", title: "Organisation Profile") {
                                store.requestSettingsDetail(.organisationProfile)
                            }
                            if organisation.canManageRangers {
                                heroActionPill(icon: "person.2", title: "Manage Rangers") {
                                    store.requestSettingsDetail(.manageRangers)
                                }
                            }
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                heroActionPill(icon: "lock", title: "Password & Security") {
                                    store.requestSettingsDetail(.passwordSecurity)
                                }
                                heroActionPill(icon: "building.2", title: "Organisation Profile") {
                                    store.requestSettingsDetail(.organisationProfile)
                                }
                            }
                            if organisation.canManageRangers {
                                heroActionPill(icon: "person.2", title: "Manage Rangers") {
                                    store.requestSettingsDetail(.manageRangers)
                                }
                            }
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AdaColors.navy, in: RoundedRectangle(cornerRadius: AdaLayout.cardRadius, style: .continuous))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("settings.accountSummary")

                // Quick settings 2x2 FigCraft cards
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)],
                    spacing: 16
                ) {
                    quickLanguageCard
                    quickContourCard
                    quickPermissionsCard
                    quickDeveloperCard
                }

                // Compact Support strip
                HStack(spacing: 14) {
                    Image(systemName: "lifepreserver")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(AdaColors.navy)
                        .frame(width: 38, height: 38)
                        .background(AdaColors.canvas, in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Need help with your organisation account?")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(AdaColors.ink)
                        Text(AppVersionInfo.displayString())
                            .font(.system(size: 12))
                            .foregroundStyle(AdaColors.secondaryInk)
                    }

                    Spacer(minLength: 10)

                    Button {
                        store.requestSettingsDetail(.helpSupport)
                    } label: {
                        HStack(spacing: 5) {
                            Text("Help & Support")
                            Image(systemName: "arrow.right")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AdaColors.navy)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(AdaColors.canvas, in: Capsule())
                        .overlay(Capsule().stroke(AdaColors.line, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                .padding(18)
                .background(AdaColors.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(AdaColors.line, lineWidth: 1)
                )
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.bottom, 32)
        }
    }

    private func heroActionPill(icon: String, title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11.5, weight: .medium))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 13)
            .frame(height: 34)
            .background(.white.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.14), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var quickLanguageCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "globe")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AdaColors.navy)
                    .frame(width: 34, height: 34)
                    .background(AdaColors.canvas, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Spacer()
                Button {
                    store.requestSettingsDetail(.language)
                } label: {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AdaColors.secondaryInk)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Language")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AdaColors.ink)
                Text("Switch desktop interface language immediately.")
                    .font(.system(size: 12))
                    .foregroundStyle(AdaColors.secondaryInk)
                    .lineLimit(2)
            }

            HStack(spacing: 6) {
                ForEach(AppLanguage.allCases) { lang in
                    let active = store.localization.language == lang
                    Button {
                        store.localization.language = lang
                    } label: {
                        Text(lang.displayName)
                            .font(.system(size: 11.5, weight: active ? .semibold : .medium))
                            .foregroundStyle(active ? .white : AdaColors.ink)
                            .padding(.horizontal, 11)
                            .frame(height: 30)
                            .background(active ? AdaColors.navy : AdaColors.canvas, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 162, alignment: .topLeading)
        .background(AdaColors.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AdaColors.line, lineWidth: 1))
    }

    private var quickContourCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "viewfinder.circle")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AdaColors.navy)
                    .frame(width: 34, height: 34)
                    .background(AdaColors.canvas, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Spacer()
                Text(store.contourPreferences.summaryText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AdaColors.navy)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(AdaColors.canvas, in: Capsule())
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Contour Review")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AdaColors.ink)
                Text("Default scale numbers, threshold, opacity, and noise reduction.")
                    .font(.system(size: 12))
                    .foregroundStyle(AdaColors.secondaryInk)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                store.requestSettingsDetail(.contourReview)
            } label: {
                HStack(spacing: 5) {
                    Text("Configure defaults")
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .semibold))
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 13)
                .frame(height: 30)
                .background(AdaColors.navy, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 162, alignment: .topLeading)
        .background(AdaColors.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AdaColors.line, lineWidth: 1))
    }

    private var quickPermissionsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "hand.raised")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AdaColors.navy)
                    .frame(width: 34, height: 34)
                    .background(AdaColors.canvas, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Spacer()
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("App Permissions")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AdaColors.ink)
                Text("Review macOS Photo Library, Files, and Privacy settings.")
                    .font(.system(size: 12))
                    .foregroundStyle(AdaColors.secondaryInk)
                    .lineLimit(2)
            }

            Button {
                store.requestSettingsDetail(.appPermissions)
            } label: {
                HStack(spacing: 5) {
                    Text("Review permissions")
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .semibold))
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AdaColors.navy)
                .padding(.horizontal, 13)
                .frame(height: 30)
                .background(AdaColors.canvas, in: Capsule())
                .overlay(Capsule().stroke(AdaColors.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 162, alignment: .topLeading)
        .background(AdaColors.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AdaColors.line, lineWidth: 1))
    }

    private var quickDeveloperCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "key.horizontal")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AdaColors.secondaryInk)
                    .frame(width: 34, height: 34)
                    .background(AdaColors.canvas, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Spacer()
                if let status = apiKeyRowStatus {
                    Text(status)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AdaColors.secondaryInk)
                        .padding(.horizontal, 9)
                        .frame(height: 24)
                        .background(AdaColors.canvas, in: Capsule())
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Organization API Key")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AdaColors.ink)
                Text("Read-only credentials for external scripts and dashboards.")
                    .font(.system(size: 12))
                    .foregroundStyle(AdaColors.secondaryInk)
                    .lineLimit(2)
            }

            Button {
                store.requestSettingsDetail(.developerAPIKey)
            } label: {
                HStack(spacing: 5) {
                    Text("Developer Options")
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .semibold))
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AdaColors.navy)
                .padding(.horizontal, 13)
                .frame(height: 30)
                .background(AdaColors.canvas, in: Capsule())
                .overlay(Capsule().stroke(AdaColors.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 162, alignment: .topLeading)
        .background(AdaColors.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AdaColors.line, lineWidth: 1))
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
        if store.isDemoBypassActive { return store.localization.localized("Demo") }
        if store.isLiveOwner { return store.localization.localized("Owner") }
        if store.isLiveRanger { return store.localization.localized("Ranger") }
        return store.accountRoleLabel
    }

    private var localizedMemberCount: String? {
        guard organisation.canManageRangers else { return nil }
        let count = organisation.profile?.memberCount ?? (organisation.rangerTotal > 0 ? organisation.rangerTotal : nil)
        guard let count else { return nil }
        let unit = store.localization.localized(count == 1 ? "member" : "members")
        return "\(count) \(unit)"
    }

    private var apiKeyRowStatus: String? {
        if store.isDemoBypassActive { return store.localization.localized("Demo") }
        if !store.isLiveOwner { return store.localization.localized("Owner only") }
        if let metadata = model.metadata {
            return store.localization.localized(metadata.configured ? "Active" : "Not configured")
        }
        return nil
    }

    private func logoutButton(compact: Bool) -> some View {
        Button {
            store.signOut()
        } label: {
            Text("Log out")
                .font(.system(size: compact ? 13.5 : 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: compact ? 42 : 46)
                .background(AdaColors.navy, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.top, compact ? 2 : 4)
        .accessibilityIdentifier("settings.logoutButton")
    }

    // MARK: - Detail Routing

    @ViewBuilder
    private func detailView(for detail: SettingsDetailRoute) -> some View {
        switch detail {
        case .passwordSecurity:
            PasswordSecurityView(store: store, model: store.passwordSecurity, onBack: { store.requestSettingsBack() })
        case .organisationProfile:
            OrganisationProfileView(
                store: store,
                model: organisation,
                onBack: { store.requestSettingsBack() },
                onOpenManageRangers: { store.requestSettingsDetail(.manageRangers) }
            )
        case .manageRangers:
            ManageRangersView(
                store: store,
                model: organisation,
                onBack: { store.requestSettingsBack() },
                onAddRanger: { store.requestSettingsDetail(.addRanger) },
                onSelectRanger: { memberID in store.requestSettingsDetail(.rangerDetails(memberID)) }
            )
        case .addRanger:
            AddRangerView(
                model: organisation,
                onBack: { store.requestSettingsBack() },
                onCreated: { store.requestSettingsDetail(.manageRangers) }
            )
        case .rangerDetails(let memberID):
            RangerDetailsView(
                memberID: memberID,
                model: organisation,
                onBack: { store.requestSettingsBack() }
            )
        case .language:
            LanguageSettingsView(
                localization: store.localization,
                onBack: { store.requestSettingsBack() }
            )
        case .appPermissions:
            AppPermissionsView(
                store: store,
                onBack: { store.requestSettingsBack() }
            )
        case .contourReview:
            ContourReviewSettingsView(
                store: store.contourPreferences,
                onBack: { store.requestSettingsBack() }
            )
        case .helpSupport:
            HelpSupportDetailView(store: store, onBack: { store.requestSettingsBack() })
        case .developerAPIKey:
            DeveloperAPIKeyDetailView(store: store, model: model, onBack: { store.requestSettingsBack() })
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
