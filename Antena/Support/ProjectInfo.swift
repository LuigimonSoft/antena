import Foundation

enum ProjectInfo {
    static let author = "Luigimonsoft"
    static let authorURL = URL(string: "https://github.com/luigimonsoft")!
    static let created = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 12))!
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—" }
}
