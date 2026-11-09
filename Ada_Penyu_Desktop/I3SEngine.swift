import AppKit
import CoreGraphics
import Foundation

// MARK: - I3S Pattern v4.0 Core Geometry & Fingerprint Types
// Fingerprint format and matcher checked against the official I3SPv4.02 distribution.
// The local blob extractor is an approximation, not OpenCV 2.4.2 SURF parity.

struct I3SPoint2D: Hashable, Codable, Sendable {
    var x: Double
    var y: Double

    static let uninitialized = I3SPoint2D(x: -1_000_000_000, y: -1_000_000_000)

    var isInitialized: Bool {
        x > -999_999_999 && y > -999_999_999
    }

    var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }

    func sqrDist(to other: I3SPoint2D) -> Double {
        let dx = x - other.x
        let dy = y - other.y
        return dx * dx + dy * dy
    }

    func dist(to other: I3SPoint2D) -> Double {
        sqrt(sqrDist(to: other))
    }

    func isEqual(to other: I3SPoint2D, eps: Double = 1e-4) -> Bool {
        abs(x - other.x) <= eps && abs(y - other.y) <= eps
    }
}

enum I3SReferencePointKind: Int, CaseIterable, Identifiable {
    case beakEdge = 0
    case innerEyeArea = 1
    case outerScaleEdge = 2

    var id: Int { rawValue }

    var indexLabel: Int { rawValue + 1 }

    /// Exact anatomical labels from `code$GetDataDir/metadata.xml` in I3S Pattern v4.02.
    var title: String {
        switch self {
        case .beakEdge: "Beak edge"
        case .innerEyeArea: "Inner edge of eye area"
        case .outerScaleEdge: "Edge of outer scale"
        }
    }

    var instructionHint: String {
        switch self {
        case .beakEdge:
            "Step 1 of 4: Click reference point 1 — Beak edge (tip of upper rhamphotheca)"
        case .innerEyeArea:
            "Step 2 of 4: Click reference point 2 — Inner edge of eye area (anterior/nasal corner of orbit)"
        case .outerScaleEdge:
            "Step 3 of 4: Click reference point 3 — Edge of outer postorbital/tympanic scale"
        }
    }
}

struct I3SKeypoint: Identifiable, Hashable, Codable, Sendable {
    var id = UUID()
    var center: I3SPoint2D
    /// Diameter of the detected scale/pattern blob in image pixels (`Keypoint.size` in Java).
    var size: Double

    enum CodingKeys: String, CodingKey {
        case center, size
    }

    init(center: I3SPoint2D, size: Double) {
        self.center = center
        self.size = max(4.0, size)
    }

    var radius: Double { size * 0.5 }

    /// Four cardinal control points (`p[0]..p[3]` in `Keypoint.java`) sent to `compareTwo`.
    var controlPoints: [I3SPoint2D] {
        let r = size * 0.5
        return [
            I3SPoint2D(x: center.x - r, y: center.y),
            I3SPoint2D(x: center.x + r, y: center.y),
            I3SPoint2D(x: center.x, y: center.y - r),
            I3SPoint2D(x: center.x, y: center.y + r),
        ]
    }
}

enum I3SRoiError: LocalizedError {
    case alreadyClosed
    case selfIntersecting

    var errorDescription: String? {
        switch self {
        case .alreadyClosed:
            "It is not possible to add points to a region of interest which is closed."
        case .selfIntersecting:
            "A region of interest cannot be self-intersecting."
        }
    }
}

/// Closed non-self-intersecting polygon Region of Interest (`Roi.java` + `pointInPolygon` in `I3SSurf.cpp`).
struct I3SRoi: Hashable, Codable, Sendable {
    var vertices: [I3SPoint2D] = []

    var isFinal: Bool {
        guard vertices.count > 3, let first = vertices.first, let last = vertices.last else {
            return false
        }
        return first.isEqual(to: last)
    }

    mutating func clear() {
        vertices.removeAll()
    }

    mutating func removeLast() {
        guard !vertices.isEmpty else { return }
        vertices.removeLast()
    }

    /// Adds a vertex to the ROI polygon following `Roi.add(Point2D)` in `Roi.java`.
    /// Returns `true` if the polygon just became closed (`isFinal == true`).
    mutating func add(_ point: I3SPoint2D, closeThresholdSquared: Double = 256.0) throws -> Bool {
        if vertices.isEmpty {
            vertices.append(point)
            return false
        }
        if let last = vertices.last, point.isEqual(to: last) {
            return isFinal
        }
        if isFinal {
            throw I3SRoiError.alreadyClosed
        }
        vertices.append(point)
        if vertices.count >= 4, let first = vertices.first, first.sqrDist(to: point) < closeThresholdSquared {
            vertices[vertices.count - 1] = first
            return true
        }
        if isSelfIntersecting() {
            vertices.removeLast()
            throw I3SRoiError.selfIntersecting
        }
        return isFinal
    }

    /// Force-closes the polygon if it has at least 3 distinct vertices.
    mutating func closePolygonIfPossible() -> Bool {
        guard !isFinal, vertices.count >= 3, let first = vertices.first else {
            return isFinal
        }
        vertices.append(first)
        if isSelfIntersecting() {
            vertices.removeLast()
            return false
        }
        return true
    }

    /// Largest Euclidean distance between any two vertices on the ROI (`Roi.largestDistance()`).
    func largestDistance() -> Double {
        guard vertices.count >= 2 else { return 0 }
        let limit = isFinal ? vertices.count - 1 : vertices.count
        var maxSqr: Double = 0
        for i in 0..<max(0, limit - 1) {
            for j in (i + 1)..<limit {
                let d = vertices[i].sqrDist(to: vertices[j])
                if d > maxSqr { maxSqr = d }
            }
        }
        return sqrt(maxSqr)
    }

    /// Bounding box around the ROI expanded by `edge` pixels (`Roi.boundingbox`).
    func boundingBox(minX: Int, minY: Int, maxX: Int, maxY: Int, edge: Int = 100) -> (x: Int, y: Int, width: Int, height: Int) {
        guard !vertices.isEmpty else {
            return (minX, minY, max(1, maxX - minX + 1), max(1, maxY - minY + 1))
        }
        var localMinX = Double.greatestFiniteMagnitude
        var localMinY = Double.greatestFiniteMagnitude
        var localMaxX = -Double.greatestFiniteMagnitude
        var localMaxY = -Double.greatestFiniteMagnitude

        for v in vertices {
            if v.x < localMinX { localMinX = v.x }
            if v.y < localMinY { localMinY = v.y }
            if v.x > localMaxX { localMaxX = v.x }
            if v.y > localMaxY { localMaxY = v.y }
        }
        localMinX = max(Double(minX), localMinX - Double(edge))
        localMinY = max(Double(minY), localMinY - Double(edge))
        localMaxX = min(Double(maxX), localMaxX + Double(edge))
        localMaxY = min(Double(maxY), localMaxY + Double(edge))

        let x = Int(localMinX)
        let y = Int(localMinY)
        let w = max(1, Int(localMaxX - localMinX + 1))
        let h = max(1, Int(localMaxY - localMinY + 1))
        return (x, y, w, h)
    }

    /// Jordan curve theorem ray-casting test (`pointInPolygon` in `I3SSurf.cpp`).
    func contains(_ p: I3SPoint2D) -> Bool {
        guard vertices.count >= 3 else { return false }
        var inside = false
        var j = vertices.count - 1
        for i in 0..<vertices.count {
            let vi = vertices[i]
            let vj = vertices[j]
            if ((vi.y > p.y) != (vj.y > p.y)) &&
                (p.x < (vj.x - vi.x) * (p.y - vi.y) / ((vj.y - vi.y) == 0 ? 1e-9 : (vj.y - vi.y)) + vi.x) {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    private func isSelfIntersecting() -> Bool {
        guard vertices.count >= 4 else { return false }
        let lastStart = vertices[vertices.count - 2]
        let lastEnd = vertices[vertices.count - 1]
        let segmentCount = vertices.count - 1
        for i in 0..<(segmentCount - 2) {
            let a = vertices[i]
            let b = vertices[i + 1]
            // Allow closing onto vertices[0]
            if i == 0 && lastEnd.isEqual(to: a) {
                continue
            }
            if Self.segmentsIntersect(a, b, lastStart, lastEnd) {
                return true
            }
        }
        return false
    }

    private static func segmentsIntersect(_ p1: I3SPoint2D, _ p2: I3SPoint2D, _ p3: I3SPoint2D, _ p4: I3SPoint2D) -> Bool {
        let denom = (p4.y - p3.y) * (p2.x - p1.x) - (p4.x - p3.x) * (p2.y - p1.y)
        if abs(denom) < 1e-9 { return false }
        let ua = ((p4.x - p3.x) * (p1.y - p3.y) - (p4.y - p3.y) * (p1.x - p3.x)) / denom
        let ub = ((p2.x - p1.x) * (p1.y - p3.y) - (p2.y - p1.y) * (p1.x - p3.x)) / denom
        return ua > 1e-5 && ua < (1.0 - 1e-5) && ub > 1e-5 && ub < (1.0 - 1e-5)
    }
}

/// Expert settings defined in `metadata.xml` of I3S Pattern v4.02.
struct I3SExpertParameters: Hashable, Codable, Sendable {
    var nrElements: Int = 35
    var warpSize: Double = 500.0
    var relKeypointDist: Double = 0.05
    var grayRed: Double = 0.1
    var grayGreen: Double = 0.6
    var grayBlue: Double = 0.3
    var maxAllowedDistance: Double = 0.01
    var minRelativeDistance: Double = 1.0
    var minRatioArea: Double = 0.5

    static let `default` = I3SExpertParameters()
}

/// Complete I3S Pattern v4.0 fingerprint (`FingerPrint.java`).
struct I3SFingerprint: Hashable, Codable, Sendable {
    var ref1: I3SPoint2D = .uninitialized
    var ref2: I3SPoint2D = .uninitialized
    var ref3: I3SPoint2D = .uninitialized
    var roi: I3SRoi = I3SRoi()
    var keypoints: [I3SKeypoint] = []
    var comment: String = ""
    var filename: String?

    var allReferencesInitialized: Bool {
        ref1.isInitialized && ref2.isInitialized && ref3.isInitialized
    }

    var readyForProcessing: Bool {
        allReferencesInitialized && roi.isFinal && !keypoints.isEmpty
    }

    /// Guided status message matching `FingerPrint.paint` / `I3S.displayHints` in `FingerPrint.java`.
    var guidedStatusBanner: String {
        if !ref1.isInitialized {
            return I3SReferencePointKind.beakEdge.instructionHint
        } else if !ref2.isInitialized {
            return I3SReferencePointKind.innerEyeArea.instructionHint
        } else if !ref3.isInitialized {
            return I3SReferencePointKind.outerScaleEdge.instructionHint
        } else if !roi.isFinal {
            if roi.vertices.isEmpty {
                return "Step 4 of 4: Outline the Region of Interest (ROI) polygon around the facial scales"
            } else if roi.vertices.count < 3 {
                return "Step 4 of 4: Keep clicking around the facial scale pattern (\(roi.vertices.count) vertices placed)"
            } else {
                return "Step 4 of 4: Click near the first green ROI vertex (or click 'Close ROI') to finalize and extract keypoints"
            }
        } else {
            return "Number of elements: \(keypoints.count) — Right-click any keypoint to remove reflection artifacts, or click 'Search in Database'"
        }
    }

    /// Computes bounding box with percentage margin (`FingerPrint.calcBoundingBox` used by `BothSharks.autoZoomIcon`).
    func boundingBox(marginPercent: Double = 20.0) -> CGRect? {
        var pts: [I3SPoint2D] = []
        if ref1.isInitialized { pts.append(ref1) }
        if ref2.isInitialized { pts.append(ref2) }
        if ref3.isInitialized { pts.append(ref3) }
        pts.append(contentsOf: roi.vertices)
        pts.append(contentsOf: keypoints.map(\.center))
        guard !pts.isEmpty else { return nil }

        var minX = Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude
        for p in pts {
            if p.x < minX { minX = p.x }
            if p.y < minY { minY = p.y }
            if p.x > maxX { maxX = p.x }
            if p.y > maxY { maxY = p.y }
        }
        let w = max(16.0, maxX - minX)
        let h = max(16.0, maxY - minY)
        let padX = w * (marginPercent / 100.0)
        let padY = h * (marginPercent / 100.0)
        return CGRect(x: minX - padX, y: minY - padY, width: w + 2 * padX, height: h + 2 * padY)
    }

    mutating func removeNearestKeypoint(to point: I3SPoint2D) {
        guard !keypoints.isEmpty else { return }
        var bestIdx = -1
        var bestDist = Double.greatestFiniteMagnitude
        for (idx, kp) in keypoints.enumerated() {
            let d = kp.center.sqrDist(to: point)
            if d < bestDist {
                bestDist = d
                bestIdx = idx
            }
        }
        if bestIdx >= 0 {
            keypoints.remove(at: bestIdx)
        }
    }
}

// MARK: - Binary .fgp (IP40) File Reader & Writer
// Exact big-endian DataInputStream / DataOutputStream format from `FingerPrint.java`, `Keypoint.java`, `Roi.java`.

enum I3SFingerprintFileError: LocalizedError {
    case invalidMagic
    case truncatedData

    var errorDescription: String? {
        switch self {
        case .invalidMagic:
            "Unsupported fingerprint header (expected I3S Pattern v4.0 'IP40')."
        case .truncatedData:
            "The .fgp fingerprint file is truncated or corrupted."
        }
    }
}

enum I3SFingerprintFile {
    static func read(from data: Data, filename: String? = nil) throws -> I3SFingerprint {
        guard data.count >= 60 else { throw I3SFingerprintFileError.truncatedData }
        let magic = String(data: data.subdata(in: 0..<4), encoding: .ascii) ?? ""
        guard magic == "IP40" || magic == "IC40" else {
            throw I3SFingerprintFileError.invalidMagic
        }
        var offset = 4

        func readDouble() throws -> Double {
            guard offset + 8 <= data.count else { throw I3SFingerprintFileError.truncatedData }
            var raw: UInt64 = 0
            _ = withUnsafeMutableBytes(of: &raw) { ptr in
                data.copyBytes(to: ptr, from: offset..<(offset + 8))
            }
            offset += 8
            return Double(bitPattern: UInt64(bigEndian: raw))
        }

        func readInt32() throws -> Int {
            guard offset + 4 <= data.count else { throw I3SFingerprintFileError.truncatedData }
            var raw: Int32 = 0
            _ = withUnsafeMutableBytes(of: &raw) { ptr in
                data.copyBytes(to: ptr, from: offset..<(offset + 4))
            }
            offset += 4
            return Int(Int32(bigEndian: raw))
        }

        let r1 = I3SPoint2D(x: try readDouble(), y: try readDouble())
        let r2 = I3SPoint2D(x: try readDouble(), y: try readDouble())
        let r3 = I3SPoint2D(x: try readDouble(), y: try readDouble())

        let kpCount = try readInt32()
        guard kpCount >= 0 && kpCount <= 2000 else { throw I3SFingerprintFileError.truncatedData }
        var keypoints: [I3SKeypoint] = []
        keypoints.reserveCapacity(kpCount)
        for _ in 0..<kpCount {
            let x = try readDouble()
            let y = try readDouble()
            let sz = try readDouble()
            keypoints.append(I3SKeypoint(center: I3SPoint2D(x: x, y: y), size: sz))
        }

        var roi = I3SRoi()
        if magic == "IP40" {
            let roiCount = try readInt32()
            guard roiCount >= 0 && roiCount <= 2000 else { throw I3SFingerprintFileError.truncatedData }
            for _ in 0..<roiCount {
                let rx = try readDouble()
                let ry = try readDouble()
                roi.vertices.append(I3SPoint2D(x: rx, y: ry))
            }
        }

        var comment = ""
        if offset + 4 <= data.count {
            let strLen = try readInt32()
            if strLen > 0, offset + strLen <= data.count {
                comment = String(data: data.subdata(in: offset..<(offset + strLen)), encoding: .utf8) ?? ""
            }
        }

        return I3SFingerprint(
            ref1: r1,
            ref2: r2,
            ref3: r3,
            roi: roi,
            keypoints: keypoints,
            comment: comment,
            filename: filename
        )
    }

    static func write(_ fp: I3SFingerprint) -> Data {
        var out = Data()
        out.append(contentsOf: Array("IP40".utf8))

        func appendDouble(_ value: Double) {
            var be = value.bitPattern.bigEndian
            withUnsafeBytes(of: &be) { out.append(contentsOf: $0) }
        }

        func appendInt32(_ value: Int) {
            var be = Int32(value).bigEndian
            withUnsafeBytes(of: &be) { out.append(contentsOf: $0) }
        }

        appendDouble(fp.ref1.x)
        appendDouble(fp.ref1.y)
        appendDouble(fp.ref2.x)
        appendDouble(fp.ref2.y)
        appendDouble(fp.ref3.x)
        appendDouble(fp.ref3.y)

        appendInt32(fp.keypoints.count)
        for kp in fp.keypoints {
            appendDouble(kp.center.x)
            appendDouble(kp.center.y)
            appendDouble(kp.size)
        }

        appendInt32(fp.roi.vertices.count)
        for v in fp.roi.vertices {
            appendDouble(v.x)
            appendDouble(v.y)
        }

        let commentBytes = Array(fp.comment.utf8)
        appendInt32(commentBytes.count)
        out.append(contentsOf: commentBytes)
        // 0 metadata fields
        appendInt32(0)
        return out
    }
}

// MARK: - I3SSurf Keypoint Extractor (`I3SSurf.cpp` + `SharkPanel.extractKeypoints`)

enum I3SSurfExtractor {
    /// Approximate multi-scale box-Hessian blobs with I3S-style ROI filtering and spacing.
    /// This does not implement OpenCV SURF's octave pyramid, scale interpolation,
    /// threshold schedule, or image warping. Use original .fgp files for reference parity.
    static func extractKeypoints(
        from image: NSImage,
        roi: I3SRoi,
        params: I3SExpertParameters = .default
    ) -> [I3SKeypoint] {
        guard roi.isFinal,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return []
        }
        let imgW = cgImage.width
        let imgH = cgImage.height
        guard imgW > 8, imgH > 8 else { return [] }

        let bbox = roi.boundingBox(minX: 0, minY: 0, maxX: imgW - 1, maxY: imgH - 1, edge: 60)
        let cropX = bbox.x
        let cropY = bbox.y
        let width = bbox.width
        let height = bbox.height
        guard width > 12, height > 12 else { return [] }

        // Render cropped region into RGBA8 buffer
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &rgba,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return []
        }
        guard let subImage = cgImage.cropping(to: CGRect(x: cropX, y: cropY, width: width, height: height)) else {
            return []
        }
        ctx.draw(subImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Weighted grayscale conversion matching ImageProc.colorToGray (default weights 0.1, 0.6, 0.3)
        let wr = params.grayRed
        let wg = params.grayGreen
        let wb = params.grayBlue
        var gray = [Double](repeating: 0, count: width * height)
        for i in 0..<(width * height) {
            let r = Double(rgba[i * 4])
            let g = Double(rgba[i * 4 + 1])
            let b = Double(rgba[i * 4 + 2])
            gray[i] = (wr * r + wg * g + wb * b) / 255.0
        }

        // Compute maxDistance across ROI vertices (`maxDistance` in `I3SSurf.cpp`)
        let maxDist = max(32.0, roi.largestDistance())
        let warpScale = params.warpSize / maxDist

        // Build integral image I(x, y) of size (width + 1) x (height + 1)
        let rowStride = width + 1
        var integral = [Double](repeating: 0, count: rowStride * (height + 1))
        for y in 0..<height {
            var rowSum = 0.0
            for x in 0..<width {
                rowSum += gray[y * width + x]
                integral[(y + 1) * rowStride + (x + 1)] = integral[y * rowStride + (x + 1)] + rowSum
            }
        }

        func boxSum(_ x1: Int, _ y1: Int, _ x2: Int, _ y2: Int) -> Double {
            let ax = max(0, min(width, x1))
            let ay = max(0, min(height, y1))
            let bx = max(0, min(width, x2))
            let by = max(0, min(height, y2))
            if bx <= ax || by <= ay { return 0 }
            return integral[by * rowStride + bx]
                - integral[ay * rowStride + bx]
                - integral[by * rowStride + ax]
                + integral[ay * rowStride + ax]
        }

        // Multi-scale upright Box-Hessian determinant (SURF filters at sizes 9, 15, 21, 27, 39, 51 in warped space)
        let warpedFilterSizes: [Double] = [9, 15, 21, 27, 39, 51]
        struct CandidateBlob {
            let x: Double
            let y: Double
            let diameter: Double
            let response: Double
        }

        var rawCandidates: [CandidateBlob] = []
        let step = max(2, Int((2.0 / warpScale).rounded()))

        for filterW in warpedFilterSizes {
            let unwarpedFilter = max(6.0, filterW / warpScale)
            let lobe = max(2, Int((unwarpedFilter / 3.0).rounded()))
            let half = (3 * lobe) / 2
            let areaNorm = 1.0 / Double((2 * lobe + 1) * (2 * lobe + 1))

            guard width > 2 * half + 2, height > 2 * half + 2 else { continue }
            var respGrid = [Double](repeating: 0, count: width * height)

            for y in half..<(height - half) where (y - half) % step == 0 {
                for x in half..<(width - half) where (x - half) % step == 0 {
                    let globalPt = I3SPoint2D(x: Double(x + cropX), y: Double(y + cropY))
                    guard roi.contains(globalPt) else { continue }

                    // Dxx
                    let lxx = boxSum(x - half, y - lobe + 1, x + half + 1, y + lobe)
                        - 3.0 * boxSum(x - lobe / 2, y - lobe + 1, x + lobe / 2 + 1, y + lobe)
                    // Dyy
                    let lyy = boxSum(x - lobe + 1, y - half, x + lobe, y + half + 1)
                        - 3.0 * boxSum(x - lobe + 1, y - lobe / 2, x + lobe, y + lobe / 2 + 1)
                    // Dxy
                    let tr = boxSum(x + 1, y - lobe, x + lobe + 1, y)
                    let bl = boxSum(x - lobe, y + 1, x, y + lobe + 1)
                    let tl = boxSum(x - lobe, y - lobe, x, y)
                    let br = boxSum(x + 1, y + 1, x + lobe + 1, y + lobe + 1)
                    let lxy = (tr + bl - tl - br)

                    let dxx = lxx * areaNorm
                    let dyy = lyy * areaNorm
                    let dxy = lxy * areaNorm
                    let det = (dxx * dyy - 0.81 * dxy * dxy)
                    if det > 1e-5 {
                        respGrid[y * width + x] = det
                    }
                }
            }

            // Spatial non-maximum suppression within scale
            for y in (half + step)..<(height - half - step) where (y - half) % step == 0 {
                for x in (half + step)..<(width - half - step) where (x - half) % step == 0 {
                    let val = respGrid[y * width + x]
                    guard val > 1e-5 else { continue }
                    var isMax = true
                    outer: for dy in stride(from: -step, through: step, by: step) {
                        for dx in stride(from: -step, through: step, by: step) {
                            if dx == 0 && dy == 0 { continue }
                            if respGrid[(y + dy) * width + (x + dx)] >= val {
                                isMax = false
                                break outer
                            }
                        }
                    }
                    if isMax {
                        // Scale-space blob diameter matching `1.2 * (ipt.scale / scale)` in `I3SSurf.cpp`
                        let diameter = max(8.0, 1.2 * (filterW * 1.2 / 9.0) * 10.0 / warpScale)
                        rawCandidates.append(
                            CandidateBlob(
                                x: Double(x + cropX),
                                y: Double(y + cropY),
                                diameter: diameter,
                                response: val
                            )
                        )
                    }
                }
            }
        }

        // Sort descending by Hessian response (`sortResponse` in `I3SSurf.cpp`)
        rawCandidates.sort { $0.response > $1.response }

        // Enforce minimum relative distance (`minDist = maxDist * relKeypointDist` in `I3SSurf.cpp`)
        let minDist = maxDist * params.relKeypointDist
        let minDistSq = minDist * minDist
        var selected: [I3SKeypoint] = []
        selected.reserveCapacity(params.nrElements)

        for cand in rawCandidates {
            if selected.count >= params.nrElements { break }
            let pt = I3SPoint2D(x: cand.x, y: cand.y)
            let tooClose = selected.contains { existing in
                existing.center.sqrDist(to: pt) < minDistSq
            }
            if !tooClose {
                selected.append(I3SKeypoint(center: pt, size: cand.diameter))
            }
        }

        return selected
    }

    /// Places a fixed proportional template, not detected anatomical landmarks.
    /// The user must adjust its references and ROI to the actual photo.
    static func autoAnnotateHead(
        image: NSImage,
        side: TurtlePhotoSide,
        params: I3SExpertParameters = .default
    ) -> I3SFingerprint {
        let w = max(100.0, Double(image.size.width))
        let h = max(100.0, Double(image.size.height))

        let ref1: I3SPoint2D
        let ref2: I3SPoint2D
        let ref3: I3SPoint2D
        let polyPoints: [I3SPoint2D]

        if side == .left {
            ref1 = I3SPoint2D(x: w * 0.20, y: h * 0.56)
            ref2 = I3SPoint2D(x: w * 0.36, y: h * 0.36)
            ref3 = I3SPoint2D(x: w * 0.78, y: h * 0.45)
            polyPoints = [
                I3SPoint2D(x: w * 0.36, y: h * 0.38),
                I3SPoint2D(x: w * 0.52, y: h * 0.31),
                I3SPoint2D(x: w * 0.72, y: h * 0.34),
                I3SPoint2D(x: w * 0.80, y: h * 0.46),
                I3SPoint2D(x: w * 0.76, y: h * 0.64),
                I3SPoint2D(x: w * 0.58, y: h * 0.69),
                I3SPoint2D(x: w * 0.40, y: h * 0.63),
                I3SPoint2D(x: w * 0.33, y: h * 0.50),
            ]
        } else {
            ref1 = I3SPoint2D(x: w * 0.80, y: h * 0.56)
            ref2 = I3SPoint2D(x: w * 0.64, y: h * 0.36)
            ref3 = I3SPoint2D(x: w * 0.22, y: h * 0.45)
            polyPoints = [
                I3SPoint2D(x: w * 0.64, y: h * 0.38),
                I3SPoint2D(x: w * 0.48, y: h * 0.31),
                I3SPoint2D(x: w * 0.28, y: h * 0.34),
                I3SPoint2D(x: w * 0.20, y: h * 0.46),
                I3SPoint2D(x: w * 0.24, y: h * 0.64),
                I3SPoint2D(x: w * 0.42, y: h * 0.69),
                I3SPoint2D(x: w * 0.60, y: h * 0.63),
                I3SPoint2D(x: w * 0.67, y: h * 0.50),
            ]
        }

        var roi = I3SRoi(vertices: polyPoints)
        _ = roi.closePolygonIfPossible()
        let kps = extractKeypoints(from: image, roi: roi, params: params)
        return I3SFingerprint(
            ref1: ref1,
            ref2: ref2,
            ref3: ref3,
            roi: roi,
            keypoints: kps
        )
    }
}

// MARK: - I3S Pattern v4.0 Affine & Point-Cloud Matcher
// Direct port of `compare.cpp`, `fingerprint.cpp`, `element.cpp`, `affine.cpp`, and `PointCloud.java`.

struct I3SNormalizedElement: Identifiable, Hashable, Sendable {
    let id: Int
    var cx: Double
    var cy: Double
    var r1: Double
    var r2: Double
    var angleDeg: Double
    var area: Double
}

struct I3SMatchedPair: Identifiable, Hashable, Sendable {
    var id: String { "\(unknownIndex)-\(candidateIndex)" }
    let unknownIndex: Int
    let candidateIndex: Int
    let unknownPoint: I3SPoint2D
    let candidatePoint: I3SPoint2D
    let distance: Double
}

struct I3SComparisonResult: Hashable, Sendable {
    static let noMatchScore: Double = 1_000_000_000.0

    let score: Double
    let pairCount: Int
    let affineMatrix: [Double]
    let normFactor: Double
    let unknownElements: [I3SNormalizedElement]
    let candidateElements: [I3SNormalizedElement]
    let unknownRefs: [I3SPoint2D]
    let candidateRefs: [I3SPoint2D]
    let matchedPairs: [I3SMatchedPair]
}

// Matching logic adapted from I3S Pattern 4.02, Copyright (C) 2004-2013
// Jurgen den Hartog & Renate Reijns. GPL-2.0-or-later; see docs/licenses/I3S-GPL-2.0.txt.
// Reference scores are generated by compiling the distribution's original C++.
enum I3SCompareEngine {
    private struct Element {
        let points: [I3SPoint2D]
        let center: I3SPoint2D
        let area: Double

        init(points: [I3SPoint2D]) {
            self.points = points
            center = I3SPoint2D(x: (points[0].x + points[1].x) / 2,
                                y: (points[0].y + points[1].y) / 2)
            area = points[0].dist(to: points[1]) * points[2].dist(to: points[3]) * .pi / 4
        }

        func transformed(by matrix: [Double]) -> Element {
            Element(points: points.map { transform($0, by: matrix) })
        }

        func displayElement(id: Int) -> I3SNormalizedElement {
            I3SNormalizedElement(id: id, cx: center.x, cy: center.y,
                                 r1: points[0].dist(to: points[1]) / 2,
                                 r2: points[2].dist(to: points[3]) / 2,
                                 angleDeg: atan2(points[1].y - points[0].y, points[1].x - points[0].x) * 180 / .pi,
                                 area: area)
        }
    }

    private struct Pair {
        let candidate: Int
        let unknown: Int
        let distance: Double
    }

    private struct Configuration {
        let score: Double
        let pairs: [Pair]
    }

    /// Reference alignment, then exhaustive refinement over the initial nearest-neighbor pairs.
    /// Coordinates remain in the query photo's pixel space; only the final score is normalized.
    static func compareTwo(
        unknown: I3SFingerprint,
        candidate: I3SFingerprint,
        params: I3SExpertParameters = .default
    ) -> I3SComparisonResult {
        let uRefs = [unknown.ref1, unknown.ref2, unknown.ref3]
        let kRefs = [candidate.ref1, candidate.ref2, candidate.ref3]
        guard unknown.allReferencesInitialized, candidate.allReferencesInitialized,
              !unknown.keypoints.isEmpty, !candidate.keypoints.isEmpty,
              (uRefs + kRefs).allSatisfy({ $0.x.isFinite && $0.y.isFinite }),
              (unknown.keypoints + candidate.keypoints).allSatisfy({
                  $0.center.x.isFinite && $0.center.y.isFinite && $0.size.isFinite && $0.size > 0
              }),
              let baseMatrix = calcAffine(from: (kRefs[0], kRefs[1], kRefs[2]),
                                          to: (uRefs[0], uRefs[1], uRefs[2])),
              abs(baseMatrix[0] * baseMatrix[4] - baseMatrix[1] * baseMatrix[3]) > 1e-12 else {
            return emptyResult()
        }

        let perimeter = uRefs[0].dist(to: uRefs[1]) + uRefs[0].dist(to: uRefs[2]) + uRefs[1].dist(to: uRefs[2])
        guard perimeter > 0 else { return emptyResult() }
        let normFactor = 10_000 / perimeter
        // addReference() prepends singular elements, which participate in matching/refinement.
        let uElements = elements(for: unknown)
        let aligned = elements(for: candidate).map { $0.transformed(by: baseMatrix) }
        let initial = score(unknown: uElements, candidate: aligned, normFactor: normFactor, params: params)
        var best = initial
        var bestElements = aligned
        var bestMatrix = baseMatrix

        // The original uses the initial accepted pairs, including references, without an arbitrary prefix cap.
        let pairs = initial.pairs
        if pairs.count >= 3 && initial.score > 0 {
            for i in 0..<(pairs.count - 2) {
                for j in (i + 1)..<(pairs.count - 1) {
                    for k in (j + 1)..<pairs.count {
                        guard let refinement = calcAffine(
                            from: (aligned[pairs[i].candidate].center, aligned[pairs[j].candidate].center, aligned[pairs[k].candidate].center),
                            to: (uElements[pairs[i].unknown].center, uElements[pairs[j].unknown].center, uElements[pairs[k].unknown].center)
                        ) else { continue }
                        let testElements = aligned.map { $0.transformed(by: refinement) }
                        let test = score(unknown: uElements, candidate: testElements, normFactor: normFactor, params: params)
                        if test.score < best.score {
                            best = test
                            bestElements = testElements
                            bestMatrix = compose(refinement, baseMatrix)
                        }
                    }
                }
            }
        }

        let matchedPairs = best.pairs.compactMap { pair -> I3SMatchedPair? in
            guard pair.unknown >= 3, pair.candidate >= 3 else { return nil }
            return I3SMatchedPair(unknownIndex: pair.unknown - 3, candidateIndex: pair.candidate - 3,
                                  unknownPoint: uElements[pair.unknown].center,
                                  candidatePoint: bestElements[pair.candidate].center, distance: pair.distance)
        }
        return I3SComparisonResult(
            score: best.score, pairCount: matchedPairs.count, affineMatrix: bestMatrix, normFactor: normFactor,
            unknownElements: uElements.dropFirst(3).enumerated().map { $0.element.displayElement(id: $0.offset) },
            candidateElements: bestElements.dropFirst(3).enumerated().map { $0.element.displayElement(id: $0.offset) },
            unknownRefs: uRefs, candidateRefs: Array(bestElements.prefix(3).map(\.center)), matchedPairs: matchedPairs
        )
    }

    private static func elements(for fingerprint: I3SFingerprint) -> [Element] {
        [fingerprint.ref1, fingerprint.ref2, fingerprint.ref3].map { Element(points: Array(repeating: $0, count: 4)) }
            + fingerprint.keypoints.map { Element(points: $0.controlPoints) }
    }

    private static func score(unknown: [Element], candidate: [Element], normFactor: Double,
                              params: I3SExpertParameters) -> Configuration {
        // determineMaxDist() uses the candidate's currently transformed reference elements.
        let maxSquaredDistance = max(candidate[0].center.sqrDist(to: candidate[1].center),
                                     candidate[0].center.sqrDist(to: candidate[2].center),
                                     candidate[1].center.sqrDist(to: candidate[2].center)) * params.maxAllowedDistance
        var pairs: [Pair] = []
        var totalDistance = 0.0
        for (i, from) in candidate.enumerated() {
            var nearest = 1_000_000_000.0
            var second = 1_000_000_000.0
            var nearestIndex: Int?
            for (j, to) in unknown.enumerated() {
                // Singular reference points match other references, never scale blobs.
                guard (from.area == 0) == (to.area == 0) else { continue }
                if from.area > 0 && min(from.area, to.area) / max(from.area, to.area) < params.minRatioArea { continue }
                let distance = from.center.sqrDist(to: to.center)
                if distance < nearest {
                    second = nearest
                    nearest = distance
                    nearestIndex = j
                } else if distance < second {
                    second = distance
                }
            }
            guard let j = nearestIndex,
                  nearest * params.minRelativeDistance <= second, nearest < maxSquaredDistance else { continue }
            let distance = sqrt(nearest)
            let similarity = from.area > 0 ? 0.5 * sqrt(max(from.area, unknown[j].area) / min(from.area, unknown[j].area)) + 0.5 : 1
            totalDistance += distance * similarity
            pairs.append(Pair(candidate: i, unknown: j, distance: distance))
        }
        pairs.sort { $0.unknown < $1.unknown }
        var index = 1
        while index < pairs.count {
            if pairs[index - 1].unknown == pairs[index].unknown {
                let removed = pairs[index - 1].distance < pairs[index].distance ? index : index - 1
                // Preserve the reference implementation's raw-distance duplicate correction.
                totalDistance -= pairs[removed].distance
                pairs.remove(at: removed)
            } else {
                index += 1
            }
        }
        let featureCount = pairs.count - 3 // affine_corr = -3 in the original
        var value = featureCount > 0 ? normFactor * totalDistance / Double(featureCount * featureCount) : 1_000_000
        if featureCount == 1 { value *= 4 }
        if featureCount == 2 { value *= 3 }
        if featureCount == 3 { value *= 2 }
        let pairedRatio = 2 * Double(pairs.count) / Double(unknown.count + candidate.count)
        value = pairedRatio > 0 ? value / (pairedRatio * pairedRatio) : I3SComparisonResult.noMatchScore
        return Configuration(score: value.isFinite ? value : I3SComparisonResult.noMatchScore, pairs: pairs)
    }

    private static func transform(_ point: I3SPoint2D, by matrix: [Double]) -> I3SPoint2D {
        I3SPoint2D(x: matrix[0] * point.x + matrix[1] * point.y + matrix[2],
                   y: matrix[3] * point.x + matrix[4] * point.y + matrix[5])
    }

    private static func compose(_ a: [Double], _ b: [Double]) -> [Double] {
        [a[0] * b[0] + a[1] * b[3], a[0] * b[1] + a[1] * b[4], a[0] * b[2] + a[1] * b[5] + a[2],
         a[3] * b[0] + a[4] * b[3], a[3] * b[1] + a[4] * b[4], a[3] * b[2] + a[4] * b[5] + a[5]]
    }

    private static func emptyResult() -> I3SComparisonResult {
        I3SComparisonResult(score: I3SComparisonResult.noMatchScore, pairCount: 0,
                            affineMatrix: [1, 0, 0, 0, 1, 0], normFactor: 1,
                            unknownElements: [], candidateElements: [], unknownRefs: [], candidateRefs: [], matchedPairs: [])
    }

    /// Solves the 2x3 affine transformation mapping `from` (3 points) to `to` (3 points).
    static func calcAffine(
        from: (I3SPoint2D, I3SPoint2D, I3SPoint2D),
        to: (I3SPoint2D, I3SPoint2D, I3SPoint2D)
    ) -> [Double]? {
        let x1 = from.0.x, y1 = from.0.y
        let x2 = from.1.x, y2 = from.1.y
        let x3 = from.2.x, y3 = from.2.y

        let det = x1 * (y2 - y3) - y1 * (x2 - x3) + (x2 * y3 - x3 * y2)
        guard abs(det) > 1e-7 else { return nil }
        let invDet = 1.0 / det

        let i00 = (y2 - y3) * invDet
        let i01 = (y3 - y1) * invDet
        let i02 = (y1 - y2) * invDet
        let i10 = (x3 - x2) * invDet
        let i11 = (x1 - x3) * invDet
        let i12 = (x2 - x1) * invDet
        let i20 = (x2 * y3 - x3 * y2) * invDet
        let i21 = (x3 * y1 - x1 * y3) * invDet
        let i22 = (x1 * y2 - x2 * y1) * invDet

        let u1 = to.0.x, v1 = to.0.y
        let u2 = to.1.x, v2 = to.1.y
        let u3 = to.2.x, v3 = to.2.y

        let m0 = i00 * u1 + i01 * u2 + i02 * u3
        let m1 = i10 * u1 + i11 * u2 + i12 * u3
        let m2 = i20 * u1 + i21 * u2 + i22 * u3
        let m3 = i00 * v1 + i01 * v2 + i02 * v3
        let m4 = i10 * v1 + i11 * v2 + i12 * v3
        let m5 = i20 * v1 + i21 * v2 + i22 * v3

        return [m0, m1, m2, m3, m4, m5]
    }
}

// MARK: - Bundled I3S Sea Turtle Sample Library (`SampleTurtles/i3s_samples.json`)

struct I3SSampleEntry: Identifiable, Hashable, Decodable {
    let id: String
    let title: String
    let side: String
    let species: String
    let imageFile: String
    let fgpFile: String
    let imageWidth: Int
    let imageHeight: Int
    let ref1: [Double]
    let ref2: [Double]
    let ref3: [Double]
    let roi: [[Double]]
    let keypoints: [[Double]]

    var photoSide: TurtlePhotoSide {
        TurtlePhotoSide(rawValue: side.lowercased()) ?? .left
    }

    var fingerprint: I3SFingerprint {
        let r1 = ref1.count >= 2 ? I3SPoint2D(x: ref1[0], y: ref1[1]) : .uninitialized
        let r2 = ref2.count >= 2 ? I3SPoint2D(x: ref2[0], y: ref2[1]) : .uninitialized
        let r3 = ref3.count >= 2 ? I3SPoint2D(x: ref3[0], y: ref3[1]) : .uninitialized
        let roiVerts = roi.compactMap { pair -> I3SPoint2D? in
            guard pair.count >= 2 else { return nil }
            return I3SPoint2D(x: pair[0], y: pair[1])
        }
        let kps = keypoints.compactMap { triple -> I3SKeypoint? in
            guard triple.count >= 3 else { return nil }
            return I3SKeypoint(center: I3SPoint2D(x: triple[0], y: triple[1]), size: triple[2])
        }
        return I3SFingerprint(
            ref1: r1,
            ref2: r2,
            ref3: r3,
            roi: I3SRoi(vertices: roiVerts),
            keypoints: kps,
            comment: "I3S Pattern v4.02 Sea Turtle Sample (\(title))",
            filename: fgpFile
        )
    }
}

enum I3SSampleLibrary {
    static let samples: [I3SSampleEntry] = {
        for url in candidateURLs(for: "i3s_samples.json") {
            if let data = try? Data(contentsOf: url),
               let decoded = try? JSONDecoder().decode([I3SSampleEntry].self, from: data) {
                return decoded
            }
        }
        return []
    }()

    static func loadImageData(for sample: I3SSampleEntry) -> Data? {
        for url in candidateURLs(for: sample.imageFile) {
            if let data = try? Data(contentsOf: url) {
                return data
            }
        }
        return nil
    }

    static func loadImage(for sample: I3SSampleEntry) -> NSImage? {
        guard let data = loadImageData(for: sample) else { return nil }
        return NSImage(data: data)
    }

    private static func candidateURLs(for filename: String) -> [URL] {
        var urls: [URL] = []
        let ns = filename as NSString
        let base = ns.deletingPathExtension
        let ext = ns.pathExtension

        if let bundled = Bundle.main.url(forResource: base, withExtension: ext, subdirectory: "SampleTurtles") {
            urls.append(bundled)
        }
        if let bundledRoot = Bundle.main.url(forResource: base, withExtension: ext) {
            urls.append(bundledRoot)
        }
        let devPath = URL(fileURLWithPath: "/Users/gung/Documents/SWIFT/ADA_Penyu_Desktop/Ada_Penyu_Desktop/Ada_Penyu_Desktop/SampleTurtles/\(filename)")
        urls.append(devPath)
        return urls
    }
}
