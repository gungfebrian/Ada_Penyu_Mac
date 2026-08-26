import SwiftUI

struct IndividualsView: View {
    let turtles: [Turtle]
    let total: Int
    @Binding var searchText: String
    @Binding var selectedSpecies: TurtleSpecies?
    @Binding var selectedCondition: TurtleCondition?
    let favoriteIDs: Set<String>
    let onToggleFavorite: (Turtle) -> Void
    let onSelect: (Turtle) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 11) {
                TurtleFilterBar(resultCount: turtles.count, selectedSpecies: $selectedSpecies, selectedCondition: $selectedCondition)
                TurtleTableView(turtles: turtles, favoriteIDs: favoriteIDs, onToggleFavorite: onToggleFavorite, onSelect: onSelect)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 22)
            .padding(.trailing, 32)
            .padding(.top, 24)
            .padding(.bottom, 22)
        }
        .scrollIndicators(.hidden)
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

    private var filtered: [Turtle] {
        turtles.filter { turtle in
            (searchText.isEmpty || turtle.id.localizedCaseInsensitiveContains(searchText) || turtle.location.localizedCaseInsensitiveContains(searchText)) &&
            (selectedCondition == nil || selectedCondition == turtle.condition)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 8) {
                    Text("Condition").font(.system(size: 11)).foregroundStyle(AdaColors.tertiaryInk)
                    FilterChip(title: "All", isSelected: selectedCondition == nil) { selectedCondition = nil }
                    ForEach(TurtleCondition.allCases) { condition in FilterChip(title: condition.rawValue, isSelected: selectedCondition == condition) { selectedCondition = condition } }
                    Spacer()
                    Text("\(filtered.count) favorites").font(.system(size: 11)).foregroundStyle(AdaColors.tertiaryInk)
                }
                TurtleTableView(turtles: filtered, favoriteIDs: favoriteIDs, onToggleFavorite: onToggleFavorite, onSelect: onSelect, emptyAction: onBrowseIndividuals, emptyTitle: "No favorites yet", emptyMessage: "Favorite a turtle to keep it one click away.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 22)
            .padding(.trailing, 32)
            .padding(.top, 24)
            .padding(.bottom, 22)
        }
        .scrollIndicators(.hidden)
    }
}

private struct TurtleFilterBar: View {
    let resultCount: Int
    @Binding var selectedSpecies: TurtleSpecies?
    @Binding var selectedCondition: TurtleCondition?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterChip(title: "All", isSelected: selectedSpecies == nil) { selectedSpecies = nil }
                    ForEach(TurtleSpecies.allCases) { species in
                        FilterChip(title: species.rawValue, isSelected: selectedSpecies == species) { selectedSpecies = species }
                    }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Text("Condition").font(.system(size: 11)).foregroundStyle(AdaColors.tertiaryInk).padding(.trailing, 4)
                    FilterChip(title: "All", isSelected: selectedCondition == nil) { selectedCondition = nil }
                    ForEach(TurtleCondition.allCases) { condition in
                        FilterChip(title: condition.rawValue, isSelected: selectedCondition == condition) { selectedCondition = condition }
                    }
                    Spacer(minLength: 8)
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Text("\(resultCount) individuals")
                .font(.system(size: 11))
                .foregroundStyle(AdaColors.tertiaryInk)
                .frame(height: 28)
        }
    }
}

private struct TurtleTableView: View {
    let turtles: [Turtle]
    let favoriteIDs: Set<String>
    let onToggleFavorite: (Turtle) -> Void
    let onSelect: (Turtle) -> Void
    let emptyAction: (() -> Void)?
    let emptyTitle: String
    let emptyMessage: String

    init(
        turtles: [Turtle],
        favoriteIDs: Set<String>,
        onToggleFavorite: @escaping (Turtle) -> Void,
        onSelect: @escaping (Turtle) -> Void,
        emptyAction: (() -> Void)? = nil,
        emptyTitle: String = "No individuals match these filters",
        emptyMessage: String = "Try clearing a filter or search term."
    ) {
        self.turtles = turtles
        self.favoriteIDs = favoriteIDs
        self.onToggleFavorite = onToggleFavorite
        self.onSelect = onSelect
        self.emptyAction = emptyAction
        self.emptyTitle = emptyTitle
        self.emptyMessage = emptyMessage
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                tableContent
                    .frame(width: max(proxy.size.width, 1_100))
            }
        }
        .frame(height: turtles.isEmpty ? 261 : 41 + CGFloat(turtles.count * 51))
        .background(AdaColors.card)
        .clipShape(RoundedRectangle(cornerRadius: AdaLayout.cardRadius, style: .continuous))
    }

    private var tableContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Individual").frame(maxWidth: .infinity, alignment: .leading)
                Text("Species").frame(width: AdaLayout.tableSpeciesWidth, alignment: .leading)
                Text("Location").frame(width: AdaLayout.tableLocationWidth, alignment: .leading)
                Text("Last seen").frame(width: AdaLayout.tableLastSeenWidth, alignment: .leading)
                Text("Sightings").frame(width: AdaLayout.tableSightingsWidth, alignment: .trailing)
                Text("Condition").frame(width: AdaLayout.tableConditionWidth, alignment: .trailing)
                Text("").frame(width: AdaLayout.tableActionWidth)
            }
            .font(.system(size: 11)).foregroundStyle(AdaColors.tertiaryInk).padding(.horizontal, 18).frame(height: 40)
            Divider().overlay(AdaColors.line)
            if turtles.isEmpty {
                EmptyCollectionState(title: emptyTitle, message: emptyMessage, action: emptyAction).frame(maxWidth: .infinity).frame(height: 220)
            } else {
                ForEach(turtles) { turtle in
                    TurtleTableRow(turtle: turtle, isFavorite: favoriteIDs.contains(turtle.id), onToggleFavorite: { onToggleFavorite(turtle) }, onSelect: { onSelect(turtle) })
                    if turtle.id != turtles.last?.id { Divider().overlay(AdaColors.line).padding(.leading, 18) }
                }
            }
        }
        .background(AdaColors.card)
    }
}

private struct EmptyCollectionState: View {
    let title: String
    let message: String
    let action: (() -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            TurtleBrandMark(size: 42)
                .opacity(0.72)
            Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(AdaColors.ink)
            Text(message).font(.system(size: 11)).foregroundStyle(AdaColors.tertiaryInk)
            if let action {
                Button("Browse individuals", action: action)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AdaColors.brandBlue)
                    .buttonStyle(.plain)
                    .padding(.top, 3)
            }
        }
    }
}

private struct TurtleTableRow: View {
    let turtle: Turtle
    let isFavorite: Bool
    let onToggleFavorite: () -> Void
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                FavoriteButton(isFavorite: isFavorite, action: onToggleFavorite)
                PlaceholderImage(size: 30)
                Text(turtle.id).font(.system(size: 13, weight: .medium)).foregroundStyle(AdaColors.ink).padding(.leading, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(turtle.species.rawValue).font(.system(size: 12)).foregroundStyle(AdaColors.secondaryInk).frame(width: AdaLayout.tableSpeciesWidth, alignment: .leading)
            Text(turtle.location).font(.system(size: 12)).foregroundStyle(AdaColors.secondaryInk).frame(width: AdaLayout.tableLocationWidth, alignment: .leading)
            Text(turtle.lastSeen).font(.system(size: 12)).foregroundStyle(AdaColors.secondaryInk).frame(width: AdaLayout.tableLastSeenWidth, alignment: .leading)
            Text("\(turtle.sightings)").font(.system(size: 12, weight: .medium)).foregroundStyle(AdaColors.ink).frame(width: AdaLayout.tableSightingsWidth, alignment: .trailing)
            ConditionPill(condition: turtle.condition).frame(width: AdaLayout.tableConditionWidth, alignment: .trailing)
            Image(systemName: "arrow.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(AdaColors.tertiaryInk).frame(width: AdaLayout.tableActionWidth, height: 28).background(Color.black.opacity(0.025)).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(.horizontal, 18)
        .frame(height: 51)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Open turtle detail")
    }
}
