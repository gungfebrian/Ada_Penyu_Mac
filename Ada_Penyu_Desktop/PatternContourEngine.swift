import AppKit
import CoreGraphics
import Foundation

// MARK: - Extracted Sea Turtle Scale Pattern Models

/// A single extracted anatomical facial scale pattern with smoothed contour geometry
/// and shape descriptors computed directly from image pixels inside the head ROI.
nonisolated struct DetectedScalePattern: Identifiable, Hashable, Codable, Sendable {
    var id: String { "scale-\(number)" }
    let number: Int
    /// Smooth closed contour vertices in normalized `[0, 1]` top-left image coordinates.
    let polygon: [ScalePoint]
    /// Area-weighted centroid in normalized `[0, 1]` image coordinates.
    let centroid: ScalePoint
    /// Scale area normalized by the ROI bounding area (zoom/crop invariant).
    let roiAreaFraction: Double
    /// Image-normalized area.
    let imageArea: Double
    /// Simplified anatomical corner count (e.g., 4-sided, 5-sided, 6-sided scute).
    let vertexCount: Int
    /// Isoperimetric quotient `4πA / P²` in `[0, 1]`.
    let circularity: Double
    /// Ratio of PCA major to minor axis (`>= 1.0`).
    let aspectRatio: Double
    /// Principal axis orientation in degrees `[-90, 90]`.
    let orientationDeg: Double
}

nonisolated struct ScaleMeshVertex: Identifiable, Hashable, Codable, Sendable {
    let id: Int
    var point: ScalePoint
    let isBoundary: Bool
}

nonisolated struct ScaleMeshEdge: Identifiable, Hashable, Codable, Sendable {
    let id: Int
    /// Ordered polyline vertex IDs connecting two topological junctions along one shared scale boundary.
    let vertexIDs: [Int]
    let leftCellNumber: Int
    let rightCellNumber: Int
    var isBoundary: Bool { leftCellNumber <= 0 || rightCellNumber <= 0 }
}

nonisolated struct ScaleMeshCell: Identifiable, Hashable, Codable, Sendable {
    var id: Int { number }
    let number: Int
    let center: ScalePoint
    let vertexIDs: [Int]
    let polygon: [ScalePoint]
    let roiAreaFraction: Double
    let imageArea: Double
    let vertexCount: Int
    let circularity: Double
    let aspectRatio: Double
    let orientationDeg: Double

    func asDetectedPattern() -> DetectedScalePattern {
        DetectedScalePattern(
            number: number,
            polygon: polygon,
            centroid: center,
            roiAreaFraction: roiAreaFraction,
            imageArea: imageArea,
            vertexCount: vertexCount,
            circularity: circularity,
            aspectRatio: aspectRatio,
            orientationDeg: orientationDeg
        )
    }
}

nonisolated struct ScaleSutureMesh: Equatable, Codable, Sendable {
    let vertices: [ScaleMeshVertex]
    let edges: [ScaleMeshEdge]
    let cells: [ScaleMeshCell]

    /// Recomputes edges & cell polygons if a user drags a junction vertex interactively.
    func movingVertex(id vertexID: Int, to newPoint: ScalePoint) -> ScaleSutureMesh {
        let clamped = ScalePoint(
            x: min(max(newPoint.x, 0.01), 0.99),
            y: min(max(newPoint.y, 0.01), 0.99)
        )
        let updatedVerts = vertices.map { v in
            v.id == vertexID ? ScaleMeshVertex(id: v.id, point: clamped, isBoundary: v.isBoundary) : v
        }
        let lookup = Dictionary(uniqueKeysWithValues: updatedVerts.map { ($0.id, $0.point) })
        let updatedCells: [ScaleMeshCell] = cells.map { cell in
            let pts = cell.vertexIDs.compactMap { lookup[$0] }
            guard pts.count >= 3 else { return cell }
            let area = abs(ScalePhotoReview.area(pts))
            let cx = pts.map(\.x).reduce(0, +) / Double(pts.count)
            let cy = pts.map(\.y).reduce(0, +) / Double(pts.count)
            return ScaleMeshCell(
                number: cell.number,
                center: ScalePoint(x: cx, y: cy),
                vertexIDs: cell.vertexIDs,
                polygon: pts,
                roiAreaFraction: cell.roiAreaFraction,
                imageArea: area,
                vertexCount: cell.vertexCount,
                circularity: cell.circularity,
                aspectRatio: cell.aspectRatio,
                orientationDeg: cell.orientationDeg
            )
        }
        return ScaleSutureMesh(vertices: updatedVerts, edges: edges, cells: updatedCells)
    }
}

nonisolated struct PatternExtractionConfig: Equatable, Sendable {
    /// Adaptive melanin-contrast sensitivity in `[0.1, 0.9]`. Higher includes fainter scales.
    var sensitivity: Double = 0.48
    /// Contour vector smoothness in `[0.0, 1.0]`.
    var smoothness: Double = 0.65
    /// Minimum scale area relative to ROI area.
    var minScaleROIFilter: Double = 0.0045
    /// Maximum single scale area relative to ROI area.
    var maxScaleROIFilter: Double = 0.22
}

// MARK: - Real Pattern-Only Scale Contour Segmentation Engine

/// Isolates and segments individual dark melanin scale patterns bounded by bright sutures
/// strictly inside a sea turtle facial ROI, tracing and smoothing each scale's contour.
nonisolated enum PatternContourEngine {
    /// Extracts numbered smooth scale pattern contours strictly inside `roiPolygon` (normalized `[0, 1]`).
    @MainActor
    static func extractPatterns(
        from image: NSImage,
        roiPolygon: [ScalePoint],
        config: PatternExtractionConfig = .init()
    ) -> [DetectedScalePattern] {
        guard let raster = underwaterLuminance(from: image, maxDimension: 420) else { return [] }
        return extractPatterns(from: raster, roiPolygon: roiPolygon, config: config)
    }

    static func extractPatterns(
        from raster: (pixels: [Float], width: Int, height: Int),
        roiPolygon: [ScalePoint],
        config: PatternExtractionConfig = .init()
    ) -> [DetectedScalePattern] {
        let w = raster.width
        let h = raster.height
        guard w >= 16, h >= 16, raster.pixels.count == w * h, roiPolygon.count >= 3, !Task.isCancelled else {
            return []
        }

        // 1. 5x5 separable Gaussian pre-smoothing to suppress water grain and JPEG artifacts
        let smoothed = gaussianSmooth5x5(raster.pixels, width: w, height: h)

        // 2. Scanline-rasterize ROI polygon into binary mask (O(H * V) instead of O(W * H * V))
        var insideROI = [Bool](repeating: false, count: w * h)
        var minPX = w - 1, minPY = h - 1, maxPX = 0, maxPY = 0
        var roiPixelCount = 0

        let polyYMin = roiPolygon.map(\.y).min() ?? 0
        let polyYMax = roiPolygon.map(\.y).max() ?? 1
        let startRow = max(0, Int(floor(polyYMin * Double(h))))
        let endRow = min(h - 1, Int(ceil(polyYMax * Double(h))))

        if endRow >= startRow {
            var xs = [Double]()
            xs.reserveCapacity(roiPolygon.count)
            for y in startRow...endRow {
                if Task.isCancelled { return [] }
                let ny = (Double(y) + 0.5) / Double(h)
                xs.removeAll(keepingCapacity: true)
                for i in roiPolygon.indices {
                    let a = roiPolygon[i]
                    let b = roiPolygon[(i + 1) % roiPolygon.count]
                    if (a.y > ny) != (b.y > ny) {
                        xs.append((b.x - a.x) * (ny - a.y) / (b.y - a.y) + a.x)
                    }
                }
                guard xs.count >= 2 else { continue }
                xs.sort()
                let rowOffset = y * w
                var k = 0
                while k + 1 < xs.count {
                    let x0 = max(0, Int(ceil(xs[k] * Double(w) - 0.5)))
                    let x1 = min(w - 1, Int(floor(xs[k + 1] * Double(w) - 0.5)))
                    if x1 >= x0 {
                        if x0 < minPX { minPX = x0 }
                        if x1 > maxPX { maxPX = x1 }
                        if y < minPY { minPY = y }
                        if y > maxPY { maxPY = y }
                        for x in x0...x1 {
                            insideROI[rowOffset + x] = true
                        }
                        roiPixelCount += (x1 - x0 + 1)
                    }
                    k += 2
                }
            }
        }

        guard roiPixelCount >= 64, maxPX > minPX + 6, maxPY > minPY + 6 else { return [] }

        // Erode ROI boundary slightly (2px) so scale contours don't glue to the outer ROI border
        var erodedROI = insideROI
        let margin = 2
        for y in max(margin, minPY)...min(h - 1 - margin, maxPY) {
            for x in max(margin, minPX)...min(w - 1 - margin, maxPX) {
                let idx = y * w + x
                guard insideROI[idx] else { continue }
                if !insideROI[(y - 2) * w + x] || !insideROI[(y + 2) * w + x]
                    || !insideROI[y * w + (x - 2)] || !insideROI[y * w + (x + 2)] {
                    erodedROI[idx] = false
                }
            }
        }

        // 3. Build Summed Area Tables (Integral Image) for O(1) multi-scale Sauvola local contrast
        let stride = w + 1
        var integral = [Double](repeating: 0, count: stride * (h + 1))
        var integralSq = [Double](repeating: 0, count: stride * (h + 1))
        for y in 0..<h {
            var rowSum = 0.0
            var rowSqSum = 0.0
            for x in 0..<w {
                let v = Double(smoothed[y * w + x])
                rowSum += v
                rowSqSum += v * v
                let dst = (y + 1) * stride + (x + 1)
                integral[dst] = integral[y * stride + (x + 1)] + rowSum
                integralSq[dst] = integralSq[y * stride + (x + 1)] + rowSqSum
            }
        }

        @inline(__always)
        func boxStats(_ cx: Int, _ cy: Int, _ r: Int) -> (mean: Double, std: Double) {
            let x0 = max(0, cx - r)
            let y0 = max(0, cy - r)
            let x1 = min(w - 1, cx + r)
            let y1 = min(h - 1, cy + r)
            let area = Double((x1 - x0 + 1) * (y1 - y0 + 1))
            let sum = integral[(y1 + 1) * stride + (x1 + 1)]
                - integral[y0 * stride + (x1 + 1)]
                - integral[(y1 + 1) * stride + x0]
                + integral[y0 * stride + x0]
            let sq = integralSq[(y1 + 1) * stride + (x1 + 1)]
                - integralSq[y0 * stride + (x1 + 1)]
                - integralSq[(y1 + 1) * stride + x0]
                + integralSq[y0 * stride + x0]
            let mean = sum / area
            let variance = max(0.0, (sq / area) - mean * mean)
            return (mean, sqrt(variance))
        }

        let roiSpan = min(maxPX - minPX, maxPY - minPY)
        let rMacro = max(12, min(48, Int(Double(roiSpan) * 0.14)))
        let rMicro = max(3, min(11, Int(Double(roiSpan) * 0.035)))

        // Map slider sensitivity [0.1..0.9] -> adaptive contrast thresholds
        let sens = min(0.92, max(0.08, config.sensitivity))
        let kScale = 0.42 - sens * 0.34         // higher sensitivity -> lower k -> picks lighter scales
        let minContrast = 0.048 - sens * 0.036  // minimum absolute intensity drop vs neighborhood

        // 4. Segment dark scale cores while enforcing bright inter-scale suture barriers
        var mask = [Bool](repeating: false, count: w * h)
        for y in minPY...maxPY {
            if Task.isCancelled { return [] }
            for x in minPX...maxPX {
                let idx = y * w + x
                guard erodedROI[idx] else { continue }
                let val = Double(smoothed[idx])
                let macro = boxStats(x, y, rMacro)
                let micro = boxStats(x, y, rMicro)

                let drop = macro.mean - val
                let requiredDrop = max(minContrast, kScale * max(macro.std, 0.03))
                let isRidgeSuture = (val - micro.mean) > 0.014
                let isSpecularGlare = val > macro.mean + 0.12

                if drop >= requiredDrop && !isRidgeSuture && !isSpecularGlare {
                    mask[idx] = true
                }
            }
        }

        // 5. Morphological opening (separates thin touching bridges) + small glare-speck hole fill
        mask = morphOpen3x3(mask, width: w, height: h, minX: minPX, maxX: maxPX, minY: minPY, maxY: maxPY, validMask: erodedROI)
        fillSmallHoles(&mask, width: w, height: h, minX: minPX, maxX: maxPX, minY: minPY, maxY: maxPY, maxHolePixels: max(18, roiPixelCount / 180))

        // 6. Connected components extraction & vector contour smoothing
        let minComponentPx = max(16, Int(Double(roiPixelCount) * config.minScaleROIFilter))
        let maxComponentPx = max(minComponentPx + 20, Int(Double(roiPixelCount) * config.maxScaleROIFilter))

        var labels = [Int](repeating: 0, count: w * h)
        var currentLabel = 0

        struct RawScale {
            let polygon: [ScalePoint]
            let centroid: ScalePoint
            let imageArea: Double
            let roiAreaFraction: Double
            let vertexCount: Int
            let circularity: Double
            let aspectRatio: Double
            let orientationDeg: Double
        }

        var extracted: [RawScale] = []
        let roiNormalizedArea = max(1e-5, Double(roiPixelCount) / Double(w * h))

        for y in minPY...maxPY {
            if Task.isCancelled { return [] }
            for x in minPX...maxPX {
                let seed = y * w + x
                guard mask[seed], labels[seed] == 0 else { continue }
                currentLabel += 1
                var queue = [seed]
                var cursor = 0
                labels[seed] = currentLabel

                var compMinX = x, compMaxX = x, compMinY = y, compMaxY = y
                while cursor < queue.count {
                    let p = queue[cursor]; cursor += 1
                    let px = p % w, py = p / w
                    if px < compMinX { compMinX = px }
                    if px > compMaxX { compMaxX = px }
                    if py < compMinY { compMinY = py }
                    if py > compMaxY { compMaxY = py }

                    if px > minPX {
                        let next = py * w + (px - 1)
                        if mask[next], labels[next] == 0 { labels[next] = currentLabel; queue.append(next) }
                    }
                    if px < maxPX {
                        let next = py * w + (px + 1)
                        if mask[next], labels[next] == 0 { labels[next] = currentLabel; queue.append(next) }
                    }
                    if py > minPY {
                        let next = (py - 1) * w + px
                        if mask[next], labels[next] == 0 { labels[next] = currentLabel; queue.append(next) }
                    }
                    if py < maxPY {
                        let next = (py + 1) * w + px
                        if mask[next], labels[next] == 0 { labels[next] = currentLabel; queue.append(next) }
                    }
                }

                guard queue.count >= minComponentPx, queue.count <= maxComponentPx else { continue }

                // Reject degenerate hair-thin streaks across wide spans
                let bw = max(1, compMaxX - compMinX + 1)
                let bh = max(1, compMaxY - compMinY + 1)
                let fillRatio = Double(queue.count) / Double(bw * bh)
                guard fillRatio >= 0.22 else { continue }

                // Trace exact closed outer boundary polygon
                let normalizedRaw = traceOuterPolygon(
                    componentPixels: queue,
                    labels: labels,
                    targetLabel: currentLabel,
                    width: w,
                    height: h
                )
                guard normalizedRaw.count >= 4 else { continue }

                // Simplify pixel stair-steps using Douglas-Peucker
                let dpEpsilon = 0.0022 + config.smoothness * 0.0028
                let simplified = douglasPeuckerClosed(normalizedRaw, epsilon: dpEpsilon)
                guard simplified.count >= 3 else { continue }

                let cornerCount = anatomicalCornerCount(simplified)

                // Smooth curved contour via Chaikin passes based on smoothness setting
                let chaikinPasses = config.smoothness >= 0.72 ? 2 : (config.smoothness >= 0.28 ? 1 : 0)
                let smoothPoly = chaikinPasses > 0 ? chaikinSmooth(simplified, passes: chaikinPasses) : simplified
                guard smoothPoly.count >= 3 else { continue }

                let area = abs(ScalePhotoReview.area(smoothPoly))
                guard area > 1e-5 else { continue }
                let perim = perimeter(of: smoothPoly)
                guard perim > 1e-4 else { continue }

                let circularity = min(1.0, (4.0 * .pi * area) / (perim * perim))
                guard circularity >= 0.16 else { continue }

                let moments = polygonMoments(smoothPoly)
                extracted.append(
                    RawScale(
                        polygon: smoothPoly,
                        centroid: moments.centroid,
                        imageArea: area,
                        roiAreaFraction: area / roiNormalizedArea,
                        vertexCount: cornerCount,
                        circularity: circularity,
                        aspectRatio: moments.aspectRatio,
                        orientationDeg: moments.orientationDeg
                    )
                )
            }
        }

        // 7. Sort deterministically top-to-bottom (row bands), left-to-right for human numbering (1, 2, 3...)
        let sorted = extracted.sorted { a, b in
            let bandA = Int((a.centroid.y * 14.0).rounded())
            let bandB = Int((b.centroid.y * 14.0).rounded())
            return bandA == bandB ? a.centroid.x < b.centroid.x : bandA < bandB
        }

        return Array(sorted.prefix(36).enumerated().map { idx, raw in
            DetectedScalePattern(
                number: idx + 1,
                polygon: raw.polygon,
                centroid: raw.centroid,
                roiAreaFraction: raw.roiAreaFraction,
                imageArea: raw.imageArea,
                vertexCount: raw.vertexCount,
                circularity: raw.circularity,
                aspectRatio: raw.aspectRatio,
                orientationDeg: raw.orientationDeg
            )
        })
    }

    // MARK: - Automatic Real Facial Pattern ROI Detector

    /// Automatically locates the dense cluster of reticulated sea turtle head scales in any photo
    /// rather than placing a hardcoded rectangle, returning the cheek polygon & initial anatomical refs.
    @MainActor
    static func detectFacialPatternROI(
        from image: NSImage,
        side: TurtlePhotoSide
    ) -> (roi: [ScalePoint], ref1: ScalePoint, ref2: ScalePoint, ref3: ScalePoint) {
        guard let raster = underwaterLuminance(from: image, maxDimension: 360) else {
            return fallbackTemplate(side: side)
        }
        return detectFacialPatternROI(from: raster, side: side)
    }

    static func detectFacialPatternROI(
        from raster: (pixels: [Float], width: Int, height: Int),
        side: TurtlePhotoSide
    ) -> (roi: [ScalePoint], ref1: ScalePoint, ref2: ScalePoint, ref3: ScalePoint) {
        let searchROI = [
            ScalePoint(x: 0.08, y: 0.06),
            ScalePoint(x: 0.92, y: 0.06),
            ScalePoint(x: 0.92, y: 0.92),
            ScalePoint(x: 0.08, y: 0.92),
        ]

        let candidates = extractPatterns(
            from: raster,
            roiPolygon: searchROI,
            config: PatternExtractionConfig(
                sensitivity: 0.45,
                smoothness: 0.5,
                minScaleROIFilter: 0.0008,
                maxScaleROIFilter: 0.045
            )
        ).filter { $0.circularity >= 0.34 && $0.aspectRatio <= 3.6 }

        guard candidates.count >= 4 else {
            return fallbackTemplate(side: side)
        }

        // Find the scale blob with highest spatial density of nearby sibling scales (excludes scattered seagrass/sand)
        let neighborRadius = 0.24
        var bestAnchor = candidates[0]
        var bestDensityScore = -1.0
        for cand in candidates {
            let neighborWeights = candidates.reduce(0.0) { acc, other in
                let dist = hypot(cand.centroid.x - other.centroid.x, cand.centroid.y - other.centroid.y)
                guard dist <= neighborRadius else { return acc }
                return acc + other.circularity * (1.0 - dist / (neighborRadius * 1.2))
            }
            if neighborWeights > bestDensityScore {
                bestDensityScore = neighborWeights
                bestAnchor = cand
            }
        }

        // Gather all clustered scale vertices belonging to the facial region around the densest cluster
        var clusterPoints: [ScalePoint] = []
        for pat in candidates {
            let dist = hypot(pat.centroid.x - bestAnchor.centroid.x, pat.centroid.y - bestAnchor.centroid.y)
            if dist <= 0.30 {
                clusterPoints.append(contentsOf: pat.polygon)
            }
        }

        guard clusterPoints.count >= 6 else {
            return fallbackTemplate(side: side)
        }

        let minX = max(0.04, (clusterPoints.map(\.x).min() ?? 0.25) - 0.03)
        let maxX = min(0.96, (clusterPoints.map(\.x).max() ?? 0.75) + 0.03)
        let minY = max(0.04, (clusterPoints.map(\.y).min() ?? 0.20) - 0.03)
        let maxY = min(0.96, (clusterPoints.map(\.y).max() ?? 0.75) + 0.03)

        let hull = paddedConvexHull(points: clusterPoints, padding: 0.03)
        let roi = hull.count >= 4 ? hull : [
            ScalePoint(x: minX, y: minY),
            ScalePoint(x: maxX, y: minY),
            ScalePoint(x: maxX, y: maxY),
            ScalePoint(x: minX, y: maxY),
        ]

        let cx = (minX + maxX) * 0.5
        let cy = (minY + maxY) * 0.5
        let w = maxX - minX
        let h = maxY - minY

        let ref1: ScalePoint
        let ref2: ScalePoint
        let ref3: ScalePoint
        if side == .left {
            // Left profile: snout/eye toward lower-left / top-left, ear toward right of ROI
            ref1 = ScalePoint(x: max(0.03, minX - w * 0.14), y: min(0.96, maxY + h * 0.08))
            ref2 = ScalePoint(x: max(0.04, cx - w * 0.38), y: max(0.04, cy - h * 0.15))
            ref3 = ScalePoint(x: min(0.96, maxX + w * 0.02), y: max(0.05, minY + h * 0.15))
        } else {
            ref1 = ScalePoint(x: min(0.97, maxX + w * 0.14), y: min(0.96, maxY + h * 0.08))
            ref2 = ScalePoint(x: min(0.96, cx + w * 0.38), y: max(0.04, cy - h * 0.15))
            ref3 = ScalePoint(x: max(0.04, minX - w * 0.02), y: max(0.05, minY + h * 0.15))
        }

        return (roi, ref1, ref2, ref3)
    }

    private static func fallbackTemplate(side: TurtlePhotoSide) -> (roi: [ScalePoint], ref1: ScalePoint, ref2: ScalePoint, ref3: ScalePoint) {
        if side == .left {
            return (
                roi: [
                    ScalePoint(x: 0.34, y: 0.30), ScalePoint(x: 0.54, y: 0.24),
                    ScalePoint(x: 0.74, y: 0.32), ScalePoint(x: 0.76, y: 0.62),
                    ScalePoint(x: 0.52, y: 0.68), ScalePoint(x: 0.32, y: 0.56),
                ],
                ref1: ScalePoint(x: 0.20, y: 0.58),
                ref2: ScalePoint(x: 0.34, y: 0.36),
                ref3: ScalePoint(x: 0.74, y: 0.42)
            )
        } else {
            return (
                roi: [
                    ScalePoint(x: 0.66, y: 0.30), ScalePoint(x: 0.46, y: 0.24),
                    ScalePoint(x: 0.26, y: 0.32), ScalePoint(x: 0.24, y: 0.62),
                    ScalePoint(x: 0.48, y: 0.68), ScalePoint(x: 0.68, y: 0.56),
                ],
                ref1: ScalePoint(x: 0.80, y: 0.58),
                ref2: ScalePoint(x: 0.66, y: 0.36),
                ref3: ScalePoint(x: 0.26, y: 0.42)
            )
        }
    }

    // MARK: - Raster & Geometry Primitives

    /// I3S underwater-tuned luminance `(0.10*R + 0.60*G + 0.30*B)` preserving scale/suture contrast.
    @MainActor
    static func underwaterLuminance(from image: NSImage, maxDimension: Int = 640) -> (pixels: [Float], width: Int, height: Int)? {
        guard maxDimension >= 16, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let scale = min(1.0, Double(maxDimension) / Double(max(cg.width, cg.height)))
        let width = max(16, Int((Double(cg.width) * scale).rounded()))
        let height = max(16, Int((Double(cg.height) * scale).rounded()))
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .high
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var pixels = [Float](repeating: 0, count: width * height)
        for i in 0..<(width * height) {
            let r = Float(bytes[i * 4])
            let g = Float(bytes[i * 4 + 1])
            let b = Float(bytes[i * 4 + 2])
            pixels[i] = (0.10 * r + 0.60 * g + 0.30 * b) / 255.0
        }
        return (pixels, width, height)
    }

    private static func gaussianSmooth5x5(_ input: [Float], width: Int, height: Int) -> [Float] {
        var horiz = [Float](repeating: 0, count: input.count)
        let weights: [Float] = [1, 4, 6, 4, 1]
        for y in 0..<height {
            let row = y * width
            for x in 0..<width {
                var sum: Float = 0
                for k in -2...2 {
                    let sx = min(width - 1, max(0, x + k))
                    sum += input[row + sx] * weights[k + 2]
                }
                horiz[row + x] = sum / 16.0
            }
        }
        var out = [Float](repeating: 0, count: input.count)
        for y in 0..<height {
            for x in 0..<width {
                var sum: Float = 0
                for k in -2...2 {
                    let sy = min(height - 1, max(0, y + k))
                    sum += horiz[sy * width + x] * weights[k + 2]
                }
                out[y * width + x] = sum / 16.0
            }
        }
        return out
    }

    private static func morphOpen3x3(
        _ mask: [Bool],
        width: Int,
        height: Int,
        minX: Int,
        maxX: Int,
        minY: Int,
        maxY: Int,
        validMask: [Bool]
    ) -> [Bool] {
        var eroded = [Bool](repeating: false, count: mask.count)
        for y in max(1, minY)...min(height - 2, maxY) {
            for x in max(1, minX)...min(width - 2, maxX) {
                let idx = y * width + x
                guard mask[idx] else { continue }
                if mask[idx - 1] && mask[idx + 1] && mask[idx - width] && mask[idx + width] {
                    eroded[idx] = true
                }
            }
        }
        var dilated = eroded
        for y in max(1, minY)...min(height - 2, maxY) {
            for x in max(1, minX)...min(width - 2, maxX) {
                let idx = y * width + x
                guard eroded[idx] else { continue }
                if validMask[idx - 1] { dilated[idx - 1] = true }
                if validMask[idx + 1] { dilated[idx + 1] = true }
                if validMask[idx - width] { dilated[idx - width] = true }
                if validMask[idx + width] { dilated[idx + width] = true }
            }
        }
        return dilated
    }

    private static func fillSmallHoles(
        _ mask: inout [Bool],
        width: Int,
        height: Int,
        minX: Int,
        maxX: Int,
        minY: Int,
        maxY: Int,
        maxHolePixels: Int
    ) {
        var visited = [Bool](repeating: false, count: mask.count)
        for y in minY...maxY {
            for x in minX...maxX {
                let seed = y * width + x
                guard !mask[seed], !visited[seed] else { continue }
                var queue = [seed]
                var cursor = 0
                var hitsBoxBorder = false
                visited[seed] = true
                while cursor < queue.count {
                    let p = queue[cursor]; cursor += 1
                    let px = p % width, py = p / width
                    if px == minX || px == maxX || py == minY || py == maxY {
                        hitsBoxBorder = true
                    }
                    if px > minX {
                        let next = py * width + (px - 1)
                        if !mask[next], !visited[next] { visited[next] = true; queue.append(next) }
                    }
                    if px < maxX {
                        let next = py * width + (px + 1)
                        if !mask[next], !visited[next] { visited[next] = true; queue.append(next) }
                    }
                    if py > minY {
                        let next = (py - 1) * width + px
                        if !mask[next], !visited[next] { visited[next] = true; queue.append(next) }
                    }
                    if py < maxY {
                        let next = (py + 1) * width + px
                        if !mask[next], !visited[next] { visited[next] = true; queue.append(next) }
                    }
                }
                if !hitsBoxBorder && queue.count <= maxHolePixels {
                    for p in queue { mask[p] = true }
                }
            }
        }
    }

    /// Walks directed boundary cracks around `componentPixels` and returns the largest closed outer polygon.
    private static func traceOuterPolygon(
        componentPixels: [Int],
        labels: [Int],
        targetLabel: Int,
        width: Int,
        height: Int
    ) -> [ScalePoint] {
        let stride = width + 1
        var links: [Int: [Int]] = [:]
        @inline(__always) func addEdge(_ a: Int, _ b: Int) { links[a, default: []].append(b) }
        for p in componentPixels {
            let px = p % width, py = p / width, v = py * stride + px
            if py == 0 || labels[p - width] != targetLabel { addEdge(v, v + 1) }
            if px == width - 1 || labels[p + 1] != targetLabel { addEdge(v + 1, v + 1 + stride) }
            if py == height - 1 || labels[p + width] != targetLabel { addEdge(v + 1 + stride, v + stride) }
            if px == 0 || labels[p - 1] != targetLabel { addEdge(v + stride, v) }
        }
        var loops: [[ScalePoint]] = []
        while let start = links.keys.min() {
            var current = start
            var vertices: [Int] = []
            var closed = false
            while let next = links[current]?.popLast() {
                if links[current]?.isEmpty == true { links.removeValue(forKey: current) }
                vertices.append(current)
                current = next
                if current == start { closed = true; break }
                if vertices.count > componentPixels.count * 4 { break }
            }
            if closed, vertices.count >= 3 {
                let pts: [ScalePoint] = vertices.indices.filter { i in
                    let prev = vertices[(i + vertices.count - 1) % vertices.count]
                    let curr = vertices[i]
                    let next = vertices[(i + 1) % vertices.count]
                    return (curr - prev) != (next - curr)
                }.map { idx in
                    let v = vertices[idx]
                    return ScalePoint(x: Double(v % stride) / Double(width), y: Double(v / stride) / Double(height))
                }
                if pts.count >= 3 {
                    loops.append(pts)
                }
            }
        }
        return loops.max(by: { abs(ScalePhotoReview.area($0)) < abs(ScalePhotoReview.area($1)) }) ?? []
    }

    private static func douglasPeuckerClosed(_ points: [ScalePoint], epsilon: Double) -> [ScalePoint] {
        guard points.count > 4 else { return points }
        // Split at farthest pair along the loop so closure preserves corners cleanly
        var maxDist = -1.0
        var splitIdx = points.count / 2
        let p0 = points[0]
        for i in 1..<points.count {
            let d = hypot(points[i].x - p0.x, points[i].y - p0.y)
            if d > maxDist { maxDist = d; splitIdx = i }
        }
        let firstHalf = douglasPeuckerOpen(Array(points[0...splitIdx]), epsilon: epsilon)
        let secondHalf = douglasPeuckerOpen(Array(points[splitIdx..<points.count]) + [points[0]], epsilon: epsilon)
        var combined = firstHalf
        if secondHalf.count > 2 {
            combined.append(contentsOf: secondHalf.dropFirst().dropLast())
        }
        return combined.count >= 3 ? combined : points
    }

    private static func douglasPeuckerOpen(_ points: [ScalePoint], epsilon: Double) -> [ScalePoint] {
        guard points.count >= 3, let first = points.first, let last = points.last else { return points }
        var maxD = 0.0
        var index = 0
        for i in 1..<(points.count - 1) {
            let d = perpendicularDistance(points[i], lineStart: first, lineEnd: last)
            if d > maxD { maxD = d; index = i }
        }
        if maxD > epsilon {
            let left = douglasPeuckerOpen(Array(points[0...index]), epsilon: epsilon)
            let right = douglasPeuckerOpen(Array(points[index..<points.count]), epsilon: epsilon)
            return Array(left.dropLast()) + right
        }
        return [first, last]
    }

    private static func perpendicularDistance(_ p: ScalePoint, lineStart a: ScalePoint, lineEnd b: ScalePoint) -> Double {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let mag = hypot(dx, dy)
        guard mag > 1e-12 else { return hypot(p.x - a.x, p.y - a.y) }
        return abs(dy * p.x - dx * p.y + b.x * a.y - b.y * a.x) / mag
    }

    private static func chaikinSmooth(_ points: [ScalePoint], passes: Int) -> [ScalePoint] {
        var poly = points
        for _ in 0..<passes {
            guard poly.count >= 3, poly.count < 80 else { break }
            var next: [ScalePoint] = []
            next.reserveCapacity(poly.count * 2)
            for i in poly.indices {
                let a = poly[i]
                let b = poly[(i + 1) % poly.count]
                next.append(ScalePoint(x: 0.75 * a.x + 0.25 * b.x, y: 0.75 * a.y + 0.25 * b.y))
                next.append(ScalePoint(x: 0.25 * a.x + 0.75 * b.x, y: 0.25 * a.y + 0.75 * b.y))
            }
            poly = next
        }
        return poly
    }

    private static func anatomicalCornerCount(_ poly: [ScalePoint]) -> Int {
        guard poly.count >= 3 else { return poly.count }
        var corners = 0
        for i in poly.indices {
            let prev = poly[(i + poly.count - 1) % poly.count]
            let curr = poly[i]
            let next = poly[(i + 1) % poly.count]
            let v1x = curr.x - prev.x, v1y = curr.y - prev.y
            let v2x = next.x - curr.x, v2y = next.y - curr.y
            let l1 = hypot(v1x, v1y), l2 = hypot(v2x, v2y)
            guard l1 > 1e-6, l2 > 1e-6 else { continue }
            let cosAngle = max(-1.0, min(1.0, (v1x * v2x + v1y * v2y) / (l1 * l2)))
            let turnAngle = acos(cosAngle)
            if turnAngle > 0.34 { corners += 1 } // ~20 degree bend counts as anatomical scute corner
        }
        return max(3, corners)
    }

    private static func perimeter(of poly: [ScalePoint]) -> Double {
        guard poly.count >= 2 else { return 0 }
        return poly.indices.reduce(0.0) { acc, i in
            let a = poly[i], b = poly[(i + 1) % poly.count]
            return acc + hypot(b.x - a.x, b.y - a.y)
        }
    }

    private static func polygonMoments(_ poly: [ScalePoint]) -> (centroid: ScalePoint, aspectRatio: Double, orientationDeg: Double) {
        guard poly.count >= 3 else {
            return (ScalePoint(x: 0.5, y: 0.5), 1.0, 0.0)
        }
        var signedArea2 = 0.0
        var cxAcc = 0.0
        var cyAcc = 0.0
        for i in poly.indices {
            let a = poly[i], b = poly[(i + 1) % poly.count]
            let cross = a.x * b.y - b.x * a.y
            signedArea2 += cross
            cxAcc += (a.x + b.x) * cross
            cyAcc += (a.y + b.y) * cross
        }
        let centroid: ScalePoint
        if abs(signedArea2) > 1e-10 {
            centroid = ScalePoint(x: cxAcc / (3.0 * signedArea2), y: cyAcc / (3.0 * signedArea2))
        } else {
            let n = Double(poly.count)
            centroid = ScalePoint(x: poly.map(\.x).reduce(0, +) / n, y: poly.map(\.y).reduce(0, +) / n)
        }

        // Covariance of vertices around centroid -> PCA aspect ratio & orientation
        var mxx = 0.0, myy = 0.0, mxy = 0.0
        for p in poly {
            let dx = p.x - centroid.x
            let dy = p.y - centroid.y
            mxx += dx * dx
            myy += dy * dy
            mxy += dx * dy
        }
        let n = Double(poly.count)
        mxx /= n; myy /= n; mxy /= n
        let trace = mxx + myy
        let diff = mxx - myy
        let root = sqrt(max(0.0, diff * diff + 4.0 * mxy * mxy))
        let eigMax = max(1e-10, (trace + root) * 0.5)
        let eigMin = max(1e-10, (trace - root) * 0.5)
        let aspect = min(8.0, sqrt(eigMax / eigMin))
        let angleDeg = 0.5 * atan2(2.0 * mxy, diff) * 180.0 / .pi
        return (centroid, aspect, angleDeg)
    }

    private static func paddedConvexHull(points: [ScalePoint], padding: Double) -> [ScalePoint] {
        guard points.count >= 3 else { return points }
        let sorted = points.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        func cross(_ o: ScalePoint, _ a: ScalePoint, _ b: ScalePoint) -> Double {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }
        var lower: [ScalePoint] = []
        for p in sorted {
            while lower.count >= 2 && cross(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 {
                lower.removeLast()
            }
            lower.append(p)
        }
        var upper: [ScalePoint] = []
        for p in sorted.reversed() {
            while upper.count >= 2 && cross(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 {
                upper.removeLast()
            }
            upper.append(p)
        }
        lower.removeLast()
        upper.removeLast()
        let hull = lower + upper
        guard hull.count >= 3 else { return points }
        let cx = hull.map(\.x).reduce(0, +) / Double(hull.count)
        let cy = hull.map(\.y).reduce(0, +) / Double(hull.count)
        return hull.map { pt in
            let vx = pt.x - cx, vy = pt.y - cy
            let d = max(1e-5, hypot(vx, vy))
            return ScalePoint(
                x: min(0.97, max(0.03, pt.x + (vx / d) * padding)),
                y: min(0.97, max(0.03, pt.y + (vy / d) * padding))
            )
        }
    }

    // MARK: - Polygonal Scale Suture Mesh Extraction (Watershed along Pale Keratin Sutures)

    /// Segments the entire facial ROI into a watertight polygonal scute mosaic whose edges trace
    /// the bright keratin sutures dividing neighboring sea turtle scales, meeting cleanly at shared junctions.
    @MainActor
    static func extractScaleSutureMesh(
        from image: NSImage,
        roiPolygon: [ScalePoint],
        patterns: [DetectedScalePattern]? = nil,
        config: PatternExtractionConfig = .init()
    ) -> ScaleSutureMesh {
        guard let raster = underwaterLuminance(from: image, maxDimension: 360) else {
            return ScaleSutureMesh(vertices: [], edges: [], cells: [])
        }
        return extractScaleSutureMesh(from: raster, roiPolygon: roiPolygon, patterns: patterns, config: config)
    }

    static func extractScaleSutureMesh(
        from raster: (pixels: [Float], width: Int, height: Int),
        roiPolygon: [ScalePoint],
        patterns: [DetectedScalePattern]? = nil,
        config: PatternExtractionConfig = .init()
    ) -> ScaleSutureMesh {
        let w = raster.width
        let h = raster.height
        guard w >= 16, h >= 16, raster.pixels.count == w * h, roiPolygon.count >= 3, !Task.isCancelled else {
            return ScaleSutureMesh(vertices: [], edges: [], cells: [])
        }

        let smoothed = gaussianSmooth5x5(raster.pixels, width: w, height: h)

        // 1. Scanline-rasterize ROI polygon
        var insideROI = [Bool](repeating: false, count: w * h)
        var minPX = w - 1, minPY = h - 1, maxPX = 0, maxPY = 0
        var roiPixelCount = 0
        let polyYMin = roiPolygon.map(\.y).min() ?? 0
        let polyYMax = roiPolygon.map(\.y).max() ?? 1
        let startRow = max(0, Int(floor(polyYMin * Double(h))))
        let endRow = min(h - 1, Int(ceil(polyYMax * Double(h))))
        if endRow >= startRow {
            var xs = [Double]()
            xs.reserveCapacity(roiPolygon.count)
            for y in startRow...endRow {
                let ny = (Double(y) + 0.5) / Double(h)
                xs.removeAll(keepingCapacity: true)
                for i in roiPolygon.indices {
                    let a = roiPolygon[i]
                    let b = roiPolygon[(i + 1) % roiPolygon.count]
                    if (a.y <= ny && b.y > ny) || (b.y <= ny && a.y > ny) {
                        let t = (ny - a.y) / (b.y - a.y)
                        xs.append(a.x + t * (b.x - a.x))
                    }
                }
                guard xs.count >= 2 else { continue }
                xs.sort()
                var k = 0
                while k + 1 < xs.count {
                    let x0 = max(0, Int(ceil(xs[k] * Double(w) - 0.5)))
                    let x1 = min(w - 1, Int(floor(xs[k + 1] * Double(w) - 0.5)))
                    if x1 >= x0 {
                        let rowBase = y * w
                        for x in x0...x1 {
                            insideROI[rowBase + x] = true
                            if x < minPX { minPX = x }
                            if x > maxPX { maxPX = x }
                            if y < minPY { minPY = y }
                            if y > maxPY { maxPY = y }
                            roiPixelCount += 1
                        }
                    }
                    k += 2
                }
            }
        }
        guard roiPixelCount >= 36, maxPX > minPX, maxPY > minPY else {
            return ScaleSutureMesh(vertices: [], edges: [], cells: [])
        }

        // Compute normalized luminance range strictly inside ROI for ridge flooding
        var minL = Float.greatestFiniteMagnitude
        var maxL = -Float.greatestFiniteMagnitude
        for y in minPY...maxPY {
            let row = y * w
            for x in minPX...maxPX where insideROI[row + x] {
                let v = smoothed[row + x]
                if v < minL { minL = v }
                if v > maxL { maxL = v }
            }
        }
        let spanL = max(Float(0.03), maxL - minL)
        let roiNormalizedArea = max(1e-5, Double(roiPixelCount) / Double(w * h))
        let roiDiag = max(0.08, hypot(Double(maxPX - minPX) / Double(w), Double(maxPY - minPY) / Double(h)))

        // 2. Collect dark scute seeds from detected ink patterns + local dark minima for crowded cheek clusters
        let basePatterns = patterns ?? extractPatterns(from: raster, roiPolygon: roiPolygon, config: config)
        var seedCenters: [ScalePoint] = basePatterns.map(\.centroid)
        let minSeedSep = max(0.045, roiDiag * 0.115)

        if seedCenters.count < 10 {
            let step = max(3, min(maxPX - minPX, maxPY - minPY) / 14)
            var candidates: [(pt: ScalePoint, lum: Float)] = []
            var yy = minPY + 2
            while yy <= maxPY - 2 {
                var xx = minPX + 2
                while xx <= maxPX - 2 {
                    let p = yy * w + xx
                    if insideROI[p] {
                        let centerLum = smoothed[p]
                        var isLocalMin = centerLum < minL + spanL * 0.62
                        if isLocalMin {
                            for dy in -2...2 where isLocalMin {
                                for dx in -2...2 {
                                    let q = (yy + dy) * w + (xx + dx)
                                    if smoothed[q] + 0.004 < centerLum {
                                        isLocalMin = false
                                        break
                                    }
                                }
                            }
                        }
                        if isLocalMin {
                            let npt = ScalePoint(x: (Double(xx) + 0.5) / Double(w), y: (Double(yy) + 0.5) / Double(h))
                            candidates.append((npt, centerLum))
                        }
                    }
                    xx += step
                }
                yy += step
            }
            candidates.sort { $0.lum < $1.lum }
            for cand in candidates {
                if seedCenters.count >= 28 { break }
                if seedCenters.allSatisfy({ hypot($0.x - cand.pt.x, $0.y - cand.pt.y) >= minSeedSep }) {
                    seedCenters.append(cand.pt)
                }
            }
        }

        // Order deterministically top-to-bottom, left-to-right so scute #1, #2, ... match Ink Contours
        seedCenters.sort { a, b in
            let bandA = Int((a.y * 14.0).rounded())
            let bandB = Int((b.y * 14.0).rounded())
            return bandA == bandB ? a.x < b.x : bandA < bandB
        }
        guard seedCenters.count >= 2 else {
            return ScaleSutureMesh(vertices: [], edges: [], cells: [])
        }

        // 3. Hierarchical Bucketed Watershed flooded from scale centers -> regions meet along pale sutures!
        var regionLabel = [Int](repeating: 0, count: w * h)
        var depthMap = [Int](repeating: 0, count: w * h)
        var buckets = [[Int]](repeating: [], count: 256)
        var nonEmptyMinBucket = 256

        for (idx, seed) in seedCenters.enumerated() {
            let sx = min(maxPX, max(minPX, Int((seed.x * Double(w)).rounded())))
            let sy = min(maxPY, max(minPY, Int((seed.y * Double(h)).rounded())))
            // Snap to nearest in-ROI pixel within small radius
            var bestIdx = -1
            var bestLum = Float.greatestFiniteMagnitude
            for dy in -2...2 {
                let ny = sy + dy
                guard ny >= minPY, ny <= maxPY else { continue }
                for dx in -2...2 {
                    let nx = sx + dx
                    guard nx >= minPX, nx <= maxPX else { continue }
                    let q = ny * w + nx
                    if insideROI[q] && smoothed[q] < bestLum {
                        bestLum = smoothed[q]
                        bestIdx = q
                    }
                }
            }
            guard bestIdx >= 0, regionLabel[bestIdx] == 0 else { continue }
            let seedID = idx + 1
            regionLabel[bestIdx] = seedID
            let normBright = min(Float(1.0), max(Float(0.0), (smoothed[bestIdx] - minL) / spanL))
            let b = min(255, max(0, Int(normBright * 180.0)))
            buckets[b].append(bestIdx)
            if b < nonEmptyMinBucket { nonEmptyMinBucket = b }
        }

        while nonEmptyMinBucket < 256 {
            if buckets[nonEmptyMinBucket].isEmpty {
                nonEmptyMinBucket += 1
                continue
            }
            if Task.isCancelled { return ScaleSutureMesh(vertices: [], edges: [], cells: []) }
            let p = buckets[nonEmptyMinBucket].removeLast()
            let px = p % w
            let py = p / w
            let lbl = regionLabel[p]
            let nextDepth = depthMap[p] + 1

            let neighbors = [
                px > minPX ? p - 1 : -1,
                px < maxPX ? p + 1 : -1,
                py > minPY ? p - w : -1,
                py < maxPY ? p + w : -1,
            ]
            for nb in neighbors where nb >= 0 && insideROI[nb] && regionLabel[nb] == 0 {
                regionLabel[nb] = lbl
                depthMap[nb] = nextDepth
                let normBright = min(Double(1.0), max(Double(0.0), Double((smoothed[nb] - minL) / spanL)))
                let b = max(nonEmptyMinBucket, min(255, Int((normBright * 210.0 + Double(nextDepth) * 0.65).rounded())))
                buckets[b].append(nb)
            }
        }

        // Gentle majority 3x3 label smoothing to prevent 1-pixel staircase notches along diagonals
        var cleanLabels = regionLabel
        for y in max(1, minPY)...min(h - 2, maxPY) {
            for x in max(1, minPX)...min(w - 2, maxPX) {
                let p = y * w + x
                guard insideROI[p] else { continue }
                let n1 = regionLabel[p - 1], n2 = regionLabel[p + 1]
                let n3 = regionLabel[p - w], n4 = regionLabel[p + w]
                if n1 > 0 && n1 == n2 && n1 == n3 && n1 != cleanLabels[p] {
                    cleanLabels[p] = n1
                } else if n2 > 0 && n2 == n3 && n2 == n4 && n2 != cleanLabels[p] {
                    cleanLabels[p] = n2
                }
            }
        }

        // 4. Topological Dual Crack-Graph Extraction (junction vertices + deduplicated polygonal shared seams)
        let stride = w + 1
        @inline(__always) func labelAt(_ x: Int, _ y: Int) -> Int {
            guard x >= 0, x < w, y >= 0, y < h else { return 0 }
            let l = cleanLabels[y * w + x]
            return l > 0 ? l : 0
        }

        struct DirectedCrack {
            let from: Int
            let to: Int
            let leftLabel: Int
            let rightLabel: Int
        }

        var cracksByFrom: [Int: [DirectedCrack]] = [:]
        var undirectedDegree: [Int: Int] = [:]

        // Horizontal cracks between (x, y-1) [top] and (x, y) [bottom]
        for y in minPY...(maxPY + 1) {
            for x in minPX...maxPX {
                let topL = labelAt(x, y - 1)
                let botL = labelAt(x, y)
                guard topL != botL, (topL > 0 || botL > 0) else { continue }
                let a = y * stride + x
                let b = y * stride + (x + 1)
                // Always keep smaller label consistently on key, emit oriented a -> b (left=topL, right=botL)
                // Canonical orientation for boundary tracing: small -> big label check for unique chain
                if topL < botL {
                    cracksByFrom[a, default: []].append(DirectedCrack(from: a, to: b, leftLabel: topL, rightLabel: botL))
                } else {
                    cracksByFrom[b, default: []].append(DirectedCrack(from: b, to: a, leftLabel: botL, rightLabel: topL))
                }
                undirectedDegree[a, default: 0] += 1
                undirectedDegree[b, default: 0] += 1
            }
        }
        // Vertical cracks between (x-1, y) [left] and (x, y) [right]
        for y in minPY...maxPY {
            for x in minPX...(maxPX + 1) {
                let leftL = labelAt(x - 1, y)
                let rightL = labelAt(x, y)
                guard leftL != rightL, (leftL > 0 || rightL > 0) else { continue }
                let a = y * stride + x
                let b = (y + 1) * stride + x
                if rightL < leftL {
                    cracksByFrom[a, default: []].append(DirectedCrack(from: a, to: b, leftLabel: rightL, rightLabel: leftL))
                } else {
                    cracksByFrom[b, default: []].append(DirectedCrack(from: b, to: a, leftLabel: leftL, rightLabel: rightL))
                }
                undirectedDegree[a, default: 0] += 1
                undirectedDegree[b, default: 0] += 1
            }
        }

        // Identify topological junction nodes (degree != 2, i.e., triple junctions or corner turns on ROI boundaries)
        var gridToVertexID: [Int: Int] = [:]
        var vertices: [ScaleMeshVertex] = []
        @inline(__always) func gridPoint(_ gv: Int) -> ScalePoint {
            ScalePoint(x: Double(gv % stride) / Double(w), y: Double(gv / stride) / Double(h))
        }
        func vertexID(for gv: Int, isBoundary: Bool) -> Int {
            if let existing = gridToVertexID[gv] { return existing }
            let id = vertices.count
            vertices.append(ScaleMeshVertex(id: id, point: gridPoint(gv), isBoundary: isBoundary))
            gridToVertexID[gv] = id
            return id
        }

        let isJunctionNode: (Int) -> Bool = { gv in
            (undirectedDegree[gv] ?? 0) != 2
        }

        // Trace maximal chains between junction nodes along fixed (leftLabel, rightLabel) pairs
        struct PairKey: Hashable {
            let low: Int
            let high: Int
        }
        var consumedCracks = Set<UInt64>()
        @inline(__always) func edgeKey(_ a: Int, _ b: Int) -> UInt64 {
            let lo = UInt64(min(a, b)), hi = UInt64(max(a, b))
            return (lo << 32) | hi
        }

        struct RawChain {
            let low: Int
            let high: Int
            let vertexIDs: [Int]
        }
        var rawChains: [RawChain] = []

        let allStarts = cracksByFrom.keys.sorted()
        // First trace chains starting at junction nodes
        for pass in 0...1 {
            for startGV in allStarts {
                if pass == 0 && !isJunctionNode(startGV) { continue }
                guard let candidates = cracksByFrom[startGV] else { continue }
                for initial in candidates {
                    let k = edgeKey(initial.from, initial.to)
                    if consumedCracks.contains(k) { continue }
                    consumedCracks.insert(k)

                    let low = initial.leftLabel
                    let high = initial.rightLabel
                    var chainGVs: [Int] = [initial.from, initial.to]
                    var current = initial.to
                    var steps = 0

                    while current != startGV && !isJunctionNode(current) && steps < 4000 {
                        steps += 1
                        guard let outgoing = cracksByFrom[current]?.first(where: {
                            $0.leftLabel == low && $0.rightLabel == high && !consumedCracks.contains(edgeKey($0.from, $0.to))
                        }) else { break }
                        consumedCracks.insert(edgeKey(outgoing.from, outgoing.to))
                        current = outgoing.to
                        chainGVs.append(current)
                    }

                    guard chainGVs.count >= 2 else { continue }
                    let pts = chainGVs.map { gridPoint($0) }
                    let isOuter = low == 0
                    // Internal sutures simplify cleanly to straight lines (just like Picture 1!); outer edge follows jawline
                    let eps = isOuter ? max(0.008, roiDiag * 0.015) : max(0.022, roiDiag * 0.048)
                    let simplifiedPts = douglasPeuckerOpen(pts, epsilon: eps)

                    // Map simplified polyline back onto vertex IDs (locking exact junction endpoints!)
                    var mappedVIDs: [Int] = []
                    mappedVIDs.reserveCapacity(simplifiedPts.count)
                    for (idx, pt) in simplifiedPts.enumerated() {
                        if idx == 0 {
                            mappedVIDs.append(vertexID(for: chainGVs[0], isBoundary: isOuter))
                        } else if idx == simplifiedPts.count - 1 {
                            mappedVIDs.append(vertexID(for: chainGVs[chainGVs.count - 1], isBoundary: isOuter))
                        } else {
                            // Closest intermediate GV on the chain
                            let bestGV = chainGVs.min(by: {
                                let pA = gridPoint($0), pB = gridPoint($1)
                                return hypot(pA.x - pt.x, pA.y - pt.y) < hypot(pB.x - pt.x, pB.y - pt.y)
                            }) ?? chainGVs[0]
                            mappedVIDs.append(vertexID(for: bestGV, isBoundary: isOuter))
                        }
                    }
                    if mappedVIDs.count >= 2 {
                        rawChains.append(RawChain(low: low, high: high, vertexIDs: mappedVIDs))
                    }
                }
            }
        }

        // Build deduplicated mesh edges
        var edges: [ScaleMeshEdge] = []
        var chainsPerCell: [Int: [[Int]]] = [:]
        for (idx, chain) in rawChains.enumerated() {
            edges.append(
                ScaleMeshEdge(
                    id: idx,
                    vertexIDs: chain.vertexIDs,
                    leftCellNumber: chain.low,
                    rightCellNumber: chain.high
                )
            )
            // In our canonical emission: chain goes clockwise/CCW consistently for `high` vs `low`
            chainsPerCell[chain.high, default: []].append(chain.vertexIDs)
            if chain.low > 0 {
                chainsPerCell[chain.low, default: []].append(Array(chain.vertexIDs.reversed()))
            }
        }

        // Assemble closed polygonal cells per watershed basin using shared vertices
        var builtCells: [ScaleMeshCell] = []
        let vertexLookup = Dictionary(uniqueKeysWithValues: vertices.map { ($0.id, $0.point) })

        for rawCellID in chainsPerCell.keys.sorted() {
            var remaining = chainsPerCell[rawCellID] ?? []
            guard !remaining.isEmpty else { continue }
            // Stitch edge chains into largest closed ring
            var bestRing: [Int] = []
            while !remaining.isEmpty {
                var ring = remaining.removeFirst()
                var guardCount = 0
                while guardCount < 120, let endV = ring.last, endV != ring.first {
                    guardCount += 1
                    if let nextIdx = remaining.firstIndex(where: { $0.first == endV }) {
                        let next = remaining.remove(at: nextIdx)
                        ring.append(contentsOf: next.dropFirst())
                    } else if let revIdx = remaining.firstIndex(where: { $0.last == endV }) {
                        let next = Array(remaining.remove(at: revIdx).reversed())
                        ring.append(contentsOf: next.dropFirst())
                    } else {
                        break
                    }
                }
                if ring.first == ring.last, ring.count > 1 { ring.removeLast() }
                // Deduplicate consecutive identical vertex IDs
                var dedup: [Int] = []
                for vid in ring where dedup.last != vid { dedup.append(vid) }
                if dedup.count >= 3, dedup.count > bestRing.count {
                    bestRing = dedup
                }
            }
            guard bestRing.count >= 3 else { continue }
            let poly = bestRing.compactMap { vertexLookup[$0] }
            guard poly.count >= 3 else { continue }
            let area = abs(ScalePhotoReview.area(poly))
            let perim = perimeter(of: poly)
            guard area > 1e-5, perim > 1e-4 else { continue }
            let circ = min(1.0, (4.0 * .pi * area) / (perim * perim))
            let moments = polygonMoments(poly)
            builtCells.append(
                ScaleMeshCell(
                    number: rawCellID,
                    center: moments.centroid,
                    vertexIDs: bestRing,
                    polygon: poly,
                    roiAreaFraction: area / roiNormalizedArea,
                    imageArea: area,
                    vertexCount: bestRing.count,
                    circularity: circ,
                    aspectRatio: moments.aspectRatio,
                    orientationDeg: moments.orientationDeg
                )
            )
        }

        // Re-number cells deterministically top-to-bottom 1...N matching display numbering
        let sortedCells = builtCells.sorted { a, b in
            let bandA = Int((a.center.y * 14.0).rounded())
            let bandB = Int((b.center.y * 14.0).rounded())
            return bandA == bandB ? a.center.x < b.center.x : bandA < bandB
        }
        var oldToNew: [Int: Int] = [:]
        let finalCells = sortedCells.enumerated().map { idx, c -> ScaleMeshCell in
            let newNum = idx + 1
            oldToNew[c.number] = newNum
            return ScaleMeshCell(
                number: newNum,
                center: c.center,
                vertexIDs: c.vertexIDs,
                polygon: c.polygon,
                roiAreaFraction: c.roiAreaFraction,
                imageArea: c.imageArea,
                vertexCount: c.vertexCount,
                circularity: c.circularity,
                aspectRatio: c.aspectRatio,
                orientationDeg: c.orientationDeg
            )
        }
        let finalEdges = edges.map { e in
            ScaleMeshEdge(
                id: e.id,
                vertexIDs: e.vertexIDs,
                leftCellNumber: e.leftCellNumber > 0 ? (oldToNew[e.leftCellNumber] ?? e.leftCellNumber) : 0,
                rightCellNumber: e.rightCellNumber > 0 ? (oldToNew[e.rightCellNumber] ?? e.rightCellNumber) : 0
            )
        }

        return ScaleSutureMesh(vertices: vertices, edges: finalEdges, cells: finalCells)
    }
}

// MARK: - Interactive Manual Pattern Pair Calculator & Geometric Alignment

nonisolated struct PatternPairLink: Identifiable, Hashable, Codable, Sendable {
    var id: String { "\(queryNumber)-\(candidateNumber)" }
    let queryNumber: Int
    let candidateNumber: Int
}

nonisolated struct PatternPairDetail: Identifiable, Hashable, Sendable {
    var id: String { "Q\(queryNumber)-C\(candidateNumber)" }
    let queryNumber: Int
    let candidateNumber: Int
    let shapeAgreementPercent: Int
    let normalizedResidualPercent: Double?
}

nonisolated struct WarpedPatternContour: Identifiable, Hashable, Sendable {
    var id: Int { number }
    let number: Int
    let polygon: [ScalePoint]
    let centroid: ScalePoint
}

nonisolated struct PatternMatchCalculation: Equatable, Sendable {
    let pairCount: Int
    let totalQueryPatterns: Int
    let totalCandidatePatterns: Int
    let coveragePercent: Int
    let shapeMatchPercent: Int
    let affineResidualPercent: Double?
    let affineFitPercent: Int?
    let i3sEquivalentDistance: Double?
    let combinedScorePercent: Int
    let pairDetails: [PatternPairDetail]
    let warpedQueryContours: [WarpedPatternContour]
}

nonisolated enum PatternMatchCalculator {
    /// Computes real shape & geometric alignment metrics strictly from the scientist's paired numbered contours.
    static func calculate(
        query: [DetectedScalePattern],
        candidate: [DetectedScalePattern],
        pairs: [PatternPairLink],
        queryROI: [ScalePoint],
        candidateROI: [ScalePoint]
    ) -> PatternMatchCalculation {
        let queryByNum = Dictionary(uniqueKeysWithValues: query.map { ($0.number, $0) })
        let candByNum = Dictionary(uniqueKeysWithValues: candidate.map { ($0.number, $0) })
        let validPairs = pairs.compactMap { pair -> (q: DetectedScalePattern, c: DetectedScalePattern)? in
            guard let q = queryByNum[pair.queryNumber], let c = candByNum[pair.candidateNumber] else { return nil }
            return (q, c)
        }

        let denom = max(1, min(query.count, candidate.count))
        let coverage = min(100, Int((Double(validPairs.count) / Double(denom) * 100.0).rounded()))

        guard !validPairs.isEmpty else {
            return PatternMatchCalculation(
                pairCount: 0,
                totalQueryPatterns: query.count,
                totalCandidatePatterns: candidate.count,
                coveragePercent: 0,
                shapeMatchPercent: 0,
                affineResidualPercent: nil,
                affineFitPercent: nil,
                i3sEquivalentDistance: nil,
                combinedScorePercent: 0,
                pairDetails: [],
                warpedQueryContours: []
            )
        }

        // Per-pair contour geometry agreement (zoom invariant via ROI-normalized area, corner count, aspect ratio, circularity)
        var shapeScores: [Double] = []
        for (q, c) in validPairs {
            let areaRatio = min(q.roiAreaFraction, c.roiAreaFraction) / max(1e-6, max(q.roiAreaFraction, c.roiAreaFraction))
            let aspectAgreement = min(q.aspectRatio, c.aspectRatio) / max(1e-6, max(q.aspectRatio, c.aspectRatio))
            let circAgreement = min(q.circularity, c.circularity) / max(1e-6, max(q.circularity, c.circularity))
            let cornerDiff = abs(q.vertexCount - c.vertexCount)
            let cornerAgreement = max(0.25, 1.0 - Double(cornerDiff) * 0.20)
            let pairShape = 0.34 * areaRatio + 0.24 * aspectAgreement + 0.18 * circAgreement + 0.24 * cornerAgreement
            shapeScores.append(pairShape)
        }

        let meanShape = shapeScores.reduce(0, +) / Double(shapeScores.count)
        let shapePercent = Int((meanShape * 100.0).rounded())

        // Solve 2D affine alignment (Query -> Candidate) once >= 3 non-collinear pattern pairs exist
        var affineMatrix: [Double]? = nil
        if validPairs.count >= 3 {
            affineMatrix = solveBestAffine(pairs: validPairs)
        }

        let candSpan = max(0.08, roiSpan(candidateROI, patterns: candidate))
        var residuals: [Double] = []
        var details: [PatternPairDetail] = []

        for (idx, (q, c)) in validPairs.enumerated() {
            var resPct: Double? = nil
            if let m = affineMatrix {
                let warped = applyAffine(q.centroid, matrix: m)
                let dist = hypot(warped.x - c.centroid.x, warped.y - c.centroid.y)
                let normPct = (dist / candSpan) * 100.0
                resPct = normPct
                residuals.append(normPct)
            }
            details.append(
                PatternPairDetail(
                    queryNumber: q.number,
                    candidateNumber: c.number,
                    shapeAgreementPercent: Int((shapeScores[idx] * 100.0).rounded()),
                    normalizedResidualPercent: resPct
                )
            )
        }

        var warpedContours: [WarpedPatternContour] = []
        if let m = affineMatrix {
            warpedContours = query.map { q in
                WarpedPatternContour(
                    number: q.number,
                    polygon: q.polygon.map { applyAffine($0, matrix: m) },
                    centroid: applyAffine(q.centroid, matrix: m)
                )
            }
        }

        let meanResidual: Double? = residuals.isEmpty ? nil : (residuals.reduce(0, +) / Double(residuals.count))
        let affineFitPercent: Int? = meanResidual.map { r in
            // 0% error -> 100%, 4% of ROI error -> ~62%, 10% error -> ~25%
            Int((100.0 * exp(-r / 9.5)).rounded())
        }
        let i3sEq: Double? = meanResidual.map { r in
            // Comparable scale to I3S score (lower is closer match)
            max(1.0, (r * 2.4) / max(0.35, Double(validPairs.count) / Double(denom)))
        }

        let combined: Int
        if let affPct = affineFitPercent {
            let covScore = min(100.0, Double(coverage) * 1.1)
            combined = Int((0.48 * Double(affPct) + 0.34 * Double(shapePercent) + 0.18 * covScore).rounded())
        } else {
            combined = Int((0.75 * Double(shapePercent) + 0.25 * Double(coverage)).rounded())
        }

        return PatternMatchCalculation(
            pairCount: validPairs.count,
            totalQueryPatterns: query.count,
            totalCandidatePatterns: candidate.count,
            coveragePercent: coverage,
            shapeMatchPercent: shapePercent,
            affineResidualPercent: meanResidual,
            affineFitPercent: affineFitPercent,
            i3sEquivalentDistance: i3sEq,
            combinedScorePercent: min(100, max(0, combined)),
            pairDetails: details,
            warpedQueryContours: warpedContours
        )
    }

    /// Auto-suggests one-to-one pattern correspondences using I3S reference triangles (when available)
    /// or ROI-normalized spatial + geometric descriptor Hungarian-lite greedy matching.
    @MainActor
    static func autoSuggestPairs(
        query: [DetectedScalePattern],
        candidate: [DetectedScalePattern],
        queryFP: I3SFingerprint?,
        candidateFP: I3SFingerprint?,
        queryImageSize: NSSize?,
        candidateImageSize: NSSize?,
        queryROI: [ScalePoint],
        candidateROI: [ScalePoint]
    ) -> [PatternPairLink] {
        guard !query.isEmpty, !candidate.isEmpty else { return [] }

        var qToCMatrix: [Double]? = nil
        if let qfp = queryFP, qfp.allReferencesInitialized,
           let cfp = candidateFP, cfp.allReferencesInitialized,
           let qs = queryImageSize, qs.width > 1, qs.height > 1,
           let cs = candidateImageSize, cs.width > 1, cs.height > 1 {
            let qr = (
                I3SPoint2D(x: qfp.ref1.x / qs.width, y: qfp.ref1.y / qs.height),
                I3SPoint2D(x: qfp.ref2.x / qs.width, y: qfp.ref2.y / qs.height),
                I3SPoint2D(x: qfp.ref3.x / qs.width, y: qfp.ref3.y / qs.height)
            )
            let cr = (
                I3SPoint2D(x: cfp.ref1.x / cs.width, y: cfp.ref1.y / cs.height),
                I3SPoint2D(x: cfp.ref2.x / cs.width, y: cfp.ref2.y / cs.height),
                I3SPoint2D(x: cfp.ref3.x / cs.width, y: cfp.ref3.y / cs.height)
            )
            qToCMatrix = I3SCompareEngine.calcAffine(from: qr, to: cr)
        }

        let qBounds = boundingRect(of: queryROI, fallback: query.map(\.centroid))
        let cBounds = boundingRect(of: candidateROI, fallback: candidate.map(\.centroid))
        let cDiag = max(0.05, hypot(cBounds.width, cBounds.height))

        struct CandidateEdge {
            let qNum: Int
            let cNum: Int
            let cost: Double
        }

        var edges: [CandidateEdge] = []
        for q in query {
            let mappedCentroid: ScalePoint = {
                if let m = qToCMatrix {
                    return applyAffine(q.centroid, matrix: m)
                }
                let u = (q.centroid.x - qBounds.minX) / max(1e-4, qBounds.width)
                let v = (q.centroid.y - qBounds.minY) / max(1e-4, qBounds.height)
                return ScalePoint(x: cBounds.minX + u * cBounds.width, y: cBounds.minY + v * cBounds.height)
            }()

            for c in candidate {
                let spatialNorm = hypot(mappedCentroid.x - c.centroid.x, mappedCentroid.y - c.centroid.y) / cDiag
                guard spatialNorm < 0.24 else { continue }
                let areaRatio = min(q.roiAreaFraction, c.roiAreaFraction) / max(1e-6, max(q.roiAreaFraction, c.roiAreaFraction))
                guard areaRatio >= 0.42 else { continue }
                let aspectRatioSim = min(q.aspectRatio, c.aspectRatio) / max(1e-6, max(q.aspectRatio, c.aspectRatio))
                let shapePenalty = (1.0 - areaRatio) * 0.45 + (1.0 - aspectRatioSim) * 0.25 + Double(abs(q.vertexCount - c.vertexCount)) * 0.06
                let totalCost = spatialNorm * 1.8 + shapePenalty * 0.35
                edges.append(CandidateEdge(qNum: q.number, cNum: c.number, cost: totalCost))
            }
        }

        edges.sort { $0.cost < $1.cost }
        var usedQ = Set<Int>()
        var usedC = Set<Int>()
        var chosen: [PatternPairLink] = []
        for edge in edges where edge.cost < 0.45 {
            guard !usedQ.contains(edge.qNum), !usedC.contains(edge.cNum) else { continue }
            usedQ.insert(edge.qNum)
            usedC.insert(edge.cNum)
            chosen.append(PatternPairLink(queryNumber: edge.qNum, candidateNumber: edge.cNum))
        }
        return chosen.sorted { $0.queryNumber < $1.queryNumber }
    }

    private static func solveBestAffine(pairs: [(q: DetectedScalePattern, c: DetectedScalePattern)]) -> [Double]? {
        if pairs.count == 3 {
            let p0 = pairs[0], p1 = pairs[1], p2 = pairs[2]
            guard let mx = solve3x3(
                p0.q.centroid.x, p0.q.centroid.y, 1,
                p1.q.centroid.x, p1.q.centroid.y, 1,
                p2.q.centroid.x, p2.q.centroid.y, 1,
                p0.c.centroid.x, p1.c.centroid.x, p2.c.centroid.x
            ),
            let my = solve3x3(
                p0.q.centroid.x, p0.q.centroid.y, 1,
                p1.q.centroid.x, p1.q.centroid.y, 1,
                p2.q.centroid.x, p2.q.centroid.y, 1,
                p0.c.centroid.y, p1.c.centroid.y, p2.c.centroid.y
            ) else {
                return nil
            }
            return [mx.0, mx.1, mx.2, my.0, my.1, my.2]
        }
        // Solve 3x3 normal equations [sum(x^2), sum(xy), sum(x); ...] for least-squares 2D affine fit
        var a00 = 0.0, a01 = 0.0, a02 = 0.0
        var a11 = 0.0, a12 = 0.0
        let a22 = Double(pairs.count)
        var bx0 = 0.0, bx1 = 0.0, bx2 = 0.0
        var by0 = 0.0, by1 = 0.0, by2 = 0.0

        for (q, c) in pairs {
            let x = q.centroid.x, y = q.centroid.y
            let u = c.centroid.x, v = c.centroid.y
            a00 += x * x; a01 += x * y; a02 += x
            a11 += y * y; a12 += y
            bx0 += x * u; bx1 += y * u; bx2 += u
            by0 += x * v; by1 += y * v; by2 += v
        }

        guard let mx = solve3x3(
            a00, a01, a02,
            a01, a11, a12,
            a02, a12, a22,
            bx0, bx1, bx2
        ), let my = solve3x3(
            a00, a01, a02,
            a01, a11, a12,
            a02, a12, a22,
            by0, by1, by2
        ) else {
            return nil
        }
        return [mx.0, mx.1, mx.2, my.0, my.1, my.2]
    }

    private static func solve3x3(
        _ m00: Double, _ m01: Double, _ m02: Double,
        _ m10: Double, _ m11: Double, _ m12: Double,
        _ m20: Double, _ m21: Double, _ m22: Double,
        _ b0: Double, _ b1: Double, _ b2: Double
    ) -> (Double, Double, Double)? {
        let det = m00 * (m11 * m22 - m12 * m21)
            - m01 * (m10 * m22 - m12 * m20)
            + m02 * (m10 * m21 - m11 * m20)
        guard abs(det) > 1e-11 else { return nil }
        let inv = 1.0 / det
        let d0 = b0 * (m11 * m22 - m12 * m21) - m01 * (b1 * m22 - m12 * b2) + m02 * (b1 * m21 - m11 * b2)
        let d1 = m00 * (b1 * m22 - m12 * b2) - b0 * (m10 * m22 - m12 * m20) + m02 * (m10 * b2 - b1 * m20)
        let d2 = m00 * (m11 * b2 - b1 * m21) - m01 * (m10 * b2 - b1 * m20) + b0 * (m10 * m21 - m11 * m20)
        return (d0 * inv, d1 * inv, d2 * inv)
    }

    private static func applyAffine(_ p: ScalePoint, matrix m: [Double]) -> ScalePoint {
        guard m.count >= 6 else { return p }
        return ScalePoint(x: m[0] * p.x + m[1] * p.y + m[2], y: m[3] * p.x + m[4] * p.y + m[5])
    }

    private static func roiSpan(_ roi: [ScalePoint], patterns: [DetectedScalePattern]) -> Double {
        let rect = boundingRect(of: roi, fallback: patterns.map(\.centroid))
        return max(0.08, hypot(rect.width, rect.height))
    }

    private static func boundingRect(of pts: [ScalePoint], fallback: [ScalePoint]) -> CGRect {
        let source = pts.isEmpty ? fallback : pts
        guard !source.isEmpty else { return CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5) }
        let minX = source.map(\.x).min() ?? 0.25
        let maxX = source.map(\.x).max() ?? 0.75
        let minY = source.map(\.y).min() ?? 0.25
        let maxY = source.map(\.y).max() ?? 0.75
        return CGRect(x: minX, y: minY, width: max(0.05, maxX - minX), height: max(0.05, maxY - minY))
    }
}
