import SwiftUI

struct IndividualsView: View {
    let turtles: [Turtle]
    let total: Int
    @Binding var searchText: String
    @Binding var selectedCondition: TurtleCondition?
    let favoriteIDs: Set<String>
    let onToggleFavorite: (Turtle) -> Void
    let onSelect: (Turtle) -> Void
    var selectedSpecies: Binding<TurtleSpecies?> = .constant(nil)
    var pageSize: Binding<Int> = .constant(10)
    var offset = 0
    var isLoading = false
    var onPage: (Int) -> Void = { _ in }
    var sort: Binding<IndividualSort> = .constant(.lastSeenDescending)
    var savedTurtles: [Turtle] = []

    @State private var showSavedOnly = false

    private var currentPage: Int { offset / max(1, pageSize.wrappedValue) }
    private var pageCount: Int { max(1, Int(ceil(Double(total) / Double(max(1, pageSize.wrappedValue))))) }

    private var hasActiveFilters: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || selectedSpecies.wrappedValue != nil
            || selectedCondition != nil
            || showSavedOnly
    }

    private var displayedTurtles: [Turtle] {
        guard showSavedOnly else { return turtles }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let pool = !savedTurtles.isEmpty
            ? savedTurtles.filter { favoriteIDs.contains($0.id) }
            : turtles.filter { favoriteIDs.contains($0.id) }
        let filtered = pool.filter { turtle in
            let matchesSearch = query.isEmpty
                || turtle.displayName.localizedCaseInsensitiveContains(query)
                || turtle.id.localizedCaseInsensitiveContains(query)
                || (turtle.profileCode?.localizedCaseInsensitiveContains(query) ?? false)
                || turtle.location.localizedCaseInsensitiveContains(query)
            let matchesSpecies = selectedSpecies.wrappedValue == nil || selectedSpecies.wrappedValue == turtle.species
            let matchesCondition = selectedCondition == nil || selectedCondition == turtle.condition
            return matchesSearch && matchesSpecies && matchesCondition
        }
        switch sort.wrappedValue {
        case .name:
            return filtered.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        case .lastSeenDescending:
            return filtered
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                TurtleCatalogFilterBar(
                    searchPlaceholder: showSavedOnly ? "Search saved sea turtles" : "Search name, code, or Turtle ID",
                    searchText: $searchText,
                    selectedSpecies: selectedSpecies,
                    selectedCondition: $selectedCondition,
                    sort: sort,
                    showSavedOnly: $showSavedOnly,
                    savedCount: favoriteIDs.count,
                    hasActiveFilters: hasActiveFilters,
                    onClearFilters: {
                        searchText = ""
                        selectedSpecies.wrappedValue = nil
                        selectedCondition = nil
                        showSavedOnly = false
                    }
                )

                Text(countSummary)
                    .font(.system(size: 12.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(AdaColors.secondaryInk)

                VStack(spacing: 0) {
                    TurtleTableView(
                        turtles: displayedTurtles,
                        favoriteIDs: favoriteIDs,
                        emptyTitle: showSavedOnly
                            ? (favoriteIDs.isEmpty ? "No saved sea turtles" : "No matching saved turtles")
                            : "No sea turtles found",
                        emptySymbol: showSavedOnly ? "bookmark" : "tortoise",
                        emptyDescription: showSavedOnly && favoriteIDs.isEmpty
                            ? "Bookmark a sea turtle to keep it in your saved list."
                            : "Try another search term or clear an active filter.",
                        onToggleFavorite: onToggleFavorite,
                        onSelect: onSelect
                    )
                    if !showSavedOnly {
                        Divider()
                            .overlay(AdaColors.line)
                            .padding(.horizontal, 20)
                        pagination
                            .padding(.horizontal, 20)
                            .padding(.vertical, 14)
                            .disabled(isLoading)
                    }
                }
                .background(AdaColors.card, in: RoundedRectangle(cornerRadius: AdaLayout.cardRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AdaLayout.cardRadius, style: .continuous)
                        .stroke(AdaColors.line, lineWidth: 1)
                )
            }
            .padding(.horizontal, AdaLayout.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
    }

    private var countSummary: String {
        if showSavedOnly {
            let count = displayedTurtles.count
            return "\(count.formatted()) \(count == 1 ? "saved individual" : "saved individuals")"
        }
        if total == 0 { return "0 individuals" }
        if turtles.count < total {
            let start = offset + 1
            let end = min(offset + turtles.count, total)
            return "Showing \(start)–\(end) of \(total.formatted()) individuals"
        }
        return "\(total.formatted()) \(total == 1 ? "individual" : "individuals")"
    }

    private var pagination: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Text("Rows")
                    .font(.system(size: 11.5))
                    .foregroundStyle(AdaColors.secondaryInk)
                ActionDropdown(
                    items: [10, 25, 50].map { size in
                        DropdownAction(
                            title: "\(size) per page",
                            selected: pageSize.wrappedValue == size,
                            action: { pageSize.wrappedValue = size }
                        )
                    },
                    placement: .aboveLeading,
                    minWidth: 140
                ) {
                    HStack(spacing: 6) {
                        Text("\(pageSize.wrappedValue)")
                            .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(AdaColors.secondaryInk)
                    }
                    .foregroundStyle(AdaColors.ink)
                    .padding(.horizontal, 11)
                    .frame(height: 28)
                    .background(AdaColors.surfaceMuted, in: Capsule())
                    .overlay(Capsule().stroke(AdaColors.line, lineWidth: 1))
                }
                .accessibilityLabel("Rows per page")
                .accessibilityValue("\(pageSize.wrappedValue)")
            }

            Text(total == 0 ? "0 of 0" : "\(offset + 1)–\(min(offset + turtles.count, total)) of \(total.formatted())")
                .font(.system(size: 11.5).monospacedDigit())
                .foregroundStyle(AdaColors.secondaryInk)

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                pageArrowButton("chevron.left", label: "Previous page", disabled: currentPage == 0) {
                    onPage(currentPage - 1)
                }

                let pageRange: [Int] = Array(max(0, currentPage - 2)..<min(pageCount, currentPage + 3))
                ForEach(pageRange, id: \.self) { page in
                    let isSelected = currentPage == page
                    let pageNumber = page + 1
                    let pageLabel = "Page \(pageNumber)"
                    Button { onPage(page) } label: {
                        Text("\(pageNumber)")
                            .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium).monospacedDigit())
                            .frame(minWidth: 28, minHeight: 28)
                            .padding(.horizontal, 4)
                            .foregroundStyle(isSelected ? Color.white : AdaColors.ink)
                            .background(isSelected ? AdaColors.navy : Color.clear, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(pageLabel)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }

                pageArrowButton("chevron.right", label: "Next page", disabled: currentPage >= pageCount - 1) {
                    onPage(currentPage + 1)
                }
            }
        }
    }

    private func pageArrowButton(_ symbol: String, label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(disabled ? AdaColors.secondaryInk.opacity(0.35) : AdaColors.ink)
                .frame(width: 28, height: 28)
                .background(AdaColors.surfaceMuted.opacity(disabled ? 0.5 : 1), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(label)
    }
}

struct FavoritesView: View {
    let turtles: [Turtle]
    @Binding var searchText: String
    @Binding var selectedCondition: TurtleCondition?
    let favoriteIDs: Set<String>
    let onToggleFavorite: (Turtle) -> Void
    let onSelect: (Turtle) -> Void
    let onBrowseIndividuals: () -> Void
    var selectedSpecies: Binding<TurtleSpecies?> = .constant(nil)

    private var hasActiveFilters: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || selectedSpecies.wrappedValue != nil
            || selectedCondition != nil
    }

    var filtered: [Turtle] {
        turtles.filter { turtle in
            let matchesSearch = searchText.isEmpty
                || turtle.displayName.localizedCaseInsensitiveContains(searchText)
                || turtle.id.localizedCaseInsensitiveContains(searchText)
                || (turtle.profileCode?.localizedCaseInsensitiveContains(searchText) ?? false)
                || turtle.location.localizedCaseInsensitiveContains(searchText)
            let matchesSpecies = selectedSpecies.wrappedValue == nil || selectedSpecies.wrappedValue == turtle.species
            let matchesCondition = selectedCondition == nil || selectedCondition == turtle.condition
            return matchesSearch && matchesSpecies && matchesCondition
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                TurtleCatalogFilterBar(
                    searchPlaceholder: "Search saved sea turtles",
                    searchText: $searchText,
                    selectedSpecies: selectedSpecies,
                    selectedCondition: $selectedCondition,
                    sort: nil,
                    hasActiveFilters: hasActiveFilters,
                    onClearFilters: {
                        searchText = ""
                        selectedSpecies.wrappedValue = nil
                        selectedCondition = nil
                    }
                )

                Text("\(filtered.count.formatted()) \(filtered.count == 1 ? "saved individual" : "saved individuals")")
                    .font(.system(size: 12.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(AdaColors.secondaryInk)

                if turtles.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "bookmark")
                            .font(.system(size: 26, weight: .regular))
                            .foregroundStyle(AdaColors.navy.opacity(0.65))
                            .frame(width: 54, height: 54)
                            .background(AdaColors.surfaceMuted, in: Circle())

                        VStack(spacing: 5) {
                            Text("No saved sea turtles")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(AdaColors.ink)
                            Text("Bookmark a sea turtle from Sea Turtles or its profile to keep it here for quick follow-up.")
                                .font(.system(size: 12.5))
                                .foregroundStyle(AdaColors.secondaryInk)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 420)
                        }

                        Button("Browse Sea Turtles", action: onBrowseIndividuals)
                            .buttonStyle(AdaPillButtonStyle())
                            .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, minHeight: 280)
                    .padding(28)
                    .background(AdaColors.card, in: RoundedRectangle(cornerRadius: AdaLayout.cardRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AdaLayout.cardRadius, style: .continuous)
                            .stroke(AdaColors.line, lineWidth: 1)
                    )
                } else {
                    TurtleTableView(
                        turtles: filtered,
                        favoriteIDs: favoriteIDs,
                        emptyTitle: "No matching saved turtles",
                        emptySymbol: "bookmark",
                        emptyDescription: "Try another search term or clear an active filter.",
                        onToggleFavorite: onToggleFavorite,
                        onSelect: onSelect
                    )
                    .background(AdaColors.card, in: RoundedRectangle(cornerRadius: AdaLayout.cardRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AdaLayout.cardRadius, style: .continuous)
                            .stroke(AdaColors.line, lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal, AdaLayout.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
    }
}

private struct TurtleCatalogFilterBar: View {
    let searchPlaceholder: String
    @Binding var searchText: String
    var selectedSpecies: Binding<TurtleSpecies?>
    @Binding var selectedCondition: TurtleCondition?
    var sort: Binding<IndividualSort>?
    var showSavedOnly: Binding<Bool>? = nil
    var savedCount: Int = 0
    let hasActiveFilters: Bool
    let onClearFilters: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                searchField
                filterPills
            }
            VStack(alignment: .leading, spacing: 10) {
                searchField
                HStack(spacing: 10) {
                    filterPills
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AdaColors.secondaryInk)
            TextField(searchPlaceholder, text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundStyle(AdaColors.ink)
                .accessibilityLabel("Search sea turtles")
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(AdaColors.secondaryInk.opacity(0.7))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(minWidth: 240, maxWidth: .infinity, minHeight: 36, maxHeight: 36)
        .background(AdaColors.card, in: Capsule())
        .overlay(Capsule().stroke(AdaColors.line, lineWidth: 1))
    }

    private var filterPills: some View {
        HStack(spacing: 8) {
            if let showSavedOnly {
                savedTogglePill(isSelected: showSavedOnly)
            }
            SpeciesPicker(selection: selectedSpecies)
            ConditionPicker(selection: $selectedCondition)
            if let sort {
                ActionDropdown(
                    items: IndividualSort.allCases.map { option in
                        DropdownAction(
                            title: option == .lastSeenDescending ? "Last seen · newest" : "Name · A–Z",
                            selected: sort.wrappedValue == option,
                            action: { sort.wrappedValue = option }
                        )
                    },
                    header: "Sort by",
                    minWidth: 186
                ) {
                    ContextPill(
                        title: sort.wrappedValue.title,
                        icon: "arrow.up.arrow.down",
                        chevron: true,
                        isActive: sort.wrappedValue != .lastSeenDescending
                    )
                }
                .fixedSize()
                .accessibilityLabel("Sort individuals")
                .accessibilityValue(sort.wrappedValue.title)
            }
            if hasActiveFilters {
                Button(action: onClearFilters) {
                    HStack(spacing: 5) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9.5, weight: .semibold))
                        Text("Clear")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(AdaColors.secondaryInk)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(AdaColors.surfaceMuted, in: Capsule())
                    .overlay(Capsule().stroke(AdaColors.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear all filters")
            }
        }
        .fixedSize()
    }

    private func savedTogglePill(isSelected: Binding<Bool>) -> some View {
        let active = isSelected.wrappedValue
        return Button {
            withAnimation(.easeOut(duration: 0.14)) {
                isSelected.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: active ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 11, weight: active ? .semibold : .medium))
                Text("Saved")
                    .font(.system(size: 12, weight: active ? .semibold : .regular))
                    .lineLimit(1)
                if savedCount > 0 {
                    Text(savedCount.formatted())
                        .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(active ? .white.opacity(0.92) : AdaColors.navy)
                        .padding(.horizontal, 6.5)
                        .frame(height: 18)
                        .background(active ? .white.opacity(0.2) : AdaColors.navy.opacity(0.09), in: Capsule())
                }
            }
            .foregroundStyle(active ? .white : AdaColors.ink)
            .padding(.horizontal, 13)
            .frame(height: 36)
            .background(active ? AdaColors.navy : AdaColors.card, in: Capsule())
            .overlay(Capsule().stroke(active ? AdaColors.navy : AdaColors.line, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel(savedCount > 0 ? "Saved, \(savedCount)" : "Saved")
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

private struct TurtleTableView: View {
    let turtles: [Turtle]
    let favoriteIDs: Set<String>
    var emptyTitle: String = "No sea turtles to show"
    var emptySymbol: String = "tortoise"
    var emptyDescription: String = "Try another search or clear a filter."
    let onToggleFavorite: (Turtle) -> Void
    let onSelect: (Turtle) -> Void

    private static let headerHeight: CGFloat = 44
    private static let rowHeight: CGFloat = 74
    private static let minWidth: CGFloat = 920

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal) {
                VStack(spacing: 0) {
                    HStack(spacing: 16) {
                        Text("Individual")
                            .frame(minWidth: 230, maxWidth: .infinity, alignment: .leading)
                        Text("Species")
                            .frame(width: 140, alignment: .leading)
                        Text("Latest location")
                            .frame(minWidth: 160, maxWidth: 210, alignment: .leading)
                        Text("Last seen")
                            .frame(width: 155, alignment: .leading)
                        Text("Sightings")
                            .frame(width: 72, alignment: .trailing)
                        Text("Condition")
                            .frame(width: 108, alignment: .leading)
                        Color.clear
                            .frame(width: 58, height: 1)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AdaColors.secondaryInk)
                    .padding(.horizontal, 20)
                    .frame(height: Self.headerHeight)

                    Divider()
                        .overlay(AdaColors.line)

                    if turtles.isEmpty {
                        ContentUnavailableView(
                            emptyTitle,
                            systemImage: emptySymbol,
                            description: Text(emptyDescription)
                        )
                        .frame(maxWidth: .infinity, minHeight: 220)
                    } else {
                        ForEach(turtles) { turtle in
                            TurtleTableRow(
                                turtle: turtle,
                                isFavorite: favoriteIDs.contains(turtle.id),
                                rowHeight: Self.rowHeight,
                                onToggleFavorite: { onToggleFavorite(turtle) },
                                onSelect: { onSelect(turtle) }
                            )
                            if turtle.id != turtles.last?.id {
                                Divider()
                                    .overlay(AdaColors.line.opacity(0.8))
                                    .padding(.horizontal, 20)
                            }
                        }
                    }
                }
                .frame(width: max(proxy.size.width, Self.minWidth))
            }
            .scrollIndicators(.hidden)
        }
        .frame(height: turtles.isEmpty ? Self.headerHeight + 221 : Self.headerHeight + 1 + CGFloat(turtles.count) * (Self.rowHeight + 1))
    }
}

private struct TurtleTableRow: View {
    let turtle: Turtle
    let isFavorite: Bool
    let rowHeight: CGFloat
    let onToggleFavorite: () -> Void
    let onSelect: () -> Void
    @State private var isHovered = false

    private func recordedValue(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.caseInsensitiveCompare("Not recorded") != .orderedSame else {
            return nil
        }
        return trimmed
    }

    var body: some View {
        let recordedLocation = recordedValue(turtle.location)
        let recordedLastSeen = recordedValue(turtle.lastSeen)
        let recordedFirst = recordedValue(turtle.firstRecorded)

        HStack(spacing: 16) {
            Button(action: onSelect) {
                HStack(spacing: 16) {
                    HStack(spacing: 12) {
                        IdentityPhotoPair(turtle: turtle, size: 42)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(turtle.displayName)
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(AdaColors.ink)
                                .lineLimit(1)
                            Text(turtle.profileCode ?? turtle.id)
                                .font(.system(size: 11).monospacedDigit())
                                .foregroundStyle(AdaColors.secondaryInk)
                                .lineLimit(1)
                        }
                    }
                    .frame(minWidth: 230, maxWidth: .infinity, alignment: .leading)

                    SpeciesLabel(species: turtle.species)
                        .font(.system(size: 12.5))
                        .frame(width: 140, alignment: .leading)

                    Group {
                        if let recordedLocation {
                            Text(recordedLocation)
                                .font(.system(size: 12.5))
                                .foregroundStyle(AdaColors.ink)
                                .lineLimit(2)
                        } else {
                            Text("—")
                                .font(.system(size: 12.5))
                                .foregroundStyle(AdaColors.secondaryInk.opacity(0.45))
                        }
                    }
                    .frame(minWidth: 160, maxWidth: 210, alignment: .leading)

                    VStack(alignment: .leading, spacing: 3) {
                        if let recordedLastSeen {
                            Text(recordedLastSeen)
                                .font(.system(size: 12.5).monospacedDigit())
                                .foregroundStyle(AdaColors.ink)
                                .lineLimit(1)
                            if let recordedFirst, recordedFirst != recordedLastSeen {
                                Text("First \(recordedFirst)")
                                    .font(.system(size: 11).monospacedDigit())
                                    .foregroundStyle(AdaColors.secondaryInk)
                                    .lineLimit(1)
                            }
                        } else {
                            Text("—")
                                .font(.system(size: 12.5))
                                .foregroundStyle(AdaColors.secondaryInk.opacity(0.45))
                            if let recordedFirst {
                                Text("Added \(recordedFirst)")
                                    .font(.system(size: 11).monospacedDigit())
                                    .foregroundStyle(AdaColors.secondaryInk)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .frame(width: 155, alignment: .leading)

                    Group {
                        if turtle.sightings > 0 {
                            Text(turtle.sightings.formatted())
                                .font(.system(size: 13.5, weight: .semibold).monospacedDigit())
                                .foregroundStyle(AdaColors.ink)
                        } else {
                            Text("—")
                                .font(.system(size: 12.5))
                                .foregroundStyle(AdaColors.secondaryInk.opacity(0.45))
                        }
                    }
                    .frame(width: 72, alignment: .trailing)

                    Group {
                        if turtle.condition == .unknown {
                            Text("—")
                                .font(.system(size: 12.5))
                                .foregroundStyle(AdaColors.secondaryInk.opacity(0.45))
                        } else {
                            ConditionPill(condition: turtle.condition)
                        }
                    }
                    .frame(width: 108, alignment: .leading)
                }
                .frame(maxWidth: .infinity, minHeight: rowHeight, maxHeight: rowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(turtle.displayName), \(turtle.species.rawValue)")

            HStack(spacing: 8) {
                FavoriteButton(isFavorite: isFavorite, isVisible: isHovered, action: onToggleFavorite)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(AdaColors.secondaryInk.opacity(isHovered ? 0.85 : 0.35))
                    .offset(x: isHovered ? 2 : 0)
                    .allowsHitTesting(false)
            }
            .frame(width: 58, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .frame(height: rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isHovered ? AdaColors.surfaceMuted.opacity(0.9) : .clear)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
        )
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

struct IdentityPhotoPair: View {
    let turtle: Turtle
    var size: CGFloat = 84

    var body: some View {
        HStack(spacing: size < 60 ? 5 : 6) {
            photo(turtle.leftPhotoURL, label: "Left")
            photo(turtle.rightPhotoURL, label: "Right")
        }
    }

    private func photo(_ path: String?, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TurtlePhoto(paths: path.map { [$0] } ?? [], size: size)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
                )
            if size >= 60 {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AdaColors.secondaryInk)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) identity photo")
    }
}

struct SightingsListView: View {
    let sightings: [Sighting]
    let onSelect: (Sighting) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionTitle("Recorded sightings", subtitle: "\(sightings.count) loaded records · current map filters")
                if sightings.isEmpty {
                    ContentUnavailableView("No sightings in this range", systemImage: "binoculars", description: Text("Change the time window or species filter."))
                } else {
                    ForEach(sightings) { sighting in
                        Button { onSelect(sighting) } label: {
                            HStack(spacing: 20) {
                                Text(sighting.displayName).font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity, alignment: .leading)
                                SpeciesLabel(species: sighting.species).font(.system(size: 12)).frame(width: 150, alignment: .leading)
                                Text(sighting.date).font(.system(size: 12)).frame(width: 115, alignment: .leading)
                                Text(sighting.location).font(.system(size: 12)).frame(width: 150, alignment: .leading)
                                Image(systemName: "arrow.right")
                            }.contentShape(Rectangle()).adaCard(padding: 22)
                        }.buttonStyle(.plain)
                    }
                }
            }.padding(AdaLayout.pagePadding)
        }
    }
}
