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

    @State private var speciesExpanded = true
    @State private var conditionsExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            windowChrome
            brandRow

            VStack(alignment: .leading, spacing: 3) {
                SidebarSectionRow(section: .dashboard, selection: $selection)
                SidebarSectionRow(section: .map, selection: $selection)
                SidebarSectionRow(section: .scientistReview, selection: $selection)
                SidebarSectionRow(section: .identification, selection: $selection)
                SidebarSectionRow(section: .favorites, selection: $selection, count: favoriteCount)
            }

            SidebarGroupHeader(title: "Sea Turtle Group", isExpanded: $speciesExpanded)
                .padding(.top, 19)
                .padding(.bottom, 3)

            if speciesExpanded {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(TurtleSpecies.allCases) { species in
                        SidebarSpeciesRow(
                            species: species,
                            isSelected: isSpeciesActive(species)
                        ) {
                            onSelectSpecies(selectedSpecies == species ? nil : species)
                        }
                    }
                }
            }

            SidebarGroupHeader(title: "Body Condition", isExpanded: $conditionsExpanded)
                .padding(.top, 19)
                .padding(.bottom, 3)

            if conditionsExpanded {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(TurtleCondition.allCases) { condition in
                        SidebarConditionRow(
                            condition: condition,
                            isSelected: selectedCondition == condition
                        ) {
                            // Tap-again-to-clear keeps it a strict single-select
                            // radio without needing a separate "All" row.
                            selectedCondition = (selectedCondition == condition) ? nil : condition
                        }
                    }
                }
            }

            Spacer(minLength: 16)

            userMenu
        }
        .frame(width: AdaLayout.sidebarWidth)
        .background(AdaColors.sidebar)
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
            Image(systemName: "sidebar.left")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AdaColors.ink.opacity(0.82))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
    }

    private var brandRow: some View {
        HStack(spacing: 14) {
            TurtleAppIconMark(size: 36)
            Text("Sea Turtle Group")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AdaColors.ink)
        }
        .padding(.horizontal, 15)
        .padding(.top, 14)
        .padding(.bottom, 22)
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
                    .foregroundStyle(AdaColors.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if !accountEmail.isEmpty {
                    Text(accountEmail)
                        .font(.system(size: 10))
                        .foregroundStyle(AdaColors.secondaryInk)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Text(statusLine)
                    .font(.system(size: 10))
                    .foregroundStyle(AdaColors.tertiaryInk)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(AdaColors.tertiaryInk)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(width: AdaLayout.sidebarWidth - 24, alignment: .leading)
        .background(AdaColors.card)
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

// MARK: - Sidebar rows

private struct SidebarSectionRow: View {
    let section: AppSection
    @Binding var selection: AppSection
    var count: Int? = nil

    private var isSelected: Bool { selection == section }

    var body: some View {
        Button { selection = section } label: {
            HStack(spacing: 10) {
                Image(systemName: section.icon)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 14)
                Text(section.title).font(.system(size: 13, weight: isSelected ? .medium : .regular))
                Spacer()
                if let count {
                    Text("\(count)")
                        .font(.system(size: 12))
                        .foregroundStyle(AdaColors.tertiaryInk)
                }
            }
            .foregroundStyle(AdaColors.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .background(isSelected ? Color.black.opacity(0.075) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .accessibilityLabel(section.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct SidebarGroupHeader: View {
    let title: String
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(AdaColors.secondaryInk)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AdaColors.tertiaryInk)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }
}

private struct SidebarSpeciesRow: View {
    let species: TurtleSpecies
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "tortoise.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AdaColors.ink)
                    .frame(width: 14)
                Text(species.rawValue).font(.system(size: 13, weight: isSelected ? .medium : .regular))
                Spacer()
            }
            .foregroundStyle(AdaColors.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .background(isSelected ? Color.black.opacity(0.075) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .accessibilityLabel(species.rawValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(isSelected ? "Clear species filter" : "Filter by \(species.rawValue)")
    }
}

/// Radio-style single-select condition row. Colored dot prefix maps to the
/// condition tint (green/orange/red). Tapping the selected row clears the
/// filter — the "All" state is implicit (no row highlighted).
private struct SidebarConditionRow: View {
    let condition: TurtleCondition
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Circle()
                    .fill(condition.tint)
                    .frame(width: 8, height: 8)
                    .frame(width: 14)
                Text(condition.rawValue).font(.system(size: 13, weight: isSelected ? .medium : .regular))
                Spacer()
            }
            .foregroundStyle(AdaColors.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .background(isSelected ? Color.black.opacity(0.075) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .accessibilityLabel(condition.rawValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(isSelected ? "Clear condition filter" : "Filter by \(condition.rawValue)")
    }
}

// MARK: - Top bar

struct TopBar: View {
    let title: String
    let subtitle: String?
    @Binding var searchText: String
    let onExport: (() -> Void)?
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(AdaColors.ink)
                if let subtitle { Text(subtitle).font(.system(size: 11)).foregroundStyle(AdaColors.tertiaryInk) }
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .medium)).foregroundStyle(AdaColors.tertiaryInk)
                TextField(
                    "",
                    text: $searchText,
                    prompt: Text("Search individuals").foregroundStyle(AdaColors.secondaryInk)
                )
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(AdaColors.ink)
                    .tint(AdaColors.navy)
                    .focused($isSearchFocused)
                    .frame(width: 214)
            }
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background(AdaColors.card)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(isSearchFocused ? AdaColors.accent : AdaColors.line, lineWidth: isSearchFocused ? 1.5 : 1)
            }

            if let onExport {
                Button(action: onExport) {
                    HStack(spacing: 7) {
                        Image(systemName: "arrow.down").font(.system(size: 10, weight: .bold))
                        Text("Export").font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                    .background(AdaColors.navy)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 23)
        .padding(.trailing, 32)
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(AdaColors.canvas)
    }
}
