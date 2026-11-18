import Combine
import Foundation

/// Versioned per-account defaults applied when opening a new photo comparison
/// in Photo ID (I3S) or Not Sure Review.
struct DesktopContourPreferences: Codable, Equatable {
    static let currentSchemaVersion = 1
    static let edgeThresholdRange: ClosedRange<Double> = 0.01...0.50
    static let overlayOpacityRange: ClosedRange<Double> = 0.20...1.00
    static let lineWeightRange: ClosedRange<Int> = 1...3

    static let factoryDefaults = DesktopContourPreferences()

    var schemaVersion: Int
    var showScaleNumbers: Bool
    var edgeThreshold: Double
    var overlayOpacity: Double
    var lineWeight: Int
    var reduceNoise: Bool

    init(
        schemaVersion: Int = DesktopContourPreferences.currentSchemaVersion,
        showScaleNumbers: Bool = true,
        edgeThreshold: Double = 0.08,
        overlayOpacity: Double = 0.95,
        lineWeight: Int = 2,
        reduceNoise: Bool = true
    ) {
        self.schemaVersion = schemaVersion
        self.showScaleNumbers = showScaleNumbers
        self.edgeThreshold = edgeThreshold
        self.overlayOpacity = overlayOpacity
        self.lineWeight = lineWeight
        self.reduceNoise = reduceNoise
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = (try? container.decodeIfPresent(Int.self, forKey: .schemaVersion)) ?? Self.currentSchemaVersion
        guard version == Self.currentSchemaVersion else {
            self = .factoryDefaults
            return
        }
        let defaults = Self.factoryDefaults
        let decoded = DesktopContourPreferences(
            schemaVersion: version,
            showScaleNumbers: (try? container.decodeIfPresent(Bool.self, forKey: .showScaleNumbers)) ?? defaults.showScaleNumbers,
            edgeThreshold: (try? container.decodeIfPresent(Double.self, forKey: .edgeThreshold)) ?? defaults.edgeThreshold,
            overlayOpacity: (try? container.decodeIfPresent(Double.self, forKey: .overlayOpacity)) ?? defaults.overlayOpacity,
            lineWeight: (try? container.decodeIfPresent(Int.self, forKey: .lineWeight)) ?? defaults.lineWeight,
            reduceNoise: (try? container.decodeIfPresent(Bool.self, forKey: .reduceNoise)) ?? defaults.reduceNoise
        )
        self = decoded.sanitized()
    }

    func sanitized() -> DesktopContourPreferences {
        let safeThreshold: Double
        if edgeThreshold.isFinite {
            safeThreshold = min(max(edgeThreshold, Self.edgeThresholdRange.lowerBound), Self.edgeThresholdRange.upperBound)
        } else {
            safeThreshold = Self.factoryDefaults.edgeThreshold
        }

        let safeOpacity: Double
        if overlayOpacity.isFinite {
            safeOpacity = min(max(overlayOpacity, Self.overlayOpacityRange.lowerBound), Self.overlayOpacityRange.upperBound)
        } else {
            safeOpacity = Self.factoryDefaults.overlayOpacity
        }

        let safeWeight = min(max(lineWeight, Self.lineWeightRange.lowerBound), Self.lineWeightRange.upperBound)

        return DesktopContourPreferences(
            schemaVersion: Self.currentSchemaVersion,
            showScaleNumbers: showScaleNumbers,
            edgeThreshold: (safeThreshold * 100).rounded() / 100,
            overlayOpacity: (safeOpacity * 100).rounded() / 100,
            lineWeight: safeWeight,
            reduceNoise: reduceNoise
        )
    }

    func makeContourSettings(
        enabled: Bool = false,
        querySide: TurtlePhotoSide = .left,
        gallerySide: TurtlePhotoSide = .left
    ) -> ContourSettings {
        let clean = sanitized()
        var settings = ContourSettings()
        settings.enabled = enabled
        settings.showNumbers = clean.showScaleNumbers
        settings.threshold = clean.edgeThreshold
        settings.opacity = clean.overlayOpacity
        settings.lineWeight = clean.lineWeight
        settings.reduceNoise = clean.reduceNoise
        settings.querySide = querySide
        settings.gallerySide = gallerySide
        return settings
    }
}

/// Persists `DesktopContourPreferences` per `(Mac account, backend URL, organisation)`
/// with a separate demo namespace so live and demo accounts never leak settings.
@MainActor
final class DesktopContourPreferencesStore: ObservableObject {
    static let storageKeyPrefix = "ada.desktop.contourPreferences.v1."

    @Published private(set) var preferences: DesktopContourPreferences = .factoryDefaults
    @Published private(set) var activeScopeKey: String = ""

    private let defaults: UserDefaults
    private var canPersist = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isFactoryDefault: Bool {
        preferences == .factoryDefaults
    }

    var summaryText: String {
        let opacityPct = Int((preferences.overlayOpacity * 100).rounded())
        return "\(String(format: "%.2f", preferences.edgeThreshold)) · \(opacityPct)%"
    }

    static func scopeKey(baseURLString: String, user: AppUser?, isDemo: Bool, demoPersonaKey: String) -> String {
        if isDemo {
            return "demo|\(demoPersonaKey.lowercased())"
        }
        guard let user, let orgID = user.organisationID else {
            return "signed-out|\(baseURLString.lowercased())"
        }
        return "live|\(baseURLString.lowercased())|\(orgID.uuidString.lowercased())|\(user.id.uuidString.lowercased())"
    }

    func configure(baseURLString: String, user: AppUser?, isDemo: Bool, demoPersonaKey: String) {
        let nextKey = Self.scopeKey(
            baseURLString: baseURLString,
            user: user,
            isDemo: isDemo,
            demoPersonaKey: demoPersonaKey
        )
        canPersist = isDemo || (user != nil && user?.organisationID != nil)
        activeScopeKey = nextKey
        preferences = load(for: nextKey)
    }

    func update(_ mutate: (inout DesktopContourPreferences) -> Void) {
        var next = preferences
        mutate(&next)
        let clean = next.sanitized()
        preferences = clean
        if canPersist && !activeScopeKey.isEmpty {
            save(clean, for: activeScopeKey)
        }
    }

    func resetDefaults() {
        preferences = .factoryDefaults
        if canPersist && !activeScopeKey.isEmpty {
            defaults.removeObject(forKey: Self.storageKeyPrefix + activeScopeKey)
        }
    }

    func makeContourSettings(
        enabled: Bool = false,
        querySide: TurtlePhotoSide = .left,
        gallerySide: TurtlePhotoSide = .left
    ) -> ContourSettings {
        preferences.makeContourSettings(enabled: enabled, querySide: querySide, gallerySide: gallerySide)
    }

    private func load(for scopeKey: String) -> DesktopContourPreferences {
        guard canPersist,
              let data = defaults.data(forKey: Self.storageKeyPrefix + scopeKey),
              let decoded = try? JSONDecoder().decode(DesktopContourPreferences.self, from: data) else {
            return .factoryDefaults
        }
        return decoded.sanitized()
    }

    private func save(_ value: DesktopContourPreferences, for scopeKey: String) {
        guard let data = try? JSONEncoder().encode(value.sanitized()) else { return }
        defaults.set(data, forKey: Self.storageKeyPrefix + scopeKey)
    }
}
