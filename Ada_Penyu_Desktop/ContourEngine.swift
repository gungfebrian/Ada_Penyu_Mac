import AppKit

/// Absolute, thinned gradient evidence. Both photos use the same cutoff;
/// nothing is normalized to look like an identity probability.
nonisolated struct ContourField: Sendable {
    let width: Int
    let height: Int
    let strengths: [Float]

    func mask(threshold: Double, lineWeight: Int = 1) -> [UInt8] {
        guard width > 0, height > 0, strengths.count == width * height, !Task.isCancelled else { return [] }
        let high = Float(min(1, max(0, threshold)))
        let low = high * 0.4
        var mask = [UInt8](repeating: 0, count: strengths.count)
        var frontier: [Int] = []
        for i in strengths.indices where strengths[i] > 0 && strengths[i] >= high {
            mask[i] = 255; frontier.append(i)
        }
        var cursor = 0
        while cursor < frontier.count {
            if cursor % 2048 == 0, Task.isCancelled { return [] }
            let i = frontier[cursor]; cursor += 1
            let x = i % width, y = i / width
            for ny in max(0, y - 1)...min(height - 1, y + 1) {
                for nx in max(0, x - 1)...min(width - 1, x + 1) {
                    let j = ny * width + nx
                    if mask[j] == 0, strengths[j] > 0, strengths[j] >= low {
                        mask[j] = 255; frontier.append(j)
                    }
                }
            }
        }
        let radius = min(2, max(0, lineWeight - 1))
        guard radius > 0 else { return mask }
        // A separable maximum filter changes visual line weight, not evidence.
        var horizontal = mask
        for y in 0..<height {
            if Task.isCancelled { return [] }
            for x in 0..<width where mask[y * width + x] > 0 {
                for nx in max(0, x - radius)...min(width - 1, x + radius) { horizontal[y * width + nx] = 255 }
            }
        }
        var expanded = horizontal
        for y in 0..<height {
            if Task.isCancelled { return [] }
            for x in 0..<width where horizontal[y * width + x] > 0 {
                for ny in max(0, y - radius)...min(height - 1, y + radius) { expanded[ny * width + x] = 255 }
            }
        }
        return expanded
    }
}

/// A local Canny-style pipeline: smoothing, Sobel, nonmaximum suppression,
/// and (in ContourField.mask) connected weak-edge hysteresis.
nonisolated enum ContourEngine {
    static func detect(luminance: [Float], width: Int, height: Int, smooth: Bool) -> ContourField? {
        guard width >= 3, height >= 3, width <= Int.max / height,
              luminance.count == width * height, !Task.isCancelled else { return nil }
        var pixels = luminance
        if smooth {
            var horizontal = pixels
            for y in 0..<height {
                if Task.isCancelled { return nil }
                for x in 0..<width {
                    let i = y * width + x
                    horizontal[i] = (pixels[y * width + max(0, x - 1)] + 2 * pixels[i]
                        + pixels[y * width + min(width - 1, x + 1)]) / 4
                }
            }
            for y in 0..<height {
                if Task.isCancelled { return nil }
                for x in 0..<width {
                    pixels[y * width + x] = (horizontal[max(0, y - 1) * width + x]
                        + 2 * horizontal[y * width + x]
                        + horizontal[min(height - 1, y + 1) * width + x]) / 4
                }
            }
        }
        var magnitude = [Float](repeating: 0, count: width * height)
        var direction = [UInt8](repeating: 0, count: width * height)
        for y in 1..<(height - 1) {
            if Task.isCancelled { return nil }
            for x in 1..<(width - 1) {
                let i = y * width + x
                let a = pixels[i - width - 1], b = pixels[i - width], c = pixels[i - width + 1]
                let d = pixels[i - 1], f = pixels[i + 1]
                let g = pixels[i + width - 1], h = pixels[i + width], j = pixels[i + width + 1]
                let gx = (c - a) + 2 * (f - d) + (j - g)
                let gy = (g - a) + 2 * (h - b) + (j - c)
                magnitude[i] = min(1, sqrt(gx * gx + gy * gy) / 4)
                let ax = abs(gx), ay = abs(gy)
                if ay <= ax * 0.41421356 { direction[i] = 0 }
                else if ay >= ax * 2.41421356 { direction[i] = 1 }
                else { direction[i] = gx * gy >= 0 ? 2 : 3 }
            }
        }
        var thinned = [Float](repeating: 0, count: width * height)
        let offsets = [1, width, width + 1, width - 1]
        for y in 1..<(height - 1) {
            if Task.isCancelled { return nil }
            for x in 1..<(width - 1) {
                let i = y * width + x
                let offset = offsets[Int(direction[i])]
                // A strict comparison on one side resolves two-pixel plateaus.
                if magnitude[i] > magnitude[i - offset], magnitude[i] >= magnitude[i + offset] {
                    thinned[i] = magnitude[i]
                }
            }
        }
        return ContourField(width: width, height: height, strengths: thinned)
    }
}

@MainActor
enum ContourRasterizer {
    static func luminance(from image: NSImage, maxDimension: Int = 1280) -> (pixels: [Float], width: Int, height: Int)? {
        guard maxDimension >= 3, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let scale = min(1, Double(maxDimension) / Double(max(cg.width, cg.height)))
        let width = max(3, Int(Double(cg.width) * scale)), height = max(3, Int(Double(cg.height) * scale))
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.interpolationQuality = .high
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        let pixels = (0..<(width * height)).map { i in
            (0.2126 * Float(bytes[i * 4]) + 0.7152 * Float(bytes[i * 4 + 1]) + 0.0722 * Float(bytes[i * 4 + 2])) / 255
        }
        return (pixels, width, height)
    }

    static func overlay(field: ContourField, mask: [UInt8]) -> NSImage? {
        guard mask.count == field.width * field.height else { return nil }
        var rgba = [UInt8](repeating: 0, count: mask.count * 4)
        for i in mask.indices where mask[i] > 0 {
            rgba[i * 4] = 255; rgba[i * 4 + 1] = 255; rgba[i * 4 + 2] = 255; rgba[i * 4 + 3] = 255
        }
        guard let provider = CGDataProvider(data: Data(rgba) as CFData),
              let cg = CGImage(width: field.width, height: field.height, bitsPerComponent: 8,
                bitsPerPixel: 32, bytesPerRow: field.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider,
                decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: field.width, height: field.height))
    }
}
