import Foundation

enum PhotoRepresentation: String, Codable, Hashable, Sendable {
    case original, thumbnail
}

struct PhotoThumbnail: Codable, Hashable, Sendable {
    let revision: String
    let url: String
    let downloadURL: String?
    let expiresAt: Date?
    let width: Int
    let height: Int
    let contentType: String?
    enum CodingKeys: String, CodingKey {
        case revision, url, width, height
        case downloadURL = "download_url", expiresAt = "expires_at", contentType = "content_type"
    }
}

struct PhotoCacheKey: Hashable, Sendable {
    let scope: String
    let photoID: String
    let sourceRevision: String
    let representation: PhotoRepresentation
    let derivativeRevision: String
}

struct PhotoReference: Codable, Hashable, Sendable {
    let url: String
    var capturedAt: Date? = nil
    var uploadedAt: Date? = nil
    var id: UUID? = nil
    var revision: String? = nil
    var downloadURL: String? = nil
    var expiresAt: Date? = nil
    var thumbnail: PhotoThumbnail? = nil
    enum CodingKeys: String, CodingKey {
        case url, id, revision, thumbnail
        case capturedAt = "captured_at", uploadedAt = "uploaded_at"
        case downloadURL = "download_url", expiresAt = "expires_at"
    }

    func locator(_ representation: PhotoRepresentation) -> (path: String, expiry: Date?)? {
        if representation == .thumbnail, revision != nil {
            guard let thumbnail else { return nil }
            return (Self.preferred(thumbnail.downloadURL, fallback: thumbnail.url), thumbnail.expiresAt)
        }
        return (Self.preferred(downloadURL, fallback: url), expiresAt)
    }

    func key(scope: String, representation: PhotoRepresentation) -> PhotoCacheKey {
        let effective: PhotoRepresentation = representation == .thumbnail && revision == nil ? .original : representation
        return PhotoCacheKey(scope: scope, photoID: id?.uuidString ?? url,
            sourceRevision: revision ?? uploadedAt.map { String($0.timeIntervalSince1970) } ?? url,
            representation: effective, derivativeRevision: effective == .thumbnail ? thumbnail?.revision ?? "" : "")
    }

    private static func preferred(_ signed: String?, fallback: String) -> String {
        guard let signed, !signed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return fallback }
        return signed // Signed query/encoding must remain untouched.
    }
}

/// One private session owns this bounded byte cache. Decoded originals stay in the active comparison.
@MainActor
final class PhotoDelivery {
    nonisolated deinit {}

    typealias Fetch = @MainActor (String) async throws -> Data
    typealias Renewal = @MainActor () async throws -> PhotoReference?
    let scope: String
    private let fetch: Fetch
    private var generation = UUID()
    private var cache: [PhotoCacheKey: Data] = [:]
    private var order: [PhotoCacheKey] = []
    private var bytes = 0
    private let byteLimit = 64 * 1024 * 1024
    private var flights: [PhotoCacheKey: (id: UUID, task: Task<Data?, Error>)] = [:]

    init(scope: String, fetch: @escaping Fetch) { self.scope = scope; self.fetch = fetch }

    func clear() {
        generation = UUID()
        flights.values.forEach { $0.task.cancel() }
        flights.removeAll()
        cache.removeAll(); order.removeAll(); bytes = 0
    }

    func cancelOriginals(except keys: Set<PhotoCacheKey>) {
        for (key, flight) in flights where key.representation == .original && !keys.contains(key) {
            flight.task.cancel()
            flights[key] = nil
        }
    }

    func data(for photo: PhotoReference, representation: PhotoRepresentation,
              renewal: Renewal? = nil) async throws -> Data? {
        try Task.checkCancellation()
        guard photo.locator(representation) != nil else { return nil }
        let key = photo.key(scope: scope, representation: representation)
        if let hit = cache[key] {
            order.removeAll { $0 == key }; order.append(key)
            return hit
        }
        let captured = generation
        let flight: (id: UUID, task: Task<Data?, Error>)
        if let running = flights[key] { flight = running }
        else {
            flight = (UUID(), Task { try await self.download(photo, representation: representation, renewal: renewal, generation: captured) })
            flights[key] = flight
        }
        defer { if flights[key]?.id == flight.id { flights[key] = nil } }
        let value = try await flight.task.value
        try Task.checkCancellation()
        guard captured == generation else { throw CancellationError() }
        return value
    }

    private func download(_ photo: PhotoReference, representation: PhotoRepresentation,
                          renewal: Renewal?, generation captured: UUID) async throws -> Data? {
        var current = photo
        var renewed = false
        for _ in 0..<2 {
            try Task.checkCancellation()
            guard let locator = current.locator(representation) else { return nil }
            if !renewed, let expiry = locator.expiry, expiry <= Date(), let renewal {
                guard let next = try await renewal() else { throw APIError.notFound("Photo unavailable.") }
                try checkIdentity(photo, next)
                current = next; renewed = true
            }
            guard let target = current.locator(representation) else { return nil }
            do {
                let data = try await fetch(target.path)
                try Task.checkCancellation()
                guard captured == generation else { throw CancellationError() }
                let key = current.key(scope: scope, representation: representation)
                insert(data, for: key)
                return data
            } catch {
                if !renewed, [403, 404].contains((error as? APIError)?.statusCode ?? 0), let renewal {
                    guard let next = try await renewal() else { throw APIError.notFound("Photo unavailable.") }
                    try checkIdentity(photo, next)
                    current = next; renewed = true
                } else { throw error }
            }
        }
        throw APIError.notFound("Photo unavailable.")
    }

    private func checkIdentity(_ previous: PhotoReference, _ next: PhotoReference) throws {
        if previous.revision == nil && (previous.id == nil || previous.id == next.id) { return }
        guard previous.id == next.id, previous.revision == next.revision else {
            throw APIError.conflict("This photo changed. Refresh the review.")
        }
    }

    private func insert(_ data: Data, for key: PhotoCacheKey) {
        guard data.count <= byteLimit else { return }
        if let old = cache.removeValue(forKey: key) { bytes -= old.count }
        order.removeAll { $0 == key }
        while bytes + data.count > byteLimit || order.count >= 128 {
            guard let oldest = order.first else { break }
            order.removeFirst()
            if let old = cache.removeValue(forKey: oldest) { bytes -= old.count }
        }
        cache[key] = data; order.append(key); bytes += data.count
    }
}

struct ReviewPhotoContext: Hashable, Sendable {
    let logID: UUID
    let attemptID: UUID
}

struct ReviewPhotoDelivery: Decodable, Sendable {
    let attemptID: UUID
    let candidates: [CandidatePhoto]
    let queries: [QueryPhoto]
    struct CandidatePhoto: Decodable, Sendable {
        let turtleID: UUID
        let side: TurtlePhotoSide
        let availability: String
        let photo: PhotoReference?
        enum CodingKeys: String, CodingKey { case side, availability, photo, turtleID = "turtle_id" }
    }
    struct QueryPhoto: Decodable, Sendable {
        let side: TurtlePhotoSide
        let photoID: UUID?
        let photo: PhotoReference
        enum CodingKeys: String, CodingKey { case side, photo, photoID = "photo_id" }
    }
    enum CodingKeys: String, CodingKey { case candidates, queries, attemptID = "attempt_id" }
}

/// Renewal observers carry an epoch, so a completed refresh serves later failures
/// from the same batch as well as failures that were concurrent with the refresh.
@MainActor
final class ReviewPhotoMetadataStore {
    nonisolated deinit {}

    typealias Fetch = @MainActor (ReviewPhotoContext) async throws -> ReviewPhotoDelivery?
    private let fetch: Fetch
    private var generation = UUID()
    private var values: [ReviewPhotoContext: (value: ReviewPhotoDelivery?, epoch: Int)] = [:]
    private var flights: [ReviewPhotoContext: Task<ReviewPhotoDelivery?, Error>] = [:]
    init(fetch: @escaping Fetch) { self.fetch = fetch }
    func epoch(_ context: ReviewPhotoContext) -> Int { values[context]?.epoch ?? 0 }
    func clear() {
        generation = UUID()
        flights.values.forEach { $0.cancel() }
        flights.removeAll(); values.removeAll()
    }
    func load(_ context: ReviewPhotoContext, refreshing: Bool = false,
              after observedEpoch: Int? = nil) async throws -> ReviewPhotoDelivery? {
        try Task.checkCancellation()
        if let previous = values[context],
           (!refreshing && observedEpoch == nil) || observedEpoch.map({ previous.epoch > $0 }) == true {
            return previous.value
        }
        let captured = generation
        let task: Task<ReviewPhotoDelivery?, Error>
        if let pending = flights[context] { task = pending }
        else {
            task = Task { try await self.fetch(context) }
            flights[context] = task
        }
        do {
            let result = try await task.value
            try Task.checkCancellation()
            guard captured == generation else { throw CancellationError() }
            // Only the first waiter records the completed generation.
            if flights[context] != nil {
                values[context] = (result, (values[context]?.epoch ?? 0) + 1)
                flights[context] = nil
            }
            return result
        } catch {
            if captured == generation { flights[context] = nil }
            throw error
        }
    }
}
