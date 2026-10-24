import AppKit

/// libVLC lifecycle is serialized; the C ring independently accepts USB data.
final class PlaybackEngine: @unchecked Sendable {
    let pointer: OpaquePointer
    private let queue = DispatchQueue(label: "Antena.decoder", qos: .userInitiated)
    private var view: NSView?
    init() throws {
        let runtime = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/VLC").path
        guard let p = ant_player_create(runtime) else {
            throw NSError(domain: "Antena", code: 1, userInfo: [NSLocalizedDescriptionKey: L10n.text("Unable to start the video engine.")])
        }
        pointer = p
    }
    @MainActor func attach(_ view: NSView) {
        self.view = view
        ant_player_set_view(pointer, Unmanaged.passUnretained(view).toOpaque())
    }
    func live() async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: ant_player_live(self.pointer) == 0) }
        }
    }
    func file(_ url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: ant_player_file(self.pointer, url.path) == 0) }
        }
    }
    func feed(_ data: Data) {
        data.withUnsafeBytes { bytes in
            if let base = bytes.baseAddress { ant_player_feed(pointer, base, bytes.count) }
        }
    }
    func endInput() { ant_player_end_input(pointer) }
    func stop() async {
        endInput()
        await withCheckedContinuation { continuation in
            queue.async { ant_player_stop(self.pointer); continuation.resume() }
        }
    }
    func stats() async -> AntenaPlayerStats {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: ant_player_stats(self.pointer)) }
        }
    }
    func captions() async -> [CaptionTrack] {
        await withCheckedContinuation { continuation in
            queue.async {
                var tracks = [AntenaTrack](repeating: AntenaTrack(), count: 32)
                let count = Int(ant_player_subtitles(self.pointer, &tracks, 32))
                let result = tracks.prefix(count).map { track -> CaptionTrack in
                    var name = track.name
                    let text = withUnsafePointer(to: &name) {
                        $0.withMemoryRebound(to: CChar.self, capacity: 160) { String(cString: $0) }
                    }
                    return CaptionTrack(id: track.id, name: text)
                }
                continuation.resume(returning: result)
            }
        }
    }
    func selectCaption(_ id: Int32) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: ant_player_set_subtitle(self.pointer, id) == 0) }
        }
    }
    func volume(_ value: Int32) { queue.async { ant_player_volume(self.pointer, value) } }
    // App-scoped engine intentionally lives until process termination. stop() wakes
    // any blocked callback before releasing a media; Cocoa view outlives playback.
}
