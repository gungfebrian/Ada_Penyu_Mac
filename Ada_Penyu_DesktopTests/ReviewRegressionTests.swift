import XCTest
import SwiftUI
@testable import Ada_Penyu_Desktop

@MainActor
final class ReviewRegressionTests: XCTestCase {
    private func encounter(condition: String) throws -> V2Sighting {
        let data = APIFixtures.data("""
        {"id":"10000000-0000-4000-8000-000000000004","observed_at":"2026-02-01T00:00:00Z",
        "event":{"type":"sighting"},"location":{"name":"Reef","coordinates":null},"notes":null,"measurements":null,
        "condition":{"status":\(condition),"notes":null,"markings":[
        {"id":"10000000-0000-4000-8000-000000000005","region":"head","kind":"wound","severity":"minor","notes":"Observed wound"},
        {"id":"10000000-0000-4000-8000-000000000006","region":"tail","kind":"tag_scar","severity":"minor","notes":null}]}}
        """)
        return try JSONDecoder.api.decode(V2Sighting.self, from: data)
    }

    func testMarkingsRemainVisibleWhenOverallAssessmentIsUnknown() throws {
        let logs = try encounter(condition: "null").logs
        let markings = logs.filter(\.isBodyConditionRecord)
        XCTAssertEqual(markings.count, 2)
        XCTAssertEqual(markings.first?.status, "Wound")
        XCTAssertNil(markings.first?.condition)
    }

    func testOverallAssessmentIsNotCopiedOntoEveryMarking() throws {
        let logs = try encounter(condition: "\"healthy\"").logs
        XCTAssertEqual(logs.first?.condition, .healthy)
        XCTAssertTrue(logs.filter { $0.bodyPart != nil }.allSatisfy { $0.condition == nil })
        XCTAssertEqual(logs.last?.status, "Tag Scar")
    }

    func testTwoMarkingsDoNotTurnOneEncounterIntoThreeSightings() throws {
        let logs = try encounter(condition: "\"injured\"").logs
        let detail = TurtleDetailData(turtle: DemoFixtures.turtles[0], measurements: [], logs: logs)
        XCTAssertEqual(detail.sightingLogs.count, 1)
        XCTAssertEqual(detail.sightingLogs.first?.location, "Reef")
    }

    func testFavoritesSearchUsesDisplayNameWhenIdentityIsUUID() throws {
        let profile = try JSONDecoder.api.decode(V2Profile.self, from: APIFixtures.data(APIFixtures.profile))
        let view = FavoritesView(turtles: [profile.turtle()], searchText: .constant("amina"),
            selectedCondition: .constant(nil), favoriteIDs: [], onToggleFavorite: { _ in },
            onSelect: { _ in }, onBrowseIndividuals: {})
        XCTAssertEqual(view.filtered.count, 1)
        XCTAssertEqual(view.filtered.first?.displayName, "Amina")
    }
}
