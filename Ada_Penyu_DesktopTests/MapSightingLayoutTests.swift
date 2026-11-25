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

    func testZoomedOutBaliReefPinsMergeIntoSingleNumberedCluster() {
        let items = [
            sighting("kuta", turtle: "T1", location: "Kuta Beach", latitude: -8.7180, longitude: 115.1690),
            sighting("sanur-1", turtle: "T2", location: "Sanur Reef", latitude: -8.6870, longitude: 115.2620),
            sighting("sanur-2", turtle: "T3", location: "Sanur Reef", latitude: -8.6870, longitude: 115.2620),
            sighting("penida", turtle: "T4", location: "Nusa Penida", latitude: -8.7280, longitude: 115.5440),
        ]
        let zoomedOutRegion = MKCoordinateRegion(
            center: .init(latitude: -8.71, longitude: 115.30),
            span: .init(latitudeDelta: 2.5, longitudeDelta: 2.5)
        )

        let clusters = MapSightingLayout.clusters(for: items, in: zoomedOutRegion)
        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(clusters.first?.count, 4)
        XCTAssertEqual(clusters.first?.uniqueTurtleCount, 4)
        XCTAssertEqual(clusters.first?.distinctLocationCount, 3)
        XCTAssertEqual(clusters.first?.isMerged, true)
        XCTAssertEqual(clusters.first?.canSplit, true)
    }

    func testZoomedInBaliReefPinsSplitIntoSeparateClusters() {
        let items = [
            sighting("kuta", turtle: "T1", location: "Kuta Beach", latitude: -8.7180, longitude: 115.1690),
            sighting("sanur-1", turtle: "T2", location: "Sanur Reef", latitude: -8.6870, longitude: 115.2620),
            sighting("sanur-2", turtle: "T3", location: "Sanur Reef", latitude: -8.6870, longitude: 115.2620),
            sighting("penida", turtle: "T4", location: "Nusa Penida", latitude: -8.7280, longitude: 115.5440),
        ]
        let zoomedInRegion = MKCoordinateRegion(
            center: .init(latitude: -8.71, longitude: 115.30),
            span: .init(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )

        let clusters = MapSightingLayout.clusters(for: items, in: zoomedInRegion)
        XCTAssertEqual(clusters.count, 3)
        XCTAssertTrue(clusters.allSatisfy { !$0.isMerged })
        XCTAssertEqual(clusters.map(\.count), [1, 2, 1])
    }

    func testExactSameCoordinateSightingsStayGroupedAtMaxZoom() {
        let items = [
            sighting("first", turtle: "X", location: "Sanur Reef", latitude: -8.6870, longitude: 115.2620),
            sighting("second", turtle: "Y", location: "Sanur Reef", latitude: -8.6870, longitude: 115.2620),
            sighting("repeat", turtle: "X", location: "Sanur Reef", latitude: -8.6870, longitude: 115.2620),
        ]
        let maxZoomRegion = MKCoordinateRegion(
            center: .init(latitude: -8.6870, longitude: 115.2620),
            span: .init(latitudeDelta: 0.0002, longitudeDelta: 0.0002)
        )

        let clusters = MapSightingLayout.clusters(for: items, in: maxZoomRegion)
        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(clusters.first?.count, 3)
        XCTAssertEqual(clusters.first?.distinctLocationCount, 1)
        XCTAssertEqual(clusters.first?.isMerged, false)
        XCTAssertEqual(clusters.first?.canSplit, false)
    }

    func testClusteringIgnoresInvalidCoordinatesSafely() {
        let items = [
            sighting("valid-1", location: "Kuta", latitude: -8.7180, longitude: 115.1690),
            sighting("nan", location: "Broken NaN", latitude: .nan, longitude: 115.2),
            sighting("inf", location: "Broken Inf", latitude: -8.7, longitude: .infinity),
            sighting("out-of-range", location: "Out of bounds", latitude: 95.0, longitude: 115.2),
            sighting("valid-2", location: "Sanur", latitude: -8.6870, longitude: 115.2620),
        ]
        let region = MKCoordinateRegion(
            center: .init(latitude: -8.70, longitude: 115.21),
            span: .init(latitudeDelta: 2.5, longitudeDelta: 2.5)
        )

        let clusters = MapSightingLayout.clusters(for: items, in: region)
        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(clusters.first?.sightings.map(\.id), ["valid-1", "valid-2"])
        XCTAssertTrue(clusters.first?.coordinate.latitude.isFinite == true)
        XCTAssertTrue(clusters.first?.coordinate.longitude.isFinite == true)
        XCTAssertTrue(MapSightingLayout.clusters(for: [], in: region).isEmpty)
    }

    func testClusteringAcrossDateLineMergesWithWrappedCentroid() {
        let items = [
            sighting("east", location: "East station", latitude: -16.0, longitude: 179.5),
            sighting("west", location: "West station", latitude: -16.0, longitude: -179.5),
        ]
        let wideRegion = MKCoordinateRegion(
            center: .init(latitude: -16.0, longitude: 180.0),
            span: .init(latitudeDelta: 25.0, longitudeDelta: 25.0)
        )

        let clusters = MapSightingLayout.clusters(for: items, in: wideRegion)
        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(clusters.first?.count, 2)
        XCTAssertEqual(clusters.first?.canSplit, true)
        XCTAssertEqual(abs(clusters.first?.coordinate.longitude ?? 0), 180, accuracy: 0.001)
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
