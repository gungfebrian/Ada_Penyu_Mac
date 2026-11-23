import AppKit
import CoreGraphics
import CoreImage
import Foundation

// MARK: - Persistent Human-Assisted Annotation & Anchor Models

/// A single human-verified or AI-seeded point correspondence `(Sighting ↔ Candidate)`
/// in normalized `[0, 1]` top-left coordinates. Works both snapped to numbered auto-scales
/// and placed freely on exact raw pixels (3-way suture junctions, scars, notches, eye corners).
nonisolated struct ManualAnchorPair: Identifiable, Hashable, Codable, Sendable {
    enum Source: String, Codable, Hashable, Sendable {
        case manual
        case aiInlier
    }

    var id: UUID = UUID()
    var label: String
    var queryPoint: ScalePoint
    var candidatePoint: ScalePoint
    var queryScaleNumber: Int?
    var candidateScaleNumber: Int?
    var source: Source = .manual
}

/// A manual scale landmark added by a scientist when glare, shadow, or oblique angle
/// prevented auto-segmentation from isolating a facial scale.
nonisolated struct ManualScaleLandmark: Identifiable, Hashable, Codable, Sendable {
    var id: UUID = UUID()
    var label: String
    var point: ScalePoint
    var note: String = ""
}

/// Rank and confidence change observed after human-assisted crop / tilt re-matching.
nonisolated struct CandidateReMatchDelta: Hashable, Codable, Sendable {
    let previousRank: Int?
    let newRank: Int
    let previousConfidence: Int?
    let newConfidence: Int

    var rankShift: Int? {
        guard let previousRank else { return nil }
        return previousRank - newRank
    }

    var confidenceDelta: Int? {
        guard let previousConfidence else { return nil }
        return newConfidence - previousConfidence
    }

    var badgeText: String? {
        if previousRank == nil {
            return "New #\(newRank)"
        }
        if let shift = rankShift, shift > 0 {
            if let dConf = confidenceDelta, dConf > 0 {
                return "↑\(shift) · +\(dConf)%"
            }
            return "↑\(shift)"
        }
        if let dConf = confidenceDelta, abs(dConf) >= 2 {
            return dConf > 0 ? "+\(dConf)%" : "\(dConf)%"
        }
        if let shift = rankShift, shift < 0 {
            return "↓\(-shift)"
        }
        return nil
    }

    var isPositive: Bool {
        if previousRank == nil { return true }
        if let shift = rankShift, shift > 0 { return true }
        if let dConf = confidenceDelta, dConf > 0 { return true }
        return false
    }
}

// MARK: - Square Overlay Image Normalizer & Cropped/Leveled Re-Match Builder

/// Prepares backend-compliant square JPEGs for `POST /api/v1/match/overlay/annotations`
/// (which strictly rejects non-square uploads with HTTP 422) while preserving exact aspect
/// ratios and inverting returned `[0, 1]` square keypoints back into original photo space.
nonisolated enum SquareOverlayMapper {
    struct PreparedOverlay: Sendable {
        let jpegData: Data
        /// Normalized `[0, 1]` top-left rect occupied by the original image inside the square canvas.
        let contentRect: CGRect
        let squareSide: Int
    }

    /// Letterboxes arbitrary-aspect photo bytes into a `side × side` square JPEG without squishing
    /// facial scale geometry. Returns the exact `contentRect` needed to unmap XFeat coordinates.
    static func prepareSquareJPEG(
        from imageData: Data,
        squareSide: Int = 512,
        quality: Double = 0.90
    ) -> PreparedOverlay? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        return prepareSquareJPEG(from: cgImage, squareSide: squareSide, quality: quality)
    }

    static func prepareSquareJPEG(
        from cgImage: CGImage,
        squareSide: Int = 512,
        quality: Double = 0.90
    ) -> PreparedOverlay? {
        let side = max(128, min(2048, squareSide))
        let srcW = Double(cgImage.width)
        let srcH = Double(cgImage.height)
        guard srcW >= 8, srcH >= 8 else { return nil }

        let scale = min(Double(side) / srcW, Double(side) / srcH)
        let drawW = srcW * scale
        let drawH = srcH * scale
        let padX = (Double(side) - drawW) * 0.5
        let padY = (Double(side) - drawH) * 0.5

        guard let context = CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }

        // Soft neutral dark ocean slate avoids high-contrast letterbox edges that attract false keypoints.
        context.setFillColor(red: 14.0 / 255.0, green: 24.0 / 255.0, blue: 34.0 / 255.0, alpha: 1.0)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: padX, y: padY, width: drawW, height: drawH))

        guard let rendered = context.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: rendered)
        guard let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: quality]) else {
            return nil
        }

        // Because letterbox padding is symmetric horizontally and vertically, normalized top-left
        // contentRect equals bottom-left contentRect identically.
        let contentRect = CGRect(
            x: padX / Double(side),
            y: padY / Double(side),
            width: drawW / Double(side),
            height: drawH / Double(side)
        )
        return PreparedOverlay(jpegData: jpeg, contentRect: contentRect, squareSide: side)
    }

    /// Maps normalized `[0, 1]` top-left coordinates from the letterboxed square canvas back
    /// into the original photo's normalized `[0, 1]` space, dropping points inside letterbox bars.
    static func mapQueryPointToOriginal(
        _ point: OverlayMatchPoint,
        contentRect: CGRect,
        borderMargin: Double = 0.004
    ) -> OverlayMatchPoint? {
        guard contentRect.width > 0.05, contentRect.height > 0.05 else { return nil }
        let ox = (point.x - contentRect.minX) / contentRect.width
        let oy = (point.y - contentRect.minY) / contentRect.height
        guard ox >= -borderMargin, ox <= 1.0 + borderMargin,
              oy >= -borderMargin, oy <= 1.0 + borderMargin else {
            return nil
        }
        return OverlayMatchPoint(
            x: min(1.0, max(0.0, ox)),
            y: min(1.0, max(0.0, oy))
        )
    }

    /// Maps an array of backend XFeat/LighterGlue overlay annotations from letterboxed square query
    /// coordinates back to the original query photo's normalized coordinate frame.
    /// Candidate coordinates are preserved directly because the backend indexes gallery photos via
    /// direct square resize (`[0, candW] -> [0, 512]`, `[0, candH] -> [0, 512]`).
    static func unmapAnnotations(
        _ annotations: [OverlayAnnotationItem],
        contentRect: CGRect
    ) -> [OverlayAnnotationItem] {
        annotations.compactMap { ann in
            guard let mappedQuery = mapQueryPointToOriginal(ann.query, contentRect: contentRect) else {
                return nil
            }
            return OverlayAnnotationItem(
                featureID: ann.featureID,
                label: ann.label,
                score: ann.score,
                query: mappedQuery,
                candidate: ann.candidate
            )
        }
    }

    /// Crops `normalizedRect` (top-left `[0, 1]`) and optionally levels head tilt by `rotationDegrees`
    /// (`-30...30`) for human-assisted open-set re-matching (`POST /api/v1/match` or `/match/pair`).
    @MainActor
    static func prepareReMatchJPEG(
        from image: NSImage,
        normalizedRect: CGRect,
        rotationDegrees: Double = 0,
        quality: Double = 0.92
    ) -> Data? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return prepareReMatchJPEG(
            from: cg,
            normalizedRect: normalizedRect,
            rotationDegrees: rotationDegrees,
            quality: quality
        )
    }

    static func prepareReMatchJPEG(
        from cg: CGImage,
        normalizedRect: CGRect,
        rotationDegrees: Double = 0,
        quality: Double = 0.92
    ) -> Data? {
        let imgW = Double(cg.width)
        let imgH = Double(cg.height)
        guard imgW >= 16, imgH >= 16 else { return nil }

        let rx = min(max(normalizedRect.minX, 0.0), 0.92)
        let ry = min(max(normalizedRect.minY, 0.0), 0.92)
        let rw = min(max(normalizedRect.width, 0.08), 1.0 - rx)
        let rh = min(max(normalizedRect.height, 0.08), 1.0 - ry)

        let outW = max(64, min(1600, Int((rw * imgW).rounded())))
        let outH = max(64, min(1600, Int((rh * imgH).rounded())))

        if abs(rotationDegrees) < 0.25 {
            let cropPx = CGRect(
                x: floor(rx * imgW),
                y: floor(ry * imgH),
                width: max(16, floor(rw * imgW)),
                height: max(16, floor(rh * imgH))
            ).intersection(CGRect(x: 0, y: 0, width: imgW, height: imgH))
            guard cropPx.width >= 16, cropPx.height >= 16, let cropped = cg.cropping(to: cropPx) else {
                return nil
            }
            return NSBitmapImageRep(cgImage: cropped).representation(
                using: .jpeg,
                properties: [.compressionFactor: quality]
            )
        }

        // Rotate about the crop center so tilt-straightening never shifts the turtle head out of frame.
        let scaleX = Double(outW) / (rw * imgW)
        let scaleY = Double(outH) / (rh * imgH)
        let cropCenterX = (rx + rw * 0.5) * imgW
        // Convert top-left normalized center Y to CoreGraphics bottom-left pixel Y.
        let cropCenterY = (1.0 - (ry + rh * 0.5)) * imgH

        guard let ctx = CGContext(
            data: nil,
            width: outW,
            height: outH,
            bitsPerComponent: 8,
            bytesPerRow: outW * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }

        ctx.setFillColor(red: 14.0 / 255.0, green: 24.0 / 255.0, blue: 34.0 / 255.0, alpha: 1.0)
        ctx.fill(CGRect(x: 0, y: 0, width: outW, height: outH))
        ctx.interpolationQuality = .high

        ctx.translateBy(x: Double(outW) * 0.5, y: Double(outH) * 0.5)
        // Positive rotationDegrees rotates clockwise visually (negated in CG's y-up frame).
        ctx.rotate(by: CGFloat(-rotationDegrees * .pi / 180.0))
        ctx.scaleBy(x: scaleX, y: scaleY)
        ctx.translateBy(x: -cropCenterX, y: -cropCenterY)
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: imgW, height: imgH))

        guard let rendered = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: rendered).representation(
            using: .jpeg,
            properties: [.compressionFactor: quality]
        )
    }
}

// MARK: - 2D Affine & Projective Homography Math (Normalized DLT + Partial-Pivot Solver)

nonisolated struct AffineTransform2D: Equatable, Sendable {
    /// `[a, b, tx, c, d, ty]` where `x' = a*x + b*y + tx`, `y' = c*x + d*y + ty`.
    let a: Double
    let b: Double
    let tx: Double
    let c: Double
    let d: Double
    let ty: Double

    func apply(_ p: ScalePoint) -> ScalePoint {
        ScalePoint(x: a * p.x + b * p.y + tx, y: c * p.x + d * p.y + ty)
    }

    var determinant: Double { a * d - b * c }

    var singularValues: (s1: Double, s2: Double) {
        let traceSq = a * a + b * b + c * c + d * d
        let det = determinant
        let disc = sqrt(max(0.0, traceSq * traceSq - 4.0 * det * det))
        let s1 = sqrt(max(0.0, (traceSq + disc) * 0.5))
        let s2 = sqrt(max(0.0, (traceSq - disc) * 0.5))
        return (s1, s2)
    }

    var anisotropyRatio: Double {
        let sv = singularValues
        return sv.s1 / max(1e-4, sv.s2)
    }

    var rotationDegrees: Double {
        atan2(c, a) * 180.0 / .pi
    }

    static func fit(pairs: [(ScalePoint, ScalePoint)]) -> AffineTransform2D? {
        guard let m = PatternMatchCalculator.solveBestAffine(pointPairs: pairs), m.count >= 6 else {
            return nil
        }
        return AffineTransform2D(a: m[0], b: m[1], tx: m[2], c: m[3], d: m[4], ty: m[5])
    }
}

nonisolated struct ProjectiveHomography: Equatable, Sendable {
    /// Row-major `3×3` matrix `H` mapping normalized top-left Query -> Candidate.
    let h00: Double, h01: Double, h02: Double
    let h10: Double, h11: Double, h12: Double
    let h20: Double, h21: Double, h22: Double

    func apply(_ p: ScalePoint) -> ScalePoint? {
        let w = h20 * p.x + h21 * p.y + h22
        guard abs(w) > 1e-6 else { return nil }
        let x = (h00 * p.x + h01 * p.y + h02) / w
        let y = (h10 * p.x + h11 * p.y + h12) / w
        guard x.isFinite, y.isFinite else { return nil }
        return ScalePoint(x: x, y: y)
    }

    func denominator(at p: ScalePoint) -> Double {
        h20 * p.x + h21 * p.y + h22
    }

    /// Computes local linear Jacobian `∂(x', y') / ∂(x, y)` at `p` for physical plausibility checks.
    func localLinearMetrics(at p: ScalePoint) -> (determinant: Double, anisotropy: Double, rotationDeg: Double)? {
        let w = h20 * p.x + h21 * p.y + h22
        guard w > 1e-4 else { return nil }
        let nx = h00 * p.x + h01 * p.y + h02
        let ny = h10 * p.x + h11 * p.y + h12
        let invW2 = 1.0 / (w * w)
        let j00 = (h00 * w - nx * h20) * invW2
        let j01 = (h01 * w - nx * h21) * invW2
        let j10 = (h10 * w - ny * h20) * invW2
        let j11 = (h11 * w - ny * h21) * invW2
        let det = j00 * j11 - j01 * j10
        let traceSq = j00 * j00 + j01 * j01 + j10 * j10 + j11 * j11
        let disc = sqrt(max(0.0, traceSq * traceSq - 4.0 * det * det))
        let s1 = sqrt(max(0.0, (traceSq + disc) * 0.5))
        let s2 = sqrt(max(0.0, (traceSq - disc) * 0.5))
        let aniso = s1 / max(1e-4, s2)
        let rot = atan2(j10, j00) * 180.0 / .pi
        return (det, aniso, rot)
    }

    /// Hartley-normalized Direct Linear Transform (DLT) solver for 4+ point correspondences.
    static func fit(pairs: [(ScalePoint, ScalePoint)]) -> ProjectiveHomography? {
        guard pairs.count >= 4 else { return nil }

        guard let (normQ, tq) = hartleyNormalize(pairs.map(\.0)),
              let (normC, tc) = hartleyNormalize(pairs.map(\.1)) else {
            return nil
        }

        // Solve A * h = b where h = [h00, h01, h02, h10, h11, h12, h20, h21]^T and h22 = 1.
        // Normal equations (A^T A) h = A^T b work cleanly for both N == 4 and overdetermined N > 4.
        var ata = [Double](repeating: 0, count: 64)
        var atb = [Double](repeating: 0, count: 8)

        for i in 0..<pairs.count {
            let x = normQ[i].x, y = normQ[i].y
            let u = normC[i].x, v = normC[i].y

            // Row 1: x*h00 + y*h01 + 1*h02 - u*x*h20 - u*y*h21 = u
            let r1: [Double] = [x, y, 1, 0, 0, 0, -u * x, -u * y]
            // Row 2: x*h10 + y*h11 + 1*h12 - v*x*h20 - v*y*h21 = v
            let r2: [Double] = [0, 0, 0, x, y, 1, -v * x, -v * y]

            for r in 0..<8 {
                let rv1 = r1[r]
                let rv2 = r2[r]
                atb[r] += rv1 * u + rv2 * v
                let base = r * 8
                for c in 0..<8 {
                    ata[base + c] += rv1 * r1[c] + rv2 * r2[c]
                }
            }
        }

        guard let hVec = solveLinearSystem(matrix: ata, rhs: atb, n: 8) else { return nil }
        let hNorm: [Double] = [
            hVec[0], hVec[1], hVec[2],
            hVec[3], hVec[4], hVec[5],
            hVec[6], hVec[7], 1.0,
        ]

        // Denormalize: H = T_c^{-1} * H_norm * T_q
        let tcInv: [Double] = [
            1.0 / tc.scale, 0, tc.meanX,
            0, 1.0 / tc.scale, tc.meanY,
            0, 0, 1.0,
        ]
        let tqMat: [Double] = [
            tq.scale, 0, -tq.scale * tq.meanX,
            0, tq.scale, -tq.scale * tq.meanY,
            0, 0, 1.0,
        ]
        let rawH = multiply3x3(multiply3x3(tcInv, hNorm), tqMat)
        guard abs(rawH[8]) > 1e-9 else { return nil }
        let invScale = 1.0 / rawH[8]
        let h = rawH.map { $0 * invScale }
        guard h.allSatisfy(\.isFinite) else { return nil }
        return ProjectiveHomography(
            h00: h[0], h01: h[1], h02: h[2],
            h10: h[3], h11: h[4], h12: h[5],
            h20: h[6], h21: h[7], h22: h[8]
        )
    }

    private struct HartleyTransform {
        let meanX: Double
        let meanY: Double
        let scale: Double
    }

    private static func hartleyNormalize(_ pts: [ScalePoint]) -> ([ScalePoint], HartleyTransform)? {
        guard !pts.isEmpty else { return nil }
        let n = Double(pts.count)
        let mx = pts.map(\.x).reduce(0, +) / n
        let my = pts.map(\.y).reduce(0, +) / n
        let meanDist = pts.map { hypot($0.x - mx, $0.y - my) }.reduce(0, +) / n
        guard meanDist > 1e-6 else { return nil }
        let s = sqrt(2.0) / meanDist
        let normalized = pts.map { ScalePoint(x: ($0.x - mx) * s, y: ($0.y - my) * s) }
        return (normalized, HartleyTransform(meanX: mx, meanY: my, scale: s))
    }

    private static func multiply3x3(_ a: [Double], _ b: [Double]) -> [Double] {
        var out = [Double](repeating: 0, count: 9)
        for r in 0..<3 {
            for c in 0..<3 {
                out[r * 3 + c] = a[r * 3] * b[c] + a[r * 3 + 1] * b[3 + c] + a[r * 3 + 2] * b[6 + c]
            }
        }
        return out
    }

    /// Gaussian elimination with partial pivoting for an `n × n` linear system.
    private static func solveLinearSystem(matrix: [Double], rhs: [Double], n: Int) -> [Double]? {
        var a = matrix
        var b = rhs
        for col in 0..<n {
            var pivotRow = col
            var maxVal = abs(a[col * n + col])
            for row in (col + 1)..<n {
                let v = abs(a[row * n + col])
                if v > maxVal {
                    maxVal = v
                    pivotRow = row
                }
            }
            guard maxVal > 1e-12 else { return nil }
            if pivotRow != col {
                for c in col..<n {
                    let tmp = a[col * n + c]
                    a[col * n + c] = a[pivotRow * n + c]
                    a[pivotRow * n + c] = tmp
                }
                let tmpB = b[col]
                b[col] = b[pivotRow]
                b[pivotRow] = tmpB
            }
            let pivot = a[col * n + col]
            for row in (col + 1)..<n {
                let factor = a[row * n + col] / pivot
                if abs(factor) < 1e-15 { continue }
                a[row * n + col] = 0
                for c in (col + 1)..<n {
                    a[row * n + c] -= factor * a[col * n + c]
                }
                b[row] -= factor * b[col]
            }
        }

        var x = [Double](repeating: 0, count: n)
        for row in stride(from: n - 1, through: 0, by: -1) {
            var sum = b[row]
            for c in (row + 1)..<n {
                sum -= a[row * n + c] * x[c]
            }
            let diag = a[row * n + row]
            guard abs(diag) > 1e-12 else { return nil }
            x[row] = sum / diag
        }
        return x.allSatisfy(\.isFinite) ? x : nil
    }
}

/// Unified geometric warp transform solved from 3 anchors (Affine) or 4+ anchors (Projective Homography).
nonisolated enum GeometricWarpTransform: Equatable, Sendable {
    case affine(AffineTransform2D)
    case homography(ProjectiveHomography, fallbackAffine: AffineTransform2D)

    func apply(_ p: ScalePoint) -> ScalePoint? {
        switch self {
        case .affine(let aff):
            return aff.apply(p)
        case .homography(let h, _):
            return h.apply(p)
        }
    }

    var isPerspective: Bool {
        if case .homography = self { return true }
        return false
    }

    var modeLabel: String {
        isPerspective ? "Perspective" : "Affine"
    }

    var fallbackAffine: AffineTransform2D {
        switch self {
        case .affine(let aff): aff
        case .homography(_, let fallback): fallback
        }
    }

    func linearMetrics(at center: ScalePoint) -> (determinant: Double, anisotropy: Double, rotationDeg: Double) {
        switch self {
        case .affine(let aff):
            return (aff.determinant, aff.anisotropyRatio, aff.rotationDegrees)
        case .homography(let h, let fallback):
            if let m = h.localLinearMetrics(at: center) { return m }
            return (fallback.determinant, fallback.anisotropyRatio, fallback.rotationDegrees)
        }
    }

    /// Fits a projective homography for 4+ well-conditioned anchors, falling back gracefully to
    /// 2D affine if 3 anchors are given or the homography horizon cuts through the image frame.
    static func fit(pairs: [(ScalePoint, ScalePoint)]) -> GeometricWarpTransform? {
        guard pairs.count >= 3, let affine = AffineTransform2D.fit(pairs: pairs) else { return nil }
        guard pairs.count >= 4, let h = ProjectiveHomography.fit(pairs: pairs) else {
            return .affine(affine)
        }

        // Verify no projective horizon inversion across the anchor hull and image center.
        let samplePoints = pairs.map(\.0) + [ScalePoint(x: 0.5, y: 0.5)]
        let validHorizon = samplePoints.allSatisfy { h.denominator(at: $0) > 0.15 }
        let cx = pairs.map(\.0.x).reduce(0, +) / Double(pairs.count)
        let cy = pairs.map(\.0.y).reduce(0, +) / Double(pairs.count)
        guard validHorizon,
              let metrics = h.localLinearMetrics(at: ScalePoint(x: cx, y: cy)),
              metrics.determinant > 0.05,
              metrics.anisotropy < 4.5 else {
            return .affine(affine)
        }
        return .homography(h, fallbackAffine: affine)
    }
}

// MARK: - Real Geometric Consensus (RANSAC over Backend XFeat/LighterGlue Correspondences)

nonisolated struct GeometricConsensusReport: Equatable, Sendable {
    enum Strength: Equatable, Sendable {
        case strong
        case moderate
        case weak
        case insufficient
    }

    let totalMatches: Int
    let inlierCount: Int
    let outlierCount: Int
    let inlierRatio: Double
    let meanInlierResidualPercent: Double?
    let spatialSpread: Double
    let inlierFeatureIDs: Set<String>
    let transform: GeometricWarpTransform?
    let suggestedAnchors: [ManualAnchorPair]
    let strength: Strength

    static let empty = GeometricConsensusReport(
        totalMatches: 0,
        inlierCount: 0,
        outlierCount: 0,
        inlierRatio: 0,
        meanInlierResidualPercent: nil,
        spatialSpread: 0,
        inlierFeatureIDs: [],
        transform: nil,
        suggestedAnchors: [],
        strength: .insufficient
    )

    var shortBadgeText: String {
        guard totalMatches > 0 else { return "No AI matches" }
        if let err = meanInlierResidualPercent, inlierCount >= 4 {
            return String(format: "%d/%d inliers · %.1f%% err", inlierCount, totalMatches, err)
        }
        return "\(inlierCount)/\(totalMatches) inliers · Weak"
    }

    var canAutoSeedWarp: Bool {
        suggestedAnchors.count >= 3 && transform != nil
    }
}

nonisolated enum GeometricConsensusRANSAC {
    /// Classifies backend XFeat/LighterGlue keypoint correspondences into geometrically consistent
    /// inliers vs. background/glare outliers using deterministic similarity/affine RANSAC + DLT
    /// projective homography refinement, then extracts 4 well-spread anchors for 1-click photo warp.
    static func evaluate(
        annotations: [OverlayAnnotationItem],
        inlierThreshold: Double = 0.036,
        minScore: Double = 0.12
    ) -> GeometricConsensusReport {
        let valid = annotations.filter { ann in
            (ann.score ?? 0.5) >= minScore
                && ann.query.x >= 0 && ann.query.x <= 1
                && ann.query.y >= 0 && ann.query.y <= 1
                && ann.candidate.x >= 0 && ann.candidate.x <= 1
                && ann.candidate.y >= 0 && ann.candidate.y <= 1
        }
        guard valid.count >= 3 else {
            return GeometricConsensusReport(
                totalMatches: valid.count,
                inlierCount: 0,
                outlierCount: valid.count,
                inlierRatio: 0,
                meanInlierResidualPercent: nil,
                spatialSpread: 0,
                inlierFeatureIDs: [],
                transform: nil,
                suggestedAnchors: [],
                strength: .insufficient
            )
        }

        let sorted = valid.sorted { ($0.score ?? 0) > ($1.score ?? 0) }
        let n = sorted.count
        let qPts = sorted.map { ScalePoint(x: $0.query.x, y: $0.query.y) }
        let cPts = sorted.map { ScalePoint(x: $0.candidate.x, y: $0.candidate.y) }

        var rng = SplitMix64(seed: 0xADA5_2026_1123)
        var bestInlierIndices: [Int] = []
        var bestWeightedScore = -1.0

        func scoreAffineHypothesis(_ aff: AffineTransform2D, tol: Double) -> ([Int], Double)? {
            let det = aff.determinant
            guard det > 0.14, det < 7.0 else { return nil }
            guard aff.anisotropyRatio < 2.65 else { return nil }
            guard abs(aff.rotationDegrees) < 62.0 else { return nil }

            var inliers: [Int] = []
            var weighted = 0.0
            for i in 0..<n {
                let mapped = aff.apply(qPts[i])
                let err = hypot(mapped.x - cPts[i].x, mapped.y - cPts[i].y)
                if err <= tol {
                    inliers.append(i)
                    let precision = max(0.0, 1.0 - err / max(tol, 1e-4))
                    weighted += 0.55 + 0.45 * precision * precision + min(0.35, (sorted[i].score ?? 0.5) * 0.35)
                }
            }
            return (inliers, weighted)
        }

        // Phase 1: Deterministic 2-point similarity hypotheses over top matches (fast & immune to shear overfitting).
        let topCap = min(n, 22)
        for i in 0..<topCap {
            for j in (i + 1)..<topCap {
                let dqx = qPts[j].x - qPts[i].x
                let dqy = qPts[j].y - qPts[i].y
                let qLen2 = dqx * dqx + dqy * dqy
                guard qLen2 >= 0.0025 else { continue }
                let dcx = cPts[j].x - cPts[i].x
                let dcy = cPts[j].y - cPts[i].y
                let a = (dqx * dcx + dqy * dcy) / qLen2
                let b = (dqx * dcy - dqy * dcx) / qLen2
                let tx = cPts[i].x - (a * qPts[i].x - b * qPts[i].y)
                let ty = cPts[i].y - (b * qPts[i].x + a * qPts[i].y)
                let sim = AffineTransform2D(a: a, b: -b, tx: tx, c: b, d: a, ty: ty)
                if let (inliers, score) = scoreAffineHypothesis(sim, tol: inlierThreshold * 1.25),
                   inliers.count >= 3, score > bestWeightedScore {
                    bestWeightedScore = score
                    bestInlierIndices = inliers
                }
            }
        }

        // Phase 2: 3-point full affine RANSAC trials (captures perspective tilt / head yaw).
        let trials = min(220, max(40, n * 4))
        for _ in 0..<trials {
            let i0 = rng.nextInt(upperBound: n)
            let i1 = rng.nextInt(upperBound: n)
            let i2 = rng.nextInt(upperBound: n)
            guard i0 != i1, i1 != i2, i0 != i2 else { continue }
            let triArea = abs(
                (qPts[i1].x - qPts[i0].x) * (qPts[i2].y - qPts[i0].y)
                    - (qPts[i1].y - qPts[i0].y) * (qPts[i2].x - qPts[i0].x)
            )
            guard triArea >= 0.0015 else { continue }
            guard let aff = AffineTransform2D.fit(pairs: [
                (qPts[i0], cPts[i0]),
                (qPts[i1], cPts[i1]),
                (qPts[i2], cPts[i2]),
            ]) else { continue }
            if let (inliers, score) = scoreAffineHypothesis(aff, tol: inlierThreshold),
               inliers.count >= 3, score > bestWeightedScore {
                bestWeightedScore = score
                bestInlierIndices = inliers
            }
        }

        guard bestInlierIndices.count >= 3 else {
            return GeometricConsensusReport(
                totalMatches: n,
                inlierCount: 0,
                outlierCount: n,
                inlierRatio: 0,
                meanInlierResidualPercent: nil,
                spatialSpread: 0,
                inlierFeatureIDs: [],
                transform: nil,
                suggestedAnchors: [],
                strength: .weak
            )
        }

        // Phase 3: Refit full projective homography (or affine) on winning inliers and re-evaluate cleanly.
        var currentIndices = bestInlierIndices
        var refinedTransform: GeometricWarpTransform? = GeometricWarpTransform.fit(
            pairs: currentIndices.map { (qPts[$0], cPts[$0]) }
        )

        if let warp = refinedTransform {
            var tightInliers: [Int] = []
            for i in 0..<n {
                guard let mapped = warp.apply(qPts[i]) else { continue }
                let err = hypot(mapped.x - cPts[i].x, mapped.y - cPts[i].y)
                if err <= inlierThreshold {
                    tightInliers.append(i)
                }
            }
            if tightInliers.count >= 3 {
                currentIndices = tightInliers
                if let refit = GeometricWarpTransform.fit(pairs: currentIndices.map { (qPts[$0], cPts[$0]) }) {
                    refinedTransform = refit
                }
            }
        }

        guard let finalTransform = refinedTransform else {
            return GeometricConsensusReport(
                totalMatches: n,
                inlierCount: 0,
                outlierCount: n,
                inlierRatio: 0,
                meanInlierResidualPercent: nil,
                spatialSpread: 0,
                inlierFeatureIDs: [],
                transform: nil,
                suggestedAnchors: [],
                strength: .weak
            )
        }

        var residuals: [Double] = []
        for idx in currentIndices {
            if let mapped = finalTransform.apply(qPts[idx]) {
                residuals.append(hypot(mapped.x - cPts[idx].x, mapped.y - cPts[idx].y) * 100.0)
            }
        }
        let meanResidual = residuals.isEmpty ? nil : (residuals.reduce(0, +) / Double(residuals.count))

        let inlierQ = currentIndices.map { qPts[$0] }
        let minX = inlierQ.map(\.x).min() ?? 0.5
        let maxX = inlierQ.map(\.x).max() ?? 0.5
        let minY = inlierQ.map(\.y).min() ?? 0.5
        let maxY = inlierQ.map(\.y).max() ?? 0.5
        let spread = hypot(maxX - minX, maxY - minY)

        let inlierCount = currentIndices.count
        let inlierRatio = Double(inlierCount) / Double(n)
        let inlierIDs = Set(currentIndices.map { sorted[$0].featureID })

        let strength: GeometricConsensusReport.Strength
        if inlierCount >= 8 && inlierRatio >= 0.35 && spread >= 0.16 && (meanResidual ?? 99) <= 2.6 {
            strength = .strong
        } else if inlierCount >= 4 && inlierRatio >= 0.20 && spread >= 0.10 {
            strength = .moderate
        } else {
            strength = .weak
        }

        // Phase 4: Farthest-point sampling to pick up to 4 well-spread anchors for 1-click photo warp.
        let seeded = selectWellSpreadAnchors(
            indices: currentIndices,
            sorted: sorted,
            qPts: qPts,
            cPts: cPts,
            maxCount: 4
        )

        return GeometricConsensusReport(
            totalMatches: n,
            inlierCount: inlierCount,
            outlierCount: max(0, n - inlierCount),
            inlierRatio: inlierRatio,
            meanInlierResidualPercent: meanResidual,
            spatialSpread: spread,
            inlierFeatureIDs: inlierIDs,
            transform: finalTransform,
            suggestedAnchors: seeded,
            strength: strength
        )
    }

    private static func selectWellSpreadAnchors(
        indices: [Int],
        sorted: [OverlayAnnotationItem],
        qPts: [ScalePoint],
        cPts: [ScalePoint],
        maxCount: Int
    ) -> [ManualAnchorPair] {
        guard indices.count >= 3 else { return [] }
        let labels = ["A", "B", "C", "D", "E", "F"]
        var chosen: [Int] = []

        // Start from the highest-score inlier (indices are already ordered by sorted index, i.e. score desc).
        if let first = indices.min() {
            chosen.append(first)
        }

        while chosen.count < min(maxCount, indices.count) {
            var bestIdx: Int?
            var bestScore = -1.0
            for idx in indices where !chosen.contains(idx) {
                let p = qPts[idx]
                let minDist = chosen.map { hypot(p.x - qPts[$0].x, p.y - qPts[$0].y) }.min() ?? 0
                // Prefer spatially spread points with good XFeat confidence.
                let score = minDist * (0.65 + 0.35 * min(1.0, sorted[idx].score ?? 0.5))
                if score > bestScore {
                    bestScore = score
                    bestIdx = idx
                }
            }
            guard let next = bestIdx, bestScore > 0.025 else { break }
            chosen.append(next)
        }

        guard chosen.count >= 3 else { return [] }
        return chosen.enumerated().map { offset, idx in
            ManualAnchorPair(
                label: offset < labels.count ? labels[offset] : "P\(offset + 1)",
                queryPoint: qPts[idx],
                candidatePoint: cPts[idx],
                queryScaleNumber: nil,
                candidateScaleNumber: nil,
                source: .aiInlier
            )
        }
    }

    private struct SplitMix64 {
        private var state: UInt64
        init(seed: UInt64) { self.state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func nextInt(upperBound: Int) -> Int {
            Int(next() % UInt64(max(1, upperBound)))
        }
    }
}

// MARK: - Unified Human-Assisted Alignment Evaluator (Works with Manual Pins OR Scale Pairs)

nonisolated struct HumanAssistedAlignmentResult: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case needsAnchors(remaining: Int)
        case aligned
        case orientationFlipped
        case extremeStretch(ratio: Double)
    }

    let status: Status
    let anchorCount: Int
    let transform: GeometricWarpTransform?
    let meanResidualPercent: Double?
    let warpedContours: [WarpedPatternContour]
    let orientationPreserved: Bool
    let anisotropyRatio: Double?

    var isReadyForWarp: Bool {
        transform != nil && orientationPreserved
    }

    var pillText: String {
        switch status {
        case .needsAnchors(let remaining):
            return anchorCount == 0 ? "Place 3+ pins or Auto-align" : "Place \(remaining) more pin\(remaining == 1 ? "" : "s")"
        case .aligned:
            let mode = transform?.modeLabel ?? "Aligned"
            if let err = meanResidualPercent, anchorCount >= 4 {
                return String(format: "%d pins · %@ (%.1f%% err)", anchorCount, mode, err)
            }
            return "\(anchorCount) pins · \(mode)"
        case .orientationFlipped:
            return "Flipped pins"
        case .extremeStretch(let ratio):
            return String(format: "Distorted (%.1f×)", ratio)
        }
    }

    var isWarning: Bool {
        switch status {
        case .orientationFlipped, .extremeStretch: true
        case .needsAnchors, .aligned: false
        }
    }
}

nonisolated enum HumanAssistedAlignmentEvaluator {
    static func evaluate(
        anchors: [ManualAnchorPair],
        queryPatterns: [DetectedScalePattern]
    ) -> HumanAssistedAlignmentResult {
        guard anchors.count >= 3 else {
            return HumanAssistedAlignmentResult(
                status: .needsAnchors(remaining: max(1, 3 - anchors.count)),
                anchorCount: anchors.count,
                transform: nil,
                meanResidualPercent: nil,
                warpedContours: [],
                orientationPreserved: true,
                anisotropyRatio: nil
            )
        }

        let pairs = anchors.map { ($0.queryPoint, $0.candidatePoint) }
        guard let transform = GeometricWarpTransform.fit(pairs: pairs) else {
            return HumanAssistedAlignmentResult(
                status: .needsAnchors(remaining: 1),
                anchorCount: anchors.count,
                transform: nil,
                meanResidualPercent: nil,
                warpedContours: [],
                orientationPreserved: true,
                anisotropyRatio: nil
            )
        }

        let cx = pairs.map(\.0.x).reduce(0, +) / Double(pairs.count)
        let cy = pairs.map(\.0.y).reduce(0, +) / Double(pairs.count)
        let metrics = transform.linearMetrics(at: ScalePoint(x: cx, y: cy))
        let orientationPreserved = metrics.determinant > 1e-6

        let status: HumanAssistedAlignmentResult.Status
        if !orientationPreserved {
            status = .orientationFlipped
        } else if metrics.anisotropy > 3.2 {
            status = .extremeStretch(ratio: metrics.anisotropy)
        } else {
            status = .aligned
        }

        let residuals: [Double] = pairs.compactMap { q, c in
            guard let mapped = transform.apply(q) else { return nil }
            return hypot(mapped.x - c.x, mapped.y - c.y) * 100.0
        }
        let meanErr = residuals.isEmpty ? nil : (residuals.reduce(0, +) / Double(residuals.count))

        let warpedContours: [WarpedPatternContour] = queryPatterns.compactMap { pat in
            let pts = pat.polygon.compactMap { transform.apply($0) }
            guard pts.count >= 3, let c = transform.apply(pat.centroid) else { return nil }
            return WarpedPatternContour(number: pat.number, polygon: pts, centroid: c)
        }

        return HumanAssistedAlignmentResult(
            status: status,
            anchorCount: anchors.count,
            transform: transform,
            meanResidualPercent: meanErr,
            warpedContours: warpedContours,
            orientationPreserved: orientationPreserved,
            anisotropyRatio: metrics.anisotropy
        )
    }
}

// MARK: - Real CoreImage Pixel-Registered Photographic Warper

/// Warps the actual Query photograph pixels into Candidate's exact coordinate frame using
/// `CIPerspectiveTransform` (handling both 3-point Affine and 4+ point Projective Homography),
/// enabling true pixel-locked Blink, Blend, and Curtain Split-Wipe visual verification.
nonisolated enum PhotoWarpRenderer {
    private static let sharedContext = CIContext(options: [.useSoftwareRenderer: false])

    static func renderWarpedQueryImage(
        queryCGImage: CGImage,
        candidatePixelSize: CGSize,
        transform: GeometricWarpTransform,
        maxDimension: CGFloat = 1100
    ) -> CGImage? {
        guard candidatePixelSize.width >= 16, candidatePixelSize.height >= 16 else { return nil }
        let scale = min(1.0, maxDimension / max(candidatePixelSize.width, candidatePixelSize.height))
        let outW = max(16, (candidatePixelSize.width * scale).rounded())
        let outH = max(16, (candidatePixelSize.height * scale).rounded())

        // Map the 4 normalized corners of Query into Candidate normalized top-left space.
        let srcCorners = [
            ScalePoint(x: 0, y: 0), // top-left
            ScalePoint(x: 1, y: 0), // top-right
            ScalePoint(x: 1, y: 1), // bottom-right
            ScalePoint(x: 0, y: 1), // bottom-left
        ]

        let mappedCorners: [ScalePoint]
        let projectiveCorners = srcCorners.compactMap { transform.apply($0) }
        let projectiveSafe = projectiveCorners.count == 4 && projectiveCorners.allSatisfy {
            abs($0.x) < 6.0 && abs($0.y) < 6.0
        }
        if projectiveSafe {
            mappedCorners = projectiveCorners
        } else {
            // Safe affine fallback if an outer image corner projects near the projective horizon.
            let aff = transform.fallbackAffine
            mappedCorners = srcCorners.map { aff.apply($0) }
        }

        func toCIVector(_ p: ScalePoint) -> CIVector {
            CIVector(x: CGFloat(p.x) * outW, y: CGFloat(1.0 - p.y) * outH)
        }

        let inputCI = CIImage(cgImage: queryCGImage)
        guard let filter = CIFilter(name: "CIPerspectiveTransform") else { return nil }
        filter.setValue(inputCI, forKey: kCIInputImageKey)
        filter.setValue(toCIVector(mappedCorners[0]), forKey: "inputTopLeft")
        filter.setValue(toCIVector(mappedCorners[1]), forKey: "inputTopRight")
        filter.setValue(toCIVector(mappedCorners[2]), forKey: "inputBottomRight")
        filter.setValue(toCIVector(mappedCorners[3]), forKey: "inputBottomLeft")

        guard let outputCI = filter.outputImage else { return nil }
        let outputRect = CGRect(x: 0, y: 0, width: outW, height: outH)
        return sharedContext.createCGImage(outputCI, from: outputRect)
    }

    @MainActor
    static func renderWarpedQueryNSImage(
        queryImage: NSImage,
        candidateImage: NSImage,
        transform: GeometricWarpTransform,
        maxDimension: CGFloat = 1100
    ) -> NSImage? {
        guard let qCG = queryImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let candSize: CGSize
        if let cCG = candidateImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            candSize = CGSize(width: cCG.width, height: cCG.height)
        } else {
            candSize = candidateImage.size
        }
        guard let warpedCG = renderWarpedQueryImage(
            queryCGImage: qCG,
            candidatePixelSize: candSize,
            transform: transform,
            maxDimension: maxDimension
        ) else { return nil }
        return NSImage(cgImage: warpedCG, size: NSSize(width: warpedCG.width, height: warpedCG.height))
    }
}
