import MapKit

/// Presentation over the sightings returned for the current filters.
enum MapSightingLayout {
    struct Location: Identifiable {
        let coordinate: TurtleCoordinate
        let sightings: [Sighting]
        var id: TurtleCoordinate { coordinate }
        var mapCoordinate: CLLocationCoordinate2D {
            .init(latitude: coordinate.latitude, longitude: coordinate.longitude)
        }
    }

    struct Country: Identifiable {
        let label: String
        let sightings: [Sighting]
        let anchor: CLLocationCoordinate2D
        let region: MKCoordinateRegion
        var id: String { label }
        var turtleCount: Int { Set(sightings.map(\.turtleID)).count }
    }

    struct Cluster: Identifiable {
        let id: String
        let coordinate: CLLocationCoordinate2D
        let sightings: [Sighting]
        let distinctLocationCount: Int

        var count: Int { sightings.count }
        var uniqueTurtleCount: Int { Set(sightings.map(\.turtleID)).count }
        var primarySighting: Sighting { sightings[0] }
        var isMerged: Bool { distinctLocationCount > 1 }

        var coordinateSpan: MKCoordinateSpan {
            let latitudes = sightings.map(\.coordinate.latitude)
            let longitudes = sightings.map(\.coordinate.longitude)
            guard let minLat = latitudes.min(), let maxLat = latitudes.max(),
                  let minLon = longitudes.min(), let maxLon = longitudes.max() else {
                return .init(latitudeDelta: 0, longitudeDelta: 0)
            }
            let rawLonDelta = maxLon - minLon
            let wrappedLonDelta: Double
            if rawLonDelta > 180 {
                let shifted = longitudes.map { $0 < 0 ? $0 + 360 : $0 }
                wrappedLonDelta = (shifted.max() ?? maxLon) - (shifted.min() ?? minLon)
            } else {
                wrappedLonDelta = rawLonDelta
            }
            return .init(latitudeDelta: maxLat - minLat, longitudeDelta: wrappedLonDelta)
        }

        /// True when sightings span distinct coordinates far enough apart to split on zoom-in.
        var canSplit: Bool {
            let span = coordinateSpan
            return span.latitudeDelta > 0.0005 || span.longitudeDelta > 0.0005
        }
    }

    static let defaultRegion = MKCoordinateRegion(
        center: .init(latitude: -8.72, longitude: 115.20),
        span: .init(latitudeDelta: 0.25, longitudeDelta: 0.32)
    )

    /// Screen-space center-to-center distance (pt) below which pins merge at the current zoom.
    static let clusterDistancePoints: Double = 76.0

    static func showsCountryMarkers(in region: MKCoordinateRegion) -> Bool {
        let latitudeScale = cos(region.center.latitude * .pi / 180)
        return region.span.latitudeDelta > 2.2 || region.span.longitudeDelta * latitudeScale > 3.4
    }

    static func locations(for sightings: [Sighting]) -> [Location] {
        let valid = sightings.filter { isValid($0.coordinate) }
        let groups = Dictionary(grouping: valid, by: \.coordinate)
        var seen = Set<TurtleCoordinate>()
        return valid.compactMap { sighting in
            let coordinate = sighting.coordinate
            guard seen.insert(coordinate).inserted, let records = groups[coordinate] else { return nil }
            return Location(coordinate: coordinate, sightings: records)
        }
    }

    static func clusters(
        for sightings: [Sighting],
        in region: MKCoordinateRegion,
        mapSize: CGSize = CGSize(width: 900, height: 640)
    ) -> [Cluster] {
        let atomicLocations = locations(for: sightings)
        guard !atomicLocations.isEmpty else { return [] }

        let safeSize: CGSize = (mapSize.width > 0 && mapSize.height > 0 && mapSize.width.isFinite && mapSize.height.isFinite)
            ? mapSize
            : CGSize(width: 900, height: 640)
        let aspect = Double(safeSize.width) / Double(safeSize.height)
        let clampedLat = min(85.0, max(-85.0, region.center.latitude))
        let cosLat = max(cos(clampedLat * .pi / 180), 0.1)
        let rawLatDelta = region.span.latitudeDelta.isFinite && region.span.latitudeDelta > 0 ? region.span.latitudeDelta : 0.25
        let rawLonDelta = region.span.longitudeDelta.isFinite && region.span.longitudeDelta > 0 ? region.span.longitudeDelta : 0.32

        // Match MapKit's aspect-ratio fit so square test spans and live camera regions scale consistently.
        let effectiveLonDelta = min(360.0, max(rawLonDelta, rawLatDelta * aspect / cosLat))
        let effectiveLatDelta = min(170.0, max(rawLatDelta, rawLonDelta / aspect * cosLat))

        let pointsPerDegreeLat = Double(safeSize.height) / effectiveLatDelta
        let pointsPerDegreeLon = Double(safeSize.width) / effectiveLonDelta
        let threshold = clusterDistancePoints

        var parents = Array(atomicLocations.indices)
        func root(_ index: Int) -> Int {
            var current = index
            while parents[current] != current {
                parents[current] = parents[parents[current]]
                current = parents[current]
            }
            return current
        }

        struct Cell: Hashable { let x: Int; let y: Int }
        let gridColumns = max(1, Int(ceil((360.0 * pointsPerDegreeLon) / threshold)))
        func wrappedColumn(_ raw: Int) -> Int {
            let mod = raw % gridColumns
            return mod < 0 ? mod + gridColumns : mod
        }

        var grid: [Cell: [Int]] = [:]
        grid.reserveCapacity(atomicLocations.count)

        for index in atomicLocations.indices {
            let coord = atomicLocations[index].coordinate
            let cellX = Int(floor(((coord.longitude + 180.0) * pointsPerDegreeLon) / threshold))
            let cellY = Int(floor(((coord.latitude + 90.0) * pointsPerDegreeLat) / threshold))
            let neighborColumns = gridColumns <= 3
                ? Array(0..<gridColumns)
                : [wrappedColumn(cellX - 1), wrappedColumn(cellX), wrappedColumn(cellX + 1)]

            for wrappedX in neighborColumns {
                for dy in -1...1 {
                    let neighborCell = Cell(x: wrappedX, y: cellY + dy)
                    for other in grid[neighborCell] ?? [] {
                        let otherCoord = atomicLocations[other].coordinate
                        let dLat = abs(coord.latitude - otherCoord.latitude) * pointsPerDegreeLat
                        let rawDLon = abs(coord.longitude - otherCoord.longitude)
                        let dLon = min(rawDLon, 360.0 - rawDLon) * pointsPerDegreeLon
                        if hypot(dLat, dLon) <= threshold {
                            let a = root(index)
                            let b = root(other)
                            if a != b { parents[max(a, b)] = min(a, b) }
                        }
                    }
                }
            }

            let ownCell = Cell(x: wrappedColumn(cellX), y: cellY)
            grid[ownCell, default: []].append(index)
        }

        let groupedIndices = Dictionary(grouping: atomicLocations.indices, by: root)
            .values
            .map { $0.sorted() }
            .sorted { $0[0] < $1[0] }

        return groupedIndices.map { indices in
            let members = indices.map { atomicLocations[$0] }
            let mergedSightings = members.flatMap(\.sightings)
            if members.count == 1, let only = members.first {
                return Cluster(
                    id: "loc-\(only.coordinate.latitude)-\(only.coordinate.longitude)",
                    coordinate: only.mapCoordinate,
                    sightings: mergedSightings,
                    distinctLocationCount: 1
                )
            }

            let centroid = weightedCentroid(for: members)
            let sortedIDs = mergedSightings.map(\.id).sorted()
            return Cluster(
                id: "cluster-\(mergedSightings.count)-\(stableHashHex(sortedIDs))",
                coordinate: centroid,
                sightings: mergedSightings,
                distinctLocationCount: members.count
            )
        }
    }

    static func countries(for sightings: [Sighting]) -> [Country] {
        var groups: [String: [Sighting]] = [:]
        for sighting in sightings {
            guard isValid(sighting.coordinate), let label = countryName(for: sighting) else { continue }
            groups[label, default: []].append(sighting)
        }
        return groups.map { label, records in
            let region = region(containing: records)
            // Keep the marker on an actual observed location even for an archipelago.
            let nearest = records.min {
                distance(from: region.center, to: $0.coordinate) < distance(from: region.center, to: $1.coordinate)
            }
            let anchor = nearest.map {
                CLLocationCoordinate2D(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
            } ?? region.center
            return Country(label: label, sightings: records, anchor: anchor, region: region)
        }.sorted { $0.label < $1.label }
    }

    static func region(containing sightings: [Sighting], minimumSpan: Double = 0.08) -> MKCoordinateRegion {
        let coordinates = sightings.map(\.coordinate).filter { isValid($0) }
        guard let south = coordinates.map(\.latitude).min(), let north = coordinates.map(\.latitude).max() else {
            return defaultRegion
        }

        // Cut the longitude circle at its largest empty arc, so observations on
        // either side of the date line fit into a single local view.
        let longitudes = coordinates.map { $0.longitude < 0 ? $0.longitude + 360 : $0.longitude }.sorted()
        var largestGap = -Double.infinity
        var first = longitudes[0]
        for index in longitudes.indices {
            let nextIndex = (index + 1) % longitudes.count
            let next = longitudes[nextIndex] + (nextIndex == 0 ? 360 : 0)
            let gap = next - longitudes[index]
            if gap > largestGap {
                largestGap = gap
                first = longitudes[nextIndex]
            }
        }
        let longitudeWidth = 360 - largestGap
        let longitudeCenter = (first + longitudeWidth / 2).truncatingRemainder(dividingBy: 360)
        return MKCoordinateRegion(
            center: .init(latitude: (south + north) / 2, longitude: longitudeCenter > 180 ? longitudeCenter - 360 : longitudeCenter),
            span: .init(latitudeDelta: min(170, max((north - south) * 1.42, minimumSpan)),
                        longitudeDelta: min(360, max(longitudeWidth * 1.42, minimumSpan)))
        )
    }

    private static let countryLabels: [String: String] = {
        let english = Locale(identifier: "en_US")
        return Locale.Region.isoRegions.reduce(into: [:]) { labels, region in
            if let name = english.localizedString(forRegionCode: region.identifier) {
                labels[name.lowercased()] = name
            }
        }
    }()

    private static let baliSiteNames: Set<String> = [
        "bali", "kuta beach", "nusa dua reef", "serangan island", "serangan coast", "serangan reef",
        "sanur flats", "sanur reef", "pantai timur", "jimbaran bay", "legian beach", "tuban beach",
        "nusa penida", "crystal bay",
    ]

    private static func countryName(for sighting: Sighting) -> String? {
        let names = sighting.location.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        if let suffix = names.last, let country = countryLabels[suffix] { return country }

        // Existing Bali and Indian Ocean fixtures use these local names without
        // a country suffix. The coordinate check avoids matching another site
        // sharing a short name. All other sites remain individual markers.
        let coordinate = sighting.coordinate
        if (-9.1 ... -7.8).contains(coordinate.latitude), (114.3...115.9).contains(coordinate.longitude),
           !baliSiteNames.isDisjoint(with: names) {
            return "Indonesia"
        }
        if (8...14).contains(coordinate.latitude), (71...75).contains(coordinate.longitude),
           names.contains("lakshadweep") {
            return "India"
        }
        return nil
    }

    private static func isValid(_ coordinate: TurtleCoordinate) -> Bool {
        coordinate.latitude.isFinite
            && coordinate.longitude.isFinite
            && CLLocationCoordinate2DIsValid(.init(latitude: coordinate.latitude, longitude: coordinate.longitude))
    }

    private static func weightedCentroid(for locations: [Location]) -> CLLocationCoordinate2D {
        var totalWeight = 0.0
        var weightedLat = 0.0
        var weightedSinLon = 0.0
        var weightedCosLon = 0.0

        for location in locations {
            let weight = Double(max(1, location.sightings.count))
            totalWeight += weight
            weightedLat += location.coordinate.latitude * weight
            let radLon = location.coordinate.longitude * .pi / 180.0
            weightedSinLon += sin(radLon) * weight
            weightedCosLon += cos(radLon) * weight
        }

        let avgLat = weightedLat / max(1.0, totalWeight)
        let avgLon: Double
        if weightedSinLon == 0 && weightedCosLon == 0 {
            avgLon = locations[0].coordinate.longitude
        } else {
            avgLon = atan2(weightedSinLon, weightedCosLon) * 180.0 / .pi
        }
        return CLLocationCoordinate2D(latitude: avgLat, longitude: avgLon)
    }

    private static func stableHashHex(_ ids: [String]) -> String {
        var hash: UInt64 = 14695981039346656037
        for id in ids {
            for byte in id.utf8 {
                hash ^= UInt64(byte)
                hash = hash &* 1099511628211
            }
            hash ^= 0xFF
            hash = hash &* 1099511628211
        }
        return String(hash, radix: 16)
    }

    private static func distance(from center: CLLocationCoordinate2D, to coordinate: TurtleCoordinate) -> Double {
        let longitude = abs(center.longitude - coordinate.longitude)
        return hypot(center.latitude - coordinate.latitude, min(longitude, 360 - longitude))
    }
}
