import Foundation

extension APIClient {
    func get<T: Decodable>(_ path: String, queryItems: [URLQueryItem] = []) async throws -> T {
        try await request(path: path, method: "GET", queryItems: queryItems)
    }

    func getData(_ path: String, queryItems: [URLQueryItem] = []) async throws -> (Data, HTTPURLResponse) {
        try await requestData(path: path, method: "GET", queryItems: queryItems)
    }

    func request<T: Decodable>(path: String, method: String, queryItems: [URLQueryItem] = [], body: Data? = nil) async throws -> T {
        let (data, _) = try await requestData(path: path, method: method, queryItems: queryItems, body: body)
        do {
            return try JSONDecoder.api.decode(T.self, from: data)
        } catch {
            throw APIError.invalidResponse
        }
    }

    func requestMultipart<T: Decodable>(
        path: String,
        method: String = "POST",
        queryItems: [URLQueryItem] = [],
        parts: [MultipartPart]
    ) async throws -> T {
        let (data, _) = try await requestMultipartData(path: path, method: method, queryItems: queryItems, parts: parts)
        do {
            return try JSONDecoder.api.decode(T.self, from: data)
        } catch {
            throw APIError.invalidResponse
        }
    }

    func requestMultipartData(
        path: String,
        method: String = "POST",
        queryItems: [URLQueryItem] = [],
        parts: [MultipartPart],
        accept: String = "application/json"
    ) async throws -> (Data, HTTPURLResponse) {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        for part in parts {
            body.append(Data("--\(boundary)\r\n".utf8))
            if let filename = part.filename {
                body.append(Data("Content-Disposition: form-data; name=\"\(part.name)\"; filename=\"\(filename)\"\r\n".utf8))
            } else {
                body.append(Data("Content-Disposition: form-data; name=\"\(part.name)\"\r\n".utf8))
            }
            if let contentType = part.contentType {
                body.append(Data("Content-Type: \(contentType)\r\n".utf8))
            }
            body.append(Data("\r\n".utf8))
            body.append(part.data)
            body.append(Data("\r\n".utf8))
        }
        body.append(Data("--\(boundary)--\r\n".utf8))
        return try await requestData(
            path: path,
            method: method,
            queryItems: queryItems,
            body: body,
            contentType: "multipart/form-data; boundary=\(boundary)",
            accept: accept
        )
    }

    func requestData(path: String, method: String, queryItems: [URLQueryItem] = [], body: Data? = nil,
                     contentType: String = "application/json", accept: String = "application/json") async throws -> (Data, HTTPURLResponse) {
        if let direct = URL(string: path), direct.scheme != nil {
            guard ["http", "https"].contains(direct.scheme?.lowercased() ?? "") else { throw APIError.invalidResponse }
            let trusted = config.isTrustedOrigin(direct)
            let spec = APIRequest(method: method, path: path, body: body, contentType: contentType,
                acceptedStatuses: Set(200..<300), authentication: trusted ? .required : .none, accept: accept, queryItems: queryItems)
            let generation = authorization?.generation
            let result = try await sendHTTP(spec, url: direct)
            if let generation { try authorization?.check(generation) }
            return (result.value, result.http)
        }
        let result = try await sendHTTP(APIRequest(method: method, path: path, body: body, contentType: contentType,
            acceptedStatuses: Set(200..<300), accept: accept, queryItems: queryItems))
        return (result.value, result.http)
    }
}
