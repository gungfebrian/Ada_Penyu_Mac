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

struct TurtleMapPin: View {
    let isSelected: Bool

    var body: some View {
        VStack(spacing: -1) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white)
                .frame(width: 44, height: 44)
                .overlay {
                    Image("TurtleMapPinIcon")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .padding(9)
                        .foregroundStyle(AdaColors.navy)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(isSelected ? AdaColors.accent : Color.clear, lineWidth: 2)
                }

            PinPointerTriangle()
                .fill(Color.white)
                .frame(width: 14, height: 8)
        }
        .shadow(color: .black.opacity(0.22), radius: 4, y: 2)
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
