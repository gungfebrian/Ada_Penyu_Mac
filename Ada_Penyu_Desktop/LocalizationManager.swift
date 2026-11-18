import Combine
import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case en
    case id

    var id: String { rawValue }
    var locale: Locale { Locale(identifier: rawValue) }

    var displayName: String {
        switch self {
        case .en: "English"
        case .id: "Bahasa Indonesia"
        }
    }
}

/// Owns the local display language on this Mac, matching AdaPenyu iPhone's
/// `LocalizationManager` storage key and `.lproj` bundle resolution.
@MainActor
final class LocalizationManager: ObservableObject {
    static let storageKey = "ADAAppLanguage"

    @Published var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: Self.storageKey)
        }
    }

    private let defaults: UserDefaults
    private let baseBundle: Bundle

    init(defaults: UserDefaults = .standard, bundle: Bundle = .main, fallbackLocale: Locale = .current) {
        self.defaults = defaults
        self.baseBundle = bundle
        if let stored = defaults.string(forKey: Self.storageKey),
           let parsed = AppLanguage(rawValue: stored) {
            self.language = parsed
        } else {
            self.language = Self.defaultLanguage(for: fallbackLocale)
        }
    }

    var locale: Locale { language.locale }

    var localizedBundle: Bundle {
        if let path = baseBundle.path(forResource: language.rawValue, ofType: "lproj"),
           let resolved = Bundle(path: path) {
            return resolved
        }
        return baseBundle
    }

    func localized(_ key: String) -> String {
        localizedBundle.localizedString(forKey: key, value: key, table: nil)
    }

    private static func defaultLanguage(for locale: Locale) -> AppLanguage {
        let code = locale.language.languageCode?.identifier.lowercased()
        return code == "id" ? .id : .en
    }
}
