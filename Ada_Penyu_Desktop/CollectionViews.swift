import SwiftUI

struct IndividualsView: View {
    @Binding var searchText: String
    @Binding var favoriteIDs: Set<String>
    let onToggleFavorite: (Turtle) -> Void
    let onSelect: (Turtle) -> Void
    @State private var selectedSpecies: TurtleSpecies?
    @State private var selectedCondition: TurtleCondition?

    private var filteredTurtles: [Turtle] {
        DemoData.turtles.filter { turtle in
            let matchesSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || turtle.id.localizedCaseInsensitiveContains(searchText)
                || turtle.species.rawValue.localizedCaseInsensitiveContains(searchText)
                || turtle.location.localizedCaseInsensitiveContains(searchText)
            let matchesSpecies = selectedSpecies == nil || turtle.species == selectedSpecies
            let matchesCondition = selectedCondition == nil || turtle.condition == selectedCondition
            return matchesSearch && matchesSpecies && matchesCondition
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                TurtleFilterBar(selectedSpecies: $selectedSpecies, selectedCondition: $selectedCondition)
                HStack {
                    Spacer()
                    Text("\(filteredTurtles.count) individuals")
                        .font(.system(size: 11))
                        .foregroundStyle(AdaColors.tertiaryInk)
                }
                TurtleTableView(
                    turtles: filteredTurtles,
                    favoriteIDs: favoriteIDs,
                    onToggleFavorite: onToggleFavorite,
                    onSelect: onSelect
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(22)
        }
        .scrollIndicators(.hidden)
    }
}

struct FavoritesView: View {
    @Binding var searchText: String
    @Binding var favoriteIDs: Set<String>
    let onToggleFavorite: (Turtle) -> Void
    let onSelect: (Turtle) -> Void
    @State private var selectedCondition: TurtleCondition?

    private var favoriteTurtles: [Turtle] {
        DemoData.turtles.filter { turtle in
            let matchesSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || turtle.id.localizedCaseInsensitiveContains(searchText)
                || turtle.location.localizedCaseInsensitiveContains(searchText)
            let matchesCondition = selectedCondition == nil || turtle.condition == selectedCondition
            return favoriteIDs.contains(turtle.id) && matchesSearch && matchesCondition
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Text("Favorites")
                        .font(.system(size: 12))
                        .foregroundStyle(AdaColors.tertiaryInk)
                    Text("\(favoriteIDs.count) of \(DemoData.turtles.count)")
                        .font(.system(size: 12))
                        .foregroundStyle(AdaColors.secondaryInk)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        Text("Condition")
                            .font(.system(size: 11))
                            .foregroundStyle(AdaColors.tertiaryInk)
                        FilterChip(title: "All", isSelected: selectedCondition == nil) { selectedCondition = nil }
                        FilterChip(title: "Healthy", isSelected: selectedCondition == .healthy) { selectedCondition = .healthy }
                        FilterChip(title: "Scarred", isSelected: selectedCondition == .scarred) { selectedCondition = .scarred }
                        FilterChip(title: "Injured", isSelected: selectedCondition == .injured) { selectedCondition = .injured }
                    }
                }

                HStack {
                    Spacer()
                    Text("\(favoriteTurtles.count) individuals")
                        .font(.system(size: 11))
                        .foregroundStyle(AdaColors.tertiaryInk)
                }
                TurtleTableView(
                    turtles: favoriteTurtles,
                    favoriteIDs: favoriteIDs,
                    onToggleFavorite: onToggleFavorite,
                    onSelect: onSelect
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(22)
        }
        .scrollIndicators(.hidden)
    }
}

private struct TurtleFilterBar: View {
    @Binding var selectedSpecies: TurtleSpecies?
    @Binding var selectedCondition: TurtleCondition?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterChip(title: "All", isSelected: selectedSpecies == nil) { selectedSpecies = nil }
                    ForEach(TurtleSpecies.allCases) { species in
                        FilterChip(title: species.rawValue, isSelected: selectedSpecies == species) {
                            selectedSpecies = species
                        }
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Text("Condition")
                        .font(.system(size: 11))
                        .foregroundStyle(AdaColors.tertiaryInk)
                        .padding(.trailing, 4)
                    FilterChip(title: "All", isSelected: selectedCondition == nil) { selectedCondition = nil }
                    ForEach(TurtleCondition.allCases) { condition in
                        FilterChip(title: condition.rawValue, isSelected: selectedCondition == condition) {
                            selectedCondition = condition
                        }
                    }
                }
            }
        }
    }
}

private struct TurtleTableView: View {
    let turtles: [Turtle]
    let favoriteIDs: Set<String>
    let onToggleFavorite: (Turtle) -> Void
    let onSelect: (Turtle) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            tableContent
                .frame(minWidth: AdaLayout.tableMinimumWidth)
        }
        .background(AdaColors.card)
        .clipShape(RoundedRectangle(cornerRadius: AdaLayout.cardRadius, style: .continuous))
    }

    private var tableContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Individual").frame(maxWidth: .infinity, alignment: .leading)
                Text("Species").frame(width: AdaLayout.tableSpeciesWidth, alignment: .leading)
                Text("Location").frame(width: AdaLayout.tableLocationWidth, alignment: .leading)
                Text("Last seen ↓").frame(width: AdaLayout.tableLastSeenWidth, alignment: .leading)
                Text("Sightings").frame(width: AdaLayout.tableSightingsWidth, alignment: .trailing)
                Text("Condition").frame(width: AdaLayout.tableConditionWidth, alignment: .leading)
                Text("").frame(width: AdaLayout.tableActionWidth)
            }
            .font(.system(size: 11))
            .foregroundStyle(AdaColors.tertiaryInk)
            .padding(.horizontal, 18)
            .frame(height: 38)

            Divider().overlay(AdaColors.line)

            if turtles.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tortoise")
                        .font(.system(size: 24))
                        .foregroundStyle(AdaColors.tertiaryInk)
                    Text("No individuals match these filters")
                        .font(.system(size: 13))
                        .foregroundStyle(AdaColors.secondaryInk)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 180)
            } else {
                ForEach(turtles) { turtle in
                    TurtleTableRow(
                        turtle: turtle,
                        isFavorite: favoriteIDs.contains(turtle.id),
                        onToggleFavorite: { onToggleFavorite(turtle) },
                        onSelect: onSelect
                    )
                    if turtle.id != turtles.last?.id {
                        Divider().overlay(AdaColors.line).padding(.leading, 18)
                    }
                }
            }
        }
        .background(AdaColors.card)
    }
}

private struct TurtleTableRow: View {
    let turtle: Turtle
    let isFavorite: Bool
    let onToggleFavorite: () -> Void
    let onSelect: (Turtle) -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                FavoriteButton(isFavorite: isFavorite, action: onToggleFavorite)
                    .padding(.trailing, 3)
                PlaceholderImage(size: 30)
                PlaceholderImage(size: 30)
                Text(turtle.id)
                    .font(.system(size: 13))
                    .foregroundStyle(AdaColors.ink)
                    .padding(.leading, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(turtle.species.rawValue)
                .font(.system(size: 12))
                .foregroundStyle(AdaColors.secondaryInk)
                .frame(width: AdaLayout.tableSpeciesWidth, alignment: .leading)
            Text(turtle.location)
                .font(.system(size: 12))
                .foregroundStyle(AdaColors.secondaryInk)
                .frame(width: AdaLayout.tableLocationWidth, alignment: .leading)
            Text(turtle.lastSeen)
                .font(.system(size: 12))
                .foregroundStyle(AdaColors.secondaryInk)
                .frame(width: AdaLayout.tableLastSeenWidth, alignment: .leading)
            Text("\(turtle.sightings)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AdaColors.ink)
                .frame(width: AdaLayout.tableSightingsWidth, alignment: .trailing)
            ConditionPill(condition: turtle.condition)
                .frame(width: AdaLayout.tableConditionWidth, alignment: .leading)
            Image(systemName: "arrow.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AdaColors.tertiaryInk)
                .frame(width: AdaLayout.tableActionWidth, height: 28)
                .background(Color.black.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(.horizontal, 18)
        .frame(height: 50)
        .contentShape(Rectangle())
        .onTapGesture { onSelect(turtle) }
    }
}
