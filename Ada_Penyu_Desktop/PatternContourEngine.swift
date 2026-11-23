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

    static let empty = ScaleSutureMesh(vertices: [], edges: [], cells: [])

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

nonisolated struct PatternExtractionConfig: Equatable, Hashable, Sendable {
    /// Adaptive melanin-contrast sensitivity in `[0.1, 0.9]`. Higher includes fainter scales.
    var sensitivity: Double = 0.48
    /// Contour vector smoothness in `[0.0, 1.0]`.
    var smoothness: Double = 0.65
    /// Minimum scale area relative to ROI area.
    var minScaleROIFilter: Double = 0.0045
    /// Maximum single scale area relative to ROI area.
    var maxScaleROIFilter: Double = 0.22
}

/// Full extracted contour & polygonal suture mesh payload for one photograph.
nonisolated struct ExtractedScaleAnalysis: Equatable, Sendable {
    let roi: [ScalePoint]
    let patterns: [DetectedScalePattern]
    let mesh: ScaleSutureMesh
    let waterCoverageFraction: Double

    static let empty = ExtractedScaleAnalysis(roi: [], patterns: [], mesh: .empty, waterCoverageFraction: 0)
}

// MARK: - Real Pattern-Only Scale Contour & Suture Mesh Engine (Mobile fd69860 Parity)

/// Isolates and segments individual dark melanin facial scales bounded by pale keratin sutures
/// strictly inside a sea turtle facial ROI — with border-connected ocean water masking,
/// 8-octant surrounding suture-ring validation, anterior eyeball rejection, O(1) integral
/// images, tight morphological cluster ROI, and watertight polygonal suture mesh tessellation.
nonisolated enum PatternContourEngine {
    struct LuminanceRaster: Sendable {
        let pixels: [Float]
        let width: Int
        let height: Int
        /// Normalized RGB channels in `[0, 1]` (empty if constructed from luminance-only input).
        let red: [Float]
        let green: [Float]
        let blue: [Float]
        /// Per-pixel blue dominance `max(0, b - max(r, g))` in `[0, 1]`.
        let blueExcess: [Float]
        /// Per-pixel `b - r` in `[-1, 1]`.
        let blueMinusRed: [Float]
        /// Border-connected open ocean water mask (`true` = open water background).
        let isWater: [Bool]

        init(
            pixels: [Float],
            width: Int,
            height: Int,
            red: [Float] = [],
            green: [Float] = [],
            blue: [Float] = [],
            blueExcess: [Float] = [],
            blueMinusRed: [Float] = [],
            isWater: [Bool] = []
        ) {
            self.pixels = pixels
            self.width = width
            self.height = height
            self.red = red
            self.green = green
            self.blue = blue
            self.blueExcess = blueExcess
            self.blueMinusRed = blueMinusRed
            self.isWater = isWater
        }

        var hasWaterMask: Bool { isWater.count == width * height }
        var hasColorChannels: Bool { blueExcess.count == width * height && blueMinusRed.count == width * height }
        var waterFraction: Double {
            guard hasWaterMask, !isWater.isEmpty else { return 0 }
            let count = isWater.reduce(0) { $0 + ($1 ? 1 : 0) }
            return Double(count) / Double(isWater.count)
        }
    }

    // MARK: - High-Level Single-Pass API

    /// Runs water-masked ROI detection, smooth melanin contour extraction, eyeball rejection,
    /// and watertight polygonal suture mesh tessellation in a single pass.
    @MainActor
    static func extractAnalysis(
        from image: NSImage,
        side: TurtlePhotoSide,
        config: PatternExtractionConfig = .init(),
        explicitROI: [ScalePoint]? = nil
    ) -> ExtractedScaleAnalysis {
        guard let raster = underwaterLuminanceRaster(from: image, maxDimension: 420) else {
            return .empty
        }
        return extractAnalysis(from: raster, side: side, config: config, explicitROI: explicitROI)
    }

    static func extractAnalysis(
        from raster: LuminanceRaster,
        side: TurtlePhotoSide,
        config: PatternExtractionConfig = .init(),
        explicitROI: [ScalePoint]? = nil
    ) -> ExtractedScaleAnalysis {
        guard !Task.isCancelled else { return .empty }
        let roi: [ScalePoint]
        if let explicitROI, explicitROI.count >= 3 {
            roi = explicitROI
        } else {
            roi = detectFacialPatternROI(from: raster, side: side).roi
        }
        guard !Task.isCancelled else { return .empty }
        let patterns = extractPatterns(from: raster, roiPolygon: roi, config: config, side: side)
        guard !Task.isCancelled else { return .empty }
        let mesh = extractScaleSutureMesh(from: raster, roiPolygon: roi, patterns: patterns, config: config)
        return ExtractedScaleAnalysis(
            roi: roi,
            patterns: patterns,
            mesh: mesh,
            waterCoverageFraction: raster.waterFraction
        )
    }

    // MARK: - Pattern Extraction (Backwards-Compatible + Full Raster Overloads)

    /// Extracts numbered smooth scale pattern contours strictly inside `roiPolygon` (normalized `[0, 1]`).
    @MainActor
    static func extractPatterns(
        from image: NSImage,
        roiPolygon: [ScalePoint],
        config: PatternExtractionConfig = .init(),
        side: TurtlePhotoSide? = nil
    ) -> [DetectedScalePattern] {
        guard let raster = underwaterLuminanceRaster(from: image, maxDimension: 420) else { return [] }
        return extractPatterns(from: raster, roiPolygon: roiPolygon, config: config, side: side)
    }

    static func extractPatterns(
        from raster: (pixels: [Float], width: Int, height: Int),
        roiPolygon: [ScalePoint],
        config: PatternExtractionConfig = .init(),
        side: TurtlePhotoSide? = nil
    ) -> [DetectedScalePattern] {
        extractPatterns(
            from: LuminanceRaster(pixels: raster.pixels, width: raster.width, height: raster.height),
            roiPolygon: roiPolygon,
            config: config,
            side: side
        )
    }

    static func extractPatterns(
        from raster: LuminanceRaster,
        roiPolygon: [ScalePoint],
        config: PatternExtractionConfig = .init(),
        side: TurtlePhotoSide? = nil
    ) -> [DetectedScalePattern] {
        let w = raster.width
        let h = raster.height
        guard w >= 16, h >= 16, raster.pixels.count == w * h, roiPolygon.count >= 3, !Task.isCancelled else {
            return []
        }

        let smooth3 = gaussianSmooth3x3(raster.pixels, width: w, height: h)
        let smooth5 = gaussianSmooth5x5(raster.pixels, width: w, height: h)
        let roiMask = rasterizeROI(roiPolygon, width: w, height: h)
        guard roiMask.count >= 64, roiMask.maxX > roiMask.minX + 6, roiMask.maxY > roiMask.minY + 6 else {
            return []
        }

        let hasWater = raster.hasWaterMask
        let hasColor = raster.hasColorChannels

        // Exclude open ocean water and erode outer ROI border by 1px so scales stay detached from frame edges.
        var validMask = [Bool](repeating: false, count: w * h)
        var validCount = 0
        for y in roiMask.minY...roiMask.maxY {
            let row = y * w
            for x in roiMask.minX...roiMask.maxX {
                let idx = row + x
                guard roiMask.inside[idx] else { continue }
                if hasWater && raster.isWater[idx] { continue }
                if x > 0 && x < w - 1 && y > 0 && y < h - 1 {
                    if !roiMask.inside[idx - 1] || !roiMask.inside[idx + 1]
                        || !roiMask.inside[idx - w] || !roiMask.inside[idx + w] {
                        continue
                    }
                }
                validMask[idx] = true
                validCount += 1
            }
        }
        guard validCount >= 48 else { return [] }

        // O(1) integral images for macro background & micro suture contrast.
        let stride = w + 1
        let macroInt = buildIntegral(smooth5, width: w, height: h)
        let microInt = buildIntegral(smooth3, width: w, height: h)

        @inline(__always)
        func boxStats(_ intg: IntegralImage, _ cx: Int, _ cy: Int, _ r: Int) -> (mean: Double, std: Double) {
            let x0 = max(0, cx - r)
            let y0 = max(0, cy - r)
            let x1 = min(w - 1, cx + r)
            let y1 = min(h - 1, cy + r)
            let area = Double((x1 - x0 + 1) * (y1 - y0 + 1))
            let sum = intg.sum[(y1 + 1) * stride + (x1 + 1)]
                - intg.sum[y0 * stride + (x1 + 1)]
                - intg.sum[(y1 + 1) * stride + x0]
                + intg.sum[y0 * stride + x0]
            let sq = intg.sumSq[(y1 + 1) * stride + (x1 + 1)]
                - intg.sumSq[y0 * stride + (x1 + 1)]
                - intg.sumSq[(y1 + 1) * stride + x0]
                + intg.sumSq[y0 * stride + x0]
            let mean = sum / area
            let variance = max(0.0, (sq / area) - mean * mean)
            return (mean, sqrt(variance))
        }

        let roiSpan = min(roiMask.maxX - roiMask.minX, roiMask.maxY - roiMask.minY)
        let rMacro = max(14, min(52, Int(Double(roiSpan) * 0.17)))
        let rMicro = max(3, min(9, Int(Double(roiSpan) * 0.030)))

        let sens = min(0.92, max(0.08, config.sensitivity))
        let kScale = 0.40 - sens * 0.32
        let minContrast = 0.044 - sens * 0.032

        var mask = [Bool](repeating: false, count: w * h)
        var closeAllowed = [Bool](repeating: false, count: w * h)
        for y in roiMask.minY...roiMask.maxY {
            if Task.isCancelled { return [] }
            for x in roiMask.minX...roiMask.maxX {
                let idx = y * w + x
                guard validMask[idx] else { continue }
                let val = Double(smooth3[idx])
                let macro = boxStats(macroInt, x, y, rMacro)
                let micro = boxStats(microInt, x, y, rMicro)

                let drop = macro.mean - val
                let requiredDrop = max(minContrast, kScale * max(macro.std, 0.03))
                let isMicroRidge = (val - micro.mean) > 0.012
                let isSpecularGlare = val > macro.mean + 0.10

                // 4-axis 1D directional ridge detector splits narrow bright keratin sutures
                // without biting into dark scale interiors.
                var isDirRidge = false
                if x >= 2 && x <= w - 3 && y >= 2 && y <= h - 3 && val > macro.mean - 0.012 {
                    let hRidge = val - 0.5 * Double(smooth3[idx - 2] + smooth3[idx + 2])
                    let vRidge = val - 0.5 * Double(smooth3[idx - 2 * w] + smooth3[idx + 2 * w])
                    let d1Ridge = val - 0.5 * Double(smooth3[idx - 2 * w - 2] + smooth3[idx + 2 * w + 2])
                    let d2Ridge = val - 0.5 * Double(smooth3[idx - 2 * w + 2] + smooth3[idx + 2 * w - 2])
                    let maxAxisRidge = max(max(hRidge, vRidge), max(d1Ridge, d2Ridge))
                    if maxAxisRidge > 0.016 {
                        isDirRidge = true
                    }
                }

                if drop >= requiredDrop * 0.55 && !isMicroRidge && !isDirRidge && !isSpecularGlare {
                    closeAllowed[idx] = true
                }
                if drop >= requiredDrop && !isMicroRidge && !isDirRidge && !isSpecularGlare {
                    mask[idx] = true
                }
            }
        }

        mask = morphOpen3x3(
            mask,
            width: w,
            height: h,
            minX: roiMask.minX,
            maxX: roiMask.maxX,
            minY: roiMask.minY,
            maxY: roiMask.maxY,
            validMask: validMask
        )

        // Smooth 1px boundary notches inside dark melanin cores without bridging across bright sutures.
        if roiMask.maxY - 1 >= max(1, roiMask.minY) && roiMask.maxX - 1 >= max(1, roiMask.minX) {
            var smoothedMask = mask
            for y in max(1, roiMask.minY)...min(h - 2, roiMask.maxY) {
                let row = y * w
                for x in max(1, roiMask.minX)...min(w - 2, roiMask.maxX) {
                    let idx = row + x
                    guard !mask[idx], closeAllowed[idx] else { continue }
                    let nCount = (mask[idx - 1] ? 1 : 0) + (mask[idx + 1] ? 1 : 0)
                        + (mask[idx - w] ? 1 : 0) + (mask[idx + w] ? 1 : 0)
                    if nCount >= 3 {
                        smoothedMask[idx] = true
                    }
                }
            }
            mask = smoothedMask
        }

        fillSmallHoles(
            &mask,
            width: w,
            height: h,
            minX: roiMask.minX,
            maxX: roiMask.maxX,
            minY: roiMask.minY,
            maxY: roiMask.maxY,
            maxHolePixels: max(24, validCount / 110)
        )

        let minComponentPx = max(18, Int(Double(validCount) * config.minScaleROIFilter))
        let maxComponentPx = max(minComponentPx + 24, Int(Double(validCount) * config.maxScaleROIFilter))

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
        let roiNormalizedArea = max(1e-5, Double(validCount) / Double(w * h))

        for y in roiMask.minY...roiMask.maxY {
            if Task.isCancelled { return [] }
            for x in roiMask.minX...roiMask.maxX {
                let seed = y * w + x
                guard mask[seed], labels[seed] == 0 else { continue }
                currentLabel += 1
                var queue = [seed]
                var cursor = 0
                labels[seed] = currentLabel

                var compMinX = x, compMaxX = x, compMinY = y, compMaxY = y
                var lumSum = 0.0
                var waterInside = 0
                while cursor < queue.count {
                    let p = queue[cursor]; cursor += 1
                    let px = p % w, py = p / w
                    lumSum += Double(smooth3[p])
                    if hasWater && raster.isWater[p] { waterInside += 1 }
                    if px < compMinX { compMinX = px }
                    if px > compMaxX { compMaxX = px }
                    if py < compMinY { compMinY = py }
                    if py > compMaxY { compMaxY = py }

                    if px > roiMask.minX {
                        let next = py * w + (px - 1)
                        if mask[next], labels[next] == 0 { labels[next] = currentLabel; queue.append(next) }
                    }
                    if px < roiMask.maxX {
                        let next = py * w + (px + 1)
                        if mask[next], labels[next] == 0 { labels[next] = currentLabel; queue.append(next) }
                    }
                    if py > roiMask.minY {
                        let next = (py - 1) * w + px
                        if mask[next], labels[next] == 0 { labels[next] = currentLabel; queue.append(next) }
                    }
                    if py < roiMask.maxY {
                        let next = (py + 1) * w + px
                        if mask[next], labels[next] == 0 { labels[next] = currentLabel; queue.append(next) }
                    }
                }

                guard queue.count >= minComponentPx, queue.count <= maxComponentPx else { continue }
                if hasWater && Double(waterInside) / Double(queue.count) > 0.08 { continue }
                let bw = max(1, compMaxX - compMinX + 1)
                let bh = max(1, compMaxY - compMinY + 1)
                guard Double(queue.count) / Double(bw * bh) >= 0.28 else { continue }

                // Validate surrounding 2–4px pale keratin suture ring (rejects water blobs, edge shadows, jaw crevices).
                let coreMeanLum = lumSum / Double(queue.count)
                let cpx = Double(compMinX + compMaxX) * 0.5
                let cpy = Double(compMinY + compMaxY) * 0.5
                let ringCheck = validateSurroundingSutureRing(
                    componentPixels: queue,
                    labels: labels,
                    targetLabel: currentLabel,
                    centerX: cpx,
                    centerY: cpy,
                    coreMeanLum: coreMeanLum,
                    raster: raster,
                    smooth3: smooth3,
                    hasWater: hasWater,
                    hasColor: hasColor
                )
                guard ringCheck.isValid else { continue }

                let rawPoly = traceOuterPolygon(
                    componentPixels: queue,
                    labels: labels,
                    targetLabel: currentLabel,
                    width: w,
                    height: h
                )
                guard rawPoly.count >= 4 else { continue }

                let dpEpsilon = 0.0022 + config.smoothness * 0.0024
                let simplified = douglasPeuckerClosed(rawPoly, epsilon: dpEpsilon)
                guard simplified.count >= 3 else { continue }

                let cornerCount = anatomicalCornerCount(simplified)
                let chaikinPasses = config.smoothness >= 0.72 ? 2 : (config.smoothness >= 0.25 ? 1 : 0)
                let smoothPoly = chaikinPasses > 0 ? chaikinSmooth(simplified, passes: chaikinPasses) : simplified
                guard smoothPoly.count >= 3 else { continue }

                let area = abs(ScalePhotoReview.area(smoothPoly))
                guard area > 1e-5 else { continue }
                let perim = perimeter(of: smoothPoly)
                guard perim > 1e-4 else { continue }

                let circularity = min(1.0, (4.0 * .pi * area) / (perim * perim))
                guard circularity >= 0.22 else { continue }

                // Reject jagged shadow hooks / crescent crevices via convex hull solidity.
                let hullPoly = convexHull(of: smoothPoly)
                let hullArea = abs(ScalePhotoReview.area(hullPoly))
                if hullArea > 1e-6 && (area / hullArea) < 0.48 { continue }

                let moments = polygonMoments(smoothPoly)
                guard moments.aspectRatio <= 4.2 else { continue }

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

        // Strip smaller contours nested inside larger ones (e.g. pupil inside glossy iris ring).
        var nestedChildIndices = Set<Int>()
        var parentsWithNestedChild = Set<Int>()
        for i in extracted.indices {
            for j in extracted.indices where i != j && extracted[j].imageArea > extracted[i].imageArea * 1.4 {
                if ScalePhotoReview.contains(extracted[i].centroid, polygon: extracted[j].polygon) {
                    nestedChildIndices.insert(i)
                    parentsWithNestedChild.insert(j)
                    break
                }
            }
        }

        let unnestedWithFlag = extracted.enumerated().compactMap { idx, raw -> (raw: RawScale, hadNested: Bool)? in
            guard !nestedChildIndices.contains(idx) else { return nil }
            return (raw, parentsWithNestedChild.contains(idx))
        }

        let sortedWithFlag = unnestedWithFlag.sorted { a, b in
            let bandA = Int((a.raw.centroid.y * 14.0).rounded())
            let bandB = Int((b.raw.centroid.y * 14.0).rounded())
            return bandA == bandB ? a.raw.centroid.x < b.raw.centroid.x : bandA < bandB
        }

        let capped = Array(sortedWithFlag.prefix(24))
        var numbered = capped.enumerated().map { idx, item in
            DetectedScalePattern(
                number: idx + 1,
                polygon: item.raw.polygon,
                centroid: item.raw.centroid,
                roiAreaFraction: item.raw.roiAreaFraction,
                imageArea: item.raw.imageArea,
                vertexCount: item.raw.vertexCount,
                circularity: item.raw.circularity,
                aspectRatio: item.raw.aspectRatio,
                orientationDeg: item.raw.orientationDeg
            )
        }
        let nestedParentNumbers = Set(capped.enumerated().compactMap { $0.element.hadNested ? ($0.offset + 1) : nil })

        if let side, numbered.count >= 4 {
            let filtered = filterOutEyeball(
                scales: numbered,
                raster: raster,
                smooth3: smooth3,
                side: side,
                nestedParentNumbers: nestedParentNumbers
            )
            if filtered.count != numbered.count, filtered.count >= 3 {
                numbered = filtered.enumerated().map { idx, pat in
                    DetectedScalePattern(
                        number: idx + 1,
                        polygon: pat.polygon,
                        centroid: pat.centroid,
                        roiAreaFraction: pat.roiAreaFraction,
                        imageArea: pat.imageArea,
                        vertexCount: pat.vertexCount,
                        circularity: pat.circularity,
                        aspectRatio: pat.aspectRatio,
                        orientationDeg: pat.orientationDeg
                    )
                }
            }
        }

        return numbered
    }

    // MARK: - Automatic Facial Pattern ROI Localization (Ocean-Masked + Eyeball-Filtered)

    @MainActor
    static func detectFacialPatternROI(
        from image: NSImage,
        side: TurtlePhotoSide
    ) -> (roi: [ScalePoint], ref1: ScalePoint, ref2: ScalePoint, ref3: ScalePoint) {
        guard let raster = underwaterLuminanceRaster(from: image, maxDimension: 420) else {
            return fallbackTemplate(side: side)
        }
        return detectFacialPatternROI(from: raster, side: side)
    }

    static func detectFacialPatternROI(
        from raster: (pixels: [Float], width: Int, height: Int),
        side: TurtlePhotoSide
    ) -> (roi: [ScalePoint], ref1: ScalePoint, ref2: ScalePoint, ref3: ScalePoint) {
        detectFacialPatternROI(
            from: LuminanceRaster(pixels: raster.pixels, width: raster.width, height: raster.height),
            side: side
        )
    }

    static func detectFacialPatternROI(
        from raster: LuminanceRaster,
        side: TurtlePhotoSide
    ) -> (roi: [ScalePoint], ref1: ScalePoint, ref2: ScalePoint, ref3: ScalePoint) {
        let searchROI = [
            ScalePoint(x: 0.03, y: 0.03),
            ScalePoint(x: 0.97, y: 0.03),
            ScalePoint(x: 0.97, y: 0.96),
            ScalePoint(x: 0.03, y: 0.96),
        ]

        let candidates = extractPatterns(
            from: raster,
            roiPolygon: searchROI,
            config: PatternExtractionConfig(
                sensitivity: 0.48,
                smoothness: 0.55,
                minScaleROIFilter: 0.0014,
                maxScaleROIFilter: 0.060
            ),
            side: side
        ).filter { $0.circularity >= 0.34 && $0.aspectRatio <= 3.4 }

        guard candidates.count >= 4 else {
            return fallbackTemplate(side: side)
        }

        // Weight anchor candidates by scale area & circularity so bold post-ocular cheek scutes
        // outvote dense clusters of tiny neck speckles or distant flipper scutes.
        let neighborRadius = 0.24
        var bestAnchorIndex = 0
        var bestDensityScore = -1.0
        for i in candidates.indices {
            let cand = candidates[i]
            let sidePreference: Double = {
                switch side {
                case .left:
                    return (cand.centroid.x >= 0.36 && cand.centroid.x <= 0.90) ? 1.24 : 0.82
                case .right:
                    return (cand.centroid.x >= 0.10 && cand.centroid.x <= 0.64) ? 1.24 : 0.82
                }
            }()
            let verticalPref: Double = (cand.centroid.y >= 0.18 && cand.centroid.y <= 0.78) ? 1.12 : 0.82
            let score = candidates.reduce(0.0) { acc, other in
                let dist = hypot(cand.centroid.x - other.centroid.x, cand.centroid.y - other.centroid.y)
                guard dist <= neighborRadius else { return acc }
                if segmentCrossesWater(from: cand.centroid, to: other.centroid, raster: raster) {
                    return acc
                }
                let areaWeight = sqrt(max(1e-5, other.imageArea))
                return acc + areaWeight * other.circularity * (1.0 - dist / (neighborRadius * 1.25))
            } * sidePreference * verticalPref
            if score > bestDensityScore {
                bestDensityScore = score
                bestAnchorIndex = i
            }
        }

        // Grow contiguous facial scale cluster via BFS without crossing open ocean water.
        let bestAnchor = candidates[bestAnchorIndex]
        let anchorMinChainArea = max(0.0020, bestAnchor.imageArea * 0.16)
        var included = Set<Int>([bestAnchorIndex])
        var queue = [bestAnchorIndex]
        var head = 0
        while head < queue.count {
            let currIdx = queue[head]
            head += 1
            let curr = candidates[currIdx]
            if currIdx != bestAnchorIndex && curr.imageArea < anchorMinChainArea { continue }
            let rCurr = sqrt(max(1e-5, curr.imageArea) / .pi)
            for j in candidates.indices where !included.contains(j) {
                let other = candidates[j]
                let distFromAnchor = hypot(other.centroid.x - bestAnchor.centroid.x, other.centroid.y - bestAnchor.centroid.y)
                guard distFromAnchor <= 0.42 else { continue }
                let rOther = sqrt(max(1e-5, other.imageArea) / .pi)
                let linkThreshold = max(0.088, 2.25 * (rCurr + rOther))
                let dist = hypot(other.centroid.x - curr.centroid.x, other.centroid.y - curr.centroid.y)
                guard dist <= linkThreshold else { continue }
                guard !segmentCrossesWater(from: curr.centroid, to: other.centroid, raster: raster) else { continue }
                included.insert(j)
                queue.append(j)
            }
        }

        let clusterScales = included.sorted().map { candidates[$0] }
        let smooth3 = gaussianSmooth3x3(raster.pixels, width: raster.width, height: raster.height)
        let cleanedCluster = filterOutEyeball(scales: clusterScales, raster: raster, smooth3: smooth3, side: side)
        let finalCluster = cleanedCluster.count >= 3 ? cleanedCluster : clusterScales

        guard finalCluster.count >= 3 else {
            return fallbackTemplate(side: side)
        }

        let roi: [ScalePoint]
        if let tightPoly = buildTightClusterROI(scales: finalCluster, raster: raster) {
            roi = tightPoly
        } else {
            var clusterPoints: [ScalePoint] = []
            for s in finalCluster { clusterPoints.append(contentsOf: s.polygon) }
            let hull = paddedConvexHull(points: clusterPoints, padding: 0.022)
            roi = hull.count >= 4 ? hull : fallbackTemplate(side: side).roi
        }

        let minX = roi.map(\.x).min() ?? 0.25
        let maxX = roi.map(\.x).max() ?? 0.75
        let minY = roi.map(\.y).min() ?? 0.22
        let maxY = roi.map(\.y).max() ?? 0.72
        let rw = max(0.12, maxX - minX)
        let rh = max(0.12, maxY - minY)
        let cx = (minX + maxX) * 0.5
        let cy = (minY + maxY) * 0.5

        let ref1: ScalePoint
        let ref2: ScalePoint
        let ref3: ScalePoint
        if side == .left {
            ref1 = ScalePoint(x: max(0.03, minX - rw * 0.14), y: min(0.96, maxY + rh * 0.08))
            ref2 = ScalePoint(x: max(0.04, cx - rw * 0.38), y: max(0.04, cy - rh * 0.15))
            ref3 = ScalePoint(x: min(0.96, maxX + rw * 0.02), y: max(0.05, minY + rh * 0.15))
        } else {
            ref1 = ScalePoint(x: min(0.97, maxX + rw * 0.14), y: min(0.96, maxY + rh * 0.08))
            ref2 = ScalePoint(x: min(0.96, cx + rw * 0.38), y: max(0.04, cy - rh * 0.15))
            ref3 = ScalePoint(x: max(0.04, minX - rw * 0.02), y: max(0.05, minY + rh * 0.15))
        }

        return (roi, ref1, ref2, ref3)
    }

    // MARK: - Watertight Polygonal Keratin Suture Mesh

    @MainActor
    static func extractScaleSutureMesh(
        from image: NSImage,
        roiPolygon: [ScalePoint],
        patterns: [DetectedScalePattern]? = nil,
        config: PatternExtractionConfig = .init()
    ) -> ScaleSutureMesh {
        guard let raster = underwaterLuminanceRaster(from: image, maxDimension: 420) else { return .empty }
        return extractScaleSutureMesh(from: raster, roiPolygon: roiPolygon, patterns: patterns, config: config)
    }

    static func extractScaleSutureMesh(
        from raster: (pixels: [Float], width: Int, height: Int),
        roiPolygon: [ScalePoint],
        patterns: [DetectedScalePattern]? = nil,
        config: PatternExtractionConfig = .init()
    ) -> ScaleSutureMesh {
        extractScaleSutureMesh(
            from: LuminanceRaster(pixels: raster.pixels, width: raster.width, height: raster.height),
            roiPolygon: roiPolygon,
            patterns: patterns,
            config: config
        )
    }

    static func extractScaleSutureMesh(
        from raster: LuminanceRaster,
        roiPolygon: [ScalePoint],
        patterns: [DetectedScalePattern]? = nil,
        config: PatternExtractionConfig = .init()
    ) -> ScaleSutureMesh {
        let w = raster.width
        let h = raster.height
        guard w >= 16, h >= 16, raster.pixels.count == w * h, roiPolygon.count >= 3, !Task.isCancelled else {
            return .empty
        }

        let smooth3 = gaussianSmooth3x3(raster.pixels, width: w, height: h)
        let smooth5 = gaussianSmooth5x5(raster.pixels, width: w, height: h)
        let roiMask = rasterizeROI(roiPolygon, width: w, height: h)
        guard roiMask.count >= 36, roiMask.maxX > roiMask.minX, roiMask.maxY > roiMask.minY else {
            return .empty
        }

        let hasWater = raster.hasWaterMask
        let basePatterns = patterns ?? extractPatterns(from: raster, roiPolygon: roiPolygon, config: config)

        var domainMask = [Bool](repeating: false, count: w * h)
        var coreMasks: [[Int]] = []
        var seedLabels: [Int] = []

        if basePatterns.count >= 2 {
            var unionMask = [Bool](repeating: false, count: w * h)
            var radiiPx: [Double] = []
            for pat in basePatterns {
                let pMask = rasterizeROI(pat.polygon, width: w, height: h)
                var pixels: [Int] = []
                pixels.reserveCapacity(pMask.count)
                if pMask.count > 0 {
                    for y in pMask.minY...pMask.maxY {
                        let row = y * w
                        for x in pMask.minX...pMask.maxX {
                            let idx = row + x
                            if pMask.inside[idx] && !(hasWater && raster.isWater[idx]) {
                                unionMask[idx] = true
                                pixels.append(idx)
                            }
                        }
                    }
                }
                if pixels.isEmpty {
                    let cx = min(w - 1, max(0, Int((pat.centroid.x * Double(w)).rounded())))
                    let cy = min(h - 1, max(0, Int((pat.centroid.y * Double(h)).rounded())))
                    let cidx = cy * w + cx
                    if !(hasWater && raster.isWater[cidx]) {
                        unionMask[cidx] = true
                        pixels.append(cidx)
                    }
                }
                guard !pixels.isEmpty else { continue }
                radiiPx.append(sqrt(Double(pixels.count) / .pi))
                coreMasks.append(pixels)
                seedLabels.append(pat.number)
            }

            guard coreMasks.count >= 2 else { return .empty }
            let sortedRadii = radiiPx.sorted()
            let medianR = sortedRadii[sortedRadii.count / 2]
            let suturePad = max(5, min(14, Int((medianR * 0.52).rounded())))
            var dilated = morphDilateDisk(unionMask, width: w, height: h, radius: suturePad)
            let closeR = max(3, min(7, suturePad / 2 + 1))
            dilated = morphCloseDisk(dilated, width: w, height: h, radius: closeR)

            for i in 0..<(w * h) {
                if hasWater && raster.isWater[i] { continue }
                if unionMask[i] || (dilated[i] && roiMask.inside[i]) {
                    domainMask[i] = true
                }
            }
        } else {
            for i in 0..<(w * h) {
                if roiMask.inside[i] && !(hasWater && raster.isWater[i]) {
                    domainMask[i] = true
                }
            }
        }

        var domMinX = w - 1, domMaxX = 0, domMinY = h - 1, domMaxY = 0
        var domCount = 0
        var minL = Float.greatestFiniteMagnitude
        var maxL = -Float.greatestFiniteMagnitude
        for y in 0..<h {
            let row = y * w
            for x in 0..<w {
                let idx = row + x
                guard domainMask[idx] else { continue }
                domCount += 1
                if x < domMinX { domMinX = x }
                if x > domMaxX { domMaxX = x }
                if y < domMinY { domMinY = y }
                if y > domMaxY { domMaxY = y }
                let v = smooth3[idx]
                if v < minL { minL = v }
                if v > maxL { maxL = v }
            }
        }
        guard domCount >= 36, domMaxX > domMinX, domMaxY > domMinY else { return .empty }

        let spanL = max(Float(0.03), maxL - minL)
        let roiNormalizedArea = max(1e-5, Double(domCount) / Double(w * h))
        let roiDiag = max(0.08, hypot(Double(domMaxX - domMinX) / Double(w), Double(domMaxY - domMinY) / Double(h)))

        let stride = w + 1
        let macroInt = buildIntegral(smooth5, width: w, height: h)
        let microInt = buildIntegral(smooth3, width: w, height: h)
        let domSpan = min(domMaxX - domMinX, domMaxY - domMinY)
        let rMacro = max(10, min(38, Int(Double(domSpan) * 0.14)))
        let rMicro = max(3, min(8, Int(Double(domSpan) * 0.032)))

        @inline(__always)
        func meanBox(_ intg: IntegralImage, _ cx: Int, _ cy: Int, _ r: Int) -> Double {
            let x0 = max(0, cx - r)
            let y0 = max(0, cy - r)
            let x1 = min(w - 1, cx + r)
            let y1 = min(h - 1, cy + r)
            let area = Double((x1 - x0 + 1) * (y1 - y0 + 1))
            let sum = intg.sum[(y1 + 1) * stride + (x1 + 1)]
                - intg.sum[y0 * stride + (x1 + 1)]
                - intg.sum[(y1 + 1) * stride + x0]
                + intg.sum[y0 * stride + x0]
            return sum / area
        }

        var ridgeHeight = [Float](repeating: 1.0, count: w * h)
        var maxRidge: Float = 0.05
        for y in domMinY...domMaxY {
            let row = y * w
            for x in domMinX...domMaxX {
                let idx = row + x
                guard domainMask[idx] else { continue }
                let val = Double(smooth3[idx])
                let macroM = meanBox(macroInt, x, y, rMacro)
                let microM = meanBox(microInt, x, y, rMicro)
                let macroHigh = max(0.0, val - macroM)
                let microHigh = max(0.0, val - microM)
                var dirRidge = 0.0
                if x >= 2 && x <= w - 3 && y >= 2 && y <= h - 3 {
                    let hR = val - 0.5 * Double(smooth3[idx - 2] + smooth3[idx + 2])
                    let vR = val - 0.5 * Double(smooth3[idx - 2 * w] + smooth3[idx + 2 * w])
                    let d1R = val - 0.5 * Double(smooth3[idx - 2 * w - 2] + smooth3[idx + 2 * w + 2])
                    let d2R = val - 0.5 * Double(smooth3[idx - 2 * w + 2] + smooth3[idx + 2 * w - 2])
                    dirRidge = max(0.0, max(max(hR, vR), max(d1R, d2R)))
                }
                let localLum = Double((smooth3[idx] - minL) / spanL)
                let ridge = Float(1.75 * macroHigh + 1.45 * microHigh + 2.15 * dirRidge + 0.16 * localLum)
                ridgeHeight[idx] = ridge
                if ridge > maxRidge { maxRidge = ridge }
            }
        }
        let invMaxRidge: Float = 1.0 / max(Float(0.05), maxRidge)

        if coreMasks.count < 2 {
            let step = max(3, domSpan / 12)
            let minSeedSep = max(0.05, roiDiag * 0.12)
            var candidates: [(pt: ScalePoint, idx: Int, lum: Float)] = []
            var yy = domMinY + 2
            while yy <= domMaxY - 2 {
                var xx = domMinX + 2
                while xx <= domMaxX - 2 {
                    let p = yy * w + xx
                    if domainMask[p] {
                        let centerLum = smooth3[p]
                        var isLocalMin = centerLum < minL + spanL * 0.55
                        if isLocalMin {
                            for dy in -2...2 where isLocalMin {
                                for dx in -2...2 {
                                    let q = (yy + dy) * w + (xx + dx)
                                    if smooth3[q] + 0.004 < centerLum { isLocalMin = false; break }
                                }
                            }
                        }
                        if isLocalMin {
                            let npt = ScalePoint(x: (Double(xx) + 0.5) / Double(w), y: (Double(yy) + 0.5) / Double(h))
                            candidates.append((npt, p, centerLum))
                        }
                    }
                    xx += step
                }
                yy += step
            }
            candidates.sort { $0.lum < $1.lum }
            var chosenPts: [ScalePoint] = []
            for cand in candidates {
                if chosenPts.count >= 16 { break }
                if chosenPts.allSatisfy({ hypot($0.x - cand.pt.x, $0.y - cand.pt.y) >= minSeedSep }) {
                    chosenPts.append(cand.pt)
                    coreMasks.append([cand.idx])
                    seedLabels.append(chosenPts.count)
                }
            }
        }
        guard coreMasks.count >= 2 else { return .empty }

        var regionLabel = [Int](repeating: 0, count: w * h)
        var depthMap = [Int](repeating: 0, count: w * h)
        var buckets = [[Int]](repeating: [], count: 256)
        var nonEmptyMinBucket = 256

        var rawCoreOwner = [Int](repeating: 0, count: w * h)
        for (i, pixels) in coreMasks.enumerated() {
            let lbl = i + 1
            for p in pixels {
                if rawCoreOwner[p] == 0 { rawCoreOwner[p] = lbl }
            }
        }

        for (i, pixels) in coreMasks.enumerated() {
            let lbl = i + 1
            var seededAny = false
            for p in pixels {
                let px = p % w, py = p / w
                let isInterior = px > 0 && px < w - 1 && py > 0 && py < h - 1
                    && rawCoreOwner[p - 1] == lbl && rawCoreOwner[p + 1] == lbl
                    && rawCoreOwner[p - w] == lbl && rawCoreOwner[p + w] == lbl
                if isInterior && regionLabel[p] == 0 {
                    regionLabel[p] = lbl
                    buckets[0].append(p)
                    seededAny = true
                }
            }
            if !seededAny {
                for p in pixels where regionLabel[p] == 0 {
                    regionLabel[p] = lbl
                    buckets[0].append(p)
                    seededAny = true
                }
            }
            if seededAny { nonEmptyMinBucket = 0 }
        }

        while nonEmptyMinBucket < 256 {
            if buckets[nonEmptyMinBucket].isEmpty {
                nonEmptyMinBucket += 1
                continue
            }
            if Task.isCancelled { return .empty }
            let p = buckets[nonEmptyMinBucket].removeLast()
            let px = p % w
            let py = p / w
            let lbl = regionLabel[p]
            let nextDepth = depthMap[p] + 1

            let neighbors = [
                px > domMinX ? p - 1 : -1,
                px < domMaxX ? p + 1 : -1,
                py > domMinY ? p - w : -1,
                py < domMaxY ? p + w : -1,
            ]
            for nb in neighbors where nb >= 0 && domainMask[nb] && regionLabel[nb] == 0 {
                regionLabel[nb] = lbl
                depthMap[nb] = nextDepth
                let normRidge = min(1.0, max(0.0, Double(ridgeHeight[nb] * invMaxRidge)))
                let b = max(nonEmptyMinBucket, min(255, Int((normRidge * 238.0 + Double(nextDepth) * 0.16).rounded())))
                buckets[b].append(nb)
            }
        }

        var cleanLabels = regionLabel
        if domMaxY - 1 >= max(1, domMinY) && domMaxX - 1 >= max(1, domMinX) {
            for y in max(1, domMinY)...min(h - 2, domMaxY) {
                for x in max(1, domMinX)...min(w - 2, domMaxX) {
                    let p = y * w + x
                    guard domainMask[p] else { continue }
                    let n1 = regionLabel[p - 1], n2 = regionLabel[p + 1]
                    let n3 = regionLabel[p - w], n4 = regionLabel[p + w]
                    if n1 > 0 && n1 == n2 && n1 == n3 && n1 != cleanLabels[p] {
                        cleanLabels[p] = n1
                    } else if n2 > 0 && n2 == n3 && n2 == n4 && n2 != cleanLabels[p] {
                        cleanLabels[p] = n2
                    }
                }
            }
        }

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

        for y in domMinY...(domMaxY + 1) {
            for x in domMinX...domMaxX {
                let topL = labelAt(x, y - 1)
                let botL = labelAt(x, y)
                guard topL != botL, (topL > 0 || botL > 0) else { continue }
                let a = y * stride + x
                let b = y * stride + (x + 1)
                if topL < botL {
                    cracksByFrom[a, default: []].append(DirectedCrack(from: a, to: b, leftLabel: topL, rightLabel: botL))
                } else {
                    cracksByFrom[b, default: []].append(DirectedCrack(from: b, to: a, leftLabel: botL, rightLabel: topL))
                }
                undirectedDegree[a, default: 0] += 1
                undirectedDegree[b, default: 0] += 1
            }
        }
        for y in domMinY...domMaxY {
            for x in domMinX...(domMaxX + 1) {
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

        var gridToVertexID: [Int: Int] = [:]
        var vertices: [ScaleMeshVertex] = []
        @inline(__always) func gridPoint(_ gv: Int) -> ScalePoint {
            ScalePoint(x: Double(gv % stride) / Double(w), y: Double(gv / stride) / Double(h))
        }
        func junctionVertexID(for gv: Int, isBoundary: Bool) -> Int {
            if let existing = gridToVertexID[gv] { return existing }
            let id = vertices.count
            vertices.append(ScaleMeshVertex(id: id, point: gridPoint(gv), isBoundary: isBoundary))
            gridToVertexID[gv] = id
            return id
        }
        func interiorVertexID(for pt: ScalePoint, isBoundary: Bool) -> Int {
            let id = vertices.count
            vertices.append(ScaleMeshVertex(id: id, point: pt, isBoundary: isBoundary))
            return id
        }

        let isJunctionNode: (Int) -> Bool = { gv in (undirectedDegree[gv] ?? 0) != 2 }
        var consumedCracks = Set<UInt64>()
        @inline(__always) func edgeKey(_ a: Int, _ b: Int) -> UInt64 {
            (UInt64(min(a, b)) << 32) | UInt64(max(a, b))
        }

        struct RawChain {
            let low: Int
            let high: Int
            let vertexIDs: [Int]
        }
        var rawChains: [RawChain] = []
        let allStarts = cracksByFrom.keys.sorted()

        for pass in 0...1 {
            for startGV in allStarts {
                if pass == 0 && !isJunctionNode(startGV) { continue }
                guard let outgoingList = cracksByFrom[startGV] else { continue }
                for initial in outgoingList {
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
                        guard let nextCrack = cracksByFrom[current]?.first(where: {
                            $0.leftLabel == low && $0.rightLabel == high && !consumedCracks.contains(edgeKey($0.from, $0.to))
                        }) else { break }
                        consumedCracks.insert(edgeKey(nextCrack.from, nextCrack.to))
                        current = nextCrack.to
                        chainGVs.append(current)
                    }

                    guard chainGVs.count >= 2 else { continue }
                    let rawPts = chainGVs.map { gridPoint($0) }
                    let isOuter = low == 0
                    let isClosedLoop = chainGVs.first == chainGVs.last && chainGVs.count >= 4

                    let smoothedPts = isClosedLoop
                        ? smoothClosedPolyline(Array(rawPts.dropLast()), passes: 2) + [rawPts[0]]
                        : smoothOpenPolylinePinned(rawPts, passes: 2)
                    let eps = isOuter
                        ? max(0.0032, min(0.0052, roiDiag * 0.0068))
                        : max(0.0028, min(0.0045, roiDiag * 0.0060))
                    let simplifiedPts = douglasPeuckerOpen(smoothedPts, epsilon: eps)

                    var mappedVIDs: [Int] = []
                    mappedVIDs.reserveCapacity(simplifiedPts.count)
                    for (idx, pt) in simplifiedPts.enumerated() {
                        if idx == 0 {
                            mappedVIDs.append(junctionVertexID(for: chainGVs[0], isBoundary: isOuter))
                        } else if idx == simplifiedPts.count - 1 {
                            mappedVIDs.append(junctionVertexID(for: chainGVs[chainGVs.count - 1], isBoundary: isOuter))
                        } else {
                            mappedVIDs.append(interiorVertexID(for: pt, isBoundary: isOuter))
                        }
                    }
                    if mappedVIDs.count >= 2 {
                        rawChains.append(RawChain(low: low, high: high, vertexIDs: mappedVIDs))
                    }
                }
            }
        }

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
            chainsPerCell[chain.high, default: []].append(chain.vertexIDs)
            if chain.low > 0 {
                chainsPerCell[chain.low, default: []].append(Array(chain.vertexIDs.reversed()))
            }
        }

        var builtCells: [ScaleMeshCell] = []
        let vertexLookup = Dictionary(uniqueKeysWithValues: vertices.map { ($0.id, $0.point) })

        for rawCellID in chainsPerCell.keys.sorted() {
            var remaining = chainsPerCell[rawCellID] ?? []
            guard !remaining.isEmpty else { continue }
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
                    vertexCount: anatomicalCornerCount(poly),
                    circularity: circ,
                    aspectRatio: moments.aspectRatio,
                    orientationDeg: moments.orientationDeg
                )
            )
        }

        let sortedCells: [ScaleMeshCell]
        if basePatterns.count >= 2 {
            sortedCells = builtCells.sorted { $0.number < $1.number }
        } else {
            sortedCells = builtCells.sorted { a, b in
                let bandA = Int((a.center.y * 14.0).rounded())
                let bandB = Int((b.center.y * 14.0).rounded())
                return bandA == bandB ? a.center.x < b.center.x : bandA < bandB
            }
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

    // MARK: - Raster Extraction (Full Color + Ocean Water Mask + Legacy Tuple Adapter)

    /// Full underwater luminance + RGB color + border-connected ocean water mask raster.
    @MainActor
    static func underwaterLuminanceRaster(from image: NSImage, maxDimension: Int = 420) -> LuminanceRaster? {
        guard maxDimension >= 16, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return underwaterLuminanceRaster(from: cg, maxDimension: maxDimension)
    }

    /// Nonisolated CGImage rasterizer for background-thread contour & mesh extraction.
    static func underwaterLuminanceRaster(from cgImage: CGImage, maxDimension: Int = 420) -> LuminanceRaster? {
        guard maxDimension >= 16, cgImage.width > 1, cgImage.height > 1 else { return nil }
        let scale = min(1.0, Double(maxDimension) / Double(max(cgImage.width, cgImage.height)))
        let width = max(16, Int((Double(cgImage.width) * scale).rounded()))
        let height = max(16, Int((Double(cgImage.height) * scale).rounded()))

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
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        let n = width * height
        var pixels = [Float](repeating: 0, count: n)
        var red = [Float](repeating: 0, count: n)
        var green = [Float](repeating: 0, count: n)
        var blue = [Float](repeating: 0, count: n)
        var blueExcess = [Float](repeating: 0, count: n)
        var blueMinusRed = [Float](repeating: 0, count: n)

        for i in 0..<n {
            let r = Float(bytes[i * 4]) / 255.0
            let g = Float(bytes[i * 4 + 1]) / 255.0
            let b = Float(bytes[i * 4 + 2]) / 255.0
            red[i] = r
            green[i] = g
            blue[i] = b
            pixels[i] = 0.10 * r + 0.60 * g + 0.30 * b
            blueExcess[i] = max(0, b - max(r, g))
            blueMinusRed[i] = b - r
        }

        let waterMask = computeOceanWaterMask(
            red: red,
            green: green,
            blue: blue,
            lum: pixels,
            blueExcess: blueExcess,
            blueMinusRed: blueMinusRed,
            width: width,
            height: height
        )

        return LuminanceRaster(
            pixels: pixels,
            width: width,
            height: height,
            red: red,
            green: green,
            blue: blue,
            blueExcess: blueExcess,
            blueMinusRed: blueMinusRed,
            isWater: waterMask
        )
    }

    /// Backwards-compatible luminance tuple helper for existing callers.
    @MainActor
    static func underwaterLuminance(from image: NSImage, maxDimension: Int = 640) -> (pixels: [Float], width: Int, height: Int)? {
        guard let raster = underwaterLuminanceRaster(from: image, maxDimension: maxDimension) else { return nil }
        return (raster.pixels, raster.width, raster.height)
    }

    // MARK: - Internal CV Primitives (Integral Image, Ocean Water Mask, Suture Ring, Eyeball Filter)

    private struct IntegralImage {
        let sum: [Double]
        let sumSq: [Double]
        let stride: Int
    }

    private static func buildIntegral(_ input: [Float], width w: Int, height h: Int) -> IntegralImage {
        let stride = w + 1
        var sum = [Double](repeating: 0, count: stride * (h + 1))
        var sumSq = [Double](repeating: 0, count: stride * (h + 1))
        for y in 0..<h {
            var rowSum = 0.0
            var rowSq = 0.0
            let rowBase = y * w
            let dstRow = (y + 1) * stride
            let prevRow = y * stride
            for x in 0..<w {
                let v = Double(input[rowBase + x])
                rowSum += v
                rowSq += v * v
                sum[dstRow + x + 1] = sum[prevRow + x + 1] + rowSum
                sumSq[dstRow + x + 1] = sumSq[prevRow + x + 1] + rowSq
            }
        }
        return IntegralImage(sum: sum, sumSq: sumSq, stride: stride)
    }

    private static func computeOceanWaterMask(
        red: [Float],
        green: [Float],
        blue: [Float],
        lum: [Float],
        blueExcess: [Float],
        blueMinusRed: [Float],
        width w: Int,
        height h: Int
    ) -> [Bool] {
        let n = w * h
        guard n > 0 else { return [] }
        let smooth3 = gaussianSmooth3x3(lum, width: w, height: h)
        let microInt = buildIntegral(smooth3, width: w, height: h)
        let intStride = w + 1

        @inline(__always)
        func localMean3(_ x: Int, _ y: Int) -> Float {
            let x0 = max(0, x - 3), y0 = max(0, y - 3)
            let x1 = min(w - 1, x + 3), y1 = min(h - 1, y + 3)
            let area = Double((x1 - x0 + 1) * (y1 - y0 + 1))
            let sum = microInt.sum[(y1 + 1) * intStride + (x1 + 1)]
                - microInt.sum[y0 * intStride + (x1 + 1)]
                - microInt.sum[(y1 + 1) * intStride + x0]
                + microInt.sum[y0 * intStride + x0]
            return Float(sum / area)
        }

        // Detect globally blue-green deep-water monochrome cast (e.g. hazy deep shots where red light
        // is absorbed across BOTH the water AND the turtle's cheek). In that regime, absolute teal
        // thresholds would flood right across the turtle's head, so restrict water flooding to strict
        // high-blue-excess open water only.
        var globalTealPixels = 0
        for i in 0..<n {
            if blueMinusRed[i] > 0.19 && blue[i] >= green[i] - 0.025 {
                globalTealPixels += 1
            }
        }
        let hasGlobalDeepWaterCast = Double(globalTealPixels) / Double(n) > 0.62

        func runFlood(strict: Bool) -> [Bool] {
            var isWater = [Bool](repeating: false, count: n)
            var seedOf = [Int](repeating: -1, count: n)
            var queue: [Int] = []
            queue.reserveCapacity(n / 4)

            let allowTealFlood = !strict && !hasGlobalDeepWaterCast
            let minSeedBEx: Float = strict ? 0.11 : 0.055
            let minSeedBMR: Float = strict ? 0.22 : 0.13

            @inline(__always)
            func trySeed(_ idx: Int) {
                guard !isWater[idx] else { return }
                let bEx = blueExcess[idx]
                let bmr = blueMinusRed[idx]
                let isBlue = bEx > minSeedBEx && bmr > minSeedBMR
                let isTeal = allowTealFlood && bEx > 0.04 && bmr > 0.22 && blue[idx] >= green[idx] - 0.03 && lum[idx] > 0.20
                if isBlue || isTeal {
                    isWater[idx] = true
                    seedOf[idx] = idx
                    queue.append(idx)
                }
            }

            let borderDepth = min(2, min(w, h) / 4)
            for b in 0..<max(1, borderDepth) {
                for x in 0..<w {
                    trySeed(b * w + x)
                    trySeed((h - 1 - b) * w + x)
                }
                for y in 0..<h {
                    trySeed(y * w + b)
                    trySeed(y * w + (w - 1 - b))
                }
            }

            let minGrowBEx: Float = strict ? 0.115 : 0.080
            let minGrowBMR: Float = strict ? 0.22 : 0.165

            var cursor = 0
            while cursor < queue.count {
                let p = queue[cursor]
                cursor += 1
                let px = p % w
                let py = p / w
                let s = seedOf[p]
                let sr = red[s], sg = green[s], sb = blue[s]
                let sBEx = blueExcess[s]
                let sLum = smooth3[s]

                let neighbors = [
                    px > 0 ? p - 1 : -1,
                    px < w - 1 ? p + 1 : -1,
                    py > 0 ? p - w : -1,
                    py < h - 1 ? p + w : -1,
                ]
                for q in neighbors where q >= 0 && !isWater[q] {
                    let bEx = blueExcess[q]
                    let bmr = blueMinusRed[q]
                    let ql = smooth3[q]
                    if ql > 0.45 && bEx < 0.06 { continue }
                    if bEx < 0.05 && bmr < 0.145 { continue }

                    let qx = q % w
                    let qy = q / w
                    let stepJump = abs(ql - smooth3[p])
                    let colorDist = abs(red[q] - sr) + abs(green[q] - sg) + abs(blue[q] - sb)

                    if stepJump > 0.065 && bEx < 0.24 { continue }
                    if (ql - localMean3(qx, qy)) > 0.022 && bEx < 0.22 { continue }

                    if ql < sLum - 0.16 && bEx < 0.18 { continue }
                    if red[q] > sr + 0.075 && bEx < sBEx - 0.09 { continue }
                    if bEx < sBEx - 0.14 && ql > sLum + 0.05 { continue }

                    let deepRippleBlue = bEx > 0.14 && bmr > 0.30 && red[q] < 0.09 && ql < 0.48
                    let coherentBlue = bEx > minGrowBEx && bmr > minGrowBMR && colorDist < 0.36 && abs(ql - sLum) < 0.22
                    let smoothTeal = allowTealFlood
                        && bEx > 0.04
                        && bmr > 0.19
                        && blue[q] >= green[q] - 0.025
                        && colorDist < 0.24
                        && abs(ql - sLum) < 0.16
                        && stepJump < 0.045
                    if deepRippleBlue || coherentBlue || smoothTeal {
                        isWater[q] = true
                        seedOf[q] = s
                        queue.append(q)
                    }
                }
            }
            return isWater
        }

        var water = runFlood(strict: hasGlobalDeepWaterCast)
        let waterCount = water.reduce(0) { $0 + ($1 ? 1 : 0) }
        if !hasGlobalDeepWaterCast && Double(waterCount) / Double(n) > 0.65 {
            water = runFlood(strict: true)
        }

        water = morphCloseDisk(water, width: w, height: h, radius: 1)

        var expanded = water
        for y in 1..<(h - 1) {
            let row = y * w
            for x in 1..<(w - 1) {
                let idx = row + x
                guard !water[idx] else { continue }
                guard blueExcess[idx] > 0.055 && blueMinusRed[idx] > 0.13 else { continue }
                if water[idx - 1] || water[idx + 1] || water[idx - w] || water[idx + w] {
                    expanded[idx] = true
                }
            }
        }
        return expanded
    }

    private static func segmentCrossesWater(
        from a: ScalePoint,
        to b: ScalePoint,
        raster: LuminanceRaster
    ) -> Bool {
        guard raster.hasWaterMask else { return false }
        let w = raster.width
        let h = raster.height
        var waterHits = 0
        for step in 1...7 {
            let t = Double(step) / 8.0
            let x = min(w - 1, max(0, Int(((a.x + (b.x - a.x) * t) * Double(w)).rounded())))
            let y = min(h - 1, max(0, Int(((a.y + (b.y - a.y) * t) * Double(h)).rounded())))
            if raster.isWater[y * w + x] {
                waterHits += 1
                if waterHits >= 2 { return true }
            }
        }
        return false
    }

    private struct SutureRingValidation {
        let isValid: Bool
        let ringContrast: Double
        let brightOctants: Int
    }

    private static func validateSurroundingSutureRing(
        componentPixels: [Int],
        labels: [Int],
        targetLabel: Int,
        centerX: Double,
        centerY: Double,
        coreMeanLum: Double,
        raster: LuminanceRaster,
        smooth3: [Float],
        hasWater: Bool,
        hasColor: Bool
    ) -> SutureRingValidation {
        let w = raster.width
        let h = raster.height
        let ringRadius = 4

        var minX = w - 1, maxX = 0, minY = h - 1, maxY = 0
        for p in componentPixels {
            let px = p % w, py = p / w
            if px < minX { minX = px }
            if px > maxX { maxX = px }
            if py < minY { minY = py }
            if py > maxY { maxY = py }
        }
        let bx0 = max(0, minX - ringRadius)
        let bx1 = min(w - 1, maxX + ringRadius)
        let by0 = max(0, minY - ringRadius)
        let by1 = min(h - 1, maxY + ringRadius)
        let bw = bx1 - bx0 + 1
        let bh = by1 - by0 + 1

        var dist = [UInt8](repeating: 255, count: bw * bh)
        var bfs: [Int] = []
        bfs.reserveCapacity(componentPixels.count / 2 + 64)

        for p in componentPixels {
            let px = p % w, py = p / w
            let lidx = (py - by0) * bw + (px - bx0)
            dist[lidx] = 0
            if px == 0 || px == w - 1 || py == 0 || py == h - 1
                || labels[p - 1] != targetLabel || labels[p + 1] != targetLabel
                || labels[p - w] != targetLabel || labels[p + w] != targetLabel {
                bfs.append(lidx)
            }
        }

        var totalRing = 0
        var waterRing = 0
        var blueRing = 0
        var octantLums = [[Double]](repeating: [], count: 8)

        var cursor = 0
        while cursor < bfs.count {
            let cur = bfs[cursor]
            cursor += 1
            let d = dist[cur]
            if d >= UInt8(ringRadius) { continue }
            let lx = cur % bw
            let ly = cur / bw
            let nextD = d + 1

            let nbs = [
                lx > 0 ? cur - 1 : -1,
                lx < bw - 1 ? cur + 1 : -1,
                ly > 0 ? cur - bw : -1,
                ly < bh - 1 ? cur + bw : -1,
            ]
            for nb in nbs where nb >= 0 && dist[nb] == 255 {
                dist[nb] = nextD
                bfs.append(nb)
                if nextD >= 2 {
                    let gx = bx0 + (nb % bw)
                    let gy = by0 + (nb / bw)
                    let gidx = gy * w + gx
                    totalRing += 1
                    if hasWater && raster.isWater[gidx] {
                        waterRing += 1
                        continue
                    }
                    if hasColor && raster.blueExcess[gidx] > 0.11 && raster.blueMinusRed[gidx] > 0.24 {
                        blueRing += 1
                    }
                    let angle = atan2(Double(gy) - centerY, Double(gx) - centerX)
                    let oct = min(7, max(0, Int(((angle + .pi) / (2.0 * .pi)) * 8.0) % 8))
                    octantLums[oct].append(Double(smooth3[gidx]))
                }
            }
        }

        guard totalRing >= 12 else {
            return SutureRingValidation(isValid: false, ringContrast: 0, brightOctants: 0)
        }
        if hasWater && Double(waterRing) / Double(totalRing) > 0.16 {
            return SutureRingValidation(isValid: false, ringContrast: 0, brightOctants: 0)
        }
        if hasColor && Double(blueRing) / Double(totalRing) > 0.42 {
            return SutureRingValidation(isValid: false, ringContrast: 0, brightOctants: 0)
        }

        let octantContrastThresh = coreMeanLum < 0.18 ? 0.024 : 0.032
        var populatedOctants = 0
        var brightOctants = 0
        var octantSum = 0.0
        for bucket in octantLums where !bucket.isEmpty {
            populatedOctants += 1
            let sorted = bucket.sorted()
            let p75 = sorted[min(sorted.count - 1, (sorted.count * 3) / 4)]
            octantSum += p75
            if p75 >= coreMeanLum + octantContrastThresh {
                brightOctants += 1
            }
        }

        guard populatedOctants >= 6 else {
            return SutureRingValidation(isValid: false, ringContrast: 0, brightOctants: brightOctants)
        }
        let ringContrast = (octantSum / Double(populatedOctants)) - coreMeanLum
        let minRingContrast = coreMeanLum < 0.18 ? 0.030 : 0.042
        let valid = brightOctants >= 5 && ringContrast >= minRingContrast
        return SutureRingValidation(isValid: valid, ringContrast: ringContrast, brightOctants: brightOctants)
    }

    private static func filterOutEyeball(
        scales: [DetectedScalePattern],
        raster: LuminanceRaster,
        smooth3: [Float],
        side: TurtlePhotoSide,
        nestedParentNumbers: Set<Int> = []
    ) -> [DetectedScalePattern] {
        guard scales.count >= 4 else { return scales }
        let w = raster.width
        let h = raster.height
        let hasWater = raster.hasWaterMask
        let anteriorSign: Double = (side == .left) ? -1.0 : 1.0

        let sortedAreas = scales.map(\.imageArea).sorted()
        let medianArea = sortedAreas[sortedAreas.count / 2]
        let minY = scales.map(\.centroid.y).min() ?? 0.2
        let maxY = scales.map(\.centroid.y).max() ?? 0.8
        let ySpan = max(0.12, maxY - minY)

        var bestEyeIndex: Int? = nil
        var bestEyeScore: Double = 0.0

        for (idx, s) in scales.enumerated() {
            guard s.imageArea >= max(0.0065, medianArea * 0.72) else { continue }
            guard s.centroid.y <= minY + ySpan * 0.68 else { continue }

            let anteriorNeighbors = scales.enumerated().filter { j, other in
                guard j != idx else { return false }
                guard other.imageArea >= medianArea * 0.35 else { return false }
                let anteriorDelta = (other.centroid.x - s.centroid.x) * anteriorSign
                return anteriorDelta > 0.035 && abs(other.centroid.y - s.centroid.y) <= 0.15
            }
            guard anteriorNeighbors.isEmpty else { continue }

            let pMask = rasterizeROI(s.polygon, width: w, height: h)
            guard pMask.count >= 12 else { continue }
            var coreLumSum = 0.0
            for y in pMask.minY...pMask.maxY {
                let row = y * w
                for x in pMask.minX...pMask.maxX where pMask.inside[row + x] {
                    coreLumSum += Double(smooth3[row + x])
                }
            }
            let coreLum = coreLumSum / Double(pMask.count)
            let darkCutoff = coreLum + max(0.075, min(0.16, (0.50 - coreLum) * 0.35))

            let bh = max(4, pMask.maxY - pMask.minY)
            let cy = (pMask.minY + pMask.maxY) / 2
            let maxRayAnt = max(12, Int(Double(w) * 0.24))
            let maxRayPost = max(10, Int(Double(w) * 0.14))

            var antBrightRuns: [Double] = []
            var postSutureWidths: [Double] = []
            var antWaterOrBorderHits = 0

            for slice in [-2, -1, 0, 1, 2] {
                let sy = min(h - 2, max(1, cy + (slice * bh) / 6))
                var rowMinX = w, rowMaxX = -1
                for x in pMask.minX...pMask.maxX where pMask.inside[sy * w + x] {
                    if x < rowMinX { rowMinX = x }
                    if x > rowMaxX { rowMaxX = x }
                }
                if rowMaxX < rowMinX {
                    rowMinX = pMask.minX
                    rowMaxX = pMask.maxX
                }

                let startAntX = side == .left ? rowMinX - 2 : rowMaxX + 2
                let stepAnt = side == .left ? -1 : 1
                var brightPx = 0
                var sawBright = false
                var hitDark = false
                var hitWaterOrEdge = false
                for step in 0..<maxRayAnt {
                    let rx = startAntX + step * stepAnt
                    if rx <= 1 || rx >= w - 2 {
                        hitWaterOrEdge = true
                        break
                    }
                    let q = sy * w + rx
                    if hasWater && raster.isWater[q] {
                        hitWaterOrEdge = true
                        break
                    }
                    let ql = Double(smooth3[q])
                    if ql > darkCutoff {
                        sawBright = true
                        brightPx += 1
                    } else if sawBright && brightPx >= 2 {
                        hitDark = true
                        break
                    } else if step >= 4 {
                        hitDark = true
                        break
                    }
                }
                antBrightRuns.append(Double(brightPx) / Double(w))
                if hitWaterOrEdge && !hitDark && Double(brightPx) / Double(w) < 0.12 {
                    antWaterOrBorderHits += 1
                }

                let startPostX = side == .left ? rowMaxX + 2 : rowMinX - 2
                let stepPost = -stepAnt
                var postBright = 0
                var postSawBright = false
                for step in 0..<maxRayPost {
                    let rx = startPostX + step * stepPost
                    if rx <= 1 || rx >= w - 2 { break }
                    let q = sy * w + rx
                    if hasWater && raster.isWater[q] { break }
                    let ql = Double(smooth3[q])
                    if ql > darkCutoff {
                        postSawBright = true
                        postBright += 1
                    } else if postSawBright && postBright >= 2 {
                        break
                    } else if step >= 4 {
                        break
                    }
                }
                postSutureWidths.append(Double(max(2, postBright)) / Double(w))
            }

            let cpx = min(w - 1, max(0, Int((s.centroid.x * Double(w)).rounded())))
            let cpy = min(h - 1, max(0, Int((s.centroid.y * Double(h)).rounded())))
            var distToWater = 1.0
            let stepDir = side == .left ? -1 : 1
            for k in 1..<w {
                let rx = cpx + k * stepDir
                if rx <= 1 || rx >= w - 2 || (hasWater && raster.isWater[cpy * w + rx]) {
                    distToWater = Double(k) / Double(w)
                    break
                }
            }

            let sMinX = s.polygon.map(\.x).min() ?? s.centroid.x
            let sMaxX = s.polygon.map(\.x).max() ?? s.centroid.x
            var minPostEdgeGap = 1.0
            for (j, other) in scales.enumerated() where j != idx && other.imageArea >= medianArea * 0.45 {
                guard abs(other.centroid.y - s.centroid.y) <= 0.14 else { continue }
                let postDelta = (other.centroid.x - s.centroid.x) * (-anteriorSign)
                guard postDelta > 0.03 else { continue }
                let oMinX = other.polygon.map(\.x).min() ?? other.centroid.x
                let oMaxX = other.polygon.map(\.x).max() ?? other.centroid.x
                let gap = side == .left ? (oMinX - sMaxX) : (sMinX - oMaxX)
                if gap < minPostEdgeGap { minPostEdgeGap = gap }
            }

            let sortedAnt = antBrightRuns.sorted()
            let sortedPost = postSutureWidths.sorted()
            let medAnt = sortedAnt[sortedAnt.count / 2]
            let medPost = max(0.012, sortedPost[sortedPost.count / 2])
            let hasNestedPupil = nestedParentNumbers.contains(s.number)

            let wideAnteriorEyelid = medAnt >= 0.062 || (medAnt >= 0.052 && (medAnt / medPost) >= 1.85)
            let eyeSocketRim = medAnt >= 0.036 && (minPostEdgeGap >= 0.038 || (distToWater <= 0.21 && s.imageArea >= medianArea * 1.5))
            let snoutEdgeSocket = antWaterOrBorderHits >= 3 && s.imageArea >= medianArea * 1.10 && s.circularity >= 0.45

            if hasNestedPupil || wideAnteriorEyelid || eyeSocketRim || snoutEdgeSocket {
                let eyeScore = (hasNestedPupil ? 4.0 : 0.0)
                    + medAnt * 12.0
                    + min(0.08, max(0.0, minPostEdgeGap)) * 10.0
                    + (s.imageArea / max(1e-5, medianArea))
                if eyeScore > bestEyeScore {
                    bestEyeScore = eyeScore
                    bestEyeIndex = idx
                }
            }
        }

        guard let removeIdx = bestEyeIndex else { return scales }
        let removed = scales[removeIdx]
        let rEye = sqrt(max(1e-5, removed.imageArea) / .pi)
        return scales.enumerated().compactMap { idx, pat in
            if idx == removeIdx { return nil }
            let dist = hypot(pat.centroid.x - removed.centroid.x, pat.centroid.y - removed.centroid.y)
            if pat.imageArea < medianArea * 0.32 && dist < rEye * 1.95 {
                return nil
            }
            return pat
        }
    }

    private static func buildTightClusterROI(
        scales: [DetectedScalePattern],
        raster: LuminanceRaster
    ) -> [ScalePoint]? {
        let w = raster.width
        let h = raster.height
        let hasWater = raster.hasWaterMask
        var unionMask = [Bool](repeating: false, count: w * h)
        var radiiPx: [Double] = []
        for s in scales {
            let pMask = rasterizeROI(s.polygon, width: w, height: h)
            guard pMask.count > 0 else { continue }
            radiiPx.append(sqrt(Double(pMask.count) / .pi))
            for y in pMask.minY...pMask.maxY {
                let row = y * w
                for x in pMask.minX...pMask.maxX where pMask.inside[row + x] {
                    if !(hasWater && raster.isWater[row + x]) {
                        unionMask[row + x] = true
                    }
                }
            }
        }
        guard !radiiPx.isEmpty else { return nil }
        let sortedR = radiiPx.sorted()
        let medR = sortedR[sortedR.count / 2]
        let dilateR = max(7, min(16, Int((medR * 0.62).rounded())))
        var mask = morphDilateDisk(unionMask, width: w, height: h, radius: dilateR)
        let closeR = max(5, min(14, Int((medR * 0.55).rounded())))
        mask = morphCloseDisk(mask, width: w, height: h, radius: closeR)
        if hasWater {
            for i in 0..<(w * h) where raster.isWater[i] {
                mask[i] = false
            }
        }

        var labels = [Int](repeating: 0, count: w * h)
        var bestLabel = 0
        var bestPixels: [Int] = []
        var curLabel = 0
        for i in 0..<(w * h) where mask[i] && labels[i] == 0 {
            curLabel += 1
            var queue = [i]
            var cursor = 0
            labels[i] = curLabel
            while cursor < queue.count {
                let p = queue[cursor]; cursor += 1
                let px = p % w, py = p / w
                if px > 0, mask[p - 1], labels[p - 1] == 0 { labels[p - 1] = curLabel; queue.append(p - 1) }
                if px < w - 1, mask[p + 1], labels[p + 1] == 0 { labels[p + 1] = curLabel; queue.append(p + 1) }
                if py > 0, mask[p - w], labels[p - w] == 0 { labels[p - w] = curLabel; queue.append(p - w) }
                if py < h - 1, mask[p + w], labels[p + w] == 0 { labels[p + w] = curLabel; queue.append(p + w) }
            }
            if queue.count > bestPixels.count {
                bestPixels = queue
                bestLabel = curLabel
            }
        }
        guard bestLabel > 0, bestPixels.count >= 64 else { return nil }

        let rawPoly = traceOuterPolygon(
            componentPixels: bestPixels,
            labels: labels,
            targetLabel: bestLabel,
            width: w,
            height: h
        )
        guard rawPoly.count >= 4 else { return nil }
        let simplified = douglasPeuckerClosed(rawPoly, epsilon: 0.0065)
        let smoothed = chaikinSmooth(simplified, passes: 1)
        return smoothed.count >= 4 ? smoothed : (simplified.count >= 4 ? simplified : nil)
    }

    private struct ROIMask {
        let inside: [Bool]
        let minX: Int
        let maxX: Int
        let minY: Int
        let maxY: Int
        let count: Int
    }

    private static func rasterizeROI(_ roiPolygon: [ScalePoint], width w: Int, height h: Int) -> ROIMask {
        var inside = [Bool](repeating: false, count: w * h)
        var minPX = w - 1, minPY = h - 1, maxPX = 0, maxPY = 0
        var count = 0

        let polyYMin = roiPolygon.map(\.y).min() ?? 0
        let polyYMax = roiPolygon.map(\.y).max() ?? 1
        let startRow = max(0, Int(floor(polyYMin * Double(h))))
        let endRow = min(h - 1, Int(ceil(polyYMax * Double(h))))

        if endRow >= startRow {
            var xs: [Double] = []
            xs.reserveCapacity(roiPolygon.count)
            for y in startRow...endRow {
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
                let rowBase = y * w
                var k = 0
                while k + 1 < xs.count {
                    let x0 = max(0, Int(ceil(xs[k] * Double(w) - 0.5)))
                    let x1 = min(w - 1, Int(floor(xs[k + 1] * Double(w) - 0.5)))
                    if x1 >= x0 {
                        if x0 < minPX { minPX = x0 }
                        if x1 > maxPX { maxPX = x1 }
                        if y < minPY { minPY = y }
                        if y > maxPY { maxPY = y }
                        for x in x0...x1 { inside[rowBase + x] = true }
                        count += (x1 - x0 + 1)
                    }
                    k += 2
                }
            }
        }
        return ROIMask(inside: inside, minX: minPX, maxX: maxPX, minY: minPY, maxY: maxPY, count: count)
    }

    private static func fallbackTemplate(side: TurtlePhotoSide) -> (roi: [ScalePoint], ref1: ScalePoint, ref2: ScalePoint, ref3: ScalePoint) {
        if side == .left {
            return (
                roi: [
                    ScalePoint(x: 0.30, y: 0.26), ScalePoint(x: 0.54, y: 0.22),
                    ScalePoint(x: 0.76, y: 0.30), ScalePoint(x: 0.78, y: 0.64),
                    ScalePoint(x: 0.52, y: 0.70), ScalePoint(x: 0.28, y: 0.58),
                ],
                ref1: ScalePoint(x: 0.20, y: 0.58),
                ref2: ScalePoint(x: 0.34, y: 0.36),
                ref3: ScalePoint(x: 0.74, y: 0.42)
            )
        } else {
            return (
                roi: [
                    ScalePoint(x: 0.70, y: 0.26), ScalePoint(x: 0.46, y: 0.22),
                    ScalePoint(x: 0.24, y: 0.30), ScalePoint(x: 0.22, y: 0.64),
                    ScalePoint(x: 0.48, y: 0.70), ScalePoint(x: 0.72, y: 0.58),
                ],
                ref1: ScalePoint(x: 0.80, y: 0.58),
                ref2: ScalePoint(x: 0.66, y: 0.36),
                ref3: ScalePoint(x: 0.26, y: 0.42)
            )
        }
    }

    private static func gaussianSmooth3x3(_ input: [Float], width: Int, height: Int) -> [Float] {
        var horiz = [Float](repeating: 0, count: input.count)
        for y in 0..<height {
            let row = y * width
            for x in 0..<width {
                let l = input[row + max(0, x - 1)]
                let c = input[row + x]
                let r = input[row + min(width - 1, x + 1)]
                horiz[row + x] = (l + 2.0 * c + r) * 0.25
            }
        }
        var out = [Float](repeating: 0, count: input.count)
        for y in 0..<height {
            let ym1 = max(0, y - 1) * width
            let y0 = y * width
            let yp1 = min(height - 1, y + 1) * width
            for x in 0..<width {
                out[y0 + x] = (horiz[ym1 + x] + 2.0 * horiz[y0 + x] + horiz[yp1 + x]) * 0.25
            }
        }
        return out
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

    private static func morphDilateDisk(_ mask: [Bool], width w: Int, height h: Int, radius r: Int) -> [Bool] {
        guard r >= 1 else { return mask }
        var horiz = [Bool](repeating: false, count: w * h)
        for y in 0..<h {
            let row = y * w
            var run = 0
            for x in 0..<w {
                if mask[row + x] { run = r + 1 }
                else if run > 0 { run -= 1 }
                if run > 0 { horiz[row + x] = true }
            }
            run = 0
            for x in stride(from: w - 1, through: 0, by: -1) {
                if mask[row + x] { run = r + 1 }
                else if run > 0 { run -= 1 }
                if run > 0 { horiz[row + x] = true }
            }
        }
        var out = [Bool](repeating: false, count: w * h)
        for x in 0..<w {
            var run = 0
            for y in 0..<h {
                if horiz[y * w + x] { run = r + 1 }
                else if run > 0 { run -= 1 }
                if run > 0 { out[y * w + x] = true }
            }
            run = 0
            for y in stride(from: h - 1, through: 0, by: -1) {
                if horiz[y * w + x] { run = r + 1 }
                else if run > 0 { run -= 1 }
                if run > 0 { out[y * w + x] = true }
            }
        }
        return out
    }

    private static func morphErodeDisk(_ mask: [Bool], width w: Int, height h: Int, radius r: Int) -> [Bool] {
        guard r >= 1 else { return mask }
        var inv = [Bool](repeating: false, count: w * h)
        for i in 0..<(w * h) { inv[i] = !mask[i] }
        let dilatedInv = morphDilateDisk(inv, width: w, height: h, radius: r)
        var out = [Bool](repeating: false, count: w * h)
        for i in 0..<(w * h) { out[i] = !dilatedInv[i] }
        return out
    }

    private static func morphCloseDisk(_ mask: [Bool], width w: Int, height h: Int, radius r: Int) -> [Bool] {
        guard r >= 1 else { return mask }
        let dil = morphDilateDisk(mask, width: w, height: h, radius: r)
        return morphErodeDisk(dil, width: w, height: h, radius: r)
    }

    private static func morphOpen3x3(
        _ mask: [Bool],
        width w: Int,
        height h: Int,
        minX: Int,
        maxX: Int,
        minY: Int,
        maxY: Int,
        validMask: [Bool]
    ) -> [Bool] {
        let loX = max(1, minX), hiX = min(w - 2, maxX)
        let loY = max(1, minY), hiY = min(h - 2, maxY)
        guard hiX >= loX, hiY >= loY else { return mask }

        var eroded = [Bool](repeating: false, count: w * h)
        for y in loY...hiY {
            let row = y * w
            for x in loX...hiX {
                let idx = row + x
                if mask[idx], mask[idx - 1], mask[idx + 1], mask[idx - w], mask[idx + w] {
                    eroded[idx] = true
                }
            }
        }
        var opened = [Bool](repeating: false, count: w * h)
        for y in loY...hiY {
            let row = y * w
            for x in loX...hiX {
                let idx = row + x
                guard validMask[idx] else { continue }
                if eroded[idx] || eroded[idx - 1] || eroded[idx + 1] || eroded[idx - w] || eroded[idx + w] {
                    opened[idx] = true
                }
            }
        }
        return opened
    }

    private static func fillSmallHoles(
        _ mask: inout [Bool],
        width w: Int,
        height h: Int,
        minX: Int,
        maxX: Int,
        minY: Int,
        maxY: Int,
        maxHolePixels: Int
    ) {
        var visited = [Bool](repeating: false, count: w * h)
        for y in minY...maxY {
            for x in minX...maxX {
                let seed = y * w + x
                guard !mask[seed], !visited[seed] else { continue }
                var queue = [seed]
                var cursor = 0
                visited[seed] = true
                var touchesBorder = false
                while cursor < queue.count {
                    let p = queue[cursor]; cursor += 1
                    let px = p % w, py = p / w
                    if px <= minX || px >= maxX || py <= minY || py >= maxY { touchesBorder = true }
                    if px > minX {
                        let nb = p - 1
                        if !mask[nb], !visited[nb] { visited[nb] = true; queue.append(nb) }
                    }
                    if px < maxX {
                        let nb = p + 1
                        if !mask[nb], !visited[nb] { visited[nb] = true; queue.append(nb) }
                    }
                    if py > minY {
                        let nb = p - w
                        if !mask[nb], !visited[nb] { visited[nb] = true; queue.append(nb) }
                    }
                    if py < maxY {
                        let nb = p + w
                        if !mask[nb], !visited[nb] { visited[nb] = true; queue.append(nb) }
                    }
                }
                if !touchesBorder && queue.count <= maxHolePixels {
                    for p in queue { mask[p] = true }
                }
            }
        }
    }

    private static func traceOuterPolygon(
        componentPixels: [Int],
        labels: [Int],
        targetLabel: Int,
        width w: Int,
        height h: Int
    ) -> [ScalePoint] {
        let stride = w + 1
        var links: [Int: [Int]] = [:]
        @inline(__always) func addEdge(_ a: Int, _ b: Int) { links[a, default: []].append(b) }

        for p in componentPixels {
            let x = p % w
            let y = p / w
            if y == 0 || labels[p - w] != targetLabel { addEdge(y * stride + x, y * stride + (x + 1)) }
            if x == w - 1 || labels[p + 1] != targetLabel { addEdge(y * stride + (x + 1), (y + 1) * stride + (x + 1)) }
            if y == h - 1 || labels[p + w] != targetLabel { addEdge((y + 1) * stride + (x + 1), (y + 1) * stride + x) }
            if x == 0 || labels[p - 1] != targetLabel { addEdge((y + 1) * stride + x, y * stride + x) }
        }

        var used = Set<UInt64>()
        var bestLoop: [ScalePoint] = []
        let keys = links.keys.sorted()
        for start in keys {
            guard let nexts = links[start] else { continue }
            for firstNext in nexts {
                let firstKey = (UInt64(start) << 32) | UInt64(firstNext)
                if used.contains(firstKey) { continue }
                var loop: [ScalePoint] = []
                var curr = start
                var next = firstNext
                var steps = 0
                while steps < 4000 {
                    steps += 1
                    used.insert((UInt64(curr) << 32) | UInt64(next))
                    let vx = curr % stride
                    let vy = curr / stride
                    loop.append(ScalePoint(x: Double(vx) / Double(w), y: Double(vy) / Double(h)))
                    curr = next
                    if curr == start { break }
                    guard let candidates = links[curr],
                          let candidateNext = candidates.first(where: { !used.contains((UInt64(curr) << 32) | UInt64($0)) })
                    else { break }
                    next = candidateNext
                }
                if loop.count > bestLoop.count { bestLoop = loop }
            }
        }
        return bestLoop
    }

    private static func smoothOpenPolylinePinned(_ points: [ScalePoint], passes: Int) -> [ScalePoint] {
        guard points.count >= 3 else { return points }
        var poly = points
        for _ in 0..<passes {
            var next = poly
            for i in 1..<(poly.count - 1) {
                let a = poly[i - 1], b = poly[i], c = poly[i + 1]
                next[i] = ScalePoint(
                    x: 0.25 * a.x + 0.50 * b.x + 0.25 * c.x,
                    y: 0.25 * a.y + 0.50 * b.y + 0.25 * c.y
                )
            }
            poly = next
        }
        return poly
    }

    private static func smoothClosedPolyline(_ points: [ScalePoint], passes: Int) -> [ScalePoint] {
        guard points.count >= 3 else { return points }
        var poly = points
        for _ in 0..<passes {
            var next = poly
            let n = poly.count
            for i in 0..<n {
                let a = poly[(i + n - 1) % n], b = poly[i], c = poly[(i + 1) % n]
                next[i] = ScalePoint(
                    x: 0.25 * a.x + 0.50 * b.x + 0.25 * c.x,
                    y: 0.25 * a.y + 0.50 * b.y + 0.25 * c.y
                )
            }
            poly = next
        }
        return poly
    }

    private static func convexHull(of points: [ScalePoint]) -> [ScalePoint] {
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
        return lower + upper
    }

    private static func douglasPeuckerClosed(_ points: [ScalePoint], epsilon: Double) -> [ScalePoint] {
        guard points.count > 4 else { return points }
        var maxDist = 0.0
        var splitIndex = points.count / 2
        let first = points[0]
        for i in 1..<points.count {
            let d = hypot(points[i].x - first.x, points[i].y - first.y)
            if d > maxDist { maxDist = d; splitIndex = i }
        }
        let partA = douglasPeuckerOpen(Array(points[0...splitIndex]), epsilon: epsilon)
        let partB = douglasPeuckerOpen(Array(points[splitIndex..<points.count]) + [first], epsilon: epsilon)
        var combined = partA
        if partB.count > 2 { combined.append(contentsOf: partB[1..<(partB.count - 1)]) }
        return combined
    }

    private static func douglasPeuckerOpen(_ points: [ScalePoint], epsilon: Double) -> [ScalePoint] {
        guard points.count > 2 else { return points }
        var maxDist = 0.0
        var index = 0
        let a = points[0], b = points[points.count - 1]
        for i in 1..<(points.count - 1) {
            let d = perpendicularDistance(points[i], lineStart: a, lineEnd: b)
            if d > maxDist { maxDist = d; index = i }
        }
        if maxDist > epsilon {
            let left = douglasPeuckerOpen(Array(points[0...index]), epsilon: epsilon)
            let right = douglasPeuckerOpen(Array(points[index..<points.count]), epsilon: epsilon)
            return Array(left.dropLast()) + right
        }
        return [a, b]
    }

    private static func perpendicularDistance(_ p: ScalePoint, lineStart a: ScalePoint, lineEnd b: ScalePoint) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let denom = hypot(dx, dy)
        guard denom > 1e-9 else { return hypot(p.x - a.x, p.y - a.y) }
        return abs(dy * p.x - dx * p.y + b.x * a.y - b.y * a.x) / denom
    }

    private static func chaikinSmooth(_ points: [ScalePoint], passes: Int) -> [ScalePoint] {
        guard points.count >= 3, passes > 0 else { return points }
        var current = points
        for _ in 0..<passes {
            var next: [ScalePoint] = []
            next.reserveCapacity(current.count * 2)
            for i in current.indices {
                let p0 = current[i]
                let p1 = current[(i + 1) % current.count]
                next.append(ScalePoint(x: 0.75 * p0.x + 0.25 * p1.x, y: 0.75 * p0.y + 0.25 * p1.y))
                next.append(ScalePoint(x: 0.25 * p0.x + 0.75 * p1.x, y: 0.25 * p0.y + 0.75 * p1.y))
            }
            current = next
        }
        return current
    }

    private static func anatomicalCornerCount(_ poly: [ScalePoint]) -> Int {
        guard poly.count >= 3 else { return poly.count }
        var corners = 0
        for i in poly.indices {
            let prev = poly[(i + poly.count - 1) % poly.count]
            let curr = poly[i]
            let next = poly[(i + 1) % poly.count]
            let v1x = prev.x - curr.x, v1y = prev.y - curr.y
            let v2x = next.x - curr.x, v2y = next.y - curr.y
            let mag = hypot(v1x, v1y) * hypot(v2x, v2y)
            guard mag > 1e-8 else { continue }
            let cosAngle = min(1.0, max(-1.0, (v1x * v2x + v1y * v2y) / mag))
            if acos(cosAngle) < 2.65 { corners += 1 }
        }
        return max(3, min(10, corners))
    }

    private static func perimeter(of poly: [ScalePoint]) -> Double {
        guard poly.count >= 2 else { return 0 }
        return poly.indices.reduce(0.0) { acc, i in
            let next = poly[(i + 1) % poly.count]
            return acc + hypot(next.x - poly[i].x, next.y - poly[i].y)
        }
    }

    private static func polygonMoments(_ poly: [ScalePoint]) -> (centroid: ScalePoint, aspectRatio: Double, orientationDeg: Double) {
        let n = poly.count
        guard n >= 3 else { return (poly.first ?? ScalePoint(x: 0.5, y: 0.5), 1.0, 0.0) }
        var aSum = 0.0, cxSum = 0.0, cySum = 0.0
        for i in 0..<n {
            let p0 = poly[i], p1 = poly[(i + 1) % n]
            let cross = p0.x * p1.y - p1.x * p0.y
            aSum += cross
            cxSum += (p0.x + p1.x) * cross
            cySum += (p0.y + p1.y) * cross
        }
        let centroid: ScalePoint
        if abs(aSum) > 1e-8 {
            centroid = ScalePoint(x: cxSum / (3.0 * aSum), y: cySum / (3.0 * aSum))
        } else {
            centroid = ScalePoint(
                x: poly.map(\.x).reduce(0, +) / Double(n),
                y: poly.map(\.y).reduce(0, +) / Double(n)
            )
        }

        var cxx = 0.0, cyy = 0.0, cxy = 0.0
        for p in poly {
            let dx = p.x - centroid.x, dy = p.y - centroid.y
            cxx += dx * dx; cyy += dy * dy; cxy += dx * dy
        }
        cxx /= Double(n); cyy /= Double(n); cxy /= Double(n)

        let trace = cxx + cyy
        let det = max(0.0, cxx * cyy - cxy * cxy)
        let disc = sqrt(max(0.0, (trace * trace) * 0.25 - det))
        let l1 = max(1e-7, trace * 0.5 + disc)
        let l2 = max(1e-7, trace * 0.5 - disc)
        let aspect = min(6.0, max(1.0, sqrt(l1 / l2)))
        let angle = 0.5 * atan2(2.0 * cxy, cxx - cyy) * (180.0 / .pi)
        return (centroid, aspect, angle)
    }

    private static func paddedConvexHull(points: [ScalePoint], padding: Double) -> [ScalePoint] {
        guard points.count >= 3 else { return points }
        let hull = convexHull(of: points)
        guard hull.count >= 3 else { return points }
        let cx = hull.map(\.x).reduce(0, +) / Double(hull.count)
        let cy = hull.map(\.y).reduce(0, +) / Double(hull.count)
        return hull.map { p in
            let dx = p.x - cx, dy = p.y - cy
            let d = max(1e-5, hypot(dx, dy))
            return ScalePoint(
                x: min(0.97, max(0.03, p.x + (dx / d) * padding)),
                y: min(0.97, max(0.03, p.y + (dy / d) * padding))
            )
        }
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
    /// Computes real shape & geometric alignment metrics strictly from paired numbered contours.
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

        var affineMatrix: [Double]? = nil
        if validPairs.count >= 3 {
            affineMatrix = solveBestAffine(pointPairs: validPairs.map { ($0.q.centroid, $0.c.centroid) })
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
            Int((100.0 * exp(-r / 9.5)).rounded())
        }
        let i3sEq: Double? = meanResidual.map { r in
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

    /// Auto-suggests one-to-one numbered scale pairings `(Q# ↔ C#)` using:
    /// 1. I3S reference triangles (when supplied in legacy studio views), OR
    /// 2. Backend XFeat/LighterGlue correspondences (when supplied), OR
    /// 3. 2-point similarity RANSAC + full 2D affine refit (Mobile fd69860 parity).
    @MainActor
    static func autoSuggestPairs(
        query: [DetectedScalePattern],
        candidate: [DetectedScalePattern],
        queryFP: I3SFingerprint? = nil,
        candidateFP: I3SFingerprint? = nil,
        queryImageSize: NSSize? = nil,
        candidateImageSize: NSSize? = nil,
        queryROI: [ScalePoint],
        candidateROI: [ScalePoint],
        annotations: [OverlayAnnotationItem] = []
    ) -> [PatternPairLink] {
        guard !query.isEmpty, !candidate.isEmpty else { return [] }

        var anchorAffine: [Double]? = nil
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
            anchorAffine = I3SCompareEngine.calcAffine(from: qr, to: cr)
        }

        if anchorAffine == nil {
            anchorAffine = affineFromAnnotations(annotations)
        }

        return suggestPairsCore(
            query: query,
            candidate: candidate,
            queryROI: queryROI,
            candidateROI: candidateROI,
            anchorAffine: anchorAffine,
            annotations: annotations
        )
    }

    /// Nonisolated zero-.fgp scale pairing using backend XFeat correspondences or similarity RANSAC.
    static func autoSuggestPairs(
        query: [DetectedScalePattern],
        candidate: [DetectedScalePattern],
        queryROI: [ScalePoint],
        candidateROI: [ScalePoint],
        annotations: [OverlayAnnotationItem] = []
    ) -> [PatternPairLink] {
        suggestPairsCore(
            query: query,
            candidate: candidate,
            queryROI: queryROI,
            candidateROI: candidateROI,
            anchorAffine: affineFromAnnotations(annotations),
            annotations: annotations
        )
    }

    private static func suggestPairsCore(
        query: [DetectedScalePattern],
        candidate: [DetectedScalePattern],
        queryROI: [ScalePoint],
        candidateROI: [ScalePoint],
        anchorAffine: [Double]?,
        annotations: [OverlayAnnotationItem]
    ) -> [PatternPairLink] {
        guard !query.isEmpty, !candidate.isEmpty else { return [] }

        let qBounds = boundingRect(of: queryROI, fallback: query.map(\.centroid))
        let cBounds = boundingRect(of: candidateROI, fallback: candidate.map(\.centroid))
        let cDiag = max(0.05, hypot(cBounds.width, cBounds.height))

        var directKeypointHits: [String: Int] = [:]
        if !annotations.isEmpty {
            for ann in annotations where (ann.score ?? 0.5) >= 0.25 {
                let qp = ScalePoint(x: ann.query.x, y: ann.query.y)
                let cp = ScalePoint(x: ann.candidate.x, y: ann.candidate.y)
                if let qMatch = scaleContainingOrNear(qp, in: query, maxDistance: 0.025),
                   let cMatch = scaleContainingOrNear(cp, in: candidate, maxDistance: 0.025) {
                    directKeypointHits["\(qMatch.number)-\(cMatch.number)", default: 0] += 1
                }
            }
        }

        struct CandidateEdge {
            let qNum: Int
            let cNum: Int
            let cost: Double
            let hits: Int
        }

        let qByNum = Dictionary(uniqueKeysWithValues: query.map { ($0.number, $0) })
        let cByNum = Dictionary(uniqueKeysWithValues: candidate.map { ($0.number, $0) })

        var edges: [CandidateEdge] = []
        for q in query {
            let mappedCentroid: ScalePoint = {
                if let m = anchorAffine {
                    return applyAffine(q.centroid, matrix: m)
                }
                let u = (q.centroid.x - qBounds.minX) / max(1e-4, qBounds.width)
                let v = (q.centroid.y - qBounds.minY) / max(1e-4, qBounds.height)
                return ScalePoint(x: cBounds.minX + u * cBounds.width, y: cBounds.minY + v * cBounds.height)
            }()

            for c in candidate {
                let hits = directKeypointHits["\(q.number)-\(c.number)"] ?? 0
                let spatialNorm = hypot(mappedCentroid.x - c.centroid.x, mappedCentroid.y - c.centroid.y) / cDiag
                let maxSpatial = anchorAffine != nil ? (hits > 0 ? 0.36 : 0.28) : (hits > 0 ? 0.48 : 0.44)
                guard spatialNorm < maxSpatial else { continue }

                let areaRatio = min(q.roiAreaFraction, c.roiAreaFraction) / max(1e-6, max(q.roiAreaFraction, c.roiAreaFraction))
                guard areaRatio >= (hits > 0 ? 0.26 : 0.32) else { continue }

                let aspectSim = min(q.aspectRatio, c.aspectRatio) / max(1e-6, max(q.aspectRatio, c.aspectRatio))
                let shapePenalty = (1.0 - areaRatio) * 0.45
                    + (1.0 - aspectSim) * 0.25
                    + Double(abs(q.vertexCount - c.vertexCount)) * 0.06
                let hitBonus = min(0.28, Double(hits) * 0.11)
                let totalCost = max(0.0, spatialNorm * 1.45 + shapePenalty * 0.45 - hitBonus)
                edges.append(CandidateEdge(qNum: q.number, cNum: c.number, cost: totalCost, hits: hits))
            }
        }

        edges.sort { $0.cost < $1.cost }

        // 2-point similarity RANSAC + full 2D affine refit when no external anchor affine is present.
        if anchorAffine == nil, edges.count >= 3 {
            let qDiag = max(0.05, hypot(qBounds.width, qBounds.height))
            let largeQNums = Set(query.sorted { $0.imageArea > $1.imageArea }.prefix(10).map(\.number))
            var perQueryCount: [Int: Int] = [:]
            var seedPool: [CandidateEdge] = []
            for e in edges {
                let cap = largeQNums.contains(e.qNum) ? 4 : 2
                if (perQueryCount[e.qNum] ?? 0) < cap {
                    seedPool.append(e)
                    perQueryCount[e.qNum, default: 0] += 1
                    if seedPool.count >= 42 { break }
                }
            }

            var bestInliers: [PatternPairLink] = []
            var bestScore = -1.0

            func evaluateTransformHypothesis(_ m: [Double], tol: Double) -> ([PatternPairLink], Double)? {
                let det = m[0] * m[4] - m[1] * m[3]
                guard det > 0.24 && det < 4.2 else { return nil }
                let col1Norm = hypot(m[0], m[3])
                let col2Norm = hypot(m[1], m[4])
                guard col1Norm > 0.35, col2Norm > 0.35 else { return nil }
                let scaleAniso = max(col1Norm, col2Norm) / max(1e-5, min(col1Norm, col2Norm))
                guard scaleAniso < 1.55 else { return nil }
                let orthoDot = abs(m[0] * m[1] + m[3] * m[4]) / (col1Norm * col2Norm)
                guard orthoDot < 0.38 else { return nil }
                let rotAngle = abs(atan2(m[3], m[0]))
                guard rotAngle < 0.72 else { return nil }

                let expectedAreaScale = abs(det)
                var matches: [(qNum: Int, cNum: Int, errNorm: Double, shapeScore: Double, hits: Int)] = []
                for q in query {
                    let warped = applyAffine(q.centroid, matrix: m)
                    for c in candidate {
                        let errNorm = hypot(warped.x - c.centroid.x, warped.y - c.centroid.y) / cDiag
                        guard errNorm <= tol else { continue }
                        let expectedCArea = q.imageArea * expectedAreaScale
                        let areaRatio = min(expectedCArea, c.imageArea) / max(1e-6, max(expectedCArea, c.imageArea))
                        guard areaRatio >= 0.34 else { continue }
                        let aspectSim = min(q.aspectRatio, c.aspectRatio) / max(1e-6, max(q.aspectRatio, c.aspectRatio))
                        let cornerSim = max(0.25, 1.0 - Double(abs(q.vertexCount - c.vertexCount)) * 0.2)
                        let shapeScore = 0.48 * areaRatio + 0.28 * aspectSim + 0.24 * cornerSim
                        let hits = directKeypointHits["\(q.number)-\(c.number)"] ?? 0
                        matches.append((q.number, c.number, errNorm, shapeScore, hits))
                    }
                }
                matches.sort {
                    ($0.errNorm - Double($0.hits) * 0.025 - $0.shapeScore * 0.035)
                        < ($1.errNorm - Double($1.hits) * 0.025 - $1.shapeScore * 0.035)
                }

                var usedQ = Set<Int>()
                var usedC = Set<Int>()
                var inliers: [PatternPairLink] = []
                var score = 0.0
                for item in matches {
                    guard !usedQ.contains(item.qNum), !usedC.contains(item.cNum) else { continue }
                    usedQ.insert(item.qNum)
                    usedC.insert(item.cNum)
                    inliers.append(PatternPairLink(queryNumber: item.qNum, candidateNumber: item.cNum))
                    let precision = max(0.0, 1.0 - item.errNorm / max(tol, 1e-4))
                    score += precision * precision * 0.70 + item.shapeScore * 0.45 + Double(item.hits) * 0.25
                }
                return (inliers, score)
            }

            let nSeeds = seedPool.count
            for i in 0..<nSeeds {
                let e0 = seedPool[i]
                guard let q0 = qByNum[e0.qNum], let c0 = cByNum[e0.cNum] else { continue }
                for j in (i + 1)..<nSeeds {
                    let e1 = seedPool[j]
                    guard e0.qNum != e1.qNum, e0.cNum != e1.cNum else { continue }
                    guard let q1 = qByNum[e1.qNum], let c1 = cByNum[e1.cNum] else { continue }
                    let dqx = q1.centroid.x - q0.centroid.x
                    let dqy = q1.centroid.y - q0.centroid.y
                    let qLen2 = dqx * dqx + dqy * dqy
                    guard sqrt(qLen2) >= qDiag * 0.14 else { continue }
                    let dcx = c1.centroid.x - c0.centroid.x
                    let dcy = c1.centroid.y - c0.centroid.y
                    let a = (dqx * dcx + dqy * dcy) / qLen2
                    let b = (dqx * dcy - dqy * dcx) / qLen2
                    let tx = c0.centroid.x - (a * q0.centroid.x - b * q0.centroid.y)
                    let ty = c0.centroid.y - (b * q0.centroid.x + a * q0.centroid.y)
                    let simMatrix = [a, -b, tx, b, a, ty]

                    if let (inliers, score) = evaluateTransformHypothesis(simMatrix, tol: 0.095),
                       inliers.count >= 3, score > bestScore {
                        bestScore = score
                        bestInliers = inliers
                    }
                }
            }

            if bestInliers.count >= 3 {
                var currentInliers = bestInliers
                for tol in [0.088, 0.080] {
                    let refitPairs: [(ScalePoint, ScalePoint)] = currentInliers.compactMap { link in
                        guard let q = qByNum[link.queryNumber], let c = cByNum[link.candidateNumber] else { return nil }
                        return (q.centroid, c.centroid)
                    }
                    if let refinedMatrix = solveBestAffine(pointPairs: refitPairs),
                       let (refinedInliers, _) = evaluateTransformHypothesis(refinedMatrix, tol: tol),
                       refinedInliers.count >= 3 {
                        currentInliers = refinedInliers
                    }
                }
                return currentInliers.sorted { $0.queryNumber < $1.queryNumber }
            }
        }

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

    private static func scaleContainingOrNear(
        _ point: ScalePoint,
        in scales: [DetectedScalePattern],
        maxDistance: Double
    ) -> DetectedScalePattern? {
        if let inside = scales.last(where: { ScalePhotoReview.contains(point, polygon: $0.polygon) }) {
            return inside
        }
        guard let nearest = scales.min(by: {
            hypot($0.centroid.x - point.x, $0.centroid.y - point.y)
                < hypot($1.centroid.x - point.x, $1.centroid.y - point.y)
        }) else { return nil }
        return hypot(nearest.centroid.x - point.x, nearest.centroid.y - point.y) <= maxDistance ? nearest : nil
    }

    private static func affineFromAnnotations(_ annotations: [OverlayAnnotationItem]) -> [Double]? {
        let top = annotations
            .filter { ($0.score ?? 0.5) >= 0.35 }
            .sorted { ($0.score ?? 0) > ($1.score ?? 0) }
            .prefix(24)
        guard top.count >= 4 else { return nil }
        let pairs = top.map { (ScalePoint(x: $0.query.x, y: $0.query.y), ScalePoint(x: $0.candidate.x, y: $0.candidate.y)) }
        guard let m = solveBestAffine(pointPairs: pairs) else { return nil }
        let det = m[0] * m[4] - m[1] * m[3]
        guard det > 0.15 && det < 6.5 else { return nil }
        return m
    }

    static func solveBestAffine(pointPairs pairs: [(ScalePoint, ScalePoint)]) -> [Double]? {
        guard pairs.count >= 3 else { return nil }
        if pairs.count == 3 {
            let p0 = pairs[0], p1 = pairs[1], p2 = pairs[2]
            guard let mx = solve3x3(
                p0.0.x, p0.0.y, 1,
                p1.0.x, p1.0.y, 1,
                p2.0.x, p2.0.y, 1,
                p0.1.x, p1.1.x, p2.1.x
            ),
            let my = solve3x3(
                p0.0.x, p0.0.y, 1,
                p1.0.x, p1.0.y, 1,
                p2.0.x, p2.0.y, 1,
                p0.1.y, p1.1.y, p2.1.y
            ) else { return nil }
            return [mx.0, mx.1, mx.2, my.0, my.1, my.2]
        }

        var a00 = 0.0, a01 = 0.0, a02 = 0.0
        var a11 = 0.0, a12 = 0.0
        let a22 = Double(pairs.count)
        var bx0 = 0.0, bx1 = 0.0, bx2 = 0.0
        var by0 = 0.0, by1 = 0.0, by2 = 0.0

        for (q, c) in pairs {
            a00 += q.x * q.x; a01 += q.x * q.y; a02 += q.x
            a11 += q.y * q.y; a12 += q.y
            bx0 += q.x * c.x; bx1 += q.y * c.x; bx2 += c.x
            by0 += q.x * c.y; by1 += q.y * c.y; by2 += c.y
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
