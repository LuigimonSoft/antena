import Foundation

/// ATSC A/65 PSIP reader. Only metadata PIDs are assembled; video is never stored.
/// Each decoder belongs to one tuned transport. A new tune creates a new decoder.
final class ProgramGuideDecoder: @unchecked Sendable {
    private struct RawEvent {
        var id: Int
        var gpsStart: UInt32
        var duration: Int
        var title: String?
    }
    private struct EventSection {
        var pid: Int
        var source: Int
        var version: Int
        var lastSection: Int
        var data: [UInt8]
        var events: [RawEvent]
    }
    private let lock = NSLock()
    private var pending: [UInt8] = []
    private var watched: Set<Int> = [0x1ffb]
    private var buffers: [Int: [UInt8]] = [:]
    private var previous: [Int: (counter: Int, packet: [UInt8])] = [:]
    private var sources: [String: Int] = [:]
    private var vctVersion: Int?
    private var eventSections: [String: EventSection] = [:]
    private var gpsOffset: Int?
    private var counts: [String: Int] = [:]
    private var crcErrors = 0
    private var unsupportedTitles = 0
    private let preferredLanguage: String
    init(language: String = "en") { preferredLanguage = language }

    func feed(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        pending.append(contentsOf: data)
        var offset = 0
        while offset + 188 <= pending.count {
            if pending[offset] != 0x47 { offset += 1; continue }
            let pid = Int(pending[offset + 1] & 31) << 8 | Int(pending[offset + 2])
            if watched.contains(pid) { packet(Array(pending[offset..<offset + 188]), pid: pid) }
            offset += 188
        }
        pending = Array(pending.dropFirst(offset)) // At most 187 residual bytes.
    }
    func snapshot(channelNumber: String, at now: Date = Date()) -> ProgramGuideSnapshot {
        lock.lock(); defer { lock.unlock() }
        var result = ProgramGuideSnapshot(hasClock: gpsOffset != nil, tableCounts: counts,
            sourceCount: sources.count, unsupportedTitles: unsupportedTitles, crcErrors: crcErrors)
        // Never guess source identity or the GPS/UTC offset.
        guard let source = sources[channelNumber], let gpsOffset else { return result }
        var unique: [String: BroadcastProgram] = [:]
        for section in eventSections.values where section.source == source {
            for raw in section.events {
                let start = Date(timeIntervalSince1970: Double(raw.gpsStart) + 315_964_800 - Double(gpsOffset))
                let end = start.addingTimeInterval(Double(raw.duration))
                guard end > now && start < now.addingTimeInterval(48 * 3600) else { continue }
                let event = BroadcastProgram(sourceID: source, eventID: raw.id, title: raw.title, start: start, end: end)
                if unique[event.id]?.title == nil { unique[event.id] = event }
            }
        }
        result.programs = Array(unique.values).sorted { $0.start == $1.start ? $0.eventID < $1.eventID : $0.start < $1.start }
        result.programs = Array(result.programs.prefix(256))
        return result
    }
    private func packet(_ bytes: [UInt8], pid: Int) {
        let control = (bytes[3] >> 4) & 3
        guard bytes[1] & 0x80 == 0, bytes[3] & 0xc0 == 0, control != 0 else {
            buffers[pid] = nil; previous[pid] = nil; return
        }
        var at = 4
        if control & 2 != 0 {
            at += 1 + Int(bytes[4])
            guard at <= 188 else { buffers[pid] = nil; previous[pid] = nil; return }
            if bytes[4] > 0 && bytes[5] & 0x80 != 0 { buffers[pid] = nil; previous[pid] = nil }
        }
        guard control & 1 != 0, at < 188 else { return }
        let counter = Int(bytes[3] & 15)
        if let prior = previous[pid] {
            if prior.counter == counter && prior.packet == bytes { return }
            if counter != (prior.counter + 1) % 16 { buffers[pid] = nil }
        }
        previous[pid] = (counter, bytes)
        if bytes[1] & 0x40 != 0 {
            let pointer = Int(bytes[at]); at += 1
            guard at + pointer <= 188 else { buffers[pid] = nil; return }
            if !(buffers[pid] ?? []).isEmpty && pointer > 0 {
                consume(pid: pid, chunk: bytes[at..<at + pointer])
            }
            buffers[pid] = []
            consume(pid: pid, chunk: bytes[(at + pointer)...])
        } else if !(buffers[pid] ?? []).isEmpty { consume(pid: pid, chunk: bytes[at...]) }
    }
    private func consume(pid: Int, chunk: ArraySlice<UInt8>) {
        var buffer = buffers[pid] ?? []
        buffer.append(contentsOf: chunk)
        while buffer.count >= 3 {
            if buffer[0] == 0xff { buffer.removeAll(); break }
            let size = 3 + (Int(buffer[1] & 15) << 8 | Int(buffer[2]))
            guard size >= 12 && size <= 4096 else { buffer.removeAll(); break }
            if buffer.count < size { break }
            section(Array(buffer.prefix(size)), pid: pid)
            buffer.removeFirst(size)
        }
        buffers[pid] = buffer
    }
    private func crc(_ bytes: [UInt8]) -> UInt32 {
        var value: UInt32 = 0xffffffff
        for byte in bytes {
            value ^= UInt32(byte) << 24
            for _ in 0..<8 { value = (value << 1) ^ (value & 0x80000000 != 0 ? 0x04c11db7 : 0) }
        }
        return value
    }
    private func section(_ bytes: [UInt8], pid: Int) {
        guard bytes.count >= 12, bytes[1] & 0x80 != 0, bytes[5] & 1 != 0, bytes[8] == 0 else { return }
        guard crc(bytes) == 0 else { crcErrors += 1; return }
        let name = String(format: "%02X", bytes[0])
        counts[name, default: 0] = min(1_000_000, (counts[name] ?? 0) + 1)
        switch bytes[0] {
        case 0xcd where pid == 0x1ffb:
            if bytes.count >= 20 { gpsOffset = Int(bytes[13]) }
        case 0xc7 where pid == 0x1ffb: parseMGT(bytes)
        case 0xc8 where pid == 0x1ffb, 0xc9 where pid == 0x1ffb: parseVCT(bytes)
        case 0xcb: parseEIT(bytes, pid: pid)
        default: break
        }
    }
    private func big(_ bytes: [UInt8], _ at: Int) -> Int { Int(bytes[at]) << 8 | Int(bytes[at + 1]) }
    private func parseMGT(_ bytes: [UInt8]) {
        guard bytes.count >= 17 else { return }
        var at = 11
        var pids: Set<Int> = [0x1ffb]
        for _ in 0..<big(bytes, 9) {
            guard at + 11 <= bytes.count - 4 else { return }
            let type = big(bytes, at)
            let pid = big(bytes, at + 2) & 0x1fff
            let length = big(bytes, at + 9) & 0xfff
            guard at + 11 + length <= bytes.count - 4 else { return }
            if (0x100...0x17f).contains(type), pid != 0x1fff { pids.insert(pid) }
            at += 11 + length
        }
        guard at + 2 <= bytes.count - 4, at + 2 + (big(bytes, at) & 0xfff) == bytes.count - 4 else { return }
        watched = pids
        buffers = buffers.filter { pids.contains($0.key) }
        previous = previous.filter { pids.contains($0.key) }
        eventSections = eventSections.filter { pids.contains($0.value.pid) }
    }
    private func parseVCT(_ bytes: [UInt8]) {
        guard bytes.count >= 16 else { return }
        var mapping: [String: Int] = [:]
        var at = 10
        for _ in 0..<Int(bytes[9]) {
            guard at + 32 <= bytes.count - 4 else { return }
            let major = Int(bytes[at + 14] & 15) << 6 | Int(bytes[at + 15] >> 2)
            let minor = Int(bytes[at + 15] & 3) << 8 | Int(bytes[at + 16])
            let length = big(bytes, at + 30) & 0x3ff
            guard at + 32 + length <= bytes.count - 4 else { return }
            if big(bytes, at + 22) == big(bytes, 3) {
                mapping["\(major).\(minor)"] = big(bytes, at + 28)
            }
            at += 32 + length
        }
        guard at + 2 <= bytes.count - 4, at + 2 + (big(bytes, at) & 0x3ff) == bytes.count - 4 else { return }
        let version = Int(bytes[5] >> 1 & 31)
        if vctVersion != version { sources.removeAll(); vctVersion = version }
        guard Set(sources.keys).union(mapping.keys).count <= 256 else { return }
        sources.merge(mapping) { _, new in new }
    }
    private func parseEIT(_ bytes: [UInt8], pid: Int) {
        guard bytes.count >= 14 else { return }
        let source = big(bytes, 3)
        let version = Int(bytes[5] >> 1 & 31)
        let key = "\(pid)-\(source)-\(bytes[6])"
        if eventSections[key]?.data == bytes { return }
        var events: [RawEvent] = []
        var at = 10
        var unsupported = 0
        for _ in 0..<Int(bytes[9]) {
            guard at + 10 <= bytes.count - 4 else { return }
            let eventID = big(bytes, at) & 0x3fff
            let start = (0..<4).reduce(UInt32(0)) { $0 << 8 | UInt32(bytes[at + 2 + $1]) }
            let duration = Int(bytes[at + 6] & 15) << 16 | Int(bytes[at + 7]) << 8 | Int(bytes[at + 8])
            let titleLength = Int(bytes[at + 9])
            at += 10
            guard at + titleLength + 2 <= bytes.count - 4 else { return }
            let title = Self.decodeText(Array(bytes[at..<at + titleLength]), language: preferredLanguage)
            if titleLength > 0 && title == nil { unsupported += 1 }
            at += titleLength
            let descriptors = big(bytes, at) & 0xfff
            at += 2
            guard at + descriptors <= bytes.count - 4 else { return }
            at += descriptors
            if duration > 0 { events.append(RawEvent(id: eventID, gpsStart: start, duration: duration, title: title)) }
        }
        guard at == bytes.count - 4 else { return }
        // Versions apply per EIT PID/source, never across future EIT time slots.
        eventSections = eventSections.filter { _, section in
            section.pid != pid || section.source != source || (section.version == version && section.lastSection == Int(bytes[7]))
        }
        guard eventSections[key] != nil || eventSections.count < 256 else { return }
        eventSections[key] = EventSection(pid: pid, source: source, version: version, lastSection: Int(bytes[7]), data: bytes, events: events)
        unsupportedTitles = min(1_000_000, unsupportedTitles + unsupported)
    }
    /// Decode uncompressed A/65 multiple-string structures. Unsupported segments
    /// invalidate that language entry instead of showing corrupt text.
    static func decodeText(_ bytes: [UInt8], language: String) -> String? {
        guard let count = bytes.first else { return nil }
        var at = 1
        var strings: [(String, String)] = []
        let modes = Set([0] + Array(1...6) + Array(9...16) + Array(32...39) + Array(48...51))
        for _ in 0..<Int(count) {
            guard at + 4 <= bytes.count else { return nil }
            let code = String(decoding: bytes[at..<at + 3], as: UTF8.self)
            let segments = Int(bytes[at + 3]); at += 4
            var text = ""
            var supported = true
            for _ in 0..<segments {
                guard at + 3 <= bytes.count else { return nil }
                let compression = bytes[at], mode = bytes[at + 1], length = Int(bytes[at + 2]); at += 3
                guard at + length <= bytes.count else { return nil }
                let payload = Array(bytes[at..<at + length]); at += length
                if length == 0 { continue }
                guard compression == 0 else { supported = false; continue }
                if mode == 0x3f && length % 2 == 0 {
                    let units: [UInt16] = stride(from: 0, to: length, by: 2).map { UInt16(payload[$0]) << 8 | UInt16(payload[$0 + 1]) }
                    text += String(decoding: units, as: UTF16.self)
                } else if modes.contains(Int(mode)) {
                    text += String(decoding: payload.map { UInt16(mode) << 8 | UInt16($0) }, as: UTF16.self)
                } else { supported = false }
            }
            text = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
            if supported && !text.isEmpty { strings.append((code, String(text.prefix(512)))) }
        }
        guard at == bytes.count else { return nil }
        let codes = ["en": ["eng"], "es": ["spa"], "fr": ["fra", "fre"]]
        return strings.first { (codes[language] ?? []).contains($0.0) }?.1 ?? strings.first?.1
    }
}
