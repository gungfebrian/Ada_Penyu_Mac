import Foundation
@testable import Ada_Penyu_Desktop

final class TestTurtleRepository: TurtleRepository {
    static var turtle: Turtle { try! JSONDecoder.api.decode(V2Profile.self, from: APIFixtures.data(APIFixtures.profile)).turtle() }
    private var favoriteIDs: Set<String> = []
    func listIndividuals(query: IndividualQuery) async throws -> Page<Turtle> { Page(items: [Self.turtle], total: 1, request: query.page) }
    func listFavorites() async throws -> [Turtle] { favoriteIDs.contains(Self.turtle.id) ? [Self.turtle] : [] }
    func setFavorite(turtleID: String, isFavorite: Bool) async throws -> Bool {
        if isFavorite { favoriteIDs.insert(turtleID) } else { favoriteIDs.remove(turtleID) }
        return isFavorite
    }
    func dashboard(query: DashboardQuery) async throws -> DashboardSnapshot { DashboardSnapshot(months: [], species: []) }
    func mapSightings(query: MapQuery) async throws -> [Sighting] { [] }
    func detail(for turtle: Turtle) async throws -> TurtleDetailData { TurtleDetailData(turtle: turtle, measurements: [], logs: []) }
    func export(_ request: ExportRequest) async throws -> DownloadedFile { throw APIError.invalidResponse }
}
