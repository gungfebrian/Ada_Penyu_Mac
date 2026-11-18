import Combine
import Foundation

@MainActor
final class OrganisationSettingsModel: ObservableObject {
    @Published private(set) var profile: OrganisationProfile?
    @Published var nameDraft = ""
    @Published var emailDraft = ""
    @Published var locationDraft = ""

    @Published private(set) var rangers: [RangerMember] = []
    @Published private(set) var rangerTotal = 0
    @Published private(set) var rangerOffset = 0
    @Published var rangerSearchQuery = ""
    @Published private(set) var selectedRangerDetail: RangerMember?

    @Published private(set) var isLoadingProfile = false
    @Published private(set) var isLoadingRangers = false
    @Published private(set) var isLoadingRangerDetail = false
    @Published private(set) var isPerformingAction = false

    @Published private(set) var profileError: String?
    @Published private(set) var rangersError: String?
    @Published private(set) var actionError: String?
    @Published private(set) var actionSuccess: String?
    @Published private(set) var accessDeniedMessage: String?
    @Published private(set) var profileEditForbidden = false
    @Published private(set) var rangersForbidden = false
    @Published private(set) var isDemo = false
    @Published private(set) var isOwner = false
    @Published private(set) var hasLiveUser = false

    let pageSize: Int
    private var client: APIClient
    private var service: OrganisationSettingsService
    private var activeUser: AppUser?
    private var context: Context?
    private var revision = UUID()
    private var rangerQueryGeneration = UUID()
    private var detailLoadGeneration = UUID()

    private struct Context: Equatable {
        let client: ObjectIdentifier
        let userID: UUID?
        let organizationID: UUID?
        let role: UserRole?
        let demo: Bool
    }

    init(client: APIClient, pageSize: Int = 25) {
        self.client = client
        self.service = OrganisationSettingsService(client: client)
        self.pageSize = pageSize
        configure(client: client, user: client.account, isDemo: false)
    }

    var canViewProfile: Bool {
        hasLiveUser && !isDemo && activeUser?.organisationID != nil
    }

    var canEditProfile: Bool {
        canViewProfile && isOwner && !profileEditForbidden
    }

    var canManageRangers: Bool {
        canViewProfile && isOwner && !rangersForbidden
    }

    var canLoadMoreRangers: Bool {
        rangers.count < rangerTotal && !isLoadingRangers
    }

    var demoMessage: String? {
        guard isDemo else { return nil }
        return "Organisation settings are not available in demo mode. Sign in to a live organisation to view or manage team settings."
    }

    var hasUnsavedProfileChanges: Bool {
        guard let profile else { return false }
        return nameDraft.trimmingCharacters(in: .whitespacesAndNewlines) != profile.name
            || emailDraft.trimmingCharacters(in: .whitespacesAndNewlines) != (profile.email ?? "")
            || locationDraft.trimmingCharacters(in: .whitespacesAndNewlines) != (profile.location ?? "")
    }

    var canSaveProfile: Bool {
        canEditProfile
            && profile != nil
            && hasUnsavedProfileChanges
            && !nameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isPerformingAction
    }

    var memberCountSummary: String? {
        guard canManageRangers else { return nil }
        if let count = profile?.memberCount {
            return count == 1 ? "1 member" : "\(count) members"
        }
        if rangerTotal > 0 {
            return rangerTotal == 1 ? "1 member" : "\(rangerTotal) members"
        }
        return nil
    }

    func member(for id: UUID) -> RangerMember? {
        if let selectedRangerDetail, selectedRangerDetail.id == id {
            return selectedRangerDetail
        }
        return rangers.first { $0.id == id }
    }

    func configure(client: APIClient, user: AppUser?, isDemo: Bool) {
        let next = Context(
            client: ObjectIdentifier(client),
            userID: isDemo ? nil : user?.id,
            organizationID: isDemo ? nil : user?.organisationID,
            role: isDemo ? nil : user?.role,
            demo: isDemo
        )
        self.client = client
        self.activeUser = isDemo ? nil : user
        self.isDemo = isDemo
        self.hasLiveUser = !isDemo && user != nil
        self.isOwner = !isDemo && user?.role == .owner && user?.organisationID != nil
        guard next != context else { return }
        context = next
        service = OrganisationSettingsService(client: client)
        reset()
    }

    func reset() {
        revision = UUID()
        rangerQueryGeneration = UUID()
        detailLoadGeneration = UUID()
        service.clearSession()
        profile = nil
        nameDraft = ""
        emailDraft = ""
        locationDraft = ""
        rangers = []
        rangerTotal = 0
        rangerOffset = 0
        rangerSearchQuery = ""
        selectedRangerDetail = nil
        isLoadingProfile = false
        isLoadingRangers = false
        isLoadingRangerDetail = false
        isPerformingAction = false
        profileEditForbidden = false
        rangersForbidden = false
        clearMessages()
    }

    func clearMessages() {
        profileError = nil
        rangersError = nil
        actionError = nil
        actionSuccess = nil
        accessDeniedMessage = nil
    }

    // MARK: - Organisation Profile

    func loadProfile() async {
        guard canViewProfile, let user = activeUser, !isLoadingProfile else { return }
        let capturedRevision = revision
        let capturedUserID = user.id
        profileError = nil
        accessDeniedMessage = nil
        isLoadingProfile = true
        defer {
            if revision == capturedRevision { isLoadingProfile = false }
        }
        do {
            let loaded = try await service.fetchOrganisationProfile(for: user)
            guard revision == capturedRevision, activeUser?.id == capturedUserID else { return }
            applyProfile(loaded)
        } catch {
            guard revision == capturedRevision, activeUser?.id == capturedUserID else { return }
            if error is CancellationError { return }
            handleProfileError(error)
        }
    }

    @discardableResult
    func saveProfile() async -> Bool {
        guard !isPerformingAction else { return false }
        clearMessages()
        guard canEditProfile, let user = activeUser else {
            accessDeniedMessage = "Only the organisation owner can edit the organisation profile."
            return false
        }
        let trimmedName = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            actionError = "Organisation name cannot be empty."
            return false
        }
        guard hasUnsavedProfileChanges else {
            return true
        }

        let capturedRevision = revision
        let capturedUserID = user.id
        isPerformingAction = true
        defer {
            if revision == capturedRevision { isPerformingAction = false }
        }

        do {
            let updated = try await service.updateOrganisationProfile(
                OrganisationProfileUpdate(name: trimmedName, email: emailDraft, location: locationDraft),
                for: user
            )
            guard revision == capturedRevision, activeUser?.id == capturedUserID else { return false }
            applyProfile(updated)
            actionSuccess = "Organisation profile updated."
            return true
        } catch {
            guard revision == capturedRevision, activeUser?.id == capturedUserID else { return false }
            if error is CancellationError { return false }
            handleMutationError(error, forProfileEdit: true)
            return false
        }
    }

    private func applyProfile(_ loaded: OrganisationProfile) {
        profile = loaded
        nameDraft = loaded.name
        emailDraft = loaded.email ?? ""
        locationDraft = loaded.location ?? ""
    }

    // MARK: - Manage Rangers

    func reloadRangers(query: String? = nil) async {
        if let query {
            rangerSearchQuery = query
        }
        guard canManageRangers, let user = activeUser else {
            rangers = []
            rangerTotal = 0
            rangerOffset = 0
            return
        }
        let capturedRevision = revision
        let capturedUserID = user.id
        let queryGen = UUID()
        rangerQueryGeneration = queryGen
        rangersError = nil
        isLoadingRangers = true
        defer {
            if revision == capturedRevision, rangerQueryGeneration == queryGen {
                isLoadingRangers = false
            }
        }
        let trimmedQuery = rangerSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let page = try await service.fetchRangers(for: user, query: trimmedQuery, limit: pageSize, offset: 0)
            guard revision == capturedRevision,
                  rangerQueryGeneration == queryGen,
                  activeUser?.id == capturedUserID else { return }
            rangers = page.items
            rangerTotal = page.total
            rangerOffset = page.items.count
            if trimmedQuery.isEmpty, let existing = profile {
                profile = OrganisationProfile(
                    id: existing.id,
                    name: existing.name,
                    email: existing.email,
                    location: existing.location,
                    memberCount: page.total
                )
            }
        } catch {
            guard revision == capturedRevision,
                  rangerQueryGeneration == queryGen,
                  activeUser?.id == capturedUserID else { return }
            if error is CancellationError { return }
            handleRangersLoadError(error)
        }
    }

    func loadMoreRangers() async {
        guard canManageRangers, canLoadMoreRangers, let user = activeUser else { return }
        let capturedRevision = revision
        let capturedUserID = user.id
        let queryGen = rangerQueryGeneration
        rangersError = nil
        isLoadingRangers = true
        defer {
            if revision == capturedRevision, rangerQueryGeneration == queryGen {
                isLoadingRangers = false
            }
        }
        let trimmedQuery = rangerSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let page = try await service.fetchRangers(for: user, query: trimmedQuery, limit: pageSize, offset: rangerOffset)
            guard revision == capturedRevision,
                  rangerQueryGeneration == queryGen,
                  activeUser?.id == capturedUserID else { return }
            let existingIDs = Set(rangers.map(\.id))
            let newItems = page.items.filter { !existingIDs.contains($0.id) }
            rangers.append(contentsOf: newItems)
            rangerTotal = page.total
            rangerOffset += page.items.count
        } catch {
            guard revision == capturedRevision,
                  rangerQueryGeneration == queryGen,
                  activeUser?.id == capturedUserID else { return }
            if error is CancellationError { return }
            handleRangersLoadError(error)
        }
    }

    func loadRangerDetail(id: UUID) async {
        guard canManageRangers, let user = activeUser else { return }
        let capturedRevision = revision
        let capturedUserID = user.id
        let detailGen = UUID()
        detailLoadGeneration = detailGen
        actionError = nil
        isLoadingRangerDetail = true
        defer {
            if revision == capturedRevision, detailLoadGeneration == detailGen {
                isLoadingRangerDetail = false
            }
        }
        do {
            let member = try await service.fetchRangerDetail(id: id, for: user)
            guard revision == capturedRevision,
                  detailLoadGeneration == detailGen,
                  activeUser?.id == capturedUserID else { return }
            selectedRangerDetail = member
            upsertMember(member)
        } catch {
            guard revision == capturedRevision,
                  detailLoadGeneration == detailGen,
                  activeUser?.id == capturedUserID else { return }
            if error is CancellationError { return }
            handleMutationError(error)
        }
    }

    @discardableResult
    func addRanger(fullName: String, email: String) async -> RangerMember? {
        guard !isPerformingAction else { return nil }
        clearMessages()
        guard canManageRangers, let user = activeUser else {
            accessDeniedMessage = "Only the organisation owner can add rangers."
            return nil
        }
        let trimmedName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedEmail.isEmpty else {
            actionError = "Please enter the ranger's full name and email."
            return nil
        }

        let capturedRevision = revision
        let capturedUserID = user.id
        isPerformingAction = true
        defer {
            if revision == capturedRevision { isPerformingAction = false }
        }
        do {
            let created = try await service.addRanger(fullName: trimmedName, email: trimmedEmail, for: user)
            guard revision == capturedRevision, activeUser?.id == capturedUserID else { return nil }
            upsertMember(created)
            rangerTotal = max(rangerTotal + 1, rangers.count)
            actionSuccess = "Invitation sent to \(created.email)."
            return created
        } catch {
            guard revision == capturedRevision, activeUser?.id == capturedUserID else { return nil }
            if error is CancellationError { return nil }
            handleMutationError(error)
            return nil
        }
    }

    @discardableResult
    func updateRanger(id: UUID, fullName: String, email: String) async -> Bool {
        guard !isPerformingAction else { return false }
        clearMessages()
        guard canManageRangers, let user = activeUser else {
            accessDeniedMessage = "Only the organisation owner can edit rangers."
            return false
        }
        guard let existing = member(for: id) else {
            actionError = "Ranger member not found."
            return false
        }
        guard existing.canEditDetails else {
            accessDeniedMessage = "This account cannot be edited here."
            return false
        }
        let trimmedName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedEmail.isEmpty else {
            actionError = "Please enter the ranger's full name and email."
            return false
        }
        if trimmedName == existing.fullName && trimmedEmail == existing.email {
            return true
        }

        let capturedRevision = revision
        let capturedUserID = user.id
        isPerformingAction = true
        defer {
            if revision == capturedRevision { isPerformingAction = false }
        }
        do {
            let updated = try await service.updateRanger(id: id, fullName: trimmedName, email: trimmedEmail, for: user)
            guard revision == capturedRevision, activeUser?.id == capturedUserID else { return false }
            selectedRangerDetail = updated
            upsertMember(updated)
            actionSuccess = "Ranger details updated."
            return true
        } catch {
            guard revision == capturedRevision, activeUser?.id == capturedUserID else { return false }
            if error is CancellationError { return false }
            handleMutationError(error)
            return false
        }
    }

    @discardableResult
    func resendInvitation(id: UUID) async -> Bool {
        guard !isPerformingAction else { return false }
        clearMessages()
        guard canManageRangers, let user = activeUser else {
            accessDeniedMessage = "Only the organisation owner can resend invitations."
            return false
        }
        guard let existing = member(for: id), existing.canResendInvitation else {
            actionError = "Invitation can only be resent for invited rangers."
            return false
        }

        let capturedRevision = revision
        let capturedUserID = user.id
        isPerformingAction = true
        defer {
            if revision == capturedRevision { isPerformingAction = false }
        }
        do {
            try await service.resendInvitation(id: id, for: user)
            guard revision == capturedRevision, activeUser?.id == capturedUserID else { return false }
            actionSuccess = "A replacement invitation has been sent."
            return true
        } catch {
            guard revision == capturedRevision, activeUser?.id == capturedUserID else { return false }
            if error is CancellationError { return false }
            handleMutationError(error)
            return false
        }
    }

    @discardableResult
    func removeRangerAccess(id: UUID) async -> Bool {
        guard !isPerformingAction else { return false }
        clearMessages()
        guard canManageRangers, let user = activeUser else {
            accessDeniedMessage = "Only the organisation owner can remove ranger access."
            return false
        }
        guard let existing = member(for: id), existing.canBeRemoved else {
            accessDeniedMessage = "You do not have permission to remove this account."
            return false
        }

        let capturedRevision = revision
        let capturedUserID = user.id
        isPerformingAction = true
        defer {
            if revision == capturedRevision { isPerformingAction = false }
        }
        do {
            try await service.removeRangerAccess(id: id, for: user)
            guard revision == capturedRevision, activeUser?.id == capturedUserID else { return false }
            rangers.removeAll { $0.id == id }
            if selectedRangerDetail?.id == id { selectedRangerDetail = nil }
            rangerTotal = max(0, rangerTotal - 1)
            if let existingProfile = profile, let count = existingProfile.memberCount {
                profile = OrganisationProfile(
                    id: existingProfile.id,
                    name: existingProfile.name,
                    email: existingProfile.email,
                    location: existingProfile.location,
                    memberCount: max(0, count - 1)
                )
            }
            actionSuccess = "Ranger access removed."
            return true
        } catch {
            guard revision == capturedRevision, activeUser?.id == capturedUserID else { return false }
            if error is CancellationError { return false }
            handleMutationError(error)
            return false
        }
    }

    private func upsertMember(_ member: RangerMember) {
        if let index = rangers.firstIndex(where: { $0.id == member.id }) {
            rangers[index] = member
        } else {
            rangers.append(member)
        }
    }

    private func handleProfileError(_ error: Error) {
        if let apiError = error as? APIError {
            switch apiError.statusCode {
            case 403:
                accessDeniedMessage = apiError.errorDescription ?? "Your account does not have permission to view this organisation profile."
                return
            case 404, 405:
                profileError = "Organisation profile is not available on this server."
                return
            default:
                break
            }
        }
        profileError = error.localizedDescription
    }

    private func handleRangersLoadError(_ error: Error) {
        if let apiError = error as? APIError {
            switch apiError.statusCode {
            case 403:
                rangersForbidden = true
                accessDeniedMessage = apiError.errorDescription ?? "Only the organisation owner can manage rangers."
                return
            case 404, 405:
                rangersError = "Ranger management is not available on this server."
                return
            default:
                break
            }
        }
        rangersError = error.localizedDescription
    }

    private func handleMutationError(_ error: Error, forProfileEdit: Bool = false) {
        if let apiError = error as? APIError {
            switch apiError.statusCode {
            case 403:
                if forProfileEdit { profileEditForbidden = true }
                accessDeniedMessage = apiError.errorDescription ?? "Access denied by server."
                return
            case 404, 405:
                actionError = "This organisation action is not available on this server."
                return
            default:
                break
            }
        }
        actionError = error.localizedDescription
    }
}
