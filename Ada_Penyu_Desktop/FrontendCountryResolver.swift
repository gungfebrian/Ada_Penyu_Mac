import CoreLocation
import Foundation

/// Offline frontend `(latitude, longitude) -> Country` resolver using Natural Earth 50m
/// coastlines plus a 200 nautical mile (~370 km) coastal EEZ buffer so offshore reef
/// turtle sightings still resolve cleanly to their coastal nation without backend country fields
/// or rate-limited reverse geocoding APIs.
final class FrontendCountryResolver: @unchecked Sendable {
    struct Match: Hashable, Sendable {
        let nameEnglish: String
        let nameIndonesian: String
        let isoCode: String
        let isOffshore: Bool
        let distanceKm: Double

        func localizedName(for language: AppLanguage) -> String {
            switch language {
            case .en: nameEnglish
            case .id: nameIndonesian.isEmpty ? nameEnglish : nameIndonesian
            }
        }
    }

    nonisolated static let shared = FrontendCountryResolver()

    private struct CompactRing: Decodable {
        let b: [Double] // [minLon, minLat, maxLon, maxLat]
        let p: [Double] // flat [lon0, lat0, lon1, lat1, ...]
    }

    private struct CompactCountry: Decodable {
        let n: String // English name
        let i: String // Bahasa Indonesia name
        let c: String // ISO A2
        let b: [Double]
        let r: [CompactRing]
    }

    private struct CountryRecord: Sendable {
        let nameEnglish: String
        let nameIndonesian: String
        let isoCode: String
        let minLon: Double
        let minLat: Double
        let maxLon: Double
        let maxLat: Double
        let rings: [RingRecord]
    }

    private struct RingRecord: Sendable {
        let minLon: Double
        let minLat: Double
        let maxLon: Double
        let maxLat: Double
        let coords: [Double]
    }

    /// 200 nautical miles (~370 km) exclusive economic zone coastal buffer.
    nonisolated static let defaultCoastalBufferKm: Double = 370.0

    private let countries: [CountryRecord]
    private let cacheLock = NSLock()
    private var cache: [Int64: Match?] = [:]

    nonisolated init(bundle: Bundle? = nil) {
        let candidateBundles: [Bundle] = [
            bundle,
            Bundle.main,
            Bundle(for: FrontendCountryResolver.self),
        ].compactMap { $0 }

        var loaded: [CountryRecord] = []
        for candidate in candidateBundles {
            if let url = candidate.url(forResource: "WorldCountries50m", withExtension: "json")
                ?? candidate.url(forResource: "WorldCountries50m", withExtension: "json", subdirectory: "Resources"),
               let data = try? Data(contentsOf: url),
               let decoded = try? JSONDecoder().decode([CompactCountry].self, from: data) {
                loaded = decoded.compactMap { item in
                    guard item.b.count == 4 else { return nil }
                    let rings: [RingRecord] = item.r.compactMap { ring in
                        guard ring.b.count == 4, ring.p.count >= 6 else { return nil }
                        return RingRecord(
                            minLon: ring.b[0],
                            minLat: ring.b[1],
                            maxLon: ring.b[2],
                            maxLat: ring.b[3],
                            coords: ring.p
                        )
                    }
                    guard !rings.isEmpty else { return nil }
                    return CountryRecord(
                        nameEnglish: item.n,
                        nameIndonesian: item.i,
                        isoCode: item.c,
                        minLon: item.b[0],
                        minLat: item.b[1],
                        maxLon: item.b[2],
                        maxLat: item.b[3],
                        rings: rings
                    )
                }
                break
            }
        }
        self.countries = loaded
    }

    nonisolated var isLoaded: Bool { !countries.isEmpty }

    nonisolated func resolve(
        latitude: Double,
        longitude: Double,
        coastalBufferKm: Double = defaultCoastalBufferKm
    ) -> Match? {
        guard latitude.isFinite, longitude.isFinite, (-90...90).contains(latitude) else { return nil }
        let lon = normalizeLongitude(longitude)

        // Quantized ~2.2 km memoization key for fast repeated viewport aggregation
        let useCache = coastalBufferKm == Self.defaultCoastalBufferKm
        let key = (Int64((latitude * 50).rounded()) << 32) ^ Int64(Int32((lon * 50).rounded()))
        if useCache {
            cacheLock.lock()
            if let hit = cache[key] {
                cacheLock.unlock()
                return hit
            }
            cacheLock.unlock()
        }

        let resolved = computeMatch(latitude: latitude, longitude: lon, coastalBufferKm: coastalBufferKm)

        if useCache {
            cacheLock.lock()
            if cache.count > 16_384 {
                cache.removeAll(keepingCapacity: true)
            }
            cache[key] = resolved
            cacheLock.unlock()
        }

        return resolved
    }

    nonisolated func resolve(coordinate: CLLocationCoordinate2D) -> Match? {
        resolve(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    private nonisolated func computeMatch(latitude: Double, longitude: Double, coastalBufferKm: Double) -> Match? {
        // Pass 1: exact point-in-polygon over all 242 land/island polygons
        for country in countries {
            guard longitude >= country.minLon, longitude <= country.maxLon,
                  latitude >= country.minLat, latitude <= country.maxLat else {
                continue
            }
            for ring in country.rings {
                guard longitude >= ring.minLon, longitude <= ring.maxLon,
                      latitude >= ring.minLat, latitude <= ring.maxLat else {
                    continue
                }
                if pointInPolygon(lon: longitude, lat: latitude, coords: ring.coords) {
                    return Match(
                        nameEnglish: country.nameEnglish,
                        nameIndonesian: country.nameIndonesian,
                        isoCode: country.isoCode,
                        isOffshore: false,
                        distanceKm: 0
                    )
                }
            }
        }

        // Pass 2: coastal marine buffer (reef / territorial waters / EEZ)
        guard coastalBufferKm > 0 else { return nil }
        let latPad = coastalBufferKm / 111.0 + 0.25
        let cosLat = max(0.15, cos(latitude * .pi / 180.0))
        let lonPad = min(180.0, latPad / cosLat)

        var bestCountry: CountryRecord?
        var bestDistance = coastalBufferKm

        for country in countries {
            guard latitude >= country.minLat - latPad, latitude <= country.maxLat + latPad,
                  longitudeWithin(lon: longitude, minLon: country.minLon, maxLon: country.maxLon, pad: lonPad) else {
                continue
            }
            for ring in country.rings {
                guard latitude >= ring.minLat - latPad, latitude <= ring.maxLat + latPad,
                      longitudeWithin(lon: longitude, minLon: ring.minLon, maxLon: ring.maxLon, pad: lonPad) else {
                    continue
                }
                let distance = minimumDistanceKm(lon: longitude, lat: latitude, cosLat: cosLat, coords: ring.coords)
                if distance < bestDistance {
                    bestDistance = distance
                    bestCountry = country
                }
            }
        }

        guard let bestCountry else { return nil }
        return Match(
            nameEnglish: bestCountry.nameEnglish,
            nameIndonesian: bestCountry.nameIndonesian,
            isoCode: bestCountry.isoCode,
            isOffshore: true,
            distanceKm: (bestDistance * 10).rounded() / 10
        )
    }

    private nonisolated func normalizeLongitude(_ lon: Double) -> Double {
        var value = lon.truncatingRemainder(dividingBy: 360.0)
        if value > 180.0 { value -= 360.0 }
        if value < -180.0 { value += 360.0 }
        return value
    }

    private nonisolated func longitudeWithin(lon: Double, minLon: Double, maxLon: Double, pad: Double) -> Bool {
        if lon >= minLon - pad && lon <= maxLon + pad { return true }
        // Handle antimeridian wrap (e.g. Fiji / Pacific islands near +/-180)
        if lon + 360.0 >= minLon - pad && lon + 360.0 <= maxLon + pad { return true }
        if lon - 360.0 >= minLon - pad && lon - 360.0 <= maxLon + pad { return true }
        return false
    }

    private nonisolated func pointInPolygon(lon: Double, lat: Double, coords: [Double]) -> Bool {
        let count = coords.count / 2
        guard count >= 3 else { return false }
        var inside = false
        var j = count - 1
        for i in 0..<count {
            let xi = coords[i * 2]
            let yi = coords[i * 2 + 1]
            let xj = coords[j * 2]
            let yj = coords[j * 2 + 1]
            let intersects = ((yi > lat) != (yj > lat))
                && (lon < (xj - xi) * (lat - yi) / (yj - yi) + xi)
            if intersects { inside.toggle() }
            j = i
        }
        return inside
    }

    private nonisolated func minimumDistanceKm(lon: Double, lat: Double, cosLat: Double, coords: [Double]) -> Double {
        let count = coords.count / 2
        guard count >= 2 else { return .infinity }

        let px = lon * cosLat
        let py = lat
        var bestSq = Double.infinity

        for i in 0..<count {
            let j = (i + 1) % count
            var x1 = coords[i * 2]
            var x2 = coords[j * 2]
            // Unwrap segment across antimeridian relative to query longitude
            if x1 - lon > 180 { x1 -= 360 } else if x1 - lon < -180 { x1 += 360 }
            if x2 - lon > 180 { x2 -= 360 } else if x2 - lon < -180 { x2 += 360 }

            let ax = x1 * cosLat
            let ay = coords[i * 2 + 1]
            let bx = x2 * cosLat
            let by = coords[j * 2 + 1]

            let dx = bx - ax
            let dy = by - ay
            let lenSq = dx * dx + dy * dy
            let distSq: Double
            if lenSq <= 1e-12 {
                let ex = px - ax
                let ey = py - ay
                distSq = ex * ex + ey * ey
            } else {
                let t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / lenSq))
                let ex = px - (ax + t * dx)
                let ey = py - (ay + t * dy)
                distSq = ex * ex + ey * ey
            }
            if distSq < bestSq {
                bestSq = distSq
            }
        }
        return sqrt(bestSq) * 111.32
    }
}
