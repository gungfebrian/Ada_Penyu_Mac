import AppKit
import CoreGraphics
import Foundation

// MARK: - I3S Pattern v4.0 Core Geometry & Fingerprint Types
// Reverse-engineered from I3SPv4.02 (I3SSurf.cpp, compare.cpp, fingerprint.cpp,
// element.cpp, affine.cpp, FingerPrint.java, Roi.java, SharkPanel.java, PointCloud.java).

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
    /// Extracts up to `params.nrElements` multi-scale blob keypoints inside `roi`
    /// using the exact grayscale weights, ROI warp normalization (`warpSize = 500`),
    /// polygon containment test (`pointInPolygon`), and minimum inter-keypoint distance
    /// (`relKeypointDist * maxRoiDistance`) from `I3SSurf.cpp` and `SharkPanel.java`.
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

    /// Generates an automatic anatomical head ROI + 3 reference points for a turtle head image
    /// so the user can test one-click auto-annotation on any photo.
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

enum I3SCompareEngine {
    /// Compares two fingerprints using the reverse-engineered I3S Pattern v4.0 algorithm
    /// (`compareTwo` in `compare.cpp`, `FingerPrint::doAffine` in `fingerprint.cpp`, and `PointCloud.java`).
    static func compareTwo(
        unknown: I3SFingerprint,
        candidate: I3SFingerprint,
        params: I3SExpertParameters = .default
    ) -> I3SComparisonResult {
        guard unknown.allReferencesInitialized,
              candidate.allReferencesInitialized,
              !unknown.keypoints.isEmpty,
              !candidate.keypoints.isEmpty else {
            return emptyResult()
        }

        let uRef = [unknown.ref1, unknown.ref2, unknown.ref3]
        let kRef = [candidate.ref1, candidate.ref2, candidate.ref3]

        guard var bestMatrix = calcAffine(
            from: (kRef[0], kRef[1], kRef[2]),
            to: (uRef[0], uRef[1], uRef[2])
        ) else {
            return emptyResult()
        }

        let det = bestMatrix[0] * bestMatrix[4] - bestMatrix[1] * bestMatrix[3]
        guard abs(det) > 1e-9 else { return emptyResult() }
        let normFactor = 1.0 / sqrt(abs(det))

        // Build normalized elements (`FingerPrint` constructor + `doAffine` in `fingerprint.cpp`)
        let uElems = buildElements(from: unknown.keypoints)
        var kOrigElems = buildElements(from: candidate.keypoints)
        kOrigElems = applyAffine(matrix: bestMatrix, elements: kOrigElems, normFactor: normFactor)
        var kOrigRefs = applyAffinePoints(matrix: bestMatrix, points: kRef)

        // Scale both unknown and candidate into normalized metric space (`u.scale(f.getNormFactor())`)
        var uScaledElems = scaleElements(uElems, factor: normFactor)
        let uScaledRefs = scalePoints(uRef, factor: normFactor)
        kOrigElems = scaleElements(kOrigElems, factor: normFactor)
        kOrigRefs = scalePoints(kOrigRefs, factor: normFactor)

        // Append the 3 reference points as pseudo-elements (`addRefToElt` in `compare.cpp`)
        for i in 0..<3 {
            uScaledElems.append(I3SNormalizedElement(id: uScaledElems.count, cx: uScaledRefs[i].x, cy: uScaledRefs[i].y, r1: 0, r2: 0, angleDeg: 0, area: -1))
            kOrigElems.append(I3SNormalizedElement(id: kOrigElems.count, cx: kOrigRefs[i].x, cy: kOrigRefs[i].y, r1: 0, r2: 0, angleDeg: 0, area: -1))
        }

        let maxDist = calcMaxDistance(uScaledRefs)
        let maxSqDist = maxDist * maxDist * params.maxAllowedDistance

        // Initial score & pairs using reference-point affine transform
        var bestWorkingElems = kOrigElems
        var (bestScore, bestPairs, bestPairCnt) = scoreConfiguration(
            unknown: uScaledElems,
            candidate: bestWorkingElems,
            unknownCount: unknown.keypoints.count,
            candidateCount: candidate.keypoints.count,
            maxSqDist: maxSqDist,
            minRelDistSq: params.minRelativeDistance * params.minRelativeDistance,
            minRatioArea: params.minRatioArea,
            normFactor: normFactor
        )

        // Exhaustive 3-pair local affine refinement (`exhaustiveSearch` in `compare.cpp`)
        var hypotheses: [(uIdx: Int, kIdx: Int)] = []
        let candidateRadiusSq = maxSqDist * 9.0
        for uIdx in 0..<unknown.keypoints.count {
            let ue = uScaledElems[uIdx]
            var nearest: [(idx: Int, dist: Double)] = []
            for kIdx in 0..<candidate.keypoints.count {
                let ke = kOrigElems[kIdx]
                guard elementMatches(ue, ke, minRatioArea: params.minRatioArea) else { continue }
                let d = sqrDist(ue, ke)
                if d < candidateRadiusSq {
                    nearest.append((kIdx, d))
                }
            }
            nearest.sort { $0.dist < $1.dist }
            for item in nearest.prefix(2) {
                hypotheses.append((uIdx, item.idx))
            }
        }
        // Include reference point correspondences in the hypothesis pool (`compare.cpp` lines 163-167)
        for r in 0..<3 {
            hypotheses.append((unknown.keypoints.count + r, candidate.keypoints.count + r))
        }

        let maxHyp = min(hypotheses.count, 24)
        if maxHyp >= 3 {
            for j1 in 0..<(maxHyp - 2) {
                let p1From = I3SPoint2D(x: kOrigElems[hypotheses[j1].kIdx].cx, y: kOrigElems[hypotheses[j1].kIdx].cy)
                let p1To = I3SPoint2D(x: uScaledElems[hypotheses[j1].uIdx].cx, y: uScaledElems[hypotheses[j1].uIdx].cy)
                for j2 in (j1 + 1)..<(maxHyp - 1) {
                    if hypotheses[j2].uIdx == hypotheses[j1].uIdx || hypotheses[j2].kIdx == hypotheses[j1].kIdx { continue }
                    let p2From = I3SPoint2D(x: kOrigElems[hypotheses[j2].kIdx].cx, y: kOrigElems[hypotheses[j2].kIdx].cy)
                    let p2To = I3SPoint2D(x: uScaledElems[hypotheses[j2].uIdx].cx, y: uScaledElems[hypotheses[j2].uIdx].cy)
                    for j3 in (j2 + 1)..<maxHyp {
                        if hypotheses[j3].uIdx == hypotheses[j1].uIdx || hypotheses[j3].uIdx == hypotheses[j2].uIdx ||
                            hypotheses[j3].kIdx == hypotheses[j1].kIdx || hypotheses[j3].kIdx == hypotheses[j2].kIdx {
                            continue
                        }
                        let p3From = I3SPoint2D(x: kOrigElems[hypotheses[j3].kIdx].cx, y: kOrigElems[hypotheses[j3].kIdx].cy)
                        let p3To = I3SPoint2D(x: uScaledElems[hypotheses[j3].uIdx].cx, y: uScaledElems[hypotheses[j3].uIdx].cy)

                        guard let refineMat = calcAffine(from: (p1From, p2From, p3From), to: (p1To, p2To, p3To)),
                              !isSingularOrLargeShift(refineMat, normFactor: normFactor) else {
                            continue
                        }
                        let refinedDet = refineMat[0] * refineMat[4] - refineMat[1] * refineMat[3]
                        guard abs(refinedDet) > 1e-6 else { continue }
                        let refinedNorm = 1.0 / sqrt(abs(refinedDet))
                        let testElems = applyAffine(matrix: refineMat, elements: kOrigElems, normFactor: refinedNorm)

                        let (score, pairs, pairCnt) = scoreConfiguration(
                            unknown: uScaledElems,
                            candidate: testElems,
                            unknownCount: unknown.keypoints.count,
                            candidateCount: candidate.keypoints.count,
                            maxSqDist: maxSqDist,
                            minRelDistSq: params.minRelativeDistance * params.minRelativeDistance,
                            minRatioArea: params.minRatioArea,
                            normFactor: normFactor
                        )
                        if score < bestScore {
                            bestScore = score
                            bestPairs = pairs
                            bestPairCnt = pairCnt
                            bestWorkingElems = testElems
                            bestMatrix = refineMat
                        }
                    }
                }
            }
        }

        let finalUnknownElems = Array(uScaledElems.prefix(unknown.keypoints.count))
        let finalCandidateElems = Array(bestWorkingElems.prefix(candidate.keypoints.count))
        let finalCandidateRefs = (0..<3).map { r -> I3SPoint2D in
            let e = bestWorkingElems[candidate.keypoints.count + r]
            return I3SPoint2D(x: e.cx, y: e.cy)
        }

        var matchedList: [I3SMatchedPair] = []
        for (uIdx, kIdx) in bestPairs.enumerated() where kIdx >= 0 && uIdx < finalUnknownElems.count && kIdx < finalCandidateElems.count {
            let ue = finalUnknownElems[uIdx]
            let ke = finalCandidateElems[kIdx]
            let d = sqrt(sqrDist(ue, ke))
            matchedList.append(
                I3SMatchedPair(
                    unknownIndex: uIdx,
                    candidateIndex: kIdx,
                    unknownPoint: I3SPoint2D(x: ue.cx, y: ue.cy),
                    candidatePoint: I3SPoint2D(x: ke.cx, y: ke.cy),
                    distance: d
                )
            )
        }

        return I3SComparisonResult(
            score: bestScore,
            pairCount: bestPairCnt,
            affineMatrix: bestMatrix,
            normFactor: normFactor,
            unknownElements: finalUnknownElems,
            candidateElements: finalCandidateElems,
            unknownRefs: uScaledRefs,
            candidateRefs: finalCandidateRefs,
            matchedPairs: matchedList
        )
    }

    // MARK: - Internal C++ Port Helpers (`compare.cpp`, `fingerprint.cpp`, `element.cpp`, `affine.cpp`)

    private static func emptyResult() -> I3SComparisonResult {
        I3SComparisonResult(
            score: I3SComparisonResult.noMatchScore,
            pairCount: 0,
            affineMatrix: [1, 0, 0, 0, 1, 0],
            normFactor: 1.0,
            unknownElements: [],
            candidateElements: [],
            unknownRefs: [],
            candidateRefs: [],
            matchedPairs: []
        )
    }

    private static func buildElements(from keypoints: [I3SKeypoint]) -> [I3SNormalizedElement] {
        keypoints.enumerated().map { idx, kp in
            let r = kp.size * 0.5
            let area = Double.pi * r * r
            return I3SNormalizedElement(
                id: idx,
                cx: kp.center.x,
                cy: kp.center.y,
                r1: r,
                r2: r,
                angleDeg: 0,
                area: area
            )
        }
    }

    private static func applyAffine(matrix m: [Double], elements: [I3SNormalizedElement], normFactor: Double) -> [I3SNormalizedElement] {
        elements.map { e in
            let nx = m[0] * e.cx + m[1] * e.cy + m[2]
            let ny = m[3] * e.cx + m[4] * e.cy + m[5]
            let scale = 1.0 / max(1e-6, normFactor)
            let nr1 = e.r1 * scale
            let nr2 = e.r2 * scale
            let nArea = e.area > 0 ? Double.pi * nr1 * nr2 : -1
            return I3SNormalizedElement(id: e.id, cx: nx, cy: ny, r1: nr1, r2: nr2, angleDeg: e.angleDeg, area: nArea)
        }
    }

    private static func applyAffinePoints(matrix m: [Double], points: [I3SPoint2D]) -> [I3SPoint2D] {
        points.map { p in
            I3SPoint2D(
                x: m[0] * p.x + m[1] * p.y + m[2],
                y: m[3] * p.x + m[4] * p.y + m[5]
            )
        }
    }

    private static func scaleElements(_ elements: [I3SNormalizedElement], factor: Double) -> [I3SNormalizedElement] {
        elements.map { e in
            let r1 = e.r1 * factor
            let r2 = e.r2 * factor
            let area = e.area > 0 ? Double.pi * r1 * r2 : -1
            return I3SNormalizedElement(
                id: e.id,
                cx: e.cx * factor,
                cy: e.cy * factor,
                r1: r1,
                r2: r2,
                angleDeg: e.angleDeg,
                area: area
            )
        }
    }

    private static func scalePoints(_ points: [I3SPoint2D], factor: Double) -> [I3SPoint2D] {
        points.map { I3SPoint2D(x: $0.x * factor, y: $0.y * factor) }
    }

    private static func calcMaxDistance(_ refs: [I3SPoint2D]) -> Double {
        guard refs.count >= 3 else { return 100.0 }
        let d01 = refs[0].dist(to: refs[1])
        let d12 = refs[1].dist(to: refs[2])
        let d02 = refs[0].dist(to: refs[2])
        return max(d01, max(d12, d02))
    }

    private static func sqrDist(_ a: I3SNormalizedElement, _ b: I3SNormalizedElement) -> Double {
        let dx = a.cx - b.cx
        let dy = a.cy - b.cy
        return dx * dx + dy * dy
    }

    /// `Element::matches` for `I3S_PATTERN` in `element.cpp`: area ratio must be >= `minRatioArea` (`0.5`).
    private static func elementMatches(_ a: I3SNormalizedElement, _ b: I3SNormalizedElement, minRatioArea: Double) -> Bool {
        if a.area <= 0 || b.area <= 0 { return false }
        let ratio = a.area < b.area ? (a.area / b.area) : (b.area / a.area)
        return ratio >= minRatioArea
    }

    /// `Element::calcSimilarityRate` for `I3S_PATTERN` in `element.cpp`.
    private static func calcSimilarityRate(_ a: I3SNormalizedElement, _ b: I3SNormalizedElement, minRatioArea: Double) -> Double {
        if a.area <= 0 || b.area <= 0 { return 1.0 }
        let ratio = a.area < b.area ? (a.area / b.area) : (b.area / a.area)
        let denom = 2.0 * minRatioArea - 2.0
        guard abs(denom) > 1e-9 else { return 1.0 }
        let aCoef = 1.0 / denom
        let bCoef = 0.5 - aCoef
        return max(0.5, aCoef * ratio + bCoef)
    }

    private static func scoreConfiguration(
        unknown: [I3SNormalizedElement],
        candidate: [I3SNormalizedElement],
        unknownCount: Int,
        candidateCount: Int,
        maxSqDist: Double,
        minRelDistSq: Double,
        minRatioArea: Double,
        normFactor: Double
    ) -> (score: Double, pairs: [Int], pairCnt: Int) {
        var pairs = [Int](repeating: -1, count: unknownCount)
        var distanceRates = [Double](repeating: 0, count: unknownCount)

        for i in 0..<unknownCount {
            let ue = unknown[i]
            var minDist = Double.greatestFiniteMagnitude
            var secondMinDist = Double.greatestFiniteMagnitude
            var minIndex = -1

            for j in 0..<candidateCount {
                let ke = candidate[j]
                guard elementMatches(ue, ke, minRatioArea: minRatioArea) else { continue }
                let d = sqrDist(ue, ke)
                if d < minDist {
                    secondMinDist = minDist
                    minDist = d
                    minIndex = j
                } else if d < secondMinDist {
                    secondMinDist = d
                }
            }

            if minDist < maxSqDist && minDist * minRelDistSq <= secondMinDist && minIndex >= 0 {
                let sim = calcSimilarityRate(ue, candidate[minIndex], minRatioArea: minRatioArea)
                pairs[i] = minIndex
                distanceRates[i] = sqrt(minDist) * sim
            }
        }

        // Resolve duplicate matches to the same candidate point (`resolveDuplicates` in `compare.cpp`)
        for i in 0..<unknownCount where pairs[i] >= 0 {
            for j in (i + 1)..<unknownCount where pairs[j] == pairs[i] {
                if distanceRates[i] < distanceRates[j] {
                    pairs[j] = -1
                } else {
                    pairs[i] = -1
                    break
                }
            }
        }

        var totDist = 0.0
        var pairCnt = 0
        for i in 0..<unknownCount where pairs[i] >= 0 {
            totDist += distanceRates[i]
            pairCnt += 1
        }

        guard pairCnt > 2 else {
            return (I3SComparisonResult.noMatchScore, pairs, pairCnt)
        }
        let notPairedRatio = Double(2 * pairCnt) / Double(unknownCount + candidateCount)
        let denom = Double(pairCnt * pairCnt) * (notPairedRatio * notPairedRatio)
        guard denom > 1e-9 else {
            return (I3SComparisonResult.noMatchScore, pairs, pairCnt)
        }
        let score = (normFactor * totDist) / denom
        return (score < 0 ? I3SComparisonResult.noMatchScore : score, pairs, pairCnt)
    }

    private static func isSingularOrLargeShift(_ m: [Double], normFactor: Double) -> Bool {
        // Matches `singularMatrix` + `maxShift = 20.0 * normFactor` in `compare.cpp`
        let maxShift = 20.0 * normFactor
        if abs(m[2]) > maxShift || abs(m[5]) > maxShift { return true }
        if abs(m[0] - 1.0) > 0.35 || abs(m[4] - 1.0) > 0.35 { return true }
        if abs(m[1]) > 0.35 || abs(m[3]) > 0.35 { return true }
        return false
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
