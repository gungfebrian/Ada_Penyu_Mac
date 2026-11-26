// Artwork frames and outline paths adapted from ADA_Penyu's TurtleBodyDiagram.swift
// at f54176fd37ad94cbc1280e3e691b12fc9792192e. Keep these in sync with
// the bundled SVG turtle assets when the iOS illustration changes.
import SwiftUI

// MARK: - SVG path shape
/// Renders an SVG path string as a SwiftUI `Shape`, scaled to fit its frame
/// while preserving the source artwork's aspect ratio.
///
/// Supports the absolute commands used by the body-part artwork (`M`, `L`,
/// `H`, `V`, `C`, `Z`), which is all the exported assets contain — anything
/// else is ignored rather than approximated.
private struct SVGPathShape: Shape {
    let commands: String
    /// The artwork's own coordinate space, from its `viewBox`.
    let viewBox: CGSize

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width / viewBox.width, rect.height / viewBox.height)
        let dx = rect.minX + (rect.width - viewBox.width * scale) / 2
        let dy = rect.minY + (rect.height - viewBox.height * scale) / 2
        return Self.parse(commands)
            .applying(CGAffineTransform(scaleX: scale, y: scale))
            .applying(CGAffineTransform(translationX: dx, y: dy))
    }

    static func parse(_ commands: String) -> Path {
        var path = Path()
        var current = CGPoint.zero
        var start = CGPoint.zero

        var command: Character = "M"
        var numbers: [CGFloat] = []

        // Pull the tokens out in order: a letter switches command, everything
        // else is a coordinate belonging to the command in force.
        var scanner = commands.startIndex
        func flush() {
            guard !numbers.isEmpty || command == "Z" || command == "z" else { return }
            var i = 0
            switch command {
            case "M":
                while i + 2 <= numbers.count {
                    let p = CGPoint(x: numbers[i], y: numbers[i + 1])
                    // Only the first pair is a move; the rest are implicit lines.
                    if i == 0 {
                        path.move(to: p)
                        start = p
                    } else {
                        path.addLine(to: p)
                    }
                    current = p
                    i += 2
                }
            case "L":
                while i + 2 <= numbers.count {
                    let p = CGPoint(x: numbers[i], y: numbers[i + 1])
                    path.addLine(to: p)
                    current = p
                    i += 2
                }
            case "H":
                while i < numbers.count {
                    let p = CGPoint(x: numbers[i], y: current.y)
                    path.addLine(to: p)
                    current = p
                    i += 1
                }
            case "V":
                while i < numbers.count {
                    let p = CGPoint(x: current.x, y: numbers[i])
                    path.addLine(to: p)
                    current = p
                    i += 1
                }
            case "C":
                while i + 6 <= numbers.count {
                    let c1 = CGPoint(x: numbers[i],     y: numbers[i + 1])
                    let c2 = CGPoint(x: numbers[i + 2], y: numbers[i + 3])
                    let p  = CGPoint(x: numbers[i + 4], y: numbers[i + 5])
                    path.addCurve(to: p, control1: c1, control2: c2)
                    current = p
                    i += 6
                }
            case "Z", "z":
                path.closeSubpath()
                current = start
            default:
                break
            }
            numbers.removeAll(keepingCapacity: true)
        }

        while scanner < commands.endIndex {
            let char = commands[scanner]
            if char.isLetter {
                flush()
                command = char
                scanner = commands.index(after: scanner)
            } else if char == " " || char == "," || char == "\n" {
                scanner = commands.index(after: scanner)
            } else {
                var numberEnd = scanner
                // A leading '-' belongs to the number; a later one starts the next.
                if commands[numberEnd] == "-" { numberEnd = commands.index(after: numberEnd) }
                while numberEnd < commands.endIndex,
                      commands[numberEnd].isNumber || commands[numberEnd] == "." {
                    numberEnd = commands.index(after: numberEnd)
                }
                if let value = Double(commands[scanner..<numberEnd]) {
                    numbers.append(CGFloat(value))
                }
                scanner = numberEnd
            }
        }
        flush()
        return path
    }
}

// MARK: - Artwork
/// The exported SVG for one body part, plus where it sits on the shared
/// 200 × 200 diagram canvas. The frames are normalized from the supplied
/// reference so the pieces keep their intended assembled silhouette.
private struct BodyPartArt {
    let part: TurtleBodyPart
    let commands: String
    let viewBox: CGSize
    let frame: CGRect
    var isEllipse = false
}

private enum TurtleBodyArtwork {
    /// The canvas every part is positioned in.
    static let canvas = CGSize(width: 200, height: 200)

    /// Drawn back-to-front: limbs first, carapace last, so the shell overlaps
    /// the joints the way it does on a real animal.
    static let parts: [BodyPartArt] = [
        BodyPartArt(
            part: .head,
            commands: "M120.086 0C186.44 0 233.836 94.7919 233.836 145.348C233.836 185.792 216.985 233.82 208.559 252.778V322.292C189.061 317.161 156.566 310.032 116.918 309.669C77.2706 310.032 44.7757 317.161 25.2783 322.292V252.778C16.8523 233.82 0 185.792 0 145.348C0.000184238 94.792 47.3961 0.000372345 113.75 0H120.086Z",
            viewBox: CGSize(width: 234, height: 323),
            frame: CGRect(x: 82.38, y: 0, width: 36.83, height: 50.79)
        ),
        BodyPartArt(
            part: .flipperLeft,
            commands: "M245.612 0C365.683 0 390.959 37.9167 371.998 53.7154C366.484 59.2295 340.303 72.6737 311.964 104.271C283.624 135.868 280.366 170.625 255.086 170.625C122.451 170.625 62.3483 278.056 14.9471 236.98C-52.9294 178.16 125.54 0 245.612 0Z",
            viewBox: CGSize(width: 378, height: 247),
            frame: CGRect(x: 9.36, y: 52.06, width: 59.68, height: 38.73)
        ),
        BodyPartArt(
            part: .flipperRight,
            commands: "M132.058 0C11.987 0 -13.289 37.9167 5.67151 53.7154C11.1857 59.2295 37.3665 72.6737 65.7063 104.271C94.0462 135.868 97.3036 170.625 122.584 170.625C255.219 170.625 315.322 278.056 362.723 236.98C430.599 178.16 252.13 0 132.058 0Z",
            viewBox: CGSize(width: 378, height: 247),
            frame: CGRect(x: 131.26, y: 50.79, width: 59.37, height: 38.73)
        ),
        BodyPartArt(
            part: .footLeft,
            commands: "M99.8887 0C62.7286 38.7101 22.0161 87.7959 11.4492 112.744C-12.3275 168.882 2.5362 251.753 41.1709 251.753C79.805 251.752 85.969 206.741 115.474 176.902C129.623 162.594 161.433 140.111 191.441 118.474C155.038 86.6211 123.887 46.3566 99.8887 0Z",
            viewBox: CGSize(width: 192, height: 252),
            frame: CGRect(x: 38.89, y: 149.52, width: 30.16, height: 39.37)
        ),
        BodyPartArt(
            part: .footRight,
            commands: "M91.5518 0C128.712 38.7102 169.425 87.7967 179.992 112.745C203.769 168.883 188.905 251.754 150.271 251.754C111.637 251.753 105.472 206.742 75.9678 176.903C61.8189 162.595 30.0087 140.112 0 118.475C36.4035 86.6219 67.5532 46.3567 91.5518 0Z",
            viewBox: CGSize(width: 192, height: 252),
            frame: CGRect(x: 131.58, y: 149.21, width: 30.16, height: 39.68)
        ),
        BodyPartArt(
            part: .tail,
            commands: "M72.6737 139.028C42.3403 139.028 11.5857 46.3427 0 0H142.188C131.655 46.3427 103.007 139.028 72.6737 139.028Z",
            viewBox: CGSize(width: 143, height: 140),
            frame: CGRect(x: 88.73, y: 178.10, width: 22.22, height: 21.90)
        ),
        BodyPartArt(
            part: .carapace,
            commands: "",
            viewBox: CGSize(width: 620, height: 759),
            frame: CGRect(x: 51.27, y: 53.97, width: 97.78, height: 119.37),
            isEllipse: true
        )
    ]

}

private struct BodyPartShape: Shape {
    let art: BodyPartArt

    func path(in rect: CGRect) -> Path {
        if art.isEllipse {
            return Path(ellipseIn: rect)
        }
        return SVGPathShape(commands: art.commands, viewBox: art.viewBox).path(in: rect)
    }
}

// MARK: - Diagram
/// The iOS illustration geometry, colored with the Mac's recorded conditions.
struct TurtleBodyDiagram: View {
    let highlights: [TurtleBodyPart: TurtleCondition]

    private static let neutralTint = AdaColors.tertiaryInk.opacity(0.55)

    var body: some View {
        GeometryReader { proxy in
            let canvas = TurtleBodyArtwork.canvas
            let scale = min(proxy.size.width / canvas.width, proxy.size.height / canvas.height)
            let xInset = (proxy.size.width - canvas.width * scale) / 2
            let yInset = (proxy.size.height - canvas.height * scale) / 2

            ZStack(alignment: .topLeading) {
                Color.clear
                ForEach(TurtleBodyArtwork.parts, id: \.part) { art in
                    let condition = highlights[art.part]
                    Image(art.part.imageName)
                        .renderingMode(.template)
                        .resizable()
                        .foregroundStyle(condition?.tint ?? Self.neutralTint)
                        .overlay {
                            BodyPartShape(art: art)
                                .stroke(Color.white.opacity(0.72), lineWidth: max(0.7, scale * 1.1))
                        }
                        .frame(width: art.frame.width * scale, height: art.frame.height * scale)
                        .position(x: xInset + art.frame.midX * scale, y: yInset + art.frame.midY * scale)
                        .accessibilityLabel("\(art.part.displayName)\(condition.map { ": \($0.rawValue)" } ?? "")")
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 230)
        .frame(maxWidth: .infinity)
    }
}
