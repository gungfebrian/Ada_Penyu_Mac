import XCTest
@testable import Ada_Penyu_Desktop

@MainActor
final class PreferencesPermissionsTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "ada.test.localization.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testLanguagePersistsAcrossRestartAndHandlesMalformedStorage() {
        let initial = LocalizationManager(defaults: defaults, fallbackLocale: Locale(identifier: "en_US"))
        XCTAssertEqual(initial.language, .en)

        initial.language = .id
        let relaunched = LocalizationManager(defaults: defaults, fallbackLocale: Locale(identifier: "en_US"))
        XCTAssertEqual(relaunched.language, .id)
        XCTAssertEqual(relaunched.locale.identifier, "id")

        defaults.set("invalid-code", forKey: LocalizationManager.storageKey)
        let fallback = LocalizationManager(defaults: defaults, fallbackLocale: Locale(identifier: "en_US"))
        XCTAssertEqual(fallback.language, .en)
    }

    func testBundledStringsTranslateSettingsLoginAndNavigationInBahasaIndonesia() {
        let appBundle = Bundle(for: AppStore.self)
        let manager = LocalizationManager(defaults: defaults, bundle: appBundle, fallbackLocale: Locale(identifier: "en_US"))

        manager.language = .en
        XCTAssertEqual(manager.localized("Settings"), "Settings")
        XCTAssertEqual(manager.localized("Password & Security"), "Password & Security")
        XCTAssertEqual(manager.localized("Organisation Profile"), "Organisation Profile")
        XCTAssertEqual(manager.localized("Manage Rangers"), "Manage Rangers")
        XCTAssertEqual(manager.localized("Sign in"), "Sign in")

        manager.language = .id
        XCTAssertEqual(manager.localized("Settings"), "Pengaturan")
        XCTAssertEqual(manager.localized("Password & Security"), "Kata Sandi & Keamanan")
        XCTAssertEqual(manager.localized("Organisation Profile"), "Profil Organisasi")
        XCTAssertEqual(manager.localized("Manage Rangers"), "Kelola Ranger")
        XCTAssertEqual(manager.localized("Preferences & Permissions"), "Preferensi & Izin")
        XCTAssertEqual(manager.localized("Language"), "Bahasa")
        XCTAssertEqual(manager.localized("App Permissions"), "Izin Aplikasi")
        XCTAssertEqual(manager.localized("Contour Review"), "Tinjauan Kontur")
        XCTAssertEqual(manager.localized("Support"), "Dukungan")
        XCTAssertEqual(manager.localized("Log out"), "Keluar")
        XCTAssertEqual(manager.localized("Sign in"), "Masuk")
        XCTAssertEqual(manager.localized("Overview"), "Ringkasan")
        XCTAssertEqual(manager.localized("Map"), "Peta")
        XCTAssertEqual(manager.localized("Sea Turtles"), "Penyu Laut")
    }

    func testAccountMenuRespectsSelectedLanguage() {
        let appBundle = Bundle(for: AppStore.self)
        let manager = LocalizationManager(defaults: defaults, bundle: appBundle, fallbackLocale: Locale(identifier: "en_US"))
        manager.language = .id

        let menuModel = SidebarAccountMenuModel()
        menuModel.onOpenProductSettings = {}
        menuModel.onSignOut = {}
        menuModel.localize = { manager.localized($0) }

        let titles = menuModel.makeMenu().items.map(\.title)
        XCTAssertTrue(titles.contains("Pengaturan…"), "\(titles)")
        XCTAssertTrue(titles.contains("Keluar"), "\(titles)")
    }

    func testFilesAndFoldersSystemSettingsURLTargetsMacPrivacyPanel() {
        XCTAssertEqual(
            MacSystemSettingsPanel.filesAndFoldersURL.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders"
        )
    }
}
