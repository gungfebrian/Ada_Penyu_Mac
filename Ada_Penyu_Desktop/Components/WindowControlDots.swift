import SwiftUI

struct WindowControlDots: View {
    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(Color(red: 0.98, green: 0.40, blue: 0.38))
                .frame(width: 14, height: 14)
            Circle()
                .fill(Color(red: 1.00, green: 0.68, blue: 0.13))
                .frame(width: 14, height: 14)
            Circle()
                .fill(Color(red: 0.11, green: 0.72, blue: 0.25))
                .frame(width: 14, height: 14)
        }
        .accessibilityHidden(true)
    }
}
