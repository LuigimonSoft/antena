import Foundation
import Combine

@MainActor
final class LibraryStore: ObservableObject {
    private let defaults: UserDefaults
    private let persistenceEnabled: Bool
    @Published var city: String { didSet { if persistenceEnabled { defaults.set(city, forKey: "catalog.city") } } }
    @Published var channels: [Channel] { didSet { save(channels, key: "channels.v1") } }
    @Published var recordings: [Recording] { didSet { save(recordings, key: "recordings.v1") } }
    init(defaults: UserDefaults = .standard, persistenceEnabled: Bool = true) {
        self.defaults = defaults
        self.persistenceEnabled = persistenceEnabled
        if !persistenceEnabled {
            city = "Montréal"
            channels = Channel.montreal
            recordings = []
            return
        }
        city = defaults.string(forKey: "catalog.city") ?? "Montréal"
        channels = Self.load([Channel].self, key: "channels.v1", defaults: defaults) ?? Channel.montreal
        recordings = Self.load([Recording].self, key: "recordings.v1", defaults: defaults) ?? []
        if !defaults.bool(forKey: "catalog.montreal.v2") {
            importChannels(Channel.montreal, city: "Montréal")
            defaults.set(true, forKey: "catalog.montreal.v2")
        }
    }
    func importChannels(_ incoming: [Channel], city: String) {
        var updated = channels
        for var channel in incoming {
            if let index = updated.firstIndex(where: {
                ($0.callSign != nil && $0.callSign == channel.callSign) ||
                ($0.sourceURL != nil && $0.sourceURL == channel.sourceURL) ||
                ($0.frequency > 0 && $0.number == channel.number && $0.frequency == channel.frequency && ($0.catalogCity == channel.catalogCity || $0.catalogCity == nil))
            }) {
                let old = updated[index]
                channel.id = old.id
                channel.favorite = old.favorite
                channel.verified = old.verified && old.frequency == channel.frequency && old.broadcastStandard == channel.broadcastStandard
                channel.logoURL = channel.logoURL ?? old.logoURL
                updated[index] = channel
            } else { updated.append(channel) }
        }
        channels = updated.sorted { $0.number.localizedStandardCompare($1.number) == .orderedAscending }
        self.city = city
    }
    private static func load<T: Decodable>(_ type: T.Type, key: String, defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    private func save<T: Encodable>(_ value: T, key: String) {
        guard persistenceEnabled else { return }
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }
    func removeMissingRecordings() {
        let remaining = recordings.filter { recording in
            do {
                _ = try FileManager.default.attributesOfItem(atPath: recording.path)
                return true
            } catch {
                let issue = error as NSError
                let missing = (issue.domain == NSCocoaErrorDomain && [CocoaError.Code.fileNoSuchFile.rawValue, CocoaError.Code.fileReadNoSuchFile.rawValue].contains(issue.code)) ||
                    (issue.domain == NSPOSIXErrorDomain && issue.code == Int(ENOENT))
                return !missing
            }
        }
        if remaining.map(\.id) != recordings.map(\.id) { recordings = remaining }
    }
    func toggleFavorite(_ channel: Channel) {
        guard let i = channels.firstIndex(where: { $0.id == channel.id }) else { return }
        channels[i].favorite.toggle()
    }
    func markVerified(_ channel: Channel) {
        guard let i = channels.firstIndex(where: { $0.id == channel.id }), channels[i].canTune, !channels[i].verified else { return }
        channels[i].verified = true
    }
}
