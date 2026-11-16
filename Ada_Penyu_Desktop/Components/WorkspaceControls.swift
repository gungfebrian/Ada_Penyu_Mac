import SwiftUI

struct WorkspaceHeader: View {
    @ObservedObject var store: AppStore
    let title: String
    let onExport: () -> Void
    let onToggleSidebar: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 20) { heading; Spacer(minLength: 16); controls }
            VStack(alignment: .leading, spacing: 16) { heading; HStack { Spacer(minLength: 0); controls } }
        }
        .padding(.horizontal, AdaLayout.pagePadding)
        .padding(.top, 26).padding(.bottom, 28)
    }

    private var heading: some View {
        HStack(spacing: 14) {
            Button(action: onToggleSidebar) {
                Image(systemName: store.activeSection.icon).font(.system(size: 16))
                    .foregroundStyle(AdaColors.navy).frame(width: 38, height: 38)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain).help("Toggle sidebar").accessibilityLabel("Toggle sidebar")
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
                    SpeciesPicker(selection: $store.chartSpecies)
                    ContextPill(title: "Last 12 months", icon: "calendar")
                } else if store.activeSection == .map || store.activeSection == .sightings {
                    SpeciesPicker(selection: $store.mapSpecies)
                    ActionDropdown(items: MapPeriod.allCases.map { period in
                        DropdownAction(title: period.rawValue, selected: store.selectedMapPeriod == period,
                                       action: { store.selectedMapPeriod = period })
                    }) { ContextPill(title: store.selectedMapPeriod.rawValue, icon: "calendar", chevron: true) }
                    .fixedSize().accessibilityLabel("Sighting time window")
                }
            }
            if store.activeSection != .map && store.selectedTurtle == nil {
                Button(action: onExport) { Label("Export report", systemImage: "arrow.up.arrow.down").font(.system(size: 12)) }
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
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 11))
            Text(title).font(.system(size: 12)).lineLimit(1)
            if chevron { Image(systemName: "chevron.down").font(.system(size: 8)) }
        }
        .foregroundStyle(AdaColors.ink).padding(.horizontal, 16).frame(height: 36)
        .background(.white, in: Capsule())
    }
}

struct SpeciesPicker: View {
    @Binding var selection: TurtleSpecies?
    var body: some View {
        ActionDropdown(items: [DropdownAction(title: "All species", selected: selection == nil, action: { selection = nil })] +
            TurtleSpecies.allCases.map { species in DropdownAction(title: species.rawValue, selected: selection == species, action: { selection = species }) }) {
                ContextPill(title: selection?.rawValue ?? "All species", icon: "tortoise", chevron: true)
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
    var selected = false
    let action: () -> Void
    var id: String { title }
}

/// SwiftUI's macOS Menu restyles complex labels as native popup cells. A
/// popover keeps the supplied capsule/rail label and its full click target.
struct ActionDropdown<Label: View>: View {
    let items: [DropdownAction]
    @ViewBuilder let label: Label
    @State private var showing = false
    var body: some View {
        Button { showing.toggle() } label: { label.contentShape(Rectangle()) }
            .buttonStyle(.plain)
            .popover(isPresented: $showing, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(items) { item in
                        Button {
                            showing = false
                            item.action()
                        } label: {
                            HStack(spacing: 10) {
                                Text(item.title).frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "checkmark").opacity(item.selected ? 1 : 0)
                            }
                            .font(.system(size: 12)).foregroundStyle(AdaColors.ink)
                            .padding(.horizontal, 12).frame(minHeight: 30).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        .accessibilityAddTraits(item.selected ? .isSelected : [])
                    }
                }.padding(6).frame(minWidth: 190)
            }
    }
}

struct ConditionPicker: View {
    @Binding var selection: TurtleCondition?
    var body: some View {
        ActionDropdown(items: [DropdownAction(title: "All conditions", selected: selection == nil, action: { selection = nil })] +
            TurtleCondition.allCases.map { condition in DropdownAction(title: condition.rawValue, selected: selection == condition, action: { selection = condition }) }) {
                ContextPill(title: selection?.rawValue ?? "All conditions", icon: "line.3.horizontal.decrease", chevron: true)
            }
            .accessibilityLabel("Condition filter").accessibilityValue(selection?.rawValue ?? "All conditions")
    }
}
