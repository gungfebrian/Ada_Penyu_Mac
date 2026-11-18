import CoreLocation
import MapKit
import XCTest
@testable import Ada_Penyu_Desktop

@MainActor
final class H3SpatialMapTests: XCTestCase {
    func testOfficialUberH3IndexingBoundaryAndParentHierarchy() throws {
        // Sanur Reef, Bali
        let sanur = CLLocationCoordinate2D(latitude: -8.69, longitude: 115.27)
        let res6 = try XCTUnwrap(H3SpatialIndex.cell(for: sanur, resolution: 6))
        XCTAssertEqual(H3SpatialIndex.resolution(of: res6), 6)
        XCTAssertEqual(H3SpatialIndex.hexString(for: res6).count, 15)

        let boundary = H3SpatialIndex.boundary(of: res6)
        XCTAssertEqual(boundary.count, 6, "Standard H3 cells have 6 geodesic vertices")

        let center = try XCTUnwrap(H3SpatialIndex.center(of: res6))
        XCTAssertEqual(center.latitude, sanur.latitude, accuracy: 0.1)
        XCTAssertEqual(center.longitude, sanur.longitude, accuracy: 0.1)

        // Parent hierarchy must match indexing at the coarser resolution directly
        let parentRes4 = try XCTUnwrap(H3SpatialIndex.parent(of: res6, resolution: 4))
        let directRes4 = try XCTUnwrap(H3SpatialIndex.cell(for: sanur, resolution: 4))
        XCTAssertEqual(parentRes4, directRes4)

        let areaRes4 = H3SpatialIndex.areaKm2(of: directRes4)
        XCTAssertGreaterThan(areaRes4, 1_000)
        XCTAssertLessThan(areaRes4, 2_600)
    }

    func testDynamicZoomSwitchesAcrossH3ResolutionsAndDetailedPins() {
        let bali = CLLocationCoordinate2D(latitude: -8.7, longitude: 115.2)

        XCTAssertEqual(
            H3SpatialIndex.resolution(for: MKCoordinateRegion(center: bali, span: .init(latitudeDelta: 35, longitudeDelta: 45))),
            2
        )
        XCTAssertEqual(
            H3SpatialIndex.resolution(for: MKCoordinateRegion(center: bali, span: .init(latitudeDelta: 14, longitudeDelta: 16))),
            3
        )
        XCTAssertEqual(
            H3SpatialIndex.resolution(for: MKCoordinateRegion(center: bali, span: .init(latitudeDelta: 6.5, longitudeDelta: 8))),
            4
        )
        XCTAssertEqual(
            H3SpatialIndex.resolution(for: MKCoordinateRegion(center: bali, span: .init(latitudeDelta: 2.5, longitudeDelta: 3.0))),
            5
        )
        XCTAssertEqual(
            H3SpatialIndex.resolution(for: MKCoordinateRegion(center: bali, span: .init(latitudeDelta: 0.9, longitudeDelta: 1.1))),
            6
        )
        XCTAssertNil(
            H3SpatialIndex.resolution(for: MKCoordinateRegion(center: bali, span: .init(latitudeDelta: 0.25, longitudeDelta: 0.32))),
            "Zooming in close must switch from H3 hexagons to individual penyu markers"
        )
    }

    func testH3AggregationDistinguishesUniqueTurtlesFromTotalSightingsAndSpecies() throws {
        // 3 sightings of the SAME turtle + 1 sighting of a SECOND turtle inside the same Bali Res-5 hex
        let items = [
            makeSighting(id: "s1", turtleID: "turtle-A", species: .green, lat: -8.690, lon: 115.270),
            makeSighting(id: "s2", turtleID: "turtle-A", species: .green, lat: -8.692, lon: 115.272),
            makeSighting(id: "s3", turtleID: "turtle-A", species: .green, lat: -8.694, lon: 115.271),
            makeSighting(id: "s4", turtleID: "turtle-B", species: .hawksbill, lat: -8.691, lon: 115.273),
        ]

        let cells = H3SpatialIndex.aggregate(sightings: items, resolution: 5)
        XCTAssertEqual(cells.count, 1)
        let cell = try XCTUnwrap(cells.first)
        XCTAssertEqual(cell.sightingCount, 4)
        XCTAssertEqual(cell.uniqueTurtleCount, 2)
        XCTAssertEqual(cell.speciesBreakdown.count, 2)
        XCTAssertEqual(cell.countryMatch?.nameEnglish, "Indonesia")
        XCTAssertEqual(cell.countryMatch?.isoCode, "ID")
    }

    func testViewportQueryFiltersOutDistantCells() {
        let items = [
            makeSighting(id: "bali", turtleID: "t1", species: .green, lat: -8.69, lon: 115.27),
            makeSighting(id: "india", turtleID: "t2", species: .oliveRidley, lat: 10.57, lon: 72.64),
        ]
        let baliViewport = H3ViewportQuery(
            region: MKCoordinateRegion(
                center: .init(latitude: -8.7, longitude: 115.2),
                span: .init(latitudeDelta: 4.0, longitudeDelta: 4.0)
            ),
            resolution: 4
        )
        let cells = H3SpatialIndex.aggregate(sightings: items, resolution: 4, viewport: baliViewport)
        XCTAssertEqual(cells.count, 1)
        XCTAssertEqual(cells.first?.sightings.map(\.id), ["bali"])
    }

    func testOfflineFrontendCountryResolverWorksPurelyFromCoordinatesIncludingOffshoreReefs() throws {
        let resolver = FrontendCountryResolver.shared
        XCTAssertTrue(resolver.isLoaded, "Bundled WorldCountries50m.json must load offline")

        let cases: [(name: String, lat: Double, lon: Double, expectedISO: String, expectedEN: String)] = [
            ("Sanur Reef", -8.69, 115.27, "ID", "Indonesia"),
            ("Crystal Bay offshore", -8.714, 115.458, "ID", "Indonesia"),
            ("Misool Raja Ampat", -1.915, 130.145, "ID", "Indonesia"),
            ("Derawan offshore", 2.283, 118.248, "ID", "Indonesia"),
            ("Sipadan offshore", 4.115, 118.628, "MY", "Malaysia"),
            ("Lakshadweep offshore", 10.567, 72.642, "IN", "India"),
            ("Andaman Reef", 11.98, 93.00, "IN", "India"),
            ("Apo Island offshore", 9.079, 123.269, "PH", "Philippines"),
            ("Similan Islands", 8.65, 97.64, "TH", "Thailand"),
            ("Kerama Islands", 26.20, 127.30, "JP", "Japan"),
            ("Heron Island GBR", -23.442, 151.914, "AU", "Australia"),
            ("Hikkaduwa", 6.139, 80.100, "LK", "Sri Lanka"),
            ("Baa Atoll", 5.15, 73.00, "MV", "Maldives"),
            ("Con Dao", 8.69, 106.60, "VN", "Vietnam"),
            ("Palau Reef", 7.35, 134.45, "PW", "Palau"),
        ]

        for item in cases {
            let match = try XCTUnwrap(
                resolver.resolve(latitude: item.lat, longitude: item.lon),
                "Failed to resolve \(item.name)"
            )
            XCTAssertEqual(match.isoCode, item.expectedISO, "Wrong ISO for \(item.name)")
            XCTAssertEqual(match.nameEnglish, item.expectedEN, "Wrong country name for \(item.name)")
        }

        // Open ocean far from any coastline returns nil
        XCTAssertNil(resolver.resolve(latitude: -20.0, longitude: 85.0))

        // Bahasa Indonesia localization comes bundled in the dataset
        let japan = try XCTUnwrap(resolver.resolve(latitude: 26.20, longitude: 127.30))
        XCTAssertEqual(japan.localizedName(for: .id), "Jepang")
    }

    private func makeSighting(id: String, turtleID: String, species: TurtleSpecies, lat: Double, lon: Double) -> Sighting {
        Sighting(
            name: turtleID,
            id: id,
            turtleID: turtleID,
            species: species,
            location: "Unnamed reef station", // deliberately no country text!
            date: "01 Nov 2026",
            condition: .healthy,
            coordinate: .init(latitude: lat, longitude: lon)
        )
    }
}
