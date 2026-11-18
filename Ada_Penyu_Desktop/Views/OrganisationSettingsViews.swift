import SwiftUI

// MARK: - Organisation Profile

struct OrganisationProfileView: View {
    @ObservedObject var store: AppStore
    @ObservedObject var model: OrganisationSettingsModel
    let onBack: () -> Void
    let onOpenManageRangers: () -> Void

    var body: some View {
        SettingsDetailScaffold(
            title: "Organisation Profile",
            subtitle: model.canEditProfile
                ? "View and update your organisation's details."
                : "Organisation details for your current account.",
            isBackDisabled: model.isPerformingAction,
            onBack: onBack
        ) {
            VStack(alignment: .leading, spacing: 20) {
                if let demoMessage = model.demoMessage {
                    demoUnavailableCard(demoMessage)
                } else {
                    if let denied = model.accessDeniedMessage {
                        SettingsStatusBanner(style: .warning, message: denied)
                    }
                    if let success = model.actionSuccess {
                        SettingsStatusBanner(style: .success, message: success)
                    }
                    if let error = model.actionError {
                        SettingsStatusBanner(style: .error, message: error)
                    }
                    if let loadError = model.profileError {
                        VStack(alignment: .leading, spacing: 12) {
                            SettingsStatusBanner(style: .error, message: loadError)
                            Button("Retry") { Task { await model.loadProfile() } }
                                .buttonStyle(AdaPillButtonStyle(secondary: true))
                        }
                    }

                    if model.isLoadingProfile && model.profile == nil {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("Loading organisation profile…")
                                .font(.system(size: 13))
                                .foregroundStyle(AdaColors.secondaryInk)
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AdaColors.card, in: RoundedRectangle(cornerRadius: AdaLayout.cardRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: AdaLayout.cardRadius, style: .continuous)
                                .stroke(AdaColors.line, lineWidth: 1)
                        )
                    } else if model.profile != nil {
                        profileCard
                    }
                }
            }
        }
        .task(id: store.sessionGeneration) {
            await model.loadProfile()
        }
    }

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            orgField(
                label: "Organisation Name",
                placeholder: "Enter organisation name",
                text: $model.nameDraft,
                isEditable: model.canEditProfile,
                accessibilityID: "settings.org.name"
            )

            orgField(
                label: "Organisation Email",
                placeholder: "Optional contact email",
                text: $model.emailDraft,
                isEditable: model.canEditProfile,
                accessibilityID: "settings.org.email"
            )

            orgField(
                label: "Location",
                placeholder: "Optional location",
                text: $model.locationDraft,
                isEditable: model.canEditProfile,
                accessibilityID: "settings.org.location"
            )

            if model.canManageRangers {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Members")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AdaColors.ink)
                    Button(action: onOpenManageRangers) {
                        HStack {
                            Text(model.memberCountSummary ?? "Manage Rangers")
                                .font(.system(size: 14))
                                .foregroundStyle(AdaColors.ink)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AdaColors.secondaryInk.opacity(0.65))
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                        .background(AdaColors.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(AdaColors.line, lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.org.membersRow")
                }
            } else if let count = model.profile?.memberCount {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Members")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AdaColors.ink)
                    Text(count == 1 ? "1 member" : "\(count) members")
                        .font(.system(size: 14))
                        .foregroundStyle(AdaColors.secondaryInk)
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .background(AdaColors.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }

            if model.canEditProfile {
                HStack(spacing: 12) {
                    Button {
                        Task { await model.saveProfile() }
                    } label: {
                        HStack(spacing: 8) {
                            if model.isPerformingAction {
                                ProgressView().controlSize(.small).tint(.white)
                            }
                            Text("Save changes")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(model.canSaveProfile || model.isPerformingAction ? .white : AdaColors.secondaryInk)
                        .padding(.horizontal, 24)
                        .frame(height: 44)
                        .background(model.canSaveProfile || model.isPerformingAction ? AdaColors.navy : AdaColors.canvas, in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.canSaveProfile)
                    .accessibilityIdentifier("settings.org.saveButton")

                    Spacer(minLength: 0)
                }
                .padding(.top, 4)
            } else {
                Text("Only the organisation owner can edit organisation details.")
                    .font(.system(size: 12))
                    .foregroundStyle(AdaColors.secondaryInk)
            }
        }
        .padding(24)
        .background(AdaColors.card, in: RoundedRectangle(cornerRadius: AdaLayout.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdaLayout.cardRadius, style: .continuous)
                .stroke(AdaColors.line, lineWidth: 1)
        )
    }

    private func orgField(
        label: LocalizedStringKey,
        placeholder: LocalizedStringKey,
        text: Binding<String>,
        isEditable: Bool,
        accessibilityID: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AdaColors.ink)
            if isEditable {
                TextField(placeholder, text: text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(AdaColors.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(AdaColors.line, lineWidth: 1)
                    )
                    .disabled(model.isPerformingAction)
                    .accessibilityIdentifier(accessibilityID)
            } else {
                Text(text.wrappedValue.isEmpty ? "Not set" : text.wrappedValue)
                    .font(.system(size: 14))
                    .foregroundStyle(text.wrappedValue.isEmpty ? AdaColors.secondaryInk : AdaColors.ink)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .background(AdaColors.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityIdentifier(accessibilityID)
            }
        }
    }
}

// MARK: - Manage Rangers List

struct ManageRangersView: View {
    @ObservedObject var store: AppStore
    @ObservedObject var model: OrganisationSettingsModel
    let onBack: () -> Void
    let onAddRanger: () -> Void
    let onSelectRanger: (UUID) -> Void

    @State private var searchDebounceTask: Task<Void, Never>?

    var body: some View {
        SettingsDetailScaffold(
            title: "Manage Rangers",
            subtitle: "Search, invite, and manage ranger access for your organisation.",
            onBack: onBack,
            trailing: {
                if model.canManageRangers {
                    Button(action: onAddRanger) {
                        Label("Add", systemImage: "plus")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(AdaPillButtonStyle())
                    .accessibilityIdentifier("settings.rangers.addButton")
                }
            }
        ) {
            VStack(alignment: .leading, spacing: 18) {
                if let demoMessage = model.demoMessage {
                    demoUnavailableCard(demoMessage)
                } else if !model.canManageRangers {
                    SettingsStatusBanner(
                        style: .warning,
                        message: model.accessDeniedMessage ?? "Only the organisation owner can manage rangers."
                    )
                } else {
                    if let success = model.actionSuccess {
                        SettingsStatusBanner(style: .success, message: success)
                    }
                    if let error = model.actionError {
                        SettingsStatusBanner(style: .error, message: error)
                    }
                    if let loadError = model.rangersError {
                        VStack(alignment: .leading, spacing: 10) {
                            SettingsStatusBanner(style: .error, message: loadError)
                            Button("Retry") { Task { await model.reloadRangers() } }
                                .buttonStyle(AdaPillButtonStyle(secondary: true))
                        }
                    }

                    searchBar

                    HStack {
                        Text(rangersHeading)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AdaColors.ink)
                        Spacer()
                        if model.isLoadingRangers {
                            ProgressView().controlSize(.small)
                        }
                    }
                    .padding(.horizontal, 4)

                    rangersCard

                    if model.canLoadMoreRangers {
                        HStack {
                            Spacer()
                            Button("Load more") {
                                Task { await model.loadMoreRangers() }
                            }
                            .buttonStyle(AdaPillButtonStyle(secondary: true))
                            .accessibilityIdentifier("settings.rangers.loadMoreButton")
                            Spacer()
                        }
                    }
                }
            }
        }
        .task(id: store.sessionGeneration) {
            await model.reloadRangers()
        }
        .onDisappear {
            searchDebounceTask?.cancel()
        }
    }

    private var rangersHeading: String {
        if model.rangerTotal > 0 || !model.isLoadingRangers {
            return "Rangers (\(model.rangerTotal))"
        }
        return "Rangers"
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(AdaColors.secondaryInk)
            TextField("Search rangers", text: $model.rangerSearchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .accessibilityIdentifier("settings.rangers.searchField")
                .onChange(of: model.rangerSearchQuery) { _, newValue in
                    searchDebounceTask?.cancel()
                    searchDebounceTask = Task {
                        try? await Task.sleep(for: .milliseconds(220))
                        guard !Task.isCancelled else { return }
                        await model.reloadRangers(query: newValue)
                    }
                }
            if !model.rangerSearchQuery.isEmpty {
                Button {
                    searchDebounceTask?.cancel()
                    Task { await model.reloadRangers(query: "") }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(AdaColors.secondaryInk)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(AdaColors.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AdaColors.line, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var rangersCard: some View {
        if model.rangers.isEmpty && !model.isLoadingRangers {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.rangerSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                     ? "No rangers yet"
                     : "No matching rangers")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AdaColors.ink)
                Text(model.rangerSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                     ? "Use Add to invite a ranger to your organisation."
                     : "Try a different name or email.")
                    .font(.system(size: 12))
                    .foregroundStyle(AdaColors.secondaryInk)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AdaColors.card, in: RoundedRectangle(cornerRadius: AdaLayout.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AdaLayout.cardRadius, style: .continuous)
                    .stroke(AdaColors.line, lineWidth: 1)
            )
        } else {
            VStack(spacing: 0) {
                ForEach(Array(model.rangers.enumerated()), id: \.element.id) { index, member in
                    if index > 0 {
                        SettingsRowDivider(inset: 18)
                    }
                    rangerRow(member)
                }
            }
            .background(AdaColors.card)
            .clipShape(RoundedRectangle(cornerRadius: AdaLayout.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AdaLayout.cardRadius, style: .continuous)
                    .stroke(AdaColors.line, lineWidth: 1)
            )
        }
    }

    private func rangerRow(_ member: RangerMember) -> some View {
        let displayTitle = member.isCurrentUser ? "\(member.fullName) (You)" : member.fullName
        return Button {
            onSelectRanger(member.id)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(displayTitle)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AdaColors.ink)
                        Text(member.status.displayName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AdaColors.navy)
                            .padding(.horizontal, 8)
                            .frame(height: 20)
                            .background(AdaColors.canvas, in: Capsule())
                    }
                    Text(member.email)
                        .font(.system(size: 12))
                        .foregroundStyle(AdaColors.secondaryInk)
                    if let pending = member.pendingEmail, !pending.isEmpty {
                        Text("Pending email verification: \(pending)")
                            .font(.system(size: 11))
                            .foregroundStyle(AdaColors.secondaryInk)
                    }
                }
                Spacer(minLength: 12)
                if member.canEditDetails {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AdaColors.secondaryInk.opacity(0.65))
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!member.canEditDetails)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settings.rangers.row.\(member.id.uuidString)")
    }
}

// MARK: - Add Ranger

struct AddRangerView: View {
    @ObservedObject var model: OrganisationSettingsModel
    let onBack: () -> Void
    let onCreated: () -> Void

    @State private var fullName = ""
    @State private var email = ""

    private var canSubmit: Bool {
        model.canManageRangers
            && !model.isPerformingAction
            && !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        SettingsDetailScaffold(
            title: "Add Ranger",
            subtitle: "Invite a new ranger to join your organisation.",
            backLabel: "Manage Rangers",
            isBackDisabled: model.isPerformingAction,
            onBack: onBack
        ) {
            VStack(alignment: .leading, spacing: 18) {
                if let denied = model.accessDeniedMessage {
                    SettingsStatusBanner(style: .warning, message: denied)
                }
                if let error = model.actionError {
                    SettingsStatusBanner(style: .error, message: error)
                }

                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Full Name")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AdaColors.ink)
                        TextField("Enter ranger name", text: $fullName)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .padding(.horizontal, 14)
                            .frame(height: 44)
                            .background(AdaColors.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AdaColors.line, lineWidth: 1))
                            .accessibilityIdentifier("settings.addRanger.name")
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Email")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AdaColors.ink)
                        TextField("Enter ranger email", text: $email)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .padding(.horizontal, 14)
                            .frame(height: 44)
                            .background(AdaColors.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AdaColors.line, lineWidth: 1))
                            .accessibilityIdentifier("settings.addRanger.email")
                    }

                    HStack(spacing: 12) {
                        Button {
                            Task {
                                if await model.addRanger(fullName: fullName, email: email) != nil {
                                    onCreated()
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                if model.isPerformingAction {
                                    ProgressView().controlSize(.small).tint(.white)
                                }
                                Text("Add Ranger")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundStyle(canSubmit || model.isPerformingAction ? .white : AdaColors.secondaryInk)
                            .padding(.horizontal, 24)
                            .frame(height: 44)
                            .background(canSubmit || model.isPerformingAction ? AdaColors.navy : AdaColors.canvas, in: Capsule())
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSubmit)
                        .accessibilityIdentifier("settings.addRanger.submitButton")

                        Button("Cancel", action: onBack)
                            .buttonStyle(AdaPillButtonStyle(secondary: true))
                            .disabled(model.isPerformingAction)
                        Spacer(minLength: 0)
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
        .onAppear { model.clearMessages() }
    }
}

// MARK: - Ranger Details

struct RangerDetailsView: View {
    let memberID: UUID
    @ObservedObject var model: OrganisationSettingsModel
    let onBack: () -> Void

    @State private var fullNameDraft = ""
    @State private var emailDraft = ""
    @State private var didSeedDrafts = false
    @State private var showingRemoveConfirmation = false

    private var member: RangerMember? { model.member(for: memberID) }

    private var hasUnsavedChanges: Bool {
        guard let member else { return false }
        return fullNameDraft.trimmingCharacters(in: .whitespacesAndNewlines) != member.fullName
            || emailDraft.trimmingCharacters(in: .whitespacesAndNewlines) != member.email
    }

    private var canSave: Bool {
        guard let member else { return false }
        return member.canEditDetails
            && hasUnsavedChanges
            && !fullNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !emailDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !model.isPerformingAction
    }

    var body: some View {
        SettingsDetailScaffold(
            title: "Ranger Details",
            backLabel: "Manage Rangers",
            isBackDisabled: model.isPerformingAction,
            onBack: onBack
        ) {
            VStack(alignment: .leading, spacing: 18) {
                if let denied = model.accessDeniedMessage {
                    SettingsStatusBanner(style: .warning, message: denied)
                }
                if let success = model.actionSuccess {
                    SettingsStatusBanner(style: .success, message: success)
                }
                if let error = model.actionError {
                    SettingsStatusBanner(style: .error, message: error)
                }

                if model.isLoadingRangerDetail && member == nil {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Loading ranger details…")
                            .font(.system(size: 13))
                            .foregroundStyle(AdaColors.secondaryInk)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AdaColors.card, in: RoundedRectangle(cornerRadius: AdaLayout.cardRadius, style: .continuous))
                } else if let member {
                    detailCard(for: member)
                } else {
                    SettingsStatusBanner(style: .info, message: "Ranger member not found.")
                }
            }
        }
        .task(id: memberID) {
            syncDrafts(force: false)
            await model.loadRangerDetail(id: memberID)
            syncDrafts(force: !hasUnsavedChanges)
        }
        .confirmationDialog(
            "Remove Access",
            isPresented: $showingRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove Access", role: .destructive) {
                Task {
                    if await model.removeRangerAccess(id: memberID) {
                        onBack()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to remove \(member?.fullName ?? "this ranger")'s access to \(model.profile?.name ?? "this organisation")?")
        }
    }

    private func detailCard(for member: RangerMember) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Full Name")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AdaColors.ink)
                if member.canEditDetails {
                    TextField("Enter ranger name", text: $fullNameDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                        .background(AdaColors.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AdaColors.line, lineWidth: 1))
                        .disabled(model.isPerformingAction)
                        .accessibilityIdentifier("settings.rangerDetail.name")
                } else {
                    Text(member.fullName)
                        .font(.system(size: 14))
                        .foregroundStyle(AdaColors.ink)
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .background(AdaColors.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Email")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AdaColors.ink)
                if member.canEditDetails {
                    TextField("Enter ranger email", text: $emailDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                        .background(AdaColors.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AdaColors.line, lineWidth: 1))
                        .disabled(model.isPerformingAction)
                        .accessibilityIdentifier("settings.rangerDetail.email")
                } else {
                    Text(member.email)
                        .font(.system(size: 14))
                        .foregroundStyle(AdaColors.ink)
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .background(AdaColors.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }

            if let pending = member.pendingEmail, !pending.isEmpty {
                Text("Pending email verification: \(pending)")
                    .font(.system(size: 12))
                    .foregroundStyle(AdaColors.secondaryInk)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Status")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AdaColors.ink)
                Text(member.status.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AdaColors.navy)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(AdaColors.canvas, in: Capsule())
            }

            Divider().overlay(AdaColors.line)

            HStack(spacing: 12) {
                if member.canEditDetails {
                    Button {
                        Task {
                            if await model.updateRanger(id: member.id, fullName: fullNameDraft, email: emailDraft) {
                                syncDrafts(force: true)
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if model.isPerformingAction {
                                ProgressView().controlSize(.small).tint(.white)
                            }
                            Text("Save changes")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(canSave || model.isPerformingAction ? .white : AdaColors.secondaryInk)
                        .padding(.horizontal, 22)
                        .frame(height: 42)
                        .background(canSave || model.isPerformingAction ? AdaColors.navy : AdaColors.canvas, in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSave)
                    .accessibilityIdentifier("settings.rangerDetail.saveButton")
                }

                if member.canResendInvitation {
                    Button("Resend invitation") {
                        Task { await model.resendInvitation(id: member.id) }
                    }
                    .buttonStyle(AdaPillButtonStyle(secondary: true))
                    .disabled(model.isPerformingAction)
                    .accessibilityIdentifier("settings.rangerDetail.resendButton")
                }

                Spacer(minLength: 0)

                if member.canBeRemoved {
                    Button(role: .destructive) {
                        showingRemoveConfirmation = true
                    } label: {
                        Text("Remove Access")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AdaColors.red)
                            .padding(.horizontal, 16)
                            .frame(height: 40)
                            .background(AdaColors.red.opacity(0.08), in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isPerformingAction)
                    .accessibilityIdentifier("settings.rangerDetail.removeAccessButton")
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

    private func syncDrafts(force: Bool) {
        guard let member else { return }
        if force || !didSeedDrafts {
            fullNameDraft = member.fullName
            emailDraft = member.email
            didSeedDrafts = true
        }
    }
}

private func demoUnavailableCard(_ message: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
        Image(systemName: "building.2")
            .font(.system(size: 18))
            .foregroundStyle(AdaColors.navy)
            .frame(width: 40, height: 40)
            .background(AdaColors.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        Text(message)
            .font(.system(size: 13))
            .foregroundStyle(AdaColors.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
    }
    .padding(22)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(AdaColors.card, in: RoundedRectangle(cornerRadius: AdaLayout.cardRadius, style: .continuous))
    .overlay(
        RoundedRectangle(cornerRadius: AdaLayout.cardRadius, style: .continuous)
            .stroke(AdaColors.line, lineWidth: 1)
    )
}
