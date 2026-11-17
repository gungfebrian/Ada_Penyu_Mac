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
        XCTAssertEqual(markings.first?.condition, .injured)
        XCTAssertEqual(markings.last?.condition, .scarred)
        XCTAssertTrue(markings.allSatisfy(\.photoPaths.isEmpty))
    }

    func testOverallAssessmentIsNotCopiedOntoEveryMarking() throws {
        let logs = try encounter(condition: "\"healthy\"").logs
        XCTAssertEqual(logs.first?.condition, .healthy)
        let markings = logs.filter { $0.bodyPart != nil }
        XCTAssertEqual(markings.map(\.condition), [.injured, .scarred])
        XCTAssertFalse(markings.contains { $0.condition == .healthy })
        XCTAssertEqual(logs.last?.status, "Tag Scar")
    }

    func testMarkingPhotosPreferTheirOwnAndFallBackToUntagged() throws {
        let data = APIFixtures.data("""
        {"id":"10000000-0000-4000-8000-000000000004","observed_at":"2026-02-01T00:00:00Z",
        "event":{"type":"sighting"},"location":{"name":"Reef","coordinates":null},"notes":null,"measurements":null,
        "photos":[
          {"url":"https://cdn.example/untagged.jpg","download_url":"https://cdn.example/untagged-full.jpg"},
          {"url":"https://cdn.example/head.jpg","download_url":"https://cdn.example/head-full.jpg","marking_id":"10000000-0000-4000-8000-000000000005"},
          {"url":"   ","download_url":"","marking_id":"10000000-0000-4000-8000-000000000005"}
        ],
        "condition":{"status":"injured","notes":null,"markings":[
        {"id":"10000000-0000-4000-8000-000000000005","region":"head","kind":"wound","severity":"minor","notes":"Observed wound"},
        {"id":"10000000-0000-4000-8000-000000000006","region":"tail","kind":"scratch","severity":"minor","notes":null}]}}
        """)
        let logs = try JSONDecoder.api.decode(V2Sighting.self, from: data).logs
        let head = try XCTUnwrap(logs.first { $0.bodyPart == .head })
        let tail = try XCTUnwrap(logs.first { $0.bodyPart == .tail })
        XCTAssertEqual(head.photoPaths, ["https://cdn.example/head-full.jpg"])
        XCTAssertEqual(head.condition, .injured)
        XCTAssertEqual(tail.photoPaths, ["https://cdn.example/untagged-full.jpg"])
        XCTAssertEqual(tail.condition, .scarred)
    }

    func testTwoMarkingsDoNotTurnOneEncounterIntoThreeSightings() throws {
        let logs = try encounter(condition: "\"injured\"").logs
        let detail = TurtleDetailData(turtle: TestTurtleRepository.turtle, measurements: [], logs: logs)
        XCTAssertEqual(detail.sightingLogs.count, 1)
        XCTAssertEqual(detail.sightingLogs.first?.location, "Reef")
    }

    func testBodyMarkingRetainsItsParentSightingLink() throws {
        let logs = try encounter(condition: "null").logs
        XCTAssertTrue(logs.allSatisfy { $0.sourceSightingID == "10000000-0000-4000-8000-000000000004" })
        XCTAssertNotEqual(logs.last?.id, logs.last?.sourceSightingID)
    }

    func testDiagramUsesMarkingKindInsteadOfOverallHealth() throws {
        let logs = try encounter(condition: "\"healthy\"").logs
        XCTAssertEqual(logs.first?.condition, .healthy)
        XCTAssertEqual(logs.first(where: { $0.bodyPart == .head })?.markingCondition, .injured)
        XCTAssertEqual(logs.first(where: { $0.bodyPart == .tail })?.markingCondition, .scarred)
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
