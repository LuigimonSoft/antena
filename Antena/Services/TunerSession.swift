import AppKit
import Combine

private final class StreamGate: @unchecked Sendable {
    private let lock = NSLock()
    private var active = true
    let engine: PlaybackEngine
    let recorder: RecordingWriter
    let guide = ProgramGuideDecoder(language: L10n.language)
    init(engine: PlaybackEngine, recorder: RecordingWriter) { self.engine = engine; self.recorder = recorder }
    func consume(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        guard active else { return }
        engine.feed(data); recorder.append(data); guide.feed(data)
    }
    func cancel() { lock.lock(); active = false; lock.unlock() }
}

@MainActor
final class TunerSession: ObservableObject {
    enum Phase: Equatable { case stopped, tuning, buffering, playing, failed }
    @Published var phase: Phase = .stopped
    @Published var current: Channel?
    @Published var previous: Channel?
    @Published var error: String?
    @Published var detail = L10n.text("Connect your tuner and antenna.")
    @Published var captions: [CaptionTrack] = []
    @Published var selectedCaption: Int32 = -1
    @Published var volume: Double = 80 { didSet { engine?.volume(Int32(muted ? 0 : volume)) } }
    @Published var muted = false { didSet { engine?.volume(Int32(muted ? 0 : volume)) } }
    @Published var activeRecording: Recording?
    @Published var recordingSeconds: Int = 0
    @Published var playbackFile: URL?
    @Published var videoSize = ""
    @Published var decodedFrames = 0
    @Published var receivedBytes: UInt64 = 0
    @Published var scanning = false
    @Published var scanProgress = ""
    @Published var guidePrograms: [BroadcastProgram] = []
    @Published var guideCollecting = false
    @Published var guideDetailsPresented = false
    @Published var toast: String?
    let isPreview: Bool
    let library: LibraryStore
    private(set) var engine: PlaybackEngine?
    private let recorder = RecordingWriter()
    private var process: Process?
    private var gate: StreamGate?
    private var transition: Task<Void, Never>?
    private var monitor: Task<Void, Never>?
    private var scanTask: Task<Void, Never>?
    private var generation = UUID()
    private var started = false
    private var logTail = ""
    private var tuneStarted = Date()
    private var closing = false
    var isRecording: Bool { activeRecording != nil }
    var isLive: Bool { playbackFile == nil && current != nil }

    init(library: LibraryStore, preview: Bool = PreviewEnvironment.isActive) {
        self.library = library
        self.isPreview = preview
        if preview {
            current = library.channels.first
            phase = .playing
            videoSize = "1280 × 720"
            detail = L10n.text("Preview · 1280 × 720")
            captions = [CaptionTrack(id: 3, name: "Français"), CaptionTrack(id: 4, name: "English")]
            return
        }
        do { engine = try PlaybackEngine() }
        catch { self.error = error.localizedDescription; phase = .failed }
    }
    func attach(_ view: NSView) { engine?.attach(view) }
    func start() {
        guard !isPreview else { return }
        guard !started else { return }; started = true
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { break }
                await self.refresh()
            }
        }
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--sample"), index + 1 < arguments.count {
            let url = URL(fileURLWithPath: arguments[index + 1])
            playRecording(Recording(path: url.path, channel: L10n.text("Recording"), started: Date(), duration: 0))
        } else if let first = library.channels.first(where: \.canTune) { choose(first) }
    }
    func choose(_ channel: Channel) {
        if isPreview {
            previous = current; current = channel; phase = .playing
            return
        }
        guard channel.canTune else { toast = L10n.text("This station cannot be tuned with the current receiver and frequency information."); return }
        guard !scanning else { return }
        let prior = transition
        prior?.cancel()
        if current?.id != channel.id { previous = current }
        current = channel; playbackFile = nil; phase = .tuning; error = nil
        guidePrograms = []; guideCollecting = true
        detail = L10n.format("Tuning %@ · %u MHz…", channel.number, channel.frequency / 1_000_000)
        transition = Task { [weak self] in
            await prior?.value
            guard let self, !Task.isCancelled else { return }
            await self.stopSource()
            guard !Task.isCancelled, let engine = self.engine else { return }
            self.phase = .tuning; self.tuneStarted = Date()
            let token = UUID(); self.generation = token
            guard await engine.live(), !Task.isCancelled else { return }
            engine.volume(Int32(self.muted ? 0 : self.volume))
            self.launch(channel, token: token)
        }
    }
    func change(_ delta: Int) {
        let channels = library.channels.filter(\.canTune)
        guard !channels.isEmpty else { return }
        let i = channels.firstIndex(where: { $0.id == current?.id }) ?? 0
        choose(channels[(i + delta + channels.count) % channels.count])
    }
    func lastChannel() { if let previous { choose(previous) } }
    func retry() { if let current { choose(current) } else { start() } }
    private var helper: URL? { Bundle.main.url(forAuxiliaryExecutable: "kworld-tv") }
    private func launch(_ channel: Channel, token: UUID) {
        guard let engine, let helper, let resource = Bundle.main.resourceURL else {
            fail(L10n.text("The bundled tuner driver is missing.")); return
        }
        let child = Process(), output = Pipe(), diagnostic = Pipe()
        child.executableURL = helper; child.currentDirectoryURL = resource
        child.arguments = ["--stream", String(channel.frequency)]
        child.standardOutput = output; child.standardError = diagnostic
        let stream = StreamGate(engine: engine, recorder: recorder)
        gate = stream; process = child; logTail = ""
        diagnostic.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.logTail = String((self.logTail + text).suffix(4000))
                if text.contains("DEMOD LOCK") { self.phase = .buffering; self.detail = L10n.text("Signal received · opening video…") }
            }
        }
        child.terminationHandler = { [weak self] child in
            diagnostic.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.engine?.endInput()
                if child.terminationStatus != 0 { self.fail(self.friendlyError()) }
                else if self.phase != .stopped { self.fail(L10n.text("The broadcast was interrupted. Try reconnecting to the channel.")) }
            }
        }
        do {
            try child.run()
            DispatchQueue.global(qos: .userInitiated).async {
                let handle = output.fileHandleForReading
                defer { try? handle.close() }
                while let data = try? handle.read(upToCount: 32768), !data.isEmpty { stream.consume(data) }
            }
        } catch { fail(error.localizedDescription); process = nil }
    }
    private func friendlyError() -> String {
        if logTail.contains("not connected") { return L10n.text("KWorld tuner not found. Connect the USB tuner and try again.") }
        if logTail.contains("No ATSC lock") { return L10n.text("The signal is too weak on this channel. Check the antenna or try another channel.") }
        if logTail.contains("exclusive") || logTail.contains("resource shortage") || logTail.contains("USBDeviceOpen") {
            return L10n.text("Unable to open the tuner. Close other apps using it and reconnect it.")
        }
        if logTail.contains("firmware") && !logTail.contains("XC tuner model") { return L10n.text("Unable to load the tuner firmware.") }
        return L10n.text("The tuner connection was lost. Check the USB connection and try again.")
    }
    private func fail(_ message: String) {
        phase = .failed; error = message; detail = message
        finishRecording()
    }
    private func stopSource() async {
        generation = UUID(); gate?.cancel(); gate = nil
        guidePrograms = []; guideCollecting = false
        finishRecording(); engine?.endInput()
        let old = process; process = nil
        if let old, old.isRunning {
            old.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 8) {
                if old.isRunning { kill(old.processIdentifier, SIGKILL) }
            }
            await Task.detached { old.waitUntilExit() }.value
        }
        await engine?.stop()
        captions = []; selectedCaption = -1; videoSize = ""; receivedBytes = 0; decodedFrames = 0
    }
    private func refresh() async {
        guard let engine else { return }
        let token = generation
        let stats = await engine.stats()
        guard generation == token else { return }
        decodedFrames = Int(stats.decodedVideo); receivedBytes = stats.receivedBytes
        if stats.width > 0 { videoSize = "\(stats.width) × \(stats.height)" }
        if stats.displayedVideo > 0 && phase != .failed && phase != .stopped {
            phase = .playing
            detail = playbackFile == nil ? L10n.format("Live · %@", videoSize) : L10n.format("Playing recording · %@", videoSize)
            if let current, playbackFile == nil { library.markVerified(current) }
        }
        if stats.state == 7 && phase != .failed { fail(L10n.text("Unable to decode the broadcast. Reconnect to the channel.")) }
        if [.tuning, .buffering].contains(phase), Date().timeIntervalSince(tuneStarted) > 18 {
            fail(L10n.text("No video was received. Check the antenna and try again."))
        }
        let tracks = await engine.captions()
        guard generation == token else { return }
        if captions != tracks { captions = tracks }
        if let recording = activeRecording { recordingSeconds = Int(Date().timeIntervalSince(recording.started)) }
        if let issue = recorder.takeFailure() {
            finishRecording(); toast = L10n.format("Recording stopped: %@", issue)
        }
        let guide = gate?.guide.snapshot(channelNumber: current?.number ?? "") ?? ProgramGuideSnapshot()
        if guidePrograms != guide.programs { guidePrograms = guide.programs }
        guideCollecting = isLive && guide.programs.isEmpty && Date().timeIntervalSince(tuneStarted) < 25
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--diagnostics"), index + 1 < arguments.count {
            let report: [String: Any] = ["phase": String(describing: phase), "decodedVideo": stats.decodedVideo,
                "displayedVideo": stats.displayedVideo, "decodedAudio": stats.decodedAudio,
                "playedAudio": stats.playedAudio, "receivedBytes": stats.receivedBytes,
                "droppedBytes": stats.droppedBytes, "width": stats.width, "height": stats.height,
                "captions": captions.map { ["id": $0.id, "name": $0.name] as [String: Any] },
                "recording": isRecording, "error": error ?? "",
                "guide": ["tables": guide.tableCounts, "sources": guide.sourceCount, "hasClock": guide.hasClock,
                    "unsupportedTitles": guide.unsupportedTitles, "crcErrors": guide.crcErrors,
                    "programs": guide.programs.map { ["title": $0.title ?? "", "start": $0.start.timeIntervalSince1970, "end": $0.end.timeIntervalSince1970] as [String: Any] }] as [String: Any]]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: URL(fileURLWithPath: arguments[index + 1]), options: .atomic)
            }
        }
        if ProcessInfo.processInfo.environment["ANTENA_DIAGNOSTIC"] == "1" {
            NSLog("ANTENA frames=%d displayed=%d audio=%d played=%d bytes=%llu dropped=%llu", stats.decodedVideo, stats.displayedVideo, stats.decodedAudio, stats.playedAudio, stats.receivedBytes, stats.droppedBytes)
        }
    }
    func selectCaption(_ id: Int32) {
        if isPreview { selectedCaption = id; return }
        Task {
            if await engine?.selectCaption(id) == true { selectedCaption = id }
            else { toast = L10n.text("The caption track is unavailable.") }
        }
    }
    func toggleCaptions() {
        if selectedCaption >= 0 { selectCaption(-1) }
        else if let first = captions.first { selectCaption(first.id) }
        else { toast = L10n.text("This broadcast does not offer a caption track yet.") }
    }
    func openRecording() {
        guard !isPreview else { return }
        let panel = NSOpenPanel()
        panel.title = L10n.text("Open recording")
        panel.allowedContentTypes = [.init(filenameExtension: "ts") ?? .data, .movie]
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self?.playRecording(Recording(path: url.path, channel: url.deletingPathExtension().lastPathComponent, started: Date(), duration: 0))
            }
        }
    }
    func toggleRecording() {
        guard !isPreview else { return }
        if isRecording { finishRecording(); return }
        guard phase == .playing, isLive, let current else { return }
        let panel = NSSavePanel()
        panel.title = L10n.text("Save recording")
        panel.nameFieldStringValue = "\(current.name)-\(Date().formatted(.iso8601).replacingOccurrences(of: ":", with: "-" )).ts"
        panel.allowedContentTypes = [.init(filenameExtension: "ts") ?? .data]
        panel.canCreateDirectories = true
        if let folder = UserDefaults.standard.string(forKey: "recordingDirectory") { panel.directoryURL = URL(fileURLWithPath: folder) }
        let selected = current.id
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                guard let self, self.current?.id == selected, self.phase == .playing, self.isLive else { return }
                do {
                    try self.recorder.start(url)
                    self.activeRecording = Recording(path: url.path, channel: current.name, started: Date(), duration: 0)
                    self.recordingSeconds = 0
                    UserDefaults.standard.set(url.deletingLastPathComponent().path, forKey: "recordingDirectory")
                } catch { self.toast = L10n.format("Unable to create recording: %@", error.localizedDescription) }
            }
        }
    }
    func finishRecording() {
        guard var recording = activeRecording else { return }
        let issue = recorder.stop()
        recording.duration = Date().timeIntervalSince(recording.started)
        library.recordings.insert(recording, at: 0)
        activeRecording = nil
        toast = issue.map { L10n.format("Save error: %@", $0) } ?? L10n.format("Recording saved: %@", recording.url.lastPathComponent)
    }
    func playRecording(_ recording: Recording) {
        guard !isPreview else { return }
        guard FileManager.default.fileExists(atPath: recording.path) else { library.removeMissingRecordings(); toast = L10n.text("The file was not found. It may have been moved."); return }
        let prior = transition; prior?.cancel()
        transition = Task {
            await prior?.value; guard !Task.isCancelled else { return }
            await stopSource(); guard !Task.isCancelled else { return }
            playbackFile = recording.url; phase = .buffering; error = nil; tuneStarted = Date()
            if await engine?.file(recording.url) != true { fail(L10n.text("Unable to open the recording.")) }
        }
    }
    func scan() {
        guard !isPreview else { return }
        guard !scanning else { return }
        scanning = true; error = nil
        scanTask = Task {
            transition?.cancel(); await transition?.value
            await stopSource(); phase = .stopped
            let saved = current
            for rf in 2...36 {
                if Task.isCancelled { break }
                scanProgress = L10n.format("Scanning RF %d of 36…", rf)
                let hz: UInt32
                switch rf {
                case 2...4: hz = UInt32(57 + (rf-2)*6)*1_000_000
                case 5...6: hz = UInt32(79 + (rf-5)*6)*1_000_000
                case 7...13: hz = UInt32(177 + (rf-7)*6)*1_000_000
                default: hz = UInt32(473 + (rf-14)*6)*1_000_000
                }
                guard let helper, let resource = Bundle.main.resourceURL else { break }
                let child = Process(), pipe = Pipe()
                child.executableURL = helper; child.currentDirectoryURL = resource
                child.arguments = ["--tune", String(hz)]
                child.standardOutput = pipe; child.standardError = pipe
                do { try child.run() } catch { toast = error.localizedDescription; break }
                process = child
                let data = await Task.detached { pipe.fileHandleForReading.readDataToEndOfFile() }.value
                await Task.detached { child.waitUntilExit() }.value
                process = nil
                if Task.isCancelled { break }
                if child.terminationStatus == 0, String(data: data, encoding: .utf8)?.contains("DEMOD LOCK") == true {
                    if let index = library.channels.firstIndex(where: { $0.frequency == hz && $0.canTune }) {
                        library.channels[index].verified = true
                    } else {
                        library.channels.append(Channel(number: "RF \(rf)", name: L10n.format("RF channel %d", rf), language: "ATSC", frequency: hz, verified: true, tint: rf % 4))
                    }
                }
            }
            scanning = false; scanProgress = ""
            if !closing, let saved { choose(saved) }
        }
    }
    func cancelScan() {
        scanTask?.cancel()
        if let process, process.isRunning { process.terminate() }
    }
    func shutdown() async {
        closing = true
        monitor?.cancel(); scanTask?.cancel(); transition?.cancel()
        if scanning, let process, process.isRunning { process.terminate() }
        await scanTask?.value; await transition?.value; await stopSource(); phase = .stopped
    }
}
