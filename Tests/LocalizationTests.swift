import Foundation

@main struct LocalizationTests {
    static func main() throws {
        precondition(L10n.resolveLanguage(override: nil, preferredLanguages: ["en-CA"]) == "en")
        precondition(L10n.resolveLanguage(override: "system", preferredLanguages: ["es-MX", "en"]) == "es")
        precondition(L10n.resolveLanguage(override: nil, preferredLanguages: ["fr-CA", "en-CA"]) == "fr")
        precondition(L10n.resolveLanguage(override: nil, preferredLanguages: ["de-DE"]) == "en")
        precondition(L10n.resolveLanguage(override: nil, preferredLanguages: ["de-DE", "fr-CA"]) == "fr")
        precondition(L10n.resolveLanguage(override: "en", preferredLanguages: ["es"]) == "en")
        precondition(L10n.resolveLanguage(override: "es", preferredLanguages: ["fr"]) == "es")
        precondition(L10n.resolveLanguage(override: "fr", preferredLanguages: ["en"]) == "fr")
        let resources = URL(fileURLWithPath: CommandLine.arguments[1])
        var baseline: Set<String>?
        for language in L10n.supportedLanguages {
            let url = resources.appendingPathComponent("\(language).lproj/Localizable.strings")
            let data = try Data(contentsOf: url)
            let values = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: String]
            let keys = Set(values.keys)
            if let baseline { precondition(keys == baseline) } else { baseline = keys }
            for (key, value) in values {
                precondition(!value.isEmpty)
                let pattern = "%[@ud]"
                func placeholders(_ text: String) -> [String] {
                    let regex = try! NSRegularExpression(pattern: pattern)
                    return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map {
                        String(text[Range($0.range, in: text)!])
                    }
                }
                precondition(placeholders(key) == placeholders(value), "Invalid placeholders: \(language): \(key)")
            }
            let bundle = L10n.resourceBundle(language: language, in: Bundle(path: resources.deletingLastPathComponent().path)!)
            precondition(bundle.localizedString(forKey: "Your channels", value: nil, table: nil) == values["Your channels"])
        }
        print("PASS: system language matching, regional variants, overrides, English fallback, bundled translations and format arguments")
    }
}
