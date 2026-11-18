import AppKit
import SwiftUI

/// App shell chrome — the sidebar and top bar. Both are shell-level (never
/// embedded inside a page) so they live together in one file.

// MARK: - Sidebar

enum AdaSidebarStyle {
    static let animation = Animation.spring(response: 0.34, dampingFraction: 0.88)
}

struct SidebarView: View {
    @Binding var selection: AppSection
    @Binding var selectedCondition: TurtleCondition?
    let favoriteCount: Int
    let selectedSpecies: TurtleSpecies?
    /// Called when the user taps a species row. Pass `nil` to clear the
    /// species filter. The caller is expected to route to `.individuals`.
    let onSelectSpecies: (TurtleSpecies?) -> Void

    // Account actions live in the sidebar user menu.
    var onOpenProductSettings: (() -> Void)? = nil
    var onOpenAuthSettings: (() -> Void)? = nil
    var accountName = "Researcher"
    var accountEmail = ""
    var accountOrganization = ""
    var isDemoWorkspace = false
    var onSignOut: (() -> Void)? = nil

    var isCollapsed = false
    var notSurePendingCount = 0
    var isNavigationLocked = false
    var localization: LocalizationManager? = nil
    var onToggleSidebar: () -> Void = {}
    var onExpandSidebar: (() -> Void)? = nil

    @State private var speciesExpanded = true
    @State private var conditionsExpanded = true

    private func expandIfCollapsed() {
        guard isCollapsed else { return }
        (onExpandSidebar ?? onToggleSidebar)()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            windowChrome
            brandRow
            VStack(spacing: 8) {
                ForEach([AppSection.dashboard, .map, .individuals, .scientistReview, .settings]) { section in
                    navigationRow(section)
                }
            }
            .disabled(isNavigationLocked)
            .padding(.top, 28)

            // Clicking open space in the sidebar toggles/expands smoothly while preserving top chrome window dragging.
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(minHeight: 24)
                .contentShape(Rectangle())
                .onTapGesture {
                    onToggleSidebar()
                }
                .accessibilityHidden(true)

            ActionDropdown(items: [
                DropdownAction(title: localization?.localized("Sightings") ?? "Sightings", selected: selection == .sightings, action: {
                    selection = .sightings
                    expandIfCollapsed()
                }),
                DropdownAction(title: "\(localization?.localized("Favorites") ?? "Favorites") (\(favoriteCount))", selected: selection == .favorites, action: {
                    selection = .favorites
                    expandIfCollapsed()
                }),
                DropdownAction(title: "\(localization?.localized("Not Sure Review") ?? "Not Sure Review") (\(notSurePendingCount))", selected: selection == .scientistReview, action: {
                    selection = .scientistReview
                    expandIfCollapsed()
                }),
                DropdownAction(title: localization?.localized("I3S Pattern ID") ?? "I3S Pattern ID", selected: selection == .identification, action: {
                    selection = .identification
                    expandIfCollapsed()
                })
            ]) {
                HStack(spacing: 14) {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 18))
                        .frame(width: 24)
                    if !isCollapsed {
                        Text("More workspaces")
                            .font(.system(size: 12))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .transition(.opacity)
                        Spacer(minLength: 0)
                    }
                }
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .clipped()
            }
            .help("Sightings, favorites, and identification workspaces")
            .accessibilityLabel("More workspaces")
            .disabled(isNavigationLocked)
            .padding(.horizontal, 12)

            userMenu
        }
        .frame(width: isCollapsed ? AdaLayout.collapsedSidebarWidth : AdaLayout.sidebarWidth, alignment: .leading)
        .clipped()
        .background(AdaColors.sidebar)
        .animation(AdaSidebarStyle.animation, value: isCollapsed)
    }

    private func navigationRow(_ section: AppSection) -> some View {
        Button {
            if section == .settings, let onOpenProductSettings {
                onOpenProductSettings()
            } else {
                selection = section
            }
            expandIfCollapsed()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: section.icon)
                    .font(.system(size: 17))
                    .frame(width: 24)
                    .overlay(alignment: .topTrailing) {
                        if section == .scientistReview && isCollapsed && notSurePendingCount > 0 {
                            Circle()
                                .fill(.white)
                                .frame(width: 7, height: 7)
                                .offset(x: 4, y: -3)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                if !isCollapsed {
                    Text(LocalizedStringKey(section.title))
                        .font(.system(size: 14))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .transition(.opacity)
                    Spacer(minLength: 0)
                    if section == .scientistReview && notSurePendingCount > 0 {
                        Text("\(notSurePendingCount)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(AdaColors.navy)
                            .padding(.horizontal, 7)
                            .frame(height: 18)
                            .background(.white.opacity(0.92), in: Capsule())
                            .transition(.opacity)
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(selection == section || (section == .individuals && selection == .sightings) ? .white.opacity(0.1) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .clipped()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .help(section.title)
        .accessibilityLabel(section.title)
        .accessibilityAddTraits(selection == section ? .isSelected : [])
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
                Button(action: onToggleSidebar) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Collapse sidebar")
                .accessibilityLabel("Collapse sidebar")
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 14).frame(height: 40)
    }

    private var brandRow: some View {
        Button(action: onToggleSidebar) {
            HStack(spacing: 8) {
                Image("AdaPenyuMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                if !isCollapsed {
                    Image("AdaPenyuWordmark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 126, height: 28)
                        .fixedSize()
                        .transition(.opacity)
                }
            }
            .padding(.leading, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .clipped()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isCollapsed ? "Expand sidebar" : "Collapse sidebar")
        .accessibilityLabel(isCollapsed ? "AdaPenyu, Expand sidebar" : "AdaPenyu, Collapse sidebar")
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
                onOpenProductSettings: onOpenProductSettings,
                isSettingsNavigationDisabled: isNavigationLocked,
                onOpenAuthSettings: onOpenAuthSettings,
                onSignOut: onSignOut,
                localization: localization
            )
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help("Account")
        }
    }

    private var accountLabel: some View {
        HStack(spacing: isCollapsed ? 0 : 10) {
            Circle()
                .fill(isCollapsed ? .white.opacity(0.2) : AdaColors.navy)
                .frame(width: 32, height: 32)
                .overlay {
                    Text(accountInitial)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }

            if !isCollapsed {
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
                .transition(.opacity)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.65))
                    .accessibilityHidden(true)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(width: isCollapsed ? 48 : AdaLayout.sidebarWidth - 24, alignment: .leading)
        .background(Color.white.opacity(isCollapsed ? 0 : 0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AdaColors.line.opacity(isCollapsed ? 0 : 1), lineWidth: 1)
        }
        .clipped()
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var accountInitial: String {
        let trimmed = accountName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "?" }
        return String(first).uppercased()
    }

    private var statusLine: String {
        let mode = isDemoWorkspace ? "Demo" : "Live"
        return accountOrganization.isEmpty ? mode : "\(accountOrganization) · \(mode)"
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
    var onOpenProductSettings: (() -> Void)?
    var isSettingsNavigationDisabled = false
    var onOpenAuthSettings: (() -> Void)?
    var onSignOut: (() -> Void)?
    var localization: LocalizationManager? = nil

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
        model.onOpenProductSettings = onOpenProductSettings
        model.isSettingsNavigationDisabled = isSettingsNavigationDisabled
        model.onOpenAuthSettings = onOpenAuthSettings
        model.onSignOut = onSignOut
        model.localize = { key in localization?.localized(key) ?? key }
    }
}

final class SidebarAccountMenuModel: NSObject {
    var onOpenProductSettings: (() -> Void)?
    var isSettingsNavigationDisabled = false
    var onOpenAuthSettings: (() -> Void)?
    var onSignOut: (() -> Void)?
    var localize: (String) -> String = { $0 }

    @objc func openProductSettings(_ sender: NSMenuItem) { onOpenProductSettings?() }

    @objc func openSettings(_ sender: NSMenuItem) { onOpenAuthSettings?() }

    @objc func signOut(_ sender: NSMenuItem) { onSignOut?() }

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        if onOpenProductSettings != nil {
            let item = NSMenuItem(title: localize("Settings…"), action: #selector(openProductSettings(_:)), keyEquivalent: ",")
            item.keyEquivalentModifierMask = [.command]
            item.target = self
            item.isEnabled = !isSettingsNavigationDisabled
            item.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
            menu.addItem(item)
        }

        #if DEBUG
        if onOpenAuthSettings != nil {
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            let item = NSMenuItem(title: localize("Developer API Settings…"), action: #selector(openSettings(_:)), keyEquivalent: "")
            item.target = self
            item.image = NSImage(systemSymbolName: "network.badge.shield.half.filled", accessibilityDescription: nil)
            menu.addItem(item)
        }
        #endif

        if onSignOut != nil {
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            let item = NSMenuItem(title: localize("Sign Out"), action: #selector(signOut(_:)), keyEquivalent: "")
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
        wantsLayer = true
        layer?.masksToBounds = true
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
