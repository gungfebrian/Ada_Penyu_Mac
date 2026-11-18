import XCTest
@testable import Ada_Penyu_Desktop

@MainActor
final class ContourPreferencesTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "ada.test.contourPreferences.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testFactoryDefaultsMatchPhotoContourControls() {
        let factory = DesktopContourPreferences.factoryDefaults
        XCTAssertTrue(factory.showScaleNumbers)
        XCTAssertEqual(factory.edgeThreshold, 0.08, accuracy: 0.0001)
        XCTAssertEqual(factory.overlayOpacity, 0.95, accuracy: 0.0001)
        XCTAssertEqual(factory.lineWeight, 2)
        XCTAssertTrue(factory.reduceNoise)

        let settings = factory.makeContourSettings(enabled: true, querySide: .right, gallerySide: .right)
        XCTAssertTrue(settings.enabled)
        XCTAssertTrue(settings.showNumbers)
        XCTAssertEqual(settings.threshold, 0.08, accuracy: 0.0001)
        XCTAssertEqual(settings.opacity, 0.95, accuracy: 0.0001)
        XCTAssertEqual(settings.lineWeight, 2)
        XCTAssertTrue(settings.reduceNoise)
        XCTAssertEqual(settings.querySide, .right)
        XCTAssertEqual(settings.gallerySide, .right)
    }

    func testPersistenceAcrossRelaunchAndResetDefaults() {
        let user = AppUser(
            id: UUID(uuidString: APIFixtures.userID)!,
            email: "owner@example.test",
            displayName: "Owner",
            role: .owner,
            organisationID: UUID(uuidString: APIFixtures.orgID)!,
            organisationName: "Bali Reef"
        )
        let store = DesktopContourPreferencesStore(defaults: defaults)
        store.configure(baseURLString: "https://api.donagondev.my.id", user: user, isDemo: false, demoPersonaKey: "demo")
        store.update {
            $0.showScaleNumbers = false
            $0.edgeThreshold = 0.15
            $0.overlayOpacity = 0.65
            $0.lineWeight = 3
            $0.reduceNoise = false
        }

        // Simulate app relaunch with the same defaults container & account
        let relaunched = DesktopContourPreferencesStore(defaults: defaults)
        relaunched.configure(baseURLString: "https://api.donagondev.my.id", user: user, isDemo: false, demoPersonaKey: "demo")
        XCTAssertFalse(relaunched.preferences.showScaleNumbers)
        XCTAssertEqual(relaunched.preferences.edgeThreshold, 0.15, accuracy: 0.0001)
        XCTAssertEqual(relaunched.preferences.overlayOpacity, 0.65, accuracy: 0.0001)
        XCTAssertEqual(relaunched.preferences.lineWeight, 3)
        XCTAssertFalse(relaunched.preferences.reduceNoise)
        XCTAssertFalse(relaunched.isFactoryDefault)

        // Open comparison snapshot remains unaffected by Reset Defaults
        let alreadyOpenComparison = relaunched.makeContourSettings(enabled: true)
        relaunched.resetDefaults()
        XCTAssertTrue(relaunched.isFactoryDefault)
        XCTAssertEqual(relaunched.preferences, .factoryDefaults)
        XCTAssertEqual(alreadyOpenComparison.threshold, 0.15, accuracy: 0.0001)
        XCTAssertFalse(alreadyOpenComparison.showNumbers)

        let reopenedComparison = relaunched.makeContourSettings(enabled: true)
        XCTAssertEqual(reopenedComparison.threshold, 0.08, accuracy: 0.0001)
        XCTAssertTrue(reopenedComparison.showNumbers)
    }

    func testMalformedUnknownVersionAndOutOfRangePreferencesSanitizeSafely() {
        let user = AppUser(
            id: UUID(uuidString: APIFixtures.userID)!,
            email: "owner@example.test",
            displayName: "Owner",
            role: .owner,
            organisationID: UUID(uuidString: APIFixtures.orgID)!,
            organisationName: "Bali Reef"
        )
        let scope = DesktopContourPreferencesStore.scopeKey(
            baseURLString: "https://api.donagondev.my.id",
            user: user,
            isDemo: false,
            demoPersonaKey: "demo"
        )
        let storageKey = DesktopContourPreferencesStore.storageKeyPrefix + scope

        // Malformed JSON -> factory defaults
        defaults.set(Data("{not json".utf8), forKey: storageKey)
        let malformedStore = DesktopContourPreferencesStore(defaults: defaults)
        malformedStore.configure(baseURLString: "https://api.donagondev.my.id", user: user, isDemo: false, demoPersonaKey: "demo")
        XCTAssertEqual(malformedStore.preferences, .factoryDefaults)

        // Unsupported schemaVersion -> factory defaults
        defaults.set(Data(#"{"schemaVersion":99,"showScaleNumbers":false,"edgeThreshold":0.4,"overlayOpacity":0.5,"lineWeight":1,"reduceNoise":false}"#.utf8), forKey: storageKey)
        let futureVersionStore = DesktopContourPreferencesStore(defaults: defaults)
        futureVersionStore.configure(baseURLString: "https://api.donagondev.my.id", user: user, isDemo: false, demoPersonaKey: "demo")
        XCTAssertEqual(futureVersionStore.preferences, .factoryDefaults)

        // Out-of-range values clamp cleanly into real Photo Contours bounds
        defaults.set(Data(#"{"schemaVersion":1,"showScaleNumbers":false,"edgeThreshold":9.5,"overlayOpacity":0.01,"lineWeight":99,"reduceNoise":false}"#.utf8), forKey: storageKey)
        let clampedStore = DesktopContourPreferencesStore(defaults: defaults)
        clampedStore.configure(baseURLString: "https://api.donagondev.my.id", user: user, isDemo: false, demoPersonaKey: "demo")
        XCTAssertFalse(clampedStore.preferences.showScaleNumbers)
        XCTAssertEqual(clampedStore.preferences.edgeThreshold, 0.50, accuracy: 0.0001)
        XCTAssertEqual(clampedStore.preferences.overlayOpacity, 0.20, accuracy: 0.0001)
        XCTAssertEqual(clampedStore.preferences.lineWeight, 3)
        XCTAssertFalse(clampedStore.preferences.reduceNoise)

        // NaN / Infinity sanitize to factory defaults
        let nonFinite = DesktopContourPreferences(
            showScaleNumbers: false,
            edgeThreshold: .nan,
            overlayOpacity: .infinity,
            lineWeight: -10,
            reduceNoise: false
        ).sanitized()
        XCTAssertEqual(nonFinite.edgeThreshold, 0.08, accuracy: 0.0001)
        XCTAssertEqual(nonFinite.overlayOpacity, 0.95, accuracy: 0.0001)
        XCTAssertEqual(nonFinite.lineWeight, 1)
    }

    func testAccountBackendOrganisationAndDemoIsolation() {
        let orgA = UUID(uuidString: APIFixtures.orgID)!
        let orgB = UUID(uuidString: "10000000-0000-4000-8000-000000000099")!
        let owner = AppUser(id: UUID(uuidString: APIFixtures.userID)!, email: "owner@example.test", displayName: "Owner", role: .owner, organisationID: orgA, organisationName: "Org A")
        let ranger = AppUser(id: UUID(uuidString: "20000000-0000-4000-8000-000000000002")!, email: "ranger@example.test", displayName: "Ranger", role: .ranger, organisationID: orgA, organisationName: "Org A")
        let ownerOtherOrg = AppUser(id: owner.id, email: owner.email, displayName: owner.displayName, role: .owner, organisationID: orgB, organisationName: "Org B")

        let store = DesktopContourPreferencesStore(defaults: defaults)

        // Owner on Server A saves custom preferences
        store.configure(baseURLString: "https://api.donagondev.my.id", user: owner, isDemo: false, demoPersonaKey: "demo-owner")
        store.update { $0.edgeThreshold = 0.22; $0.showScaleNumbers = false }

        // Ranger in same org starts at factory defaults
        store.configure(baseURLString: "https://api.donagondev.my.id", user: ranger, isDemo: false, demoPersonaKey: "demo-owner")
        XCTAssertEqual(store.preferences, .factoryDefaults)

        // Same owner on different backend starts at factory defaults
        store.configure(baseURLString: "https://staging.example.test", user: owner, isDemo: false, demoPersonaKey: "demo-owner")
        XCTAssertEqual(store.preferences, .factoryDefaults)

        // Same owner in different organisation starts at factory defaults
        store.configure(baseURLString: "https://api.donagondev.my.id", user: ownerOtherOrg, isDemo: false, demoPersonaKey: "demo-owner")
        XCTAssertEqual(store.preferences, .factoryDefaults)

        // Demo mode is isolated from live accounts and per persona
        store.configure(baseURLString: "https://api.donagondev.my.id", user: nil, isDemo: true, demoPersonaKey: "demo-asia")
        XCTAssertEqual(store.preferences, .factoryDefaults)
        store.update { $0.lineWeight = 1 }

        store.configure(baseURLString: "https://api.donagondev.my.id", user: nil, isDemo: true, demoPersonaKey: "demo-ranger")
        XCTAssertEqual(store.preferences, .factoryDefaults)

        // Returning to live owner restores owner's saved values untouched
        store.configure(baseURLString: "https://api.donagondev.my.id", user: owner, isDemo: false, demoPersonaKey: "demo-owner")
        XCTAssertEqual(store.preferences.edgeThreshold, 0.22, accuracy: 0.0001)
        XCTAssertFalse(store.preferences.showScaleNumbers)
        XCTAssertEqual(store.preferences.lineWeight, 2)
    }

    func testScaleNumberVisibilityDefaultNeverChangesConfirmedScaleCounts() {
        let scaleStore = ScaleReviewStore()
        let hash = "test-photo-hash"
        scaleStore.ensurePhoto(hash: hash, width: 100, height: 100)
        scaleStore.update(hash) { doc in
            doc.setHeadROI(ScaleRect(x: 0.05, y: 0.05, width: 0.9, height: 0.9))
            if let id = doc.add(
                polygon: [ScalePoint(x: 0.1, y: 0.1), ScalePoint(x: 0.3, y: 0.1), ScalePoint(x: 0.2, y: 0.3)],
                source: .manual
            ) {
                doc.setStatus(id, .confirmed)
            }
        }
        let confirmedBefore = scaleStore.documents[hash]?.confirmedCount
        XCTAssertEqual(confirmedBefore, 1)

        // Opening ScaleReviewComparisonView with initialShowsNumbers = false is display-only
        let _ = ScaleReviewComparisonView(
            queryImage: nil,
            galleryImage: nil,
            store: scaleStore,
            initialShowsNumbers: false
        )
        XCTAssertEqual(scaleStore.documents[hash]?.confirmedCount, 1)
    }
}
