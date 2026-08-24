import SwiftUI

private struct PreviewCollectionScreen: View {
    let favorites: Bool
    @State private var searchText = ""
    @State private var favoriteIDs = Set(DemoData.turtles.filter { $0.isFavorite }.map { $0.id })

    var body: some View {
        Group {
            if favorites {
                FavoritesView(
                    searchText: $searchText,
                    favoriteIDs: $favoriteIDs,
                    onToggleFavorite: toggleFavorite,
                    onSelect: { _ in }
                )
            } else {
                IndividualsView(
                    searchText: $searchText,
                    favoriteIDs: $favoriteIDs,
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
    MapPageView(onSelect: { _ in })
        .frame(width: 1_260, height: 750)
}

#Preview("Sea Turtle Group · Individuals") {
    PreviewCollectionScreen(favorites: false)
}

#Preview("Sea Turtle Group · Favorites") {
    PreviewCollectionScreen(favorites: true)
}

#Preview("Sea Turtle Group · Turtle detail") {
    TurtleDetailView(turtle: DemoData.turtles[0], onBack: {})
        .frame(width: 1_260, height: 750)
        .background(AdaColors.canvas)
}
