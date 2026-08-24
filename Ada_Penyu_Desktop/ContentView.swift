import SwiftUI

struct ContentView: View {
    @State private var activeSection: AppSection = .dashboard
    @State private var selectedTurtle: Turtle?
    @State private var searchText = ""
    @State private var chartMode = "Sightings"
    @State private var showingExportAlert = false
    @State private var favoriteIDs = Set(DemoData.turtles.filter { $0.isFavorite }.map { $0.id })

    var body: some View {
        GeometryReader { _ in
            HStack(spacing: 0) {
                SidebarView(selection: $activeSection, favoriteCount: favoriteIDs.count)

                VStack(spacing: 0) {
                    TopBar(
                        title: pageTitle,
                        subtitle: pageSubtitle,
                        searchText: $searchText,
                        onExport: { showingExportAlert = true },
                        onBack: backAction
                    )

                    ZStack {
                        AdaColors.canvas
                        pageView
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AdaColors.canvas)
        .alert("Export ready", isPresented: $showingExportAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The demo report is ready to export when a data source is connected.")
        }
    }

    private var pageTitle: String {
        activeSection == .detail ? (selectedTurtle?.id ?? "Turtle #001") : activeSection.title
    }

    private var pageSubtitle: String? {
        if activeSection == .detail { return selectedTurtle?.species.rawValue }
        if activeSection == .map { return "last seen 30 days" }
        return nil
    }

    private var backAction: (() -> Void)? {
        activeSection == .detail ? { returnToIndividuals() } : nil
    }

    @ViewBuilder
    private var pageView: some View {
        switch activeSection {
        case .dashboard:
            DashboardView(chartMode: $chartMode)
        case .map:
            MapPageView(onSelect: showDetail)
        case .individuals:
            IndividualsView(
                searchText: $searchText,
                favoriteIDs: $favoriteIDs,
                onToggleFavorite: toggleFavorite,
                onSelect: showDetail
            )
        case .favorites:
            FavoritesView(
                searchText: $searchText,
                favoriteIDs: $favoriteIDs,
                onToggleFavorite: toggleFavorite,
                onSelect: showDetail
            )
        case .detail:
            TurtleDetailView(
                turtle: selectedTurtle ?? DemoData.turtles[0],
                onBack: returnToIndividuals
            )
        }
    }

    private func showDetail(_ turtle: Turtle) {
        selectedTurtle = turtle
        activeSection = .detail
    }

    private func toggleFavorite(_ turtle: Turtle) {
        if favoriteIDs.contains(turtle.id) {
            favoriteIDs.remove(turtle.id)
        } else {
            favoriteIDs.insert(turtle.id)
        }
    }

    private func returnToIndividuals() {
        selectedTurtle = nil
        activeSection = .individuals
    }
}
