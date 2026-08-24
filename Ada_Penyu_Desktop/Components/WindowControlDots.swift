import AppKit
import SwiftUI

struct WindowControlDots: View {
    private var activeWindow: NSWindow? {
        NSApp.keyWindow ?? NSApp.mainWindow
    }

    var body: some View {
        HStack(spacing: 7) {
            windowButton(
                color: Color(red: 0.98, green: 0.40, blue: 0.38),
                label: "Close window",
                action: { activeWindow?.performClose(nil) }
            )
            windowButton(
                color: Color(red: 1.00, green: 0.68, blue: 0.13),
                label: "Minimize window",
                action: { activeWindow?.miniaturize(nil) }
            )
            windowButton(
                color: Color(red: 0.11, green: 0.72, blue: 0.25),
                label: "Zoom window",
                action: { activeWindow?.performZoom(nil) }
            )
        }
    }

    private func windowButton(color: Color, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 14, height: 14)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(width: 22, height: 22)
        .contentShape(Circle())
        .accessibilityLabel(label)
        .help(label)
    }
}
