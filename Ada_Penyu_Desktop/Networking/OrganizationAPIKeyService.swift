import Foundation

struct OrganizationAPIKeyMetadata: Decodable, Equatable {
    let configured: Bool
    let prefix: String?
    let issuedAt: Date?

    enum CodingKeys: String, CodingKey {
        case configured, prefix
        case issuedAt = "issued_at"
    }

    static let unconfigured = Self(configured: false, prefix: nil, issuedAt: nil)
}

struct IssuedOrganizationAPIKey: Decodable {
    let metadata: OrganizationAPIKeyMetadata
    let apiKey: String

    private enum CodingKeys: String, CodingKey { case apiKey = "api_key" }

    init(from decoder: Decoder) throws {
        metadata = try OrganizationAPIKeyMetadata(from: decoder)
        apiKey = try decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .apiKey)
        guard metadata.configured, !apiKey.isEmpty else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Missing issued key."))
        }
    }
}

@MainActor
struct OrganizationAPIKeyService {
    let client: APIClient
    private let path = "/api/v1/organization/api-key"

    func fetchMetadata() async throws -> OrganizationAPIKeyMetadata {
        try await client.send(APIRequest(method: "GET", path: path, acceptedStatuses: [200], timeoutInterval: 30))
    }

    func rotate() async throws -> IssuedOrganizationAPIKey {
        try await client.send(APIRequest(method: "POST", path: path + "/rotate", acceptedStatuses: [200], timeoutInterval: 30))
    }

    func revoke() async throws {
        try await client.sendVoid(APIRequest(method: "DELETE", path: path, acceptedStatuses: [204], timeoutInterval: 30))
    }
}
