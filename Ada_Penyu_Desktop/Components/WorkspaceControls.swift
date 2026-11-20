import AppKit
import SwiftUI

@MainActor
enum SidebarToggleExclusionRegistry {
    static let windowMarkers = NSMapTable<NSWindow, NSView>.weakToWeakObjects()
}

private struct SidebarToggleExclusionMarker: NSViewRepresentable {
    func makeNSView(context: Context) -> MarkerView { MarkerView() }
    func updateNSView(_ nsView: MarkerView, context: Context) { nsView.registerInWindow() }

    final class MarkerView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            registerInWindow()
        }

        func registerInWindow() {
            guard let window else { return }
            SidebarToggleExclusionRegistry.windowMarkers.setObject(self, forKey: window)
        }
    }
}

struct WorkspaceHeader: View {
    @ObservedObject var store: AppStore
    let title: String
    var onImport: (() -> Void)? = nil
    let onExport: () -> Void
    var isSidebarCollapsed: Bool = false
    let onToggleSidebar: () -> Void
    @State private var isToggleHovered = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 20) { heading; Spacer(minLength: 16); controls }
            VStack(alignment: .leading, spacing: 16) { heading; HStack { Spacer(minLength: 0); controls } }
        }
        .padding(.horizontal, AdaLayout.pagePadding)
        .padding(.top, 24).padding(.bottom, 18)
    }

    private var headerIcon: String {
        switch store.activeSection {
        case .individuals, .favorites, .scientistReview:
            AppSection.individuals.icon
        default:
            store.activeSection.icon
        }
    }

    private var heading: some View {
        HStack(spacing: 14) {
            Button(action: onToggleSidebar) {
                Image(systemName: headerIcon)
                    .font(.system(size: 16))
                    .foregroundStyle(AdaColors.navy)
                    .frame(width: 38, height: 38)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isToggleHovered ? Color.white.opacity(0.92) : .white)
                            .shadow(color: Color.black.opacity(isToggleHovered ? 0.08 : 0.02), radius: isToggleHovered ? 6 : 2, y: 1)
                    )
                    .scaleEffect(isToggleHovered ? 1.03 : 1.0)
                    .background(SidebarToggleExclusionMarker())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.14)) {
                    isToggleHovered = hovering
                }
            }
            .help(isSidebarCollapsed ? "Expand sidebar" : "Collapse sidebar")
            .accessibilityLabel(isSidebarCollapsed ? "Expand sidebar" : "Toggle sidebar")
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 24, weight: .semibold)).foregroundStyle(AdaColors.ink)
                Text(store.accountOrganization.isEmpty ? "Sea Turtle Group" : store.accountOrganization)
                    .font(.system(size: 11)).foregroundStyle(AdaColors.secondaryInk)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    @ViewBuilder private var controls: some View {
        HStack(spacing: 10) {
            if store.selectedTurtle == nil {
                if store.activeSection == .dashboard {
                    if store.isDemoBypassActive {
                        ActionDropdown(items: DemoDashboardPersona.allCases.map { persona in
                            DropdownAction(
                                title: "\(persona.displayName) · \(persona.roleLabel)",
                                selected: store.demoPersona == persona,
                                action: { store.selectDemoPersona(persona) }
                            )
                        }) {
                            ContextPill(title: store.demoPersona.displayName, icon: "person.crop.circle", chevron: true)
                        }
                        .fixedSize()
                        .help("Switch account workspace")
                    }
                    SpeciesPicker(selection: $store.chartSpecies)

                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            store.isEditingDashboardWidgets.toggle()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: store.isEditingDashboardWidgets ? "checkmark" : "slider.horizontal.3")
                                .font(.system(size: 11, weight: .semibold))
                            Text(store.isEditingDashboardWidgets ? "Done" : "Customize")
                                .font(.system(size: 12, weight: store.isEditingDashboardWidgets ? .semibold : .regular))
                        }
                        .foregroundStyle(store.isEditingDashboardWidgets ? .white : AdaColors.ink)
                        .padding(.horizontal, 16)
                        .frame(height: 36)
                        .background(store.isEditingDashboardWidgets ? AdaColors.navy : .white, in: Capsule())
                    }
                    .buttonStyle(.plain)
                } else if store.activeSection == .map || store.activeSection == .sightings {
                    SpeciesPicker(selection: $store.mapSpecies)
                    ActionDropdown(items: MapPeriod.allCases.map { period in
                        DropdownAction(title: period.rawValue, selected: store.selectedMapPeriod == period,
                                       action: { store.selectedMapPeriod = period })
                    }) { ContextPill(title: store.selectedMapPeriod.rawValue, icon: "calendar", chevron: true) }
                    .fixedSize().accessibilityLabel("Sighting time window")
                }
            }
            if store.activeSection != .map && store.activeSection != .settings && store.selectedTurtle == nil {
                if let onImport {
                    Button(action: onImport) {
                        Label("Import", systemImage: "square.and.arrow.down")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(AdaColors.ink)
                    .padding(.horizontal, 16)
                    .frame(height: 34)
                    .background(AdaColors.card, in: Capsule())
                    .overlay(Capsule().stroke(AdaColors.line, lineWidth: 1))
                    .buttonStyle(.plain)
                    .help("Import HEIC, JPEG, PNG photos, folders, CSV, or XLSX")
                }
                Button(action: onExport) { Label("Export", systemImage: "square.and.arrow.up").font(.system(size: 12)) }
                    .buttonStyle(AdaPillButtonStyle())
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct ContextPill: View {
    let title: String
    let icon: String
    var chevron = false
    var isActive = false
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 11, weight: isActive ? .semibold : .regular))
            Text(title).font(.system(size: 12, weight: isActive ? .semibold : .regular)).lineLimit(1)
            if chevron { Image(systemName: "chevron.down").font(.system(size: 8.5, weight: .semibold)).opacity(0.75) }
        }
        .foregroundStyle(isActive ? .white : AdaColors.ink)
        .padding(.horizontal, 14).frame(height: 36)
        .background(isActive ? AdaColors.navy : AdaColors.card, in: Capsule())
        .overlay(Capsule().stroke(isActive ? AdaColors.navy : AdaColors.line, lineWidth: 1))
    }
}

struct SpeciesPicker: View {
    @Binding var selection: TurtleSpecies?
    var body: some View {
        ActionDropdown(items: [DropdownAction(title: "All species", selected: selection == nil, action: { selection = nil })] +
            TurtleSpecies.allCases.map { species in DropdownAction(title: species.rawValue, selected: selection == species, action: { selection = species }) }) {
                ContextPill(title: selection?.rawValue ?? "All species", icon: "tortoise", chevron: true, isActive: selection != nil)
            }
            .fixedSize().accessibilityLabel("Species filter").accessibilityValue(selection?.rawValue ?? "All species")
    }
}

struct AdaPillButtonStyle: ButtonStyle {
    var secondary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .foregroundStyle(secondary ? AdaColors.ink : .white)
            .padding(.horizontal, 18).frame(height: 34)
            .background(secondary ? AdaColors.canvas : AdaColors.navy, in: Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Capsule())
    }
}

struct SpeciesLabel: View {
    let species: TurtleSpecies
    var body: some View {
        HStack(spacing: 8) {
            if let asset = species.shellAsset {
                Image(asset).renderingMode(.template).resizable().scaledToFit().frame(width: 12, height: 16)
            } else { Image(systemName: "tortoise").font(.system(size: 11)) }
            Text(species.rawValue).lineLimit(1)
        }
        .foregroundStyle(AdaColors.ink)
    }
}

struct DropdownAction: Identifiable {
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil
    var badge: String? = nil
    var selected = false
    let action: () -> Void
    var id: String { title }
}

/// Custom non-native FigCraft floating dropdown menu. Keeps supplied capsule/rail
/// labels intact and renders a crisp elevated surface with zero native popover glass.
struct ActionDropdown<Label: View>: View {
    let items: [DropdownAction]
    var header: String? = nil
    var placement: AdaPopupPlacement = .belowLeading
    var minWidth: CGFloat = 204
    @ViewBuilder let label: Label
    @State private var showing = false

    var body: some View {
        Button {
            showing.toggle()
        } label: {
            label.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .adaFloatingPopup(isPresented: $showing, placement: placement, verticalGap: 8) {
            AdaPopupCardSurface(minWidth: minWidth) {
                if let header, !header.isEmpty {
                    AdaPopupSectionHeader(title: header)
                }
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(items) { item in
                        AdaPopupRow(
                            title: item.title,
                            subtitle: item.subtitle,
                            icon: item.icon,
                            badge: item.badge,
                            isSelected: item.selected
                        ) {
                            showing = false
                            item.action()
                        }
                    }
                }
            }
        }
    }
}

struct ConditionPicker: View {
    @Binding var selection: TurtleCondition?
    var body: some View {
        ActionDropdown(items: [DropdownAction(title: "All conditions", selected: selection == nil, action: { selection = nil })] +
            TurtleCondition.allCases.map { condition in DropdownAction(title: condition.rawValue, selected: selection == condition, action: { selection = condition }) }) {
                ContextPill(title: selection?.rawValue ?? "All conditions", icon: "line.3.horizontal.decrease", chevron: true, isActive: selection != nil)
            }
            .fixedSize()
            .accessibilityLabel("Condition filter").accessibilityValue(selection?.rawValue ?? "All conditions")
    }
}
