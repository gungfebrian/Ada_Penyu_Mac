import SwiftUI

private struct PreviewCollectionScreen: View {
    let favorites: Bool
    @State private var searchText = ""
    @State private var selectedSpecies: TurtleSpecies?
    @State private var selectedCondition: TurtleCondition?
    @State private var favoriteIDs = Set(DemoFixtures.turtles.filter { $0.isFavorite }.map { $0.id })

    var body: some View {
        Group {
            if favorites {
                FavoritesView(
                    turtles: DemoFixtures.turtles.filter { favoriteIDs.contains($0.id) },
                    searchText: $searchText,
                    selectedCondition: $selectedCondition,
                    favoriteIDs: favoriteIDs,
                    onToggleFavorite: toggleFavorite,
                    onSelect: { _ in },
                    onBrowseIndividuals: {}
                )
            } else {
                IndividualsView(
                    turtles: DemoFixtures.turtles,
                    total: DemoFixtures.turtles.count,
                    searchText: $searchText,
                    selectedSpecies: $selectedSpecies,
                    selectedCondition: $selectedCondition,
                    favoriteIDs: favoriteIDs,
                    onToggleFavorite: toggleFavorite,
                    onSelect: { _ in }
                )
            }
        }
        .frame(width: 1_260, height: 750)
        .background(AdaColors.canvas)
    }

    private func toggleFavorite(_ turtle: Turtle) {
        if favoriteIDs.contains(turtle.id) {
            favoriteIDs.remove(turtle.id)
        } else {
            favoriteIDs.insert(turtle.id)
        }
    }
}

#Preview("Sea Turtle Group · Dashboard") {
    ContentView()
        .frame(width: 1_512, height: 982)
}

#Preview("Sea Turtle Group · Map") {
    MapPageView(turtles: DemoFixtures.turtles, sightings: DemoFixtures.sightings, selectedPeriod: .constant(.thirtyDays), selectedSpecies: .constant(nil), selectedCondition: .constant(nil), onReload: {}, onSelect: { _ in })
        .frame(width: 1_260, height: 750)
}

#Preview("Sea Turtle Group · Individuals") {
    PreviewCollectionScreen(favorites: false)
}

#Preview("Sea Turtle Group · Favorites") {
    PreviewCollectionScreen(favorites: true)
}

#Preview("Sea Turtle Group · Turtle detail") {
    TurtleDetailView(turtle: DemoFixtures.turtles[0], detail: nil, isFavorite: false, onToggleFavorite: {}, onExport: {})
        .frame(width: 1_260, height: 750)
        .background(AdaColors.canvas)
}
