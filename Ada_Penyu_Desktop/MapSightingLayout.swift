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

    static let defaultRegion = MKCoordinateRegion(
        center: .init(latitude: -8.72, longitude: 115.20),
        span: .init(latitudeDelta: 0.25, longitudeDelta: 0.32)
    )

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

    static func region(containing sightings: [Sighting]) -> MKCoordinateRegion {
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
            span: .init(latitudeDelta: min(170, max((north - south) * 1.42, 0.08)),
                        longitudeDelta: min(360, max(longitudeWidth * 1.42, 0.08)))
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
        CLLocationCoordinate2DIsValid(.init(latitude: coordinate.latitude, longitude: coordinate.longitude))
    }

    private static func distance(from center: CLLocationCoordinate2D, to coordinate: TurtleCoordinate) -> Double {
        let longitude = abs(center.longitude - coordinate.longitude)
        return hypot(center.latitude - coordinate.latitude, min(longitude, 360 - longitude))
    }
}
