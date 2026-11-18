import MapKit
import XCTest
@testable import Ada_Penyu_Desktop

@MainActor
final class MapSightingLayoutTests: XCTestCase {
    func testLocalMapKeepsEveryDistinctSightingLocationWithALargeResultSet() {
        let items = (0..<60).map { index in
            sighting("reef-\(index)", location: "Sanur Reef", latitude: -8.7, longitude: 115 + Double(index) * 0.001)
        }
        let localRegion = MKCoordinateRegion(
            center: .init(latitude: -8.7, longitude: 115.2),
            span: .init(latitudeDelta: 0.15, longitudeDelta: 0.3)
        )

        XCTAssertFalse(MapSightingLayout.showsCountryMarkers(in: localRegion))
        XCTAssertEqual(MapSightingLayout.locations(for: items).count, 60)
    }

    func testZoomedOutCountriesGroupSeparateIslandsAndKeepUnknownSitesSeparate() {
        let items = [
            sighting("bali", location: "Sanur Reef", latitude: -8.69, longitude: 115.27),
            sighting("misool", location: "Misool, Raja Ampat, Indonesia", latitude: -1.915, longitude: 130.145),
            sighting("malaysia", location: "Sipadan, Sabah, Malaysia", latitude: 4.115, longitude: 118.628),
            sighting("unknown", location: "Unnamed offshore station", latitude: 4.116, longitude: 118.63),
        ]

        let groups = MapSightingLayout.countries(for: items)
        XCTAssertEqual(groups.map(\.label), ["Indonesia", "Malaysia"])
        XCTAssertEqual(Set(groups.first?.sightings.map(\.id) ?? []), ["bali", "misool"])
        XCTAssertEqual(groups.last?.sightings.map(\.id), ["malaysia"])
        XCTAssertTrue(MapSightingLayout.showsCountryMarkers(in: MapSightingLayout.region(containing: items)))
    }

    func testDistinctTurtlesAndRepeatedEncountersAtIdenticalCoordinatesStayReachable() {
        let items = [
            sighting("first", turtle: "X", location: "Reef"),
            sighting("second", turtle: "Y", location: "Reef"),
            sighting("previous", turtle: "X", location: "Reef"),
        ]

        let locations = MapSightingLayout.locations(for: items)
        XCTAssertEqual(locations.count, 1)
        XCTAssertEqual(locations.first?.sightings.map(\.id), ["first", "second", "previous"])
    }

    func testFitUsesShortLongitudeSpanAcrossDateLine() {
        let items = [
            sighting("east", location: "East station", latitude: -16, longitude: 179.5),
            sighting("west", location: "West station", latitude: -16, longitude: -179.5),
        ]

        let region = MapSightingLayout.region(containing: items)
        XCTAssertEqual(abs(region.center.longitude), 180, accuracy: 0.0001)
        XCTAssertLessThan(region.span.longitudeDelta, 2)
    }

    private func sighting(
        _ id: String, turtle: String? = nil, location: String,
        latitude: Double = -8.69, longitude: Double = 115.27
    ) -> Sighting {
        Sighting(
            id: id, turtleID: turtle ?? id, species: .green, location: location,
            date: "01 Nov 2026", condition: .unknown,
            coordinate: .init(latitude: latitude, longitude: longitude)
        )
    }
}
