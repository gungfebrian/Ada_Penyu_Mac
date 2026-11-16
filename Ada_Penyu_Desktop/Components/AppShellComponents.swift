import AppKit
import SwiftUI

/// App shell chrome — the sidebar and top bar. Both are shell-level (never
/// embedded inside a page) so they live together in one file.

// MARK: - Sidebar

struct SidebarView: View {
    @Binding var selection: AppSection
    @Binding var selectedCondition: TurtleCondition?
    let favoriteCount: Int
    let selectedSpecies: TurtleSpecies?
    /// Called when the user taps a species row. Pass `nil` to clear the
    /// species filter. The caller is expected to route to `.individuals`.
    let onSelectSpecies: (TurtleSpecies?) -> Void

    // Account actions live in the sidebar user menu.
    var onOpenAuthSettings: (() -> Void)? = nil
    var accountName = "Researcher"
    var accountEmail = ""
    var accountOrganization = ""
    var onSignOut: (() -> Void)? = nil

    var isCollapsed = false
    var onToggleSidebar: () -> Void = {}

    @State private var speciesExpanded = true
    @State private var conditionsExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            windowChrome
            brandRow
            VStack(spacing: 8) {
                ForEach([AppSection.dashboard, .map, .individuals]) { section in
                    navigationRow(section)
                }
            }
            .padding(.top, 28)
            Spacer(minLength: 24)
            ActionDropdown(items: [
                DropdownAction(title: "Sightings", selected: selection == .sightings, action: { selection = .sightings }),
                DropdownAction(title: "Favorites (\(favoriteCount))", selected: selection == .favorites, action: { selection = .favorites }),
                DropdownAction(title: "Scientist Review", selected: selection == .scientistReview, action: { selection = .scientistReview }),
                DropdownAction(title: "I3S Pattern ID", selected: selection == .identification, action: { selection = .identification })
            ]) {
                HStack(spacing: 12) {
                    Image(systemName: "ellipsis.circle").font(.system(size: 18))
                    if !isCollapsed { Text("More workspaces").font(.system(size: 12)); Spacer() }
                }
                .foregroundStyle(.white.opacity(0.85))
                .padding(14).frame(maxWidth: .infinity)
            }
            .help("Sightings, favorites, and identification workspaces")
            .accessibilityLabel("More workspaces")
            .padding(.horizontal, 12)
            if isCollapsed {
                SidebarAccountMenu(label: AnyView(accountAvatar), accessibilityLabel: accountAccessibilityLabel,
                    onOpenAuthSettings: onOpenAuthSettings, onSignOut: onSignOut)
                    .frame(width: 48, height: 52).padding(.horizontal, 12).padding(.bottom, 12)
            } else {
                userMenu
            }
        }
        .frame(width: isCollapsed ? AdaLayout.collapsedSidebarWidth : AdaLayout.sidebarWidth)
        .background(AdaColors.sidebar)
    }

    private func navigationRow(_ section: AppSection) -> some View {
        Button { selection = section } label: {
            HStack(spacing: 14) {
                Image(systemName: section.icon).font(.system(size: 17)).frame(width: 24)
                if !isCollapsed { Text(section.title).font(.system(size: 14)); Spacer() }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 13)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: isCollapsed ? .center : .leading)
            .background(selection == section || (section == .individuals && selection == .sightings) ? .white.opacity(0.1) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .help(section.title)
        .accessibilityLabel(section.title)
        .accessibilityAddTraits(selection == section ? .isSelected : [])
    }

    private var accountAvatar: some View {
        Circle().fill(.white.opacity(0.2)).frame(width: 32, height: 32)
            .overlay(Text(accountInitial).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white))
    }

    // The sidebar highlights a species only while the user is on the
    // Individuals list. A filter carried in the background doesn't cause a
    // misleading highlight on Dashboard/Map.
    private func isSpeciesActive(_ species: TurtleSpecies) -> Bool {
        selectedSpecies == species && selection == .individuals
    }

    private var windowChrome: some View {
        HStack {
            Spacer()
            if !isCollapsed {
                Button(action: onToggleSidebar) { Image(systemName: "sidebar.left").foregroundStyle(.white.opacity(0.75)) }
                    .buttonStyle(.plain).help("Collapse sidebar").accessibilityLabel("Collapse sidebar")
            }
        }
        .padding(.horizontal, 14).frame(height: 40)
    }

    private var brandRow: some View {
        HStack(spacing: 8) {
            Image("AdaPenyuMark").resizable().scaledToFit().frame(width: 36, height: 36)
            if !isCollapsed {
                Image("AdaPenyuWordmark").resizable().scaledToFit().frame(width: 126, height: 28)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8).padding(.bottom, 12)
        .accessibilityElement(children: .ignore).accessibilityLabel("AdaPenyu")
        .overlay {
            if isCollapsed {
                Button(action: onToggleSidebar) { Color.clear.contentShape(Rectangle()) }
                    .buttonStyle(.plain).help("Expand sidebar").accessibilityLabel("Expand sidebar")
            }
        }
    }

    // SwiftUI Menu draws this label as a 31pt popup button, so the profile
    // is a normal view and the actions open through an AppKit menu.
    private var userMenu: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(AdaColors.line)
                .frame(height: 1)

            SidebarAccountMenu(
                label: accountLabel,
                accessibilityLabel: accountAccessibilityLabel,
                onOpenAuthSettings: onOpenAuthSettings,
                onSignOut: onSignOut
            )
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help("Account")
        }
    }

    private var accountLabel: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(AdaColors.navy)
                .frame(width: 32, height: 32)
                .overlay {
                    Text(accountInitial)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(accountName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if !accountEmail.isEmpty {
                    Text(accountEmail)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Text(statusLine)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.65))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(width: AdaLayout.sidebarWidth - 24, alignment: .leading)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AdaColors.line, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var accountInitial: String {
        let trimmed = accountName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "?" }
        return String(first).uppercased()
    }

    private var statusLine: String {
        accountOrganization.isEmpty ? "Live" : "\(accountOrganization) · Live"
    }

    private var accountAccessibilityLabel: String {
        [accountName, accountEmail, statusLine]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

/// Full-width account row. A SwiftUI `Menu` label collapses to the initial
/// on macOS, so this view draws the profile and pops an `NSMenu` on click.
private struct SidebarAccountMenu<Label: View>: NSViewRepresentable {
    var label: Label
    var accessibilityLabel: String
    var onOpenAuthSettings: (() -> Void)?
    var onSignOut: (() -> Void)?

    func makeCoordinator() -> SidebarAccountMenuModel { SidebarAccountMenuModel() }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: SidebarAccountMenuHost, context: Context) -> CGSize? {
        let fitting = nsView.hosting.fittingSize
        let width = proposal.width ?? (fitting.width > 20 ? fitting.width : AdaLayout.sidebarWidth - 24)
        let height = fitting.height > 20 ? fitting.height : 56
        return CGSize(width: width, height: height)
    }

    func makeNSView(context: Context) -> SidebarAccountMenuHost {
        let host = SidebarAccountMenuHost(rootView: AnyView(label))
        host.model = context.coordinator
        apply(context.coordinator)
        host.syncAccessibilityLabel(accessibilityLabel)
        return host
    }

    func updateNSView(_ nsView: SidebarAccountMenuHost, context: Context) {
        nsView.hosting.rootView = AnyView(label)
        nsView.model = context.coordinator
        apply(context.coordinator)
        nsView.syncAccessibilityLabel(accessibilityLabel)
        nsView.invalidateIntrinsicContentSize()
    }

    private func apply(_ model: SidebarAccountMenuModel) {
        model.onOpenAuthSettings = onOpenAuthSettings
        model.onSignOut = onSignOut
    }
}

final class SidebarAccountMenuModel: NSObject {
    var onOpenAuthSettings: (() -> Void)?
    var onSignOut: (() -> Void)?

    @objc func openSettings(_ sender: NSMenuItem) { onOpenAuthSettings?() }

    @objc func signOut(_ sender: NSMenuItem) { onSignOut?() }

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        #if DEBUG
        if onOpenAuthSettings != nil {
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            let item = NSMenuItem(title: "Developer API Settings…", action: #selector(openSettings(_:)), keyEquivalent: "")
            item.target = self
            item.image = NSImage(systemSymbolName: "network.badge.shield.half.filled", accessibilityDescription: nil)
            menu.addItem(item)
        }
        #endif

        if onSignOut != nil {
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            let item = NSMenuItem(title: "Sign Out", action: #selector(signOut(_:)), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        return menu
    }
}

private final class SidebarAccountMenuHost: NSView {
    let hosting: InertAccountHostingView
    var model: SidebarAccountMenuModel?

    init(rootView: AnyView) {
        hosting = InertAccountHostingView(rootView: rootView)
        super.init(frame: .zero)
        hosting.translatesAutoresizingMaskIntoConstraints = true
        addSubview(hosting)
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        let fitting = hosting.fittingSize
        guard fitting.width > 20, fitting.height > 20 else {
            return NSSize(width: AdaLayout.sidebarWidth - 24, height: 56)
        }
        return fitting
    }

    override func layout() {
        super.layout()
        hosting.frame = bounds
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return bounds.contains(local) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func syncAccessibilityLabel(_ label: String) {
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(label)
    }

    override func mouseDown(with event: NSEvent) {
        guard let menu = model?.makeMenu() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func accessibilityPerformPress() -> Bool {
        guard let menu = model?.makeMenu() else { return false }
        menu.popUp(positioning: nil, at: NSPoint(x: bounds.midX, y: bounds.maxY), in: self)
        return true
    }
}

private final class InertAccountHostingView: NSHostingView<AnyView> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
