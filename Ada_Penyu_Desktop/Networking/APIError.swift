import Foundation

enum APIError: LocalizedError, Equatable {
    case invalidResponse
    case invalidFileName
    case response(HTTPFailure)
    case notConfigured(String)
    case invalidURL(String)
    case transport(String)
    case decoding(String)
    case notFound(String)
    case conflict(String)
    case payloadTooLarge(String)
    case validation(String)
    case modelsUnavailable(String)
    case http(status: Int, detail: String)
    case unexpectedStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "The API returned an invalid response."
        case .invalidFileName: return "The downloaded filename is invalid."
        case .response(let failure): return failure.detail
        case .notConfigured(let message):
            return message
        case .invalidURL(let path):
            return "Invalid API URL: \(path)"
        case .transport(let message):
            return "Could not reach the identification service. \(message)"
        case .decoding(let message):
            return "The identification service returned data this app could not read. \(message)"
        case .notFound(let detail):
            return detail
        case .conflict(let detail):
            return detail
        case .payloadTooLarge(let detail):
            return detail
        case .validation(let detail):
            return detail
        case .modelsUnavailable(let detail):
            return detail
        case .http(_, let detail):
            return detail
        case .unexpectedStatus(let status):
            return "Unexpected response (\(status)) from the identification service."
        }
    }

    var statusCode: Int? {
        switch self {
        case .response(let failure): return failure.status
        case .notFound: return 404
        case .conflict: return 409
        case .payloadTooLarge: return 413
        case .validation: return 422
        case .modelsUnavailable: return 503
        case .http(let status, _): return status
        case .unexpectedStatus(let status): return status
        default: return nil
        }
    }

    var code: String? { if case .response(let failure) = self { return failure.code }; return nil }
    var retryAfter: TimeInterval? { if case .response(let failure) = self { return failure.retryAfter }; return nil }
    var fieldErrors: [String: String] { if case .response(let failure) = self { return failure.fields }; return [:] }

    static func from(response: HTTPURLResponse, body: Data) -> APIError {
        let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        var fields: [String: String] = [:]
        for item in object?["detail"] as? [[String: Any]] ?? [] {
            if let field = (item["loc"] as? [String])?.last, let message = item["msg"] as? String {
                fields[field] = message
            }
        }
        let detail = FastAPIDetail.parse(from: body)
        let requestID = response.value(forHTTPHeaderField: "X-Request-ID").map {
            String($0.filter { $0.isLetter || $0.isNumber || "-_.".contains($0) }.prefix(128))
        }
        var fallback = response.statusCode == 413 ? "The photos are too large. Compress them or choose smaller photos." : "Request failed (HTTP \(response.statusCode)). Please try again."
        if let requestID, !requestID.isEmpty { fallback += " Request ID: \(requestID)." }
        let retryHeader = response.value(forHTTPHeaderField: "Retry-After")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
        let delay = retryHeader.flatMap(Double.init) ?? retryHeader.flatMap { formatter.date(from: $0)?.timeIntervalSinceNow }
        return .response(HTTPFailure(status: response.statusCode, detail: detail == "Request failed." ? fallback : detail,
            code: object?["code"] as? String, fields: fields, retryAfter: delay.flatMap { $0.isFinite ? max(0, $0) : nil },
            requestID: requestID))
    }

    static func from(status: Int, body: Data) -> APIError {
        let detail = FastAPIDetail.parse(from: body)
        switch status {
        case 404:
            return .notFound(detail)
        case 409:
            return .conflict(detail)
        case 413:
            return .payloadTooLarge(detail)
        case 422:
            return .validation(detail)
        case 503:
            return .modelsUnavailable(detail)
        default:
            return .http(status: status, detail: detail)
        }
    }

    static func == (lhs: APIError, rhs: APIError) -> Bool {
        switch (lhs, rhs) {
        case (.response(let a), .response(let b)): return a == b
        case (.notConfigured(let a), .notConfigured(let b)),
             (.invalidURL(let a), .invalidURL(let b)),
             (.transport(let a), .transport(let b)),
             (.decoding(let a), .decoding(let b)),
             (.notFound(let a), .notFound(let b)),
             (.conflict(let a), .conflict(let b)),
             (.payloadTooLarge(let a), .payloadTooLarge(let b)),
             (.validation(let a), .validation(let b)),
             (.modelsUnavailable(let a), .modelsUnavailable(let b)):
            return a == b
        case (.http(let s1, let d1), .http(let s2, let d2)):
            return s1 == s2 && d1 == d2
        case (.unexpectedStatus(let a), .unexpectedStatus(let b)):
            return a == b
        default:
            return false
        }
    }
}

enum FastAPIDetail {
    static func parse(from data: Data) -> String {
        guard !data.isEmpty else { return "Request failed." }
        if let envelope = try? JSONDecoder().decode(DetailEnvelope.self, from: data) {
            return envelope.rendered
        }
        return "Request failed."
    }

    private struct DetailEnvelope: Decodable {
        let detail: DetailValue

        var rendered: String { detail.rendered }
    }

    private enum DetailValue: Decodable {
        case string(String)
        case items([ValidationItem])
        case object([String: AnyCodableValue])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                self = .string(string)
                return
            }
            if let items = try? container.decode([ValidationItem].self) {
                self = .items(items)
                return
            }
            if let object = try? container.decode([String: AnyCodableValue].self) {
                self = .object(object)
                return
            }
            self = .string("Request failed.")
        }

        var rendered: String {
            switch self {
            case .string(let value):
                return value
            case .items(let items):
                let messages = items.map(\.rendered).filter { !$0.isEmpty }
                return messages.isEmpty ? "Validation failed." : messages.joined(separator: "\n")
            case .object(let object):
                if case .string(let status)? = object["status"], status != "ok" {
                    let parts = ["miewid", "xfeat"].compactMap { key -> String? in
                        guard case .object(let nested)? = object[key],
                              case .string(let detail)? = nested["detail"] else { return nil }
                        return detail
                    }
                    if !parts.isEmpty { return parts.joined(separator: "\n") }
                }
                return "Identification models are not ready."
            }
        }
    }

    private struct ValidationItem: Decodable {
        let loc: [AnyCodableValue]?
        let msg: String?
        let type: String?

        var rendered: String {
            let location = (loc ?? []).compactMap(\.stringValue).joined(separator: ".")
            let message = msg ?? type ?? "Invalid value"
            return location.isEmpty ? message : "\(location): \(message)"
        }
    }
}

enum AnyCodableValue: Decodable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: AnyCodableValue])
    case array([AnyCodableValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: AnyCodableValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([AnyCodableValue].self) {
            self = .array(value)
        } else {
            self = .null
        }
    }

    var stringValue: String? {
        switch self {
        case .string(let value): return value
        case .int(let value): return String(value)
        case .double(let value): return String(value)
        case .bool(let value): return String(value)
        default: return nil
        }
    }
}

nonisolated struct HTTPFailure: Equatable, Sendable {
    let status: Int
    let detail: String
    let code: String?
    let fields: [String: String]
    let retryAfter: TimeInterval?
    let requestID: String?
}
