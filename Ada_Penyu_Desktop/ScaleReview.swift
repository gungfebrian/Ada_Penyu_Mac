import AppKit
import Combine
import CryptoKit
import Foundation

nonisolated struct ScalePoint: Codable, Hashable, Sendable {
    var x: Double
    var y: Double
}

nonisolated struct ScaleRect: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var isValid: Bool { [x, y, width, height].allSatisfy(\.isFinite) && x >= 0 && y >= 0 && width > 0.01 && height > 0.01 && x + width <= 1.000001 && y + height <= 1.000001 }
    func contains(_ p: ScalePoint) -> Bool { p.x.isFinite && p.y.isFinite && p.x >= x && p.y >= y && p.x <= x + width && p.y <= y + height }
}

nonisolated struct ReviewedScale: Codable, Identifiable, Equatable, Sendable {
    enum Source: String, Codable, Sendable { case manual, proposal }
    enum Status: String, Codable, Sendable { case pending, confirmed, rejected }
    let id: UUID
    let number: Int
    var polygon: [ScalePoint]
    var source: Source
    var status: Status
    var center: ScalePoint {
        ScalePoint(x: polygon.map(\.x).reduce(0, +) / Double(max(1, polygon.count)),
            y: polygon.map(\.y).reduce(0, +) / Double(max(1, polygon.count)))
    }
}

nonisolated struct ScalePhotoReview: Codable, Sendable {
    let photoHash: String
    let pixelWidth: Int
    let pixelHeight: Int
    private(set) var headROI: ScaleRect?
    private(set) var headRevision = UUID()
    private(set) var scales: [ReviewedScale] = []
    private var nextNumber = 1
    init(photoHash: String, pixelWidth: Int, pixelHeight: Int) {
        self.photoHash = photoHash; self.pixelWidth = pixelWidth; self.pixelHeight = pixelHeight
    }
    var confirmedCount: Int { scales.filter { $0.status == .confirmed }.count }
    var pendingCount: Int { scales.filter { $0.status == .pending }.count }

    mutating func setHeadROI(_ roi: ScaleRect) {
        guard roi.isValid else { return }
        headROI = roi; headRevision = UUID(); scales = []; nextNumber = 1
    }
    @discardableResult mutating func add(polygon: [ScalePoint], source: ReviewedScale.Source) -> UUID? {
        guard valid(polygon) else { return nil }
        let id = UUID()
        scales.append(ReviewedScale(id: id, number: nextNumber, polygon: polygon, source: source, status: .pending))
        nextNumber += 1
        return id
    }
    mutating func setStatus(_ id: UUID, _ status: ReviewedScale.Status) {
        guard let index = scales.firstIndex(where: { $0.id == id }) else { return }
        scales[index].status = status
    }
    mutating func remove(_ id: UUID) { scales.removeAll { $0.id == id } }
    @discardableResult mutating func redraw(_ id: UUID, polygon: [ScalePoint]) -> Bool {
        guard valid(polygon), let index = scales.firstIndex(where: { $0.id == id }) else { return false }
        scales[index].polygon = polygon; scales[index].source = .manual; scales[index].status = .pending
        return true
    }
    mutating func replaceProposals(_ polygons: [[ScalePoint]], preserving protectedIDs: Set<UUID> = []) {
        // Reviewed (including rejected) and manual work must survive regeneration.
        scales.removeAll { $0.source == .proposal && $0.status == .pending && !protectedIDs.contains($0.id) }
        for polygon in polygons {
            guard !scales.contains(where: { old in polygon.contains(where: { Self.contains($0, polygon: old.polygon) }) || old.polygon.contains(where: { Self.contains($0, polygon: polygon) }) }) else { continue }
            _ = add(polygon: polygon, source: .proposal)
        }
    }
    private func valid(_ polygon: [ScalePoint]) -> Bool {
        guard let headROI, polygon.count >= 3, Set(polygon).count == polygon.count,
              polygon.allSatisfy(headROI.contains), abs(Self.area(polygon)) > 0.00001 else { return false }
        // Reject self-intersecting or self-touching nonadjacent edges.
        for i in polygon.indices {
            let a = polygon[i], b = polygon[(i + 1) % polygon.count]
            for j in polygon.indices where j > i && j != (i + 1) % polygon.count && i != (j + 1) % polygon.count {
                let c = polygon[j], d = polygon[(j + 1) % polygon.count]
                if Self.intersects(a, b, c, d) { return false }
            }
        }
        return true
    }
    static func area(_ points: [ScalePoint]) -> Double {
        guard points.count >= 3 else { return 0 }
        return points.indices.reduce(0) { total, i in
            let next = points[(i + 1) % points.count]
            return total + points[i].x * next.y - next.x * points[i].y
        } / 2
    }
    static func contains(_ p: ScalePoint, polygon: [ScalePoint]) -> Bool {
        guard polygon.count >= 3 else { return false }
        var inside = false
        for i in polygon.indices {
            let a = polygon[i], b = polygon[(i + 1) % polygon.count]
            if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
        }
        return inside
    }
    private static func intersects(_ a: ScalePoint, _ b: ScalePoint, _ c: ScalePoint, _ d: ScalePoint) -> Bool {
        func cross(_ p: ScalePoint, _ q: ScalePoint, _ r: ScalePoint) -> Double { (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x) }
        func on(_ p: ScalePoint, _ q: ScalePoint, _ r: ScalePoint) -> Bool {
            abs(cross(p, q, r)) < 1e-10 && r.x >= min(p.x, q.x) && r.x <= max(p.x, q.x) && r.y >= min(p.y, q.y) && r.y <= max(p.y, q.y)
        }
        return (cross(a, b, c) * cross(a, b, d) < 0 && cross(c, d, a) * cross(c, d, b) < 0) || on(a, b, c) || on(a, b, d) || on(c, d, a) || on(c, d, b)
    }
}

@MainActor
final class ScaleReviewStore: ObservableObject {
    @Published private(set) var documents: [String: ScalePhotoReview] = [:]
    private var redrawLeases: [String: [UUID: UUID]] = [:]
    func ensurePhoto(hash: String, width: Int, height: Int) {
        if documents[hash] == nil { documents[hash] = ScalePhotoReview(photoHash: hash, pixelWidth: width, pixelHeight: height) }
    }
    func update(_ hash: String, _ edit: (inout ScalePhotoReview) -> Void) {
        guard var doc = documents[hash] else { return }
        edit(&doc)
        redrawLeases[hash] = redrawLeases[hash]?.filter { _, id in doc.scales.contains { $0.id == id } }
        documents[hash] = doc
    }
    func beginRedraw(_ hash: String, scaleID: UUID) -> UUID? {
        guard documents[hash]?.scales.contains(where: { $0.id == scaleID }) == true else { return nil }
        let lease = UUID()
        redrawLeases[hash, default: [:]][lease] = scaleID
        return lease
    }
    func endRedraw(_ hash: String, lease: UUID) { redrawLeases[hash]?[lease] = nil }
    func replaceProposals(_ hash: String, polygons: [[ScalePoint]]) {
        let protectedIDs = Set(redrawLeases[hash, default: [:]].values)
        update(hash) { $0.replaceProposals(polygons, preserving: protectedIDs) }
    }
    static func photoHash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    /// Seeds Head ROI and real extracted scale polygons from the photograph inside the cheek ROI
    /// (falling back to `.fgp` keypoint coordinates only when no pixel image is supplied).
    func seedMockAnnotations(for hash: String, sample: I3SSampleEntry? = nil, image: NSImage? = nil) {
        update(hash) { doc in
            let w = Double(max(1, sample?.imageWidth ?? doc.pixelWidth))
            let h = Double(max(1, sample?.imageHeight ?? doc.pixelHeight))

            let roiPolygon: [ScalePoint]
            if let sample, sample.imageWidth > 0, sample.imageHeight > 0, !sample.roi.isEmpty {
                roiPolygon = sample.roi.compactMap { pair in
                    guard pair.count >= 2 else { return nil }
                    return ScalePoint(x: min(0.98, max(0.02, pair[0] / w)), y: min(0.98, max(0.02, pair[1] / h)))
                }
            } else if let image {
                roiPolygon = PatternContourEngine.detectFacialPatternROI(from: image, side: .left).roi
            } else {
                roiPolygon = []
            }

            let roiRect: ScaleRect
            if !roiPolygon.isEmpty {
                let minX = max(0.02, (roiPolygon.map(\.x).min() ?? 0.25) - 0.02)
                let minY = max(0.02, (roiPolygon.map(\.y).min() ?? 0.25) - 0.02)
                let maxX = min(0.98, (roiPolygon.map(\.x).max() ?? 0.75) + 0.02)
                let maxY = min(0.98, (roiPolygon.map(\.y).max() ?? 0.75) + 0.02)
                roiRect = ScaleRect(x: minX, y: minY, width: max(0.15, maxX - minX), height: max(0.15, maxY - minY))
            } else {
                roiRect = ScaleRect(x: 0.28, y: 0.24, width: 0.44, height: 0.48)
            }
            doc.setHeadROI(roiRect)

            if let image {
                let effectivePoly = roiPolygon.count >= 3 ? roiPolygon : [
                    ScalePoint(x: roiRect.x, y: roiRect.y),
                    ScalePoint(x: roiRect.x + roiRect.width, y: roiRect.y),
                    ScalePoint(x: roiRect.x + roiRect.width, y: roiRect.y + roiRect.height),
                    ScalePoint(x: roiRect.x, y: roiRect.y + roiRect.height),
                ]
                let extracted = PatternContourEngine.extractPatterns(from: image, roiPolygon: effectivePoly)
                if !extracted.isEmpty {
                    var addedCount = 0
                    for pat in extracted {
                        let clipped = pat.polygon.map { p in
                            ScalePoint(
                                x: min(roiRect.x + roiRect.width - 0.002, max(roiRect.x + 0.002, p.x)),
                                y: min(roiRect.y + roiRect.height - 0.002, max(roiRect.y + 0.002, p.y))
                            )
                        }
                        if let addedID = doc.add(polygon: clipped, source: .proposal) {
                            addedCount += 1
                            if addedCount <= max(4, extracted.count - 3) {
                                doc.setStatus(addedID, .confirmed)
                            }
                        }
                    }
                    return
                }
            }

            if let sample, !sample.keypoints.isEmpty {
                var placedCenters: [(Double, Double, Double)] = []
                for kp in sample.keypoints {
                    guard kp.count >= 3 else { continue }
                    let cx = kp[0] / w
                    let cy = kp[1] / h
                    let rX = max(0.016, min(0.036, (kp[2] / w) * 0.85))
                    let rY = max(0.018, min(0.040, (kp[2] / h) * 0.85))
                    let radius = max(rX, rY)

                    guard cx - rX > roiRect.x + 0.005,
                          cx + rX < roiRect.x + roiRect.width - 0.005,
                          cy - rY > roiRect.y + 0.005,
                          cy + rY < roiRect.y + roiRect.height - 0.005 else { continue }

                    let overlaps = placedCenters.contains { ox, oy, orad in
                        hypot(cx - ox, cy - oy) < (radius + orad) * 1.05
                    }
                    guard !overlaps else { continue }

                    let poly: [ScalePoint] = (0..<6).map { i in
                        let angle = Double(i) * (.pi / 3.0) + 0.2
                        return ScalePoint(x: cx + cos(angle) * rX, y: cy + sin(angle) * rY)
                    }
                    if let addedID = doc.add(polygon: poly, source: .proposal) {
                        placedCenters.append((cx, cy, radius))
                        if placedCenters.count <= 8 {
                            doc.setStatus(addedID, .confirmed)
                        }
                    }
                    if placedCenters.count >= 12 { break }
                }
            }
        }
    }
}

/// Proposes enclosed intensity regions, not anatomically recognized scales.
nonisolated enum ScaleRegionProposalEngine {
    static func closedRegions(edges: [UInt8], width: Int, height: Int, roi: ScaleRect) -> [[ScalePoint]] {
        guard width > 2, height > 2, width <= Int.max / height, edges.count == width * height, roi.isValid else { return [] }
        let x0 = max(0, Int(roi.x * Double(width))), y0 = max(0, Int(roi.y * Double(height)))
        let x1 = min(width - 1, Int((roi.x + roi.width) * Double(width)) - 1)
        let y1 = min(height - 1, Int((roi.y + roi.height) * Double(height)) - 1)
        guard x1 > x0, y1 > y0 else { return [] }
        let roiArea = (x1 - x0 + 1) * (y1 - y0 + 1)
        var labels = [Int](repeating: 0, count: edges.count)
        var label = 0
        var polygons: [[ScalePoint]] = []
        for y in y0...y1 {
            if Task.isCancelled { return [] }
            for x in x0...x1 {
                let seed = y * width + x
                guard edges[seed] == 0, labels[seed] == 0 else { continue }
                label += 1
                var queue = [seed], cursor = 0, touchesBorder = false
                labels[seed] = label
                while cursor < queue.count {
                    if cursor % 4096 == 0, Task.isCancelled { return [] }
                    let pixel = queue[cursor]; cursor += 1
                    let px = pixel % width, py = pixel / width
                    if px == x0 || py == y0 || px == x1 || py == y1 { touchesBorder = true }
                    for (nx, ny) in [(px - 1, py), (px + 1, py), (px, py - 1), (px, py + 1)] where nx >= x0 && nx <= x1 && ny >= y0 && ny <= y1 {
                        let next = ny * width + nx
                        if labels[next] == 0, edges[next] == 0 { labels[next] = label; queue.append(next) }
                    }
                }
                guard !touchesBorder, queue.count >= max(8, roiArea / 650), queue.count <= roiArea / 3 else { continue }
                // Trace directed pixel-boundary edges; holes remain part of one candidate.
                let stride = width + 1
                var links: [Int: [Int]] = [:]
                func edge(_ a: Int, _ b: Int) { links[a, default: []].append(b) }
                for p in queue {
                    let px = p % width, py = p / width, v = py * stride + px
                    if py == 0 || labels[p - width] != label { edge(v, v + 1) }
                    if px == width - 1 || labels[p + 1] != label { edge(v + 1, v + 1 + stride) }
                    if py == height - 1 || labels[p + width] != label { edge(v + 1 + stride, v + stride) }
                    if px == 0 || labels[p - 1] != label { edge(v + stride, v) }
                }
                var loops: [[ScalePoint]] = []
                while let start = links.keys.min() {
                    var current = start, vertices: [Int] = [], closed = false
                    while let next = links[current]?.popLast() {
                        if links[current]?.isEmpty == true { links.removeValue(forKey: current) }
                        vertices.append(current); current = next
                        if current == start { closed = true; break }
                        if vertices.count > queue.count * 4 { break }
                    }
                    if closed, vertices.count >= 3 {
                        let simple = vertices.indices.filter { i in
                            let prev = vertices[(i + vertices.count - 1) % vertices.count], this = vertices[i], next = vertices[(i + 1) % vertices.count]
                            return (this - prev) != (next - this)
                        }.map { v -> ScalePoint in
                            let pixel = vertices[v]
                            return ScalePoint(x: Double(pixel % stride) / Double(width), y: Double(pixel / stride) / Double(height))
                        }
                        loops.append(simple)
                    }
                }
                if let outer = loops.max(by: { abs(ScalePhotoReview.area($0)) < abs(ScalePhotoReview.area($1)) }), outer.count <= 1000 { polygons.append(outer) }
            }
        }
        return Array(polygons.sorted { a, b in
            let ay = a.map(\.y).min() ?? 0, by = b.map(\.y).min() ?? 0
            return Int(ay * 20) == Int(by * 20) ? (a.map(\.x).min() ?? 0) < (b.map(\.x).min() ?? 0) : ay < by
        }.prefix(80))
    }
}
