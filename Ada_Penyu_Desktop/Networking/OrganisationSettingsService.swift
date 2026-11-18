import Foundation

struct OrganisationProfile: Equatable, Identifiable {
    let id: UUID
    let name: String
    let email: String?
    let location: String?
    let memberCount: Int?
}

struct OrganisationProfileUpdate: Equatable {
    let name: String
    let email: String
    let location: String
}

enum RangerStatus: String, Equatable {
    case active
    case invited
    case revoked

    var displayName: String {
        switch self {
        case .active: "Active"
        case .invited: "Invited"
        case .revoked: "Revoked"
        }
    }
}

struct RangerMember: Equatable, Identifiable {
    let id: UUID
    let organizationID: UUID
    let fullName: String
    let email: String
    let role: UserRole
    let status: RangerStatus
    let pendingEmail: String?
    let canRemove: Bool
    let isCurrentUser: Bool

    var canEditDetails: Bool {
        role != .owner && !isCurrentUser
    }

    var canResendInvitation: Bool {
        status == .invited && canEditDetails
    }

    var canBeRemoved: Bool {
        canRemove && !isCurrentUser && role != .owner
    }
}

struct RangerPage: Equatable {
    let items: [RangerMember]
    let total: Int
    let limit: Int
    let offset: Int
}

struct RangerListDTO: Decodable {
    let items: [AccountDTO]
    let total: Int
    let limit: Int
    let offset: Int
}

extension OrganizationDTO {
    var profile: OrganisationProfile {
        OrganisationProfile(
            id: id,
            name: name,
            email: email,
            location: location,
            memberCount: membersCount
        )
    }
}

extension AccountDTO {
    func rangerMember() throws -> RangerMember {
        let mappedStatus: RangerStatus
        switch status {
        case "active": mappedStatus = .active
        case "invited": mappedStatus = .invited
        case "revoked": mappedStatus = .revoked
        default: throw APIError.decoding("Unknown account status.")
        }
        return RangerMember(
            id: id,
            organizationID: organizationID,
            fullName: fullName,
            email: email,
            role: role,
            status: mappedStatus,
            pendingEmail: pendingEmail,
            canRemove: canRemove ?? (!isSelf && role != .owner),
            isCurrentUser: isSelf
        )
    }
}

/// Authenticated transport for Organisation Profile and Manage Rangers matching
/// AdaPenyu iPhone's `RemoteOrganisationSettingsService` contract.
@MainActor
final class OrganisationSettingsService {
    private let client: APIClient
    private var profiles: [UUID: OrganizationDTO] = [:]
    private var members: [UUID: RangerMember] = [:]

    init(client: APIClient) {
        self.client = client
    }

    func clearSession() {
        profiles.removeAll()
        members.removeAll()
    }

    private func requireUser(_ user: AppUser, ownerOnly: Bool = false) throws {
        try client.authorization?.requireUser(user)
        if ownerOnly, user.role != .owner {
            throw APIError.http(status: 403, detail: "This operation requires an organisation owner.")
        }
    }

    private func checkGeneration(_ generation: UUID?) throws {
        if let generation {
            try client.authorization?.check(generation)
        }
    }

    private func memberPath(_ id: UUID) -> String {
        "/api/v1/rangers/\(id.uuidString.lowercased())"
    }

    private func retain(_ dto: AccountDTO, for user: AppUser) throws -> RangerMember {
        guard dto.organizationID == user.organisationID else {
            throw APIError.decoding("Member organisation does not match this session.")
        }
        let member = try dto.rangerMember()
        members[member.id] = member
        return member
    }

    func fetchOrganisationProfile(for user: AppUser) async throws -> OrganisationProfile {
        try requireUser(user)
        let generation = client.authorization?.generation
        let dto: OrganizationDTO = try await client.send(APIRequest(
            method: "GET",
            path: "/api/v1/organization",
            timeoutInterval: 30
        ))
        try checkGeneration(generation)
        guard dto.id == user.organisationID else {
            throw APIError.decoding("Organisation does not match this session.")
        }
        profiles[dto.id] = dto
        return dto.profile
    }

    func updateOrganisationProfile(_ update: OrganisationProfileUpdate, for user: AppUser) async throws -> OrganisationProfile {
        try requireUser(user, ownerOnly: true)
        let generation = client.authorization?.generation
        if user.organisationID.flatMap({ profiles[$0] }) == nil {
            _ = try await fetchOrganisationProfile(for: user)
        }
        try checkGeneration(generation)
        guard let id = user.organisationID, let original = profiles[id] else {
            throw APIError.notConfigured("Missing organisation.")
        }

        var patch: [String: Any] = [:]
        let name = update.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = update.email.trimmingCharacters(in: .whitespacesAndNewlines)
        let location = update.location.trimmingCharacters(in: .whitespacesAndNewlines)

        if name != original.name {
            patch["name"] = name
        }
        if email != (original.email ?? "") {
            patch["email"] = email.isEmpty ? NSNull() : email as Any
        }
        if location != (original.location ?? "") {
            patch["location"] = location.isEmpty ? NSNull() : location as Any
        }
        if patch.isEmpty {
            return original.profile
        }

        let dto: OrganizationDTO = try await client.send(APIRequest(
            method: "PATCH",
            path: "/api/v1/organization",
            body: try JSONSerialization.data(withJSONObject: patch),
            timeoutInterval: 30
        ))
        try checkGeneration(generation)
        guard dto.id == id else {
            throw APIError.decoding("Organisation does not match this session.")
        }
        profiles[id] = dto
        if dto.name != original.name {
            client.authorization?.updateOrganisationName(dto.name, organizationID: id)
        }
        return dto.profile
    }

    func fetchRangers(for user: AppUser, query: String, limit: Int, offset: Int) async throws -> RangerPage {
        try requireUser(user, ownerOnly: true)
        let generation = client.authorization?.generation
        let dto: RangerListDTO = try await client.send(APIRequest(
            method: "GET",
            path: "/api/v1/rangers",
            query: ["q": query, "limit": String(limit), "offset": String(offset)],
            timeoutInterval: 30
        ))
        try checkGeneration(generation)
        guard dto.items.allSatisfy({ $0.organizationID == user.organisationID }) else {
            throw APIError.decoding("Member organisation does not match this session.")
        }
        let mapped = try dto.items.map { try $0.rangerMember() }
        for member in mapped {
            members[member.id] = member
        }
        return RangerPage(items: mapped, total: dto.total, limit: dto.limit, offset: dto.offset)
    }

    func fetchRangerDetail(id: UUID, for user: AppUser) async throws -> RangerMember {
        try requireUser(user, ownerOnly: true)
        let generation = client.authorization?.generation
        let dto: AccountDTO = try await client.send(APIRequest(
            method: "GET",
            path: memberPath(id),
            timeoutInterval: 30
        ))
        try checkGeneration(generation)
        return try retain(dto, for: user)
    }

    func addRanger(fullName: String, email: String, for user: AppUser) async throws -> RangerMember {
        try requireUser(user, ownerOnly: true)
        let generation = client.authorization?.generation
        let payload = [
            "full_name": fullName.trimmingCharacters(in: .whitespacesAndNewlines),
            "email": email.trimmingCharacters(in: .whitespacesAndNewlines)
        ]
        let dto: AccountDTO = try await client.send(APIRequest(
            method: "POST",
            path: "/api/v1/rangers",
            body: try JSONEncoder().encode(payload),
            acceptedStatuses: [201],
            timeoutInterval: 30
        ))
        try checkGeneration(generation)
        return try retain(dto, for: user)
    }

    func updateRanger(id: UUID, fullName: String, email: String, for user: AppUser) async throws -> RangerMember {
        try requireUser(user, ownerOnly: true)
        let generation = client.authorization?.generation
        if members[id] == nil {
            _ = try await fetchRangerDetail(id: id, for: user)
        }
        try checkGeneration(generation)
        guard let original = members[id] else {
            throw APIError.notFound("Member not found.")
        }
        guard original.canEditDetails else {
            throw APIError.http(status: 403, detail: "This account cannot be edited here.")
        }
        var patch: [String: String] = [:]
        let trimmedName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName != original.fullName { patch["full_name"] = trimmedName }
        if trimmedEmail != original.email { patch["email"] = trimmedEmail }
        if patch.isEmpty { return original }

        let dto: AccountDTO = try await client.send(APIRequest(
            method: "PATCH",
            path: memberPath(id),
            body: try JSONEncoder().encode(patch),
            timeoutInterval: 30
        ))
        try checkGeneration(generation)
        return try retain(dto, for: user)
    }

    func resendInvitation(id: UUID, for user: AppUser) async throws {
        try requireUser(user, ownerOnly: true)
        let generation = client.authorization?.generation
        try await client.sendVoid(APIRequest(
            method: "POST",
            path: memberPath(id) + "/resend-invitation",
            acceptedStatuses: [204],
            timeoutInterval: 30
        ))
        try checkGeneration(generation)
    }

    func removeRangerAccess(id: UUID, for user: AppUser) async throws {
        try requireUser(user, ownerOnly: true)
        let generation = client.authorization?.generation
        try await client.sendVoid(APIRequest(
            method: "DELETE",
            path: memberPath(id),
            acceptedStatuses: [204],
            timeoutInterval: 30
        ))
        try checkGeneration(generation)
        members[id] = nil
    }
}
