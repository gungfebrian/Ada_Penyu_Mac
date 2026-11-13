import Foundation

enum AuthError: LocalizedError {
    case invalidCredentials
    case custom(String)
    var errorDescription: String? {
        switch self {
        case .invalidCredentials: "Enter your email and password."
        case .custom(let message): message
        }
    }
}

struct TokenPair: Codable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresIn: Int
    let refreshExpiresAt: Date
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token", refreshToken = "refresh_token", tokenType = "token_type"
        case expiresIn = "expires_in", refreshExpiresAt = "refresh_expires_at"
    }
}

enum UserRole: String, Decodable { case owner, ranger }

struct AppUser {
    let id: UUID
    let email: String
    let displayName: String
    let role: UserRole
    let organisationID: UUID?
    let organisationName: String
}

struct AuthSession { let user: AppUser }

struct AccountDTO: Decodable {
    let id: UUID
    let organizationID: UUID
    let fullName: String
    let email: String
    let status: String
    let role: UserRole
    let isSelf: Bool
    enum CodingKeys: String, CodingKey {
        case id, email, status, role
        case organizationID = "organization_id", fullName = "full_name", isSelf = "is_self"
    }
}

struct OrganizationDTO: Decodable {
    let id: UUID
    let name: String
    let ownerUserID: UUID
    enum CodingKeys: String, CodingKey { case id, name, ownerUserID = "owner_user_id" }
}

enum CurrentAccountPolicy {
    static func session(account: AccountDTO, organization: OrganizationDTO) throws -> AuthSession {
        guard account.isSelf, account.status == "active", account.organizationID == organization.id,
              (account.role == .owner) == (organization.ownerUserID == account.id) else {
            throw AuthError.custom("The server returned an inconsistent account context.")
        }
        return AuthSession(user: AppUser(id: account.id, email: account.email, displayName: account.fullName,
            role: account.role, organisationID: organization.id, organisationName: organization.name))
    }
}
