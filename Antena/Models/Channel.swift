import Foundation

struct Channel: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var number: String
    var name: String
    var language: String
    var frequency: UInt32
    var favorite: Bool = false
    var verified: Bool = false
    var tint: Int = 0
    var callSign: String?
    var logoURL: String?
    var logoAsset: String?
    var catalogCity: String?
    var sourceURL: String?
    var broadcastStandard: String?
    var countryID: String?
    var standardLabel: String? { broadcastStandard.map { $0 == "Unknown" ? L10n.text("Unknown") : $0 } }
    var canTune: Bool { frequency > 0 && (broadcastStandard == nil || broadcastStandard == "ATSC 1.0") }
    var receptionSummary: String {
        if !canTune {
            return frequency == 0 ? L10n.text("Frequency not confirmed") : L10n.text("Unsupported by this tuner")
        }
        return verified ? "ATSC · \(frequency / 1_000_000) MHz" : L10n.format("Unverified · %u MHz", frequency / 1_000_000)
    }
    var localizedLanguage: String {
        switch language {
        case "Français", "French", "fr": return L10n.text("French")
        case "English", "en": return L10n.text("English")
        case "Multilingue", "Multilingual": return L10n.text("Multilingual")
        default: return language
        }
    }
    var rf: Int? {
        if frequency >= 473_000_000 { return Int((frequency - 473_000_000) / 6_000_000) + 14 }
        if frequency >= 177_000_000 { return Int((frequency - 177_000_000) / 6_000_000) + 7 }
        return nil
    }
    static let montreal = [
        Channel(number: "2.1", name: "ICI Radio-Canada", language: "Français", frequency: 503_000_000, tint: 0, callSign: "CBFT-DT", logoAsset: "LogoCBFT", catalogCity: "Montréal", sourceURL: "https://en.wikipedia.org/wiki/CBFT-DT"),
        Channel(number: "6.1", name: "CBC Montréal", language: "English", frequency: 515_000_000, tint: 1, callSign: "CBMT-DT", logoAsset: "LogoCBMT", catalogCity: "Montréal", sourceURL: "https://en.wikipedia.org/wiki/CBMT-DT"),
        Channel(number: "10.1", name: "TVA Montréal", language: "Français", frequency: 201_000_000, tint: 2, callSign: "CFTM-DT", logoAsset: "LogoCFTM", catalogCity: "Montréal", sourceURL: "https://en.wikipedia.org/wiki/CFTM-DT"),
        Channel(number: "12.1", name: "CTV Montréal", language: "English", frequency: 207_000_000, tint: 3, callSign: "CFCF-DT", logoAsset: "LogoCFCF", catalogCity: "Montréal", sourceURL: "https://en.wikipedia.org/wiki/CFCF-DT"),
        Channel(number: "15.1", name: "Global Montréal", language: "English", frequency: 479_000_000, tint: 0, callSign: "CKMI-DT-1", logoAsset: "LogoCKMI", catalogCity: "Montréal", sourceURL: "https://en.wikipedia.org/wiki/CKMI-DT-1"),
        Channel(number: "17.1", name: "Télé-Québec", language: "Français", frequency: 545_000_000, tint: 1, callSign: "CIVM-DT", logoAsset: "LogoCIVM", catalogCity: "Montréal", sourceURL: "https://en.wikipedia.org/wiki/CIVM-DT"),
        Channel(number: "29.1", name: "Savoir média", language: "Français", frequency: 563_000_000, tint: 2, callSign: "CFTU-DT", logoAsset: "LogoCFTU", catalogCity: "Montréal", sourceURL: "https://en.wikipedia.org/wiki/CFTU-DT"),
        Channel(number: "35.1", name: "Noovo Montréal", language: "Français", frequency: 599_000_000, tint: 3, callSign: "CFJP-DT", logoAsset: "LogoCFJP", catalogCity: "Montréal", sourceURL: "https://en.wikipedia.org/wiki/CFJP-DT"),
        Channel(number: "47.1", name: "ICI Télé", language: "Multilingue", frequency: 575_000_000, tint: 0, callSign: "CFHD-DT", logoAsset: "LogoCFHD", catalogCity: "Montréal", sourceURL: "https://en.wikipedia.org/wiki/CFHD-DT"),
        Channel(number: "62.1", name: "Citytv Montréal", language: "English", frequency: 491_000_000, tint: 1, callSign: "CJNT-DT", logoAsset: "LogoCJNT", catalogCity: "Montréal", sourceURL: "https://en.wikipedia.org/wiki/CJNT-DT")
    ]
}
struct CaptionTrack: Identifiable, Equatable {
    var id: Int32
    var name: String
}
struct Recording: Identifiable, Codable {
    var id = UUID()
    var path: String
    var channel: String
    var started: Date
    var duration: TimeInterval
    var url: URL { URL(fileURLWithPath: path) }
}
