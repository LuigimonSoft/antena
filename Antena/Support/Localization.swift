import Foundation

/// English is the development language. The system preference list determines
/// the best supported translation unless the user chooses an app override.
enum L10n {
    static let preferenceKey = "interfaceLanguage"
    static let supportedLanguages = ["en", "es", "fr"]
    static func resolveLanguage(override: String?, preferredLanguages: [String]) -> String {
        if let override, supportedLanguages.contains(override) { return override }
        return Bundle.preferredLocalizations(from: supportedLanguages,
                                             forPreferences: preferredLanguages).first ?? "en"
    }
    // Resolve once per launch so menus, status messages and dialogs stay consistent.
    static let language = resolveLanguage(override: UserDefaults.standard.string(forKey: preferenceKey),
                                          preferredLanguages: Locale.preferredLanguages)
    static let locale = Locale(identifier: language)
    static func resourceBundle(language: String, in bundle: Bundle = .main) -> Bundle {
        guard let path = bundle.path(forResource: language, ofType: "lproj"),
              let localized = Bundle(path: path) else { return bundle }
        return localized
    }
    static func text(_ key: String) -> String {
        resourceBundle(language: language).localizedString(forKey: key, value: key, table: nil)
    }
    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: locale, arguments: arguments)
    }
}
