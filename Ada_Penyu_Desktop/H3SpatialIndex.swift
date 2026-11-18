import CoreLocation
import Foundation
import MapKit

/// Backend-ready viewport contract for future server-side H3 aggregation
/// (`GET /api/v1/map/h3?south=...&west=...&north=...&east=...&res=...`).
struct H3ViewportQuery: Hashable, Sendable {
    let south: Double
    let west: Double
    let north: Double
    let east: Double
    let resolution: Int

    nonisolated init(region: MKCoordinateRegion, resolution: Int, paddingFactor: Double = 0.25) {
        let halfLat = region.span.latitudeDelta * (0.5 + paddingFactor)
        let halfLon = region.span.longitudeDelta * (0.5 + paddingFactor)
        self.south = max(-90.0, region.center.latitude - halfLat)
        self.north = min(90.0, region.center.latitude + halfLat)
        self.west = region.center.longitude - halfLon
        self.east = region.center.longitude + halfLon
        self.resolution = resolution
    }

    nonisolated func contains(_ coordinate: TurtleCoordinate) -> Bool {
        guard coordinate.latitude >= south, coordinate.latitude <= north else { return false }
        if east - west >= 360.0 { return true }
        let lon = coordinate.longitude
        if lon >= west && lon <= east { return true }
        if lon + 360.0 >= west && lon + 360.0 <= east { return true }
        if lon - 360.0 >= west && lon - 360.0 <= east { return true }
        return false
    }
}

/// Aggregated turtle sightings inside a single Uber H3 hexagonal cell.
/// Explicitly separates unique observed turtles from total sightings.
struct H3CellAggregate: Identifiable {
    struct SpeciesBreakdown: Identifiable {
        let species: TurtleSpecies
        let sightingCount: Int
        let uniqueTurtleCount: Int
        var id: TurtleSpecies { species }
    }

    let index: UInt64
    let hexID: String
    let resolution: Int
    let center: CLLocationCoordinate2D
    let boundary: [CLLocationCoordinate2D]
    let areaKm2: Double
    let sightings: [Sighting]
    let uniqueTurtleCount: Int
    let speciesBreakdown: [SpeciesBreakdown]
    let countryMatch: FrontendCountryResolver.Match?
    let densityRatio: Double

    var id: UInt64 { index }
    var sightingCount: Int { sightings.count }

    /// Camera region to step smoothly one level deeper (or directly into reef pins at high res).
    var drillInRegion: MKCoordinateRegion {
        let targetSpan: Double
        switch resolution {
        case ...1: targetSpan = 28.0
        case 2: targetSpan = 14.0
        case 3: targetSpan = 6.2
        case 4: targetSpan = 2.6
        case 5: targetSpan = 0.95
        default: targetSpan = 0.24
        }

        let contentRegion = MapSightingLayout.region(containing: sightings)
        let latSpan = min(targetSpan, max(contentRegion.span.latitudeDelta, resolution >= 6 ? 0.08 : targetSpan * 0.65))
        let lonSpan = min(targetSpan * 1.25, max(contentRegion.span.longitudeDelta, resolution >= 6 ? 0.10 : targetSpan * 0.8))

        let targetCenter: CLLocationCoordinate2D
        if resolution >= 6 || sightings.count == 1 {
            targetCenter = contentRegion.center
        } else {
            targetCenter = center
        }

        return MKCoordinateRegion(
            center: targetCenter,
            span: MKCoordinateSpan(latitudeDelta: latSpan, longitudeDelta: lonSpan)
        )
    }

    func countryDisplayName(for language: AppLanguage) -> String {
        if let match = countryMatch {
            return match.localizedName(for: language)
        }
        return language == .id ? "Laut Lepas" : "Open Ocean"
    }
}

/// Official Uber H3 v4.5.0 spatial indexing & zoom-level aggregation layer for AdaPenyu.
enum H3SpatialIndex {
    /// Converts a WGS84 coordinate to its official Uber H3 cell index (`UInt64`) at `resolution` (`0...15`).
    nonisolated static func cell(for coordinate: CLLocationCoordinate2D, resolution: Int) -> UInt64? {
        guard CLLocationCoordinate2DIsValid(coordinate), (0...15).contains(resolution) else { return nil }
        var point = LatLng(
            lat: degsToRads(coordinate.latitude),
            lng: degsToRads(coordinate.longitude)
        )
        var index: H3Index = 0
        let err = latLngToCell(&point, Int32(resolution), &index)
        guard err == 0, index != 0 else { return nil }
        return index
    }

    /// Converts an H3 cell index to its canonical lowercase hexadecimal string (e.g. `"848d8a5ffffffff"`).
    nonisolated static func hexString(for index: UInt64) -> String {
        String(index, radix: 16, uppercase: false)
    }

    /// Returns the resolution (`0...15`) encoded inside an H3 cell index.
    nonisolated static func resolution(of index: UInt64) -> Int {
        Int(getResolution(index))
    }

    /// Returns the geodesic center coordinate of an H3 cell.
    nonisolated static func center(of index: UInt64) -> CLLocationCoordinate2D? {
        var point = LatLng(lat: 0, lng: 0)
        guard cellToLatLng(index, &point) == 0 else { return nil }
        let coord = CLLocationCoordinate2D(
            latitude: radsToDegs(point.lat),
            longitude: radsToDegs(point.lng)
        )
        return CLLocationCoordinate2DIsValid(coord) ? coord : nil
    }

    /// Returns the geodesic boundary polygon vertices (6 for hexagons, 5 for icosahedron pentagons).
    nonisolated static func boundary(of index: UInt64) -> [CLLocationCoordinate2D] {
        var raw = CellBoundary()
        guard cellToBoundary(index, &raw) == 0 else { return [] }
        let count = Int(raw.numVerts)
        guard count >= 3 else { return [] }

        return withUnsafePointer(to: &raw.verts) { ptr in
            ptr.withMemoryRebound(to: LatLng.self, capacity: count) { verts in
                (0..<count).map { i in
                    CLLocationCoordinate2D(
                        latitude: radsToDegs(verts[i].lat),
                        longitude: radsToDegs(verts[i].lng)
                    )
                }
            }
        }
    }

    /// Returns the parent H3 index at a coarser resolution.
    nonisolated static func parent(of index: UInt64, resolution targetResolution: Int) -> UInt64? {
        guard (0...15).contains(targetResolution), targetResolution <= resolution(of: index) else { return nil }
        var out: H3Index = 0
        guard cellToParent(index, Int32(targetResolution), &out) == 0, out != 0 else { return nil }
        return out
    }

    /// Returns the exact spherical surface area of the H3 cell in km².
    nonisolated static func areaKm2(of index: UInt64) -> Double {
        var area: Double = 0
        guard cellAreaKm2(index, &area) == 0 else { return 0 }
        return area
    }

    /// Dynamic zoom-to-H3-resolution mapping. Returns `nil` when zoomed in tightly enough
    /// to switch seamlessly to individual teardrop penyu markers.
    nonisolated static func resolution(for region: MKCoordinateRegion) -> Int? {
        let cosLat = max(0.2, cos(region.center.latitude * .pi / 180.0))
        let effectiveSpan = max(region.span.latitudeDelta, region.span.longitudeDelta * cosLat * 0.72)

        switch effectiveSpan {
        case 52.0...: return 1     // Global / World view (~607,000 km²)
        case 22.0..<52.0: return 2 // Continent / Ocean Basin (~86,800 km²)
        case 10.0..<22.0: return 3 // Multi-country / Region (~12,390 km²)
        case 4.5..<10.0: return 4  // National / Archipelago (~1,770 km²)
        case 1.8..<4.5: return 5   // Island / Province (~252 km²)
        case 0.55..<1.8: return 6  // Coastal / Reef zone (~36 km²)
        default: return nil        // Detailed view -> individual teardrop penyu markers
        }
    }

    /// Approximate average hexagon area label for legend display.
    nonisolated static func nominalScaleLabel(for resolution: Int) -> String {
        switch resolution {
        case ...1: "~607,000 km²"
        case 2: "~86,800 km²"
        case 3: "~12,390 km²"
        case 4: "~1,770 km²"
        case 5: "~252 km²"
        case 6: "~36 km²"
        case 7: "~5.2 km²"
        default: "Res \(resolution)"
        }
    }

    /// Aggregates sightings into Uber H3 hexagonal cells at `resolution`, optionally clipped to `viewport`.
    /// Tracks both unique turtles and total sightings per cell, plus frontend offline country resolution.
    static func aggregate(
        sightings: [Sighting],
        resolution: Int,
        viewport: H3ViewportQuery? = nil,
        countryResolver: FrontendCountryResolver = .shared
    ) -> [H3CellAggregate] {
        var buckets: [UInt64: [Sighting]] = [:]

        for sighting in sightings {
            let coord = sighting.coordinate
            let clCoord = CLLocationCoordinate2D(latitude: coord.latitude, longitude: coord.longitude)
            guard CLLocationCoordinate2DIsValid(clCoord) else { continue }
            if let viewport, !viewport.contains(coord) { continue }
            guard let cellIndex = cell(for: clCoord, resolution: resolution) else { continue }
            buckets[cellIndex, default: []].append(sighting)
        }

        guard !buckets.isEmpty else { return [] }
        let maxSightings = max(1, buckets.values.map(\.count).max() ?? 1)

        return buckets.compactMap { cellIndex, records in
            guard let center = center(of: cellIndex) else { return nil }
            let vertices = boundary(of: cellIndex)
            guard vertices.count >= 3 else { return nil }

            let uniqueTurtles = Set(records.map(\.turtleID)).count
            let bySpecies = Dictionary(grouping: records, by: \.species)
            let speciesBreakdown = bySpecies.map { species, items in
                H3CellAggregate.SpeciesBreakdown(
                    species: species,
                    sightingCount: items.count,
                    uniqueTurtleCount: Set(items.map(\.turtleID)).count
                )
            }
            .sorted {
                if $0.uniqueTurtleCount != $1.uniqueTurtleCount {
                    return $0.uniqueTurtleCount > $1.uniqueTurtleCount
                }
                return $0.sightingCount > $1.sightingCount
            }

            // Resolve country from the cell center first; if open water (e.g. giant Res 2 hex centered at sea),
            // fall back to the first sighting's exact coordinate so coastal archipelagos still label accurately.
            let country = countryResolver.resolve(coordinate: center)
                ?? records.first.flatMap { countryResolver.resolve(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }

            let ratio = maxSightings == 1
                ? 0.55
                : log1p(Double(records.count)) / log1p(Double(maxSightings))

            return H3CellAggregate(
                index: cellIndex,
                hexID: hexString(for: cellIndex),
                resolution: resolution,
                center: center,
                boundary: vertices,
                areaKm2: areaKm2(of: cellIndex),
                sightings: records,
                uniqueTurtleCount: uniqueTurtles,
                speciesBreakdown: speciesBreakdown,
                countryMatch: country,
                densityRatio: min(1.0, max(0.15, ratio))
            )
        }
        .sorted {
            if $0.sightingCount != $1.sightingCount {
                return $0.sightingCount > $1.sightingCount
            }
            return $0.index < $1.index
        }
    }

    /// Counts distinct countries represented across all loaded sightings purely from `(lat, lng)`.
    static func resolvedCountryCounts(
        for sightings: [Sighting],
        language: AppLanguage = .en,
        countryResolver: FrontendCountryResolver = .shared
    ) -> [(country: String, isoCode: String, uniqueTurtles: Int, sightings: Int)] {
        var grouped: [String: (name: String, iso: String, sightings: [Sighting])] = [:]
        for sighting in sightings {
            let match = countryResolver.resolve(latitude: sighting.coordinate.latitude, longitude: sighting.coordinate.longitude)
            let key = match?.isoCode.isEmpty == false ? match!.isoCode : (match?.nameEnglish ?? "OCEAN")
            let display = match?.localizedName(for: language) ?? (language == .id ? "Laut Lepas" : "Open Ocean")
            let iso = match?.isoCode ?? ""
            if var entry = grouped[key] {
                entry.sightings.append(sighting)
                grouped[key] = entry
            } else {
                grouped[key] = (name: display, iso: iso, sightings: [sighting])
            }
        }

        return grouped.values.map { entry in
            (
                country: entry.name,
                isoCode: entry.iso,
                uniqueTurtles: Set(entry.sightings.map(\.turtleID)).count,
                sightings: entry.sightings.count
            )
        }
        .sorted {
            if $0.uniqueTurtles != $1.uniqueTurtles { return $0.uniqueTurtles > $1.uniqueTurtles }
            return $0.sightings > $1.sightings
        }
    }
}
