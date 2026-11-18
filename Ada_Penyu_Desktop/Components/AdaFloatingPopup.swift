import AppKit
import SwiftUI

/// Edge preference for custom FigCraft floating popups anchored to a trigger view.
enum AdaPopupPlacement {
    case aboveLeading
    case belowLeading
    case belowTrailing
}

/// Custom non-native floating card shell styled to the AdaPenyu FigCraft design system.
/// Renders crisp white surfaces, deep navy ink, hairline borders, and soft layered shadows
/// without macOS translucent popover chrome or system-blue menu highlights.
struct AdaPopupCardSurface<Content: View>: View {
    var width: CGFloat? = nil
    var minWidth: CGFloat = 200
    var maxWidth: CGFloat = 290
    var cornerRadius: CGFloat = 18
    var padding: CGFloat = 8
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(padding)
        .frame(width: width, alignment: .leading)
        .frame(minWidth: width ?? minWidth, maxWidth: width ?? maxWidth, alignment: .leading)
        .background(AdaColors.card, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(AdaColors.navy.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: AdaColors.navy.opacity(0.16), radius: 22, x: 0, y: 12)
        .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
    }
}

/// Reusable interactive row inside any custom FigCraft floating popup.
struct AdaPopupRow: View {
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil
    var badge: String? = nil
    var shortcut: String? = nil
    var isSelected: Bool = false
    var isDestructive: Bool = false
    var isSubdued: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    private var iconColor: Color {
        if isDisabled { return AdaColors.secondaryInk.opacity(0.45) }
        if isDestructive { return AdaColors.red }
        if isSelected { return AdaColors.navy }
        if isSubdued { return AdaColors.secondaryInk }
        return AdaColors.navy.opacity(0.85)
    }

    private var titleColor: Color {
        if isDisabled { return AdaColors.secondaryInk.opacity(0.5) }
        if isDestructive { return AdaColors.red }
        if isSubdued { return AdaColors.secondaryInk }
        return AdaColors.ink
    }

    private var backgroundColor: Color {
        guard !isDisabled else { return .clear }
        if isDestructive && isHovered {
            return AdaColors.red.opacity(0.09)
        }
        if isSelected {
            return AdaColors.navy.opacity(isHovered ? 0.11 : 0.08)
        }
        if isHovered {
            return AdaColors.canvas
        }
        return .clear
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(iconColor)
                        .frame(width: 22, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(isSelected ? AdaColors.navy.opacity(0.10) : (isDestructive && isHovered ? AdaColors.red.opacity(0.10) : Color.clear))
                        )
                }

                VStack(alignment: .leading, spacing: 1.5) {
                    Text(title)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(titleColor)
                        .lineLimit(1)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(AdaColors.secondaryInk)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let badge, !badge.isEmpty {
                    Text(badge)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : AdaColors.navy)
                        .padding(.horizontal, 7)
                        .frame(height: 19)
                        .background(isSelected ? AdaColors.navy : AdaColors.canvas, in: Capsule())
                }

                if let shortcut, !shortcut.isEmpty {
                    Text(shortcut)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(AdaColors.secondaryInk)
                        .padding(.horizontal, 6)
                        .frame(height: 20)
                        .background(AdaColors.canvas, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(AdaColors.line, lineWidth: 1)
                        )
                }

                if isSelected && badge == nil && shortcut == nil {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AdaColors.navy)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, subtitle == nil ? 7 : 8)
            .frame(maxWidth: .infinity, minHeight: subtitle == nil ? 34 : 42, alignment: .leading)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.10)) {
                isHovered = hovering
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct AdaPopupSectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(AdaColors.secondaryInk)
            .padding(.horizontal, 10)
            .padding(.top, 4)
            .padding(.bottom, 5)
    }
}

struct AdaPopupDivider: View {
    var body: some View {
        Rectangle()
            .fill(AdaColors.line)
            .frame(height: 1)
            .padding(.vertical, 5)
            .padding(.horizontal, 6)
    }
}

/// Presents arbitrary SwiftUI content in a borderless, non-native floating `NSPanel`
/// anchored to the host view's screen rect so it never clips inside sidebars or scroll views.
extension View {
    func adaFloatingPopup<PopupContent: View>(
        isPresented: Binding<Bool>,
        placement: AdaPopupPlacement = .belowLeading,
        verticalGap: CGFloat = 8,
        @ViewBuilder content: @escaping () -> PopupContent
    ) -> some View {
        background(
            AdaFloatingPopupAnchor(
                isPresented: isPresented,
                placement: placement,
                verticalGap: verticalGap,
                content: content
            )
        )
    }
}

private struct AdaFloatingPopupAnchor<PopupContent: View>: NSViewRepresentable {
    @Binding var isPresented: Bool
    let placement: AdaPopupPlacement
    let verticalGap: CGFloat
    let content: () -> PopupContent

    func makeCoordinator() -> AdaFloatingPopupCoordinator {
        AdaFloatingPopupCoordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.wantsLayer = false
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onDismiss = {
            if isPresented {
                isPresented = false
            }
        }

        if isPresented {
            let root = AnyView(
                content()
                    .preferredColorScheme(.light)
                    .padding(AdaFloatingPopupCoordinator.shadowInset)
            )
            coordinator.present(
                from: nsView,
                placement: placement,
                verticalGap: verticalGap,
                content: root
            )
        } else {
            coordinator.dismiss()
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: AdaFloatingPopupCoordinator) {
        coordinator.dismiss()
    }
}

@MainActor
final class AdaFloatingPopupCoordinator: NSObject {
    static let shadowInset: CGFloat = 28

    var onDismiss: (() -> Void)?

    private var panel: AdaFloatingPanel?
    private var hostingView: NSHostingView<AnyView>?
    private weak var anchorView: NSView?
    private weak var parentWindow: NSWindow?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var windowObservers: [NSObjectProtocol] = []

    func present(
        from anchorView: NSView,
        placement: AdaPopupPlacement,
        verticalGap: CGFloat,
        content: AnyView
    ) {
        guard let window = anchorView.window else { return }
        self.anchorView = anchorView
        self.parentWindow = window

        if let panel, let hostingView {
            hostingView.rootView = content
            reposition(panel: panel, hostingView: hostingView, anchorView: anchorView, window: window, placement: placement, verticalGap: verticalGap)
            return
        }

        let hosting = NSHostingView(rootView: content)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor

        let fitting = hosting.fittingSize
        let panel = AdaFloatingPanel(
            contentRect: NSRect(origin: .zero, size: fitting),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.acceptsMouseMovedEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = true
        panel.collectionBehavior = [.moveToActiveSpace, .transient]
        panel.contentView = hosting

        self.panel = panel
        self.hostingView = hosting

        reposition(panel: panel, hostingView: hosting, anchorView: anchorView, window: window, placement: placement, verticalGap: verticalGap)

        panel.alphaValue = 0
        window.addChildWindow(panel, ordered: .above)
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.14
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        installMonitors(for: window)
    }

    private func reposition(
        panel: AdaFloatingPanel,
        hostingView: NSHostingView<AnyView>,
        anchorView: NSView,
        window: NSWindow,
        placement: AdaPopupPlacement,
        verticalGap: CGFloat
    ) {
        let fitting = hostingView.fittingSize
        let size = NSSize(width: max(fitting.width, 120), height: max(fitting.height, 60))
        let inset = Self.shadowInset
        let visibleCardSize = NSSize(width: max(size.width - inset * 2, 40), height: max(size.height - inset * 2, 20))

        let anchorInWindow = anchorView.convert(anchorView.bounds, to: nil)
        let anchorOnScreen = window.convertToScreen(anchorInWindow)
        let screenFrame = (window.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        var cardOrigin = NSPoint.zero
        switch placement {
        case .aboveLeading:
            cardOrigin.x = anchorOnScreen.minX
            cardOrigin.y = anchorOnScreen.maxY + verticalGap
            if cardOrigin.y + visibleCardSize.height > screenFrame.maxY - 8 {
                cardOrigin.y = anchorOnScreen.minY - visibleCardSize.height - verticalGap
            }
        case .belowLeading:
            cardOrigin.x = anchorOnScreen.minX
            cardOrigin.y = anchorOnScreen.minY - visibleCardSize.height - verticalGap
            if cardOrigin.y < screenFrame.minY + 8 {
                cardOrigin.y = anchorOnScreen.maxY + verticalGap
            }
        case .belowTrailing:
            cardOrigin.x = anchorOnScreen.maxX - visibleCardSize.width
            cardOrigin.y = anchorOnScreen.minY - visibleCardSize.height - verticalGap
            if cardOrigin.y < screenFrame.minY + 8 {
                cardOrigin.y = anchorOnScreen.maxY + verticalGap
            }
        }

        let minX = screenFrame.minX + 8
        let maxX = max(minX, screenFrame.maxX - visibleCardSize.width - 8)
        cardOrigin.x = min(max(cardOrigin.x, minX), maxX)

        let minY = screenFrame.minY + 8
        let maxY = max(minY, screenFrame.maxY - visibleCardSize.height - 8)
        cardOrigin.y = min(max(cardOrigin.y, minY), maxY)

        let panelOrigin = NSPoint(x: cardOrigin.x - inset, y: cardOrigin.y - inset)
        panel.setFrame(NSRect(origin: panelOrigin, size: size), display: true)
    }

    private func installMonitors(for window: NSWindow) {
        teardownMonitors()

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) { [weak self] event in
            guard let self, let panel = self.panel else { return event }

            if event.type == .keyDown {
                if event.keyCode == 53 { // Escape
                    self.requestDismiss()
                    return nil
                }
                return event
            }

            if event.window === panel {
                return event
            }

            if let anchor = self.anchorView, anchor.window === event.window {
                let pointInAnchor = anchor.convert(event.locationInWindow, from: nil)
                if anchor.bounds.contains(pointInAnchor) {
                    self.requestDismiss()
                    return nil
                }
            }

            self.requestDismiss()
            return event
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.requestDismiss()
            }
        }

        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSWindow.didResignKeyNotification,
            NSWindow.willCloseNotification,
            NSWindow.didResizeNotification,
            NSWindow.didMoveNotification
        ]
        windowObservers = names.map { name in
            center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.requestDismiss()
                }
            }
        }
    }

    private func requestDismiss() {
        dismiss()
        onDismiss?()
    }

    func dismiss() {
        teardownMonitors()
        if let panel {
            if let parentWindow, panel.parent === parentWindow {
                parentWindow.removeChildWindow(panel)
            }
            panel.orderOut(nil)
        }
        panel = nil
        hostingView = nil
    }

    private func teardownMonitors() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        for observer in windowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        windowObservers.removeAll()
    }

    deinit {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        for observer in windowObservers { NotificationCenter.default.removeObserver(observer) }
    }
}

private final class AdaFloatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
