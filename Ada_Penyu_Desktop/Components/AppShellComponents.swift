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

    // Data-source picker lives in the sidebar user menu so we only have one
    // menu affordance in the shell (top bar stays clean).
    let dataMode: DataMode
    let isFallback: Bool
    let onModeChange: (DataMode) -> Void

    @State private var speciesExpanded = true
    @State private var conditionsExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            windowChrome
            brandRow

            VStack(alignment: .leading, spacing: 3) {
                SidebarSectionRow(section: .dashboard, selection: $selection)
                SidebarSectionRow(section: .map, selection: $selection)
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

    // The user row is a Menu — the single settings surface for the whole
    // shell. Right now it hosts the demo/live toggle; future account /
    // preferences items can slot in here without adding new chrome.
    private var userMenu: some View {
        Menu {
            Section("Data source") {
                ForEach(DataMode.allCases) { value in
                    Button {
                        onModeChange(value)
                    } label: {
                        // Show a checkmark on the current mode, but only when
                        // we're NOT in fallback (fallback means the user chose
                        // live but is temporarily on demo).
                        if value == dataMode && !isFallback {
                            Label(value.title, systemImage: "checkmark")
                        } else {
                            Text(value.title)
                        }
                    }
                }
            }
            if isFallback {
                Section {
                    Text("Live backend unreachable — showing demo data.")
                }
            }
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(AdaColors.navy)
                    .frame(width: 28, height: 28)
                    .overlay { Text("B").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white) }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bli Wayan").font(.system(size: 12, weight: .medium)).foregroundStyle(AdaColors.ink)
                    Text(isFallback ? "Demo fallback" : dataModeLabel)
                        .font(.system(size: 10))
                        .foregroundStyle(isFallback ? AdaColors.orange : AdaColors.tertiaryInk)
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(AdaColors.tertiaryInk)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .accessibilityLabel("Bli Wayan, field researcher, \(dataModeLabel)")
        .help("Account and data source")
    }

    private var dataModeLabel: String {
        dataMode == .live ? "Field researcher · Live" : "Field researcher · Demo"
    }
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
