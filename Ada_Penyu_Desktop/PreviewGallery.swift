#if DEBUG
import SwiftUI

#Preview("Sign in") { AccountLoginView(store: AppStore()) }
#Preview("Empty dashboard") {
    DashboardView(snapshot: DashboardSnapshot(months: [], species: []), turtles: [], recentSightings: [], chartMode: .constant(.sightings), chartSpecies: .constant(nil), onExport: {}, onSelect: { _ in })
}
#Preview("Empty map") {
    MapPageView(turtles: [], sightings: [], selectedPeriod: .constant(.thirtyDays), selectedSpecies: .constant(nil), selectedCondition: .constant(nil), onReload: {}, onSelect: { _ in })
}
#Preview("Empty individuals") {
    IndividualsView(turtles: [], total: 0, searchText: .constant(""), selectedCondition: .constant(nil), favoriteIDs: [], onToggleFavorite: { _ in }, onSelect: { _ in })
}
#Preview("Empty favorites") {
    FavoritesView(turtles: [], searchText: .constant(""), selectedCondition: .constant(nil), favoriteIDs: [], onToggleFavorite: { _ in }, onSelect: { _ in }, onBrowseIndividuals: {})
}
#endif
