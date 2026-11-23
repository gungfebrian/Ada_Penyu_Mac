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

    private var currentPage: Int { offset / max(1, pageSize.wrappedValue) }
    private var pageCount: Int { max(1, Int(ceil(Double(total) / Double(max(1, pageSize.wrappedValue))))) }

    private var hasActiveFilters: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || selectedSpecies.wrappedValue != nil
            || selectedCondition != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                TurtleCatalogFilterBar(
                    searchPlaceholder: "Search name, code, or Turtle ID",
                    searchText: $searchText,
                    selectedSpecies: selectedSpecies,
                    selectedCondition: $selectedCondition,
                    sort: sort,
                    hasActiveFilters: hasActiveFilters,
                    onClearFilters: {
                        searchText = ""
                        selectedSpecies.wrappedValue = nil
                        selectedCondition = nil
                    }
                )

                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(countSummary)
                        .font(.system(size: 12.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(AdaColors.ink)
                    Spacer(minLength: 0)
                    Text("Select an individual to inspect sightings and body condition")
                        .font(.system(size: 11.5))
                        .foregroundStyle(AdaColors.secondaryInk)
                }

                VStack(spacing: 0) {
                    TurtleTableView(
                        turtles: turtles,
                        favoriteIDs: favoriteIDs,
                        emptyTitle: "No sea turtles found",
                        emptySymbol: "tortoise",
                        emptyDescription: "Try another search term or clear an active filter.",
                        onToggleFavorite: onToggleFavorite,
                        onSelect: onSelect
                    )
                    Divider()
                        .overlay(AdaColors.line)
                        .padding(.horizontal, 20)
                    pagination
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .disabled(isLoading)
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
                    searchPlaceholder: "Search tracked individuals",
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

                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(filtered.count.formatted()) \(filtered.count == 1 ? "tracked individual" : "tracked individuals")")
                        .font(.system(size: 12.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(AdaColors.ink)
                    Spacer(minLength: 0)
                    Text("Bookmarked for priority follow-up and encounter monitoring")
                        .font(.system(size: 11.5))
                        .foregroundStyle(AdaColors.secondaryInk)
                }

                if turtles.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "bookmark")
                            .font(.system(size: 26, weight: .regular))
                            .foregroundStyle(AdaColors.navy.opacity(0.65))
                            .frame(width: 54, height: 54)
                            .background(AdaColors.surfaceMuted, in: Circle())

                        VStack(spacing: 5) {
                            Text("No individuals on your watchlist")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(AdaColors.ink)
                            Text("Bookmark a sea turtle from the Individuals table or its profile to track its encounters and body condition here.")
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
                        emptyTitle: "No matching tracked individuals",
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
                        Text("Observation history")
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

    var body: some View {
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

                    Text(turtle.location)
                        .font(.system(size: 12.5))
                        .foregroundStyle(AdaColors.ink)
                        .lineLimit(2)
                        .frame(minWidth: 160, maxWidth: 210, alignment: .leading)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Last: \(turtle.lastSeen)")
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(AdaColors.ink)
                            .lineLimit(1)
                        Text("First: \(turtle.firstRecorded)")
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(AdaColors.secondaryInk)
                            .lineLimit(1)
                    }
                    .frame(width: 155, alignment: .leading)

                    Text(turtle.sightings.formatted())
                        .font(.system(size: 13.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(AdaColors.ink)
                        .frame(width: 72, alignment: .trailing)

                    ConditionPill(condition: turtle.condition)
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
