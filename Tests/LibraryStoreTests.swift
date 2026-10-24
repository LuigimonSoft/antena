import Foundation

@main struct LibraryStoreTests {
    @MainActor static func main() throws {
        let suite = "Antena.CatalogTest." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var legacy = Channel(number: "6.1", name: "CBC", language: "English", frequency: 515_000_000, favorite: true, verified: true)
        legacy.logoAsset = nil
        let manual = Channel(number: "99.1", name: "Canal personal", language: "ATSC", frequency: 581_000_000)
        defaults.set(try JSONEncoder().encode([legacy, manual]), forKey: "channels.v1")
        let store = LibraryStore(defaults: defaults)
        precondition(store.channels.count == 11)
        let migrated = store.channels.first { $0.callSign == "CBMT-DT" }!
        precondition(migrated.id == legacy.id && migrated.favorite && migrated.verified && migrated.logoAsset != nil)
        store.importChannels(Channel.montreal, city: "Montréal")
        store.importChannels(Channel.montreal, city: "Montréal")
        precondition(store.channels.count == 11)
        precondition(store.channels.first { $0.callSign == "CBMT-DT" }?.id == legacy.id)
        precondition(store.channels.contains { $0.id == manual.id })
        var changed = migrated; changed.frequency = 521_000_000
        store.importChannels([changed], city: "Ciudad de prueba")
        let updated = store.channels.first { $0.id == legacy.id }!
        precondition(updated.favorite && !updated.verified)
        let restored = LibraryStore(defaults: defaults)
        precondition(restored.city == "Ciudad de prueba" && restored.channels.count == 11)
        precondition(restored.channels.first { $0.id == legacy.id }?.frequency == 521_000_000)
        let savedCity = defaults.string(forKey: "catalog.city")
        let savedChannels = defaults.data(forKey: "channels.v1")
        let savedRecordings = defaults.data(forKey: "recordings.v1")
        let preview = LibraryStore(defaults: defaults, persistenceEnabled: false)
        precondition(preview.city == "Montréal" && preview.channels.count == 10 && preview.recordings.isEmpty)
        preview.city = "Preview only"
        preview.channels = []
        preview.recordings = [Recording(path: "/preview.ts", channel: "Test", started: Date(), duration: 10)]
        precondition(defaults.string(forKey: "catalog.city") == savedCity)
        precondition(defaults.data(forKey: "channels.v1") == savedChannels)
        precondition(defaults.data(forKey: "recordings.v1") == savedRecordings)
        let beforeWorld = store.channels.count
        let internationalA = Channel(number: "—", name: "Station A", language: "—", frequency: 0, catalogCity: "London", sourceURL: "https://example.org/a", broadcastStandard: "DVB-T")
        let internationalB = Channel(number: "—", name: "Station B", language: "—", frequency: 0, catalogCity: "London", sourceURL: "https://example.org/b", broadcastStandard: "Unknown")
        store.importChannels([internationalA, internationalB], city: "London")
        store.importChannels([internationalA, internationalB], city: "London")
        precondition(store.channels.count == beforeWorld + 2, "Unknown channel numbers must not merge unrelated stations")
        precondition(!internationalA.canTune && !internationalB.canTune)
        let recordingFolder = FileManager.default.temporaryDirectory.appendingPathComponent("AntenaLibrary-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: recordingFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: recordingFolder) }
        let kept = recordingFolder.appendingPathComponent("kept.ts")
        try Data([0x47]).write(to: kept)
        let existingRecording = Recording(path: kept.path, channel: "Existing", started: Date(), duration: 1)
        store.recordings = [existingRecording, Recording(path: recordingFolder.appendingPathComponent("missing.ts").path, channel: "Missing", started: Date(), duration: 1)]
        store.removeMissingRecordings()
        precondition(store.recordings.map(\.id) == [existingRecording.id])
        precondition(FileManager.default.fileExists(atPath: kept.path), "Library cleanup must not delete video files")
        precondition(LibraryStore(defaults: defaults).recordings.map(\.id) == [existingRecording.id], "Missing-file cleanup must persist")
        print("PASS: missing recordings removed and persisted; existing video retained")
        print("PASS: preview data is isolated from saved preferences")
        print("PASS: legacy migration, stable IDs, favorites, no duplicates, manual channels, RF changes, persistence")
    }
}
