import SwiftUI

struct TurtleAppIconMark: View {
    let size: CGFloat

    var body: some View {
        Image("TurtleAppIcon")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct TurtleBrandMark: View {
    let size: CGFloat
    var background: Color = AdaColors.brandBlue

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(background)
            .frame(width: size, height: size)
            .overlay {
                Image("Turtle")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.18)
                    .foregroundStyle(.white)
            }
    }
}

/// Seamless teardrop map pin matching the FigCraft AdaPenyu sighting marker
/// (`figcraft-258.png` & `figcraft-1000.png`).
struct PenyuMapPinShape: Shape {
    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        let radius = width * 0.5
        let center = CGPoint(x: rect.midX, y: rect.minY + radius)
        let angleDegrees: Double = 24
        let angle = angleDegrees * .pi / 180

        let rightJoin = CGPoint(
            x: center.x + radius * CGFloat(cos(angle)),
            y: center.y + radius * CGFloat(sin(angle))
        )
        let leftJoin = CGPoint(
            x: center.x - radius * CGFloat(cos(angle)),
            y: center.y + radius * CGFloat(sin(angle))
        )
        let tip = CGPoint(x: rect.midX, y: rect.maxY)

        // Unit tangent along the circle moving downward into the pin tail.
        let tangentLen = (height - rightJoin.y) * 0.42
        let rightCtrl1 = CGPoint(
            x: rightJoin.x - CGFloat(sin(angle)) * tangentLen,
            y: rightJoin.y + CGFloat(cos(angle)) * tangentLen
        )
        let rightCtrl2 = CGPoint(
            x: tip.x + width * 0.08,
            y: tip.y - (height - rightJoin.y) * 0.22
        )
        let leftCtrl1 = CGPoint(
            x: tip.x - width * 0.08,
            y: tip.y - (height - leftJoin.y) * 0.22
        )
        let leftCtrl2 = CGPoint(
            x: leftJoin.x + CGFloat(sin(angle)) * tangentLen,
            y: leftJoin.y + CGFloat(cos(angle)) * tangentLen
        )

        var path = Path()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(180 - angleDegrees),
            endAngle: .degrees(angleDegrees),
            clockwise: false
        )
        path.addCurve(to: tip, control1: rightCtrl1, control2: rightCtrl2)
        path.addCurve(to: leftJoin, control1: leftCtrl1, control2: leftCtrl2)
        path.closeSubpath()
        return path
    }
}

struct TurtleMapPin: View {
    enum PinState: Equatable {
        case selected
        case linked
        case other
    }

    let state: PinState
    var count: Int = 1

    init(state: PinState, count: Int = 1) {
        self.state = state
        self.count = count
    }

    init(isSelected: Bool, count: Int = 1) {
        self.state = isSelected ? .selected : .other
        self.count = count
    }

    private var fillColor: Color {
        switch state {
        case .selected: AdaColors.navy
        case .linked: AdaColors.secondaryInk
        case .other: .white
        }
    }

    private var iconColor: Color {
        state == .other ? AdaColors.navy : .white
    }

    var body: some View {
        ZStack(alignment: .top) {
            PenyuMapPinShape()
                .fill(fillColor)
                .overlay {
                    PenyuMapPinShape()
                        .stroke(state == .other ? AdaColors.navy.opacity(0.08) : Color.white.opacity(0.18), lineWidth: 1)
                }

            Image("TurtleMapPinIcon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .foregroundStyle(iconColor)
                .padding(.top, 8)
        }
        .frame(width: 40, height: 52)
        .overlay(alignment: .topTrailing) {
            if count > 1 {
                Text(count.formatted())
                    .font(.system(size: 9.5, weight: .bold).monospacedDigit())
                    .foregroundStyle(state == .other ? .white : AdaColors.navy)
                    .padding(.horizontal, 5)
                    .frame(minWidth: 18, minHeight: 18)
                    .background(state == .other ? AdaColors.navy : .white, in: Capsule())
                    .overlay(Capsule().stroke(state == .other ? .white : AdaColors.navy.opacity(0.18), lineWidth: 1.5))
                    .offset(x: 6, y: -4)
            }
        }
        .shadow(color: .black.opacity(0.24), radius: 5, y: 2.5)
        .contentShape(Rectangle())
    }
}

struct PinPointerTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
