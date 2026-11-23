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
    var accountRole = ""
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
    @State private var isAccountPopupPresented = false

    private var isSecondaryWorkspaceSelected: Bool {
        selection == .sightings || selection == .favorites || selection == .identification
    }

    private func localized(_ key: String) -> String {
        localization?.localized(key) ?? key
    }

    private func expandIfCollapsed() {
        guard isCollapsed else { return }
        (onExpandSidebar ?? onToggleSidebar)()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            windowChrome
            brandRow
            VStack(spacing: 6) {
                ForEach([AppSection.dashboard, .map, .individuals, .scientistReview]) { section in
                    navigationRow(section)
                }
            }
            .disabled(isNavigationLocked)
            .padding(.top, 24)

            // Clicking open space in the sidebar toggles/expands smoothly while preserving top chrome window dragging.
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(minHeight: 24)
                .contentShape(Rectangle())
                .onTapGesture {
                    onToggleSidebar()
                }
                .accessibilityHidden(true)

            // Bottom utility rail: cleanly separates secondary tools & Settings from main research workspaces.
            VStack(spacing: 4) {
                Rectangle()
                    .fill(.white.opacity(0.08))
                    .frame(height: 1)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)

                moreWorkspacesControl
                    .padding(.horizontal, 12)

                navigationRow(.settings)
            }
            .disabled(isNavigationLocked)
            .padding(.bottom, 8)

            userMenu
        }
        .frame(width: isCollapsed ? AdaLayout.collapsedSidebarWidth : AdaLayout.sidebarWidth, alignment: .leading)
        .clipped()
        .background(AdaColors.sidebar)
        .animation(AdaSidebarStyle.animation, value: isCollapsed)
    }

    private var moreWorkspacesControl: some View {
        ActionDropdown(
            items: secondaryWorkspaceActions,
            header: localized("More workspaces"),
            placement: .aboveLeading,
            minWidth: 248
        ) {
            HStack(spacing: 14) {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 24)
                    .overlay(alignment: .topTrailing) {
                        if isCollapsed && isSecondaryWorkspaceSelected {
                            Circle()
                                .fill(.white)
                                .frame(width: 6, height: 6)
                                .offset(x: 3, y: -2)
                        }
                    }
                if !isCollapsed {
                    Text(LocalizedStringKey("More workspaces"))
                        .font(.system(size: 13.5, weight: isSecondaryWorkspaceSelected ? .semibold : .regular))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .transition(.opacity)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                        .transition(.opacity)
                }
            }
            .foregroundStyle(.white.opacity(isSecondaryWorkspaceSelected ? 1.0 : 0.85))
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
            .background(isSecondaryWorkspaceSelected ? .white.opacity(0.11) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .clipped()
        }
        .help("Sightings, watchlist, and I3S identification")
        .accessibilityLabel("More workspaces")
    }

    private var secondaryWorkspaceActions: [DropdownAction] {
        [
            DropdownAction(
                title: localized("Sightings"),
                subtitle: localized("Encounter log & timeline"),
                icon: AppSection.sightings.icon,
                selected: selection == .sightings,
                action: {
                    selection = .sightings
                    expandIfCollapsed()
                }
            ),
            DropdownAction(
                title: localized("Watchlist"),
                subtitle: localized("Tracked sea turtles"),
                icon: AppSection.favorites.icon,
                badge: favoriteCount > 0 ? "\(favoriteCount)" : nil,
                selected: selection == .favorites,
                action: {
                    selection = .favorites
                    expandIfCollapsed()
                }
            ),
            DropdownAction(
                title: localized("I3S Pattern ID"),
                subtitle: localized("Spot-matching workbench"),
                icon: AppSection.identification.icon,
                selected: selection == .identification,
                action: {
                    selection = .identification
                    expandIfCollapsed()
                }
            )
        ]
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
            .background(selection == section || (section == .individuals && (selection == .sightings || selection == .favorites)) ? .white.opacity(0.1) : .clear)
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

    private var userMenu: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)

            SidebarAccountTrigger(
                label: accountLabel,
                accessibilityLabel: accountAccessibilityLabel,
                onPress: { isAccountPopupPresented.toggle() }
            )
            .adaFloatingPopup(isPresented: $isAccountPopupPresented, placement: .aboveLeading, verticalGap: 10) {
                SidebarAccountPopupCard(
                    accountName: accountName,
                    accountEmail: accountEmail,
                    accountOrganization: accountOrganization,
                    roleBadge: resolvedRoleBadge,
                    actions: accountMenuModel.popupActions(dismiss: { isAccountPopupPresented = false })
                )
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help("Account")
        }
    }

    private var accountMenuModel: SidebarAccountMenuModel {
        let model = SidebarAccountMenuModel()
        model.onOpenProductSettings = onOpenProductSettings
        model.isSettingsNavigationDisabled = isNavigationLocked
        model.onOpenAuthSettings = onOpenAuthSettings
        model.onSignOut = onSignOut
        model.localize = { key in localization?.localized(key) ?? key }
        return model
    }

    private var resolvedRoleBadge: String {
        if !accountRole.isEmpty { return localized(accountRole) }
        return localized(isDemoWorkspace ? "Demo" : "Live")
    }

    private var accountLabel: some View {
        HStack(spacing: isCollapsed ? 0 : 10) {
            Circle()
                .fill(isCollapsed ? .white.opacity(0.2) : AdaColors.navySoft)
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
        .background(Color.white.opacity(isCollapsed ? 0 : (isAccountPopupPresented ? 0.11 : 0.05)))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(isCollapsed ? 0 : (isAccountPopupPresented ? 0.18 : 0.09)), lineWidth: 1)
        }
        .clipped()
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var accountInitial: String {
        let trimmed = accountName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "?" }
        return String(first).uppercased()
    }

    private var statusLine: String {
        let mode = resolvedRoleBadge
        return accountOrganization.isEmpty ? mode : "\(accountOrganization) · \(mode)"
    }

    private var accountAccessibilityLabel: String {
        [accountName, accountEmail, statusLine]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

struct SidebarAccountPopupAction: Identifiable {
    enum Kind {
        case settings
        case debugEndpoint
        case signOut
    }

    let id: String
    let kind: Kind
    let title: String
    var subtitle: String? = nil
    let icon: String
    var shortcut: String? = nil
    var isEnabled: Bool = true
    var isSubdued: Bool = false
    var isDestructive: Bool = false
    let perform: () -> Void
}

/// Custom non-native FigCraft floating account menu card.
struct SidebarAccountPopupCard: View {
    let accountName: String
    let accountEmail: String
    let accountOrganization: String
    let roleBadge: String
    let actions: [SidebarAccountPopupAction]

    private var initial: String {
        let trimmed = accountName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "?" }
        return String(first).uppercased()
    }

    private var primaryActions: [SidebarAccountPopupAction] {
        actions.filter { !$0.isDestructive }
    }

    private var destructiveActions: [SidebarAccountPopupAction] {
        actions.filter(\.isDestructive)
    }

    var body: some View {
        AdaPopupCardSurface(width: 268, cornerRadius: 18, padding: 10) {
            HStack(spacing: 10) {
                Circle()
                    .fill(AdaColors.navy)
                    .frame(width: 36, height: 36)
                    .overlay {
                        Text(initial)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(accountName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AdaColors.ink)
                            .lineLimit(1)
                        if !roleBadge.isEmpty {
                            Text(roleBadge)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(AdaColors.navy)
                                .padding(.horizontal, 7)
                                .frame(height: 18)
                                .background(AdaColors.canvas, in: Capsule())
                                .overlay(Capsule().stroke(AdaColors.line, lineWidth: 1))
                        }
                    }

                    if !accountEmail.isEmpty {
                        Text(accountEmail)
                            .font(.system(size: 11))
                            .foregroundStyle(AdaColors.secondaryInk)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    if !accountOrganization.isEmpty {
                        Text(accountOrganization)
                            .font(.system(size: 10.5))
                            .foregroundStyle(AdaColors.secondaryInk.opacity(0.85))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)

            if !primaryActions.isEmpty {
                AdaPopupDivider()
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(primaryActions) { item in
                        AdaPopupRow(
                            title: item.title,
                            subtitle: item.subtitle,
                            icon: item.icon,
                            shortcut: item.shortcut,
                            isSubdued: item.isSubdued,
                            isDisabled: !item.isEnabled,
                            action: item.perform
                        )
                    }
                }
            }

            if !destructiveActions.isEmpty {
                AdaPopupDivider()
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(destructiveActions) { item in
                        AdaPopupRow(
                            title: item.title,
                            subtitle: item.subtitle,
                            icon: item.icon,
                            isDestructive: true,
                            isDisabled: !item.isEnabled,
                            action: item.perform
                        )
                    }
                }
            }
        }
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

    func popupActions(dismiss: @escaping () -> Void = {}) -> [SidebarAccountPopupAction] {
        var result: [SidebarAccountPopupAction] = []

        if let openProduct = onOpenProductSettings {
            result.append(SidebarAccountPopupAction(
                id: "settings",
                kind: .settings,
                title: localize("Settings"),
                icon: "gearshape",
                shortcut: "⌘,",
                isEnabled: !isSettingsNavigationDisabled,
                perform: {
                    dismiss()
                    openProduct()
                }
            ))
        }

        #if DEBUG
        if let openAuth = onOpenAuthSettings {
            result.append(SidebarAccountPopupAction(
                id: "debugEndpoint",
                kind: .debugEndpoint,
                title: localize("API Endpoint"),
                subtitle: localize("Debug backend server"),
                icon: "server.rack",
                isEnabled: true,
                isSubdued: true,
                perform: {
                    dismiss()
                    openAuth()
                }
            ))
        }
        #endif

        if let signOut = onSignOut {
            result.append(SidebarAccountPopupAction(
                id: "signOut",
                kind: .signOut,
                title: localize("Sign Out"),
                icon: "rectangle.portrait.and.arrow.right",
                isEnabled: true,
                isDestructive: true,
                perform: {
                    dismiss()
                    signOut()
                }
            ))
        }

        return result
    }

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

/// Full-width account card trigger that avoids SwiftUI's native macOS popup button
/// chrome while presenting our custom FigCraft floating popup card on press.
private struct SidebarAccountTrigger<Label: View>: NSViewRepresentable {
    var label: Label
    var accessibilityLabel: String
    var onPress: () -> Void

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: SidebarAccountMenuHost, context: Context) -> CGSize? {
        let fitting = nsView.hosting.fittingSize
        let width = proposal.width ?? (fitting.width > 20 ? fitting.width : AdaLayout.sidebarWidth - 24)
        let height = fitting.height > 20 ? fitting.height : 56
        return CGSize(width: width, height: height)
    }

    func makeNSView(context: Context) -> SidebarAccountMenuHost {
        let host = SidebarAccountMenuHost(rootView: AnyView(label))
        host.onPress = onPress
        host.syncAccessibilityLabel(accessibilityLabel)
        return host
    }

    func updateNSView(_ nsView: SidebarAccountMenuHost, context: Context) {
        nsView.hosting.rootView = AnyView(label)
        nsView.onPress = onPress
        nsView.syncAccessibilityLabel(accessibilityLabel)
        nsView.invalidateIntrinsicContentSize()
    }
}

private final class SidebarAccountMenuHost: NSView {
    let hosting: InertAccountHostingView
    var onPress: (() -> Void)?

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
        onPress?()
    }

    override func accessibilityPerformPress() -> Bool {
        onPress?()
        return true
    }
}

private final class InertAccountHostingView: NSHostingView<AnyView> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
