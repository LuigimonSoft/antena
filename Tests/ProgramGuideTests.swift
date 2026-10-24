import Foundation

@main struct ProgramGuideTests {
    static func crc(_ bytes: [UInt8]) -> UInt32 {
        var result: UInt32 = 0xffffffff
        for byte in bytes {
            result ^= UInt32(byte) << 24
            for _ in 0..<8 { result = result << 1 ^ (result & 0x80000000 != 0 ? 0x04c11db7 : 0) }
        }
        return result
    }
    static func u32(_ value: UInt32) -> [UInt8] {
        [UInt8(value >> 24), UInt8(value >> 16 & 255), UInt8(value >> 8 & 255), UInt8(value & 255)]
    }
    static func section(_ table: UInt8, source: Int = 1, version: UInt8 = 0, body: [UInt8]) -> [UInt8] {
        let length = 6 + body.count + 4
        let bytes: [UInt8] = [table, 0xf0 | UInt8(length >> 8), UInt8(length & 255), UInt8(source >> 8), UInt8(source & 255), 0xc1 | version << 1, 0, 0, 0] + body
        return bytes + u32(crc(bytes))
    }
    static func packet(_ bytes: [UInt8], pid: Int = 0x1ffb, counter: Int, start: Bool = true) -> [UInt8] {
        let payload = (start ? [UInt8(0)] : []) + bytes
        let padding = 183 - payload.count
        let adaptation: [UInt8] = padding > 0 ? [0] + Array(repeating: 0xff, count: padding - 1) : []
        return [0x47, UInt8(pid >> 8) | (start ? 0x40 : 0), UInt8(pid & 255), 0x30 | UInt8(counter & 15), UInt8(padding)] + adaptation + payload
    }
    static func text(_ string: String, code: String = "eng") -> [UInt8] {
        [1] + Array(code.utf8) + [1, 0, 0, UInt8(string.utf8.count)] + Array(string.utf8)
    }
    static func event(_ id: Int, gps: UInt32, title: [UInt8]) -> [UInt8] {
        [UInt8(id >> 8), UInt8(id & 255)] + u32(gps) + [0xc0, 7, 8, UInt8(title.count)] + title + [0xf0, 0] // 1800 seconds
    }
    static func main() throws {
        let gps: UInt32 = 1_400_000_000
        let now = Date(timeIntervalSince1970: Double(gps) + 315_964_800 - 18 + 600)
        let mgt = section(0xc7, source: 0, body: [0, 1, 1, 0, 0xe1, 0, 0xe0, 0, 0, 0, 100, 0xf0, 0, 0xf0, 0])
        var channel = Array(repeating: UInt8(0), count: 32)
        channel[15] = 8; channel[16] = 1; channel[23] = 1; channel[25] = 1; channel[29] = 77
        let vct = section(0xc8, body: [1] + channel + [0xfc, 0])
        let stt = section(0xcd, source: 0, body: u32(gps) + [18, 0, 0])
        let eit = section(0xcb, source: 77, body: [2] + event(1, gps: gps, title: text("Current show")) + event(2, gps: gps + 1800, title: text("Next show")))
        let guide = ProgramGuideDecoder()
        let seed = packet(mgt, counter: 0) + packet(vct, counter: 1) + packet(eit, pid: 256, counter: 0)
        // Chunk boundaries deliberately split sync bytes, headers and sections.
        for byte in seed { guide.feed(Data([byte])) }
        precondition(guide.snapshot(channelNumber: "2.1", at: now).programs.isEmpty, "Must wait for transmitted GPS offset")
        guide.feed(Data(packet(stt, counter: 2)))
        let snapshot = guide.snapshot(channelNumber: "2.1", at: now)
        precondition(snapshot.programs.count == 2 && snapshot.hasClock)
        precondition(snapshot.programs[0].title == "Current show" && snapshot.programs[0].isCurrent(at: now))
        precondition(abs(snapshot.programs[0].progress(at: now) - 1.0 / 3) < 0.0001)
        precondition(snapshot.programs[1].title == "Next show")
        precondition(guide.snapshot(channelNumber: "6.1", at: now).programs.isEmpty, "Do not guess a different source")
        var broken = eit; broken[broken.count - 1] ^= 1
        guide.feed(Data(packet(broken, pid: 256, counter: 1)))
        precondition(guide.snapshot(channelNumber: "2.1", at: now).crcErrors == 1)
        precondition(guide.snapshot(channelNumber: "2.1", at: now).programs.count == 2)
        let replacement = section(0xcb, source: 77, version: 1, body: [1] + event(3, gps: gps, title: text("Updated show")))
        guide.feed(Data(packet(replacement, pid: 256, counter: 2)))
        precondition(guide.snapshot(channelNumber: "2.1", at: now).programs.map(\.title) == ["Updated show"], "Version update must remove canceled events")
        let empty = section(0xcb, source: 77, version: 2, body: [0])
        guide.feed(Data(packet(empty, pid: 256, counter: 3)))
        precondition(guide.snapshot(channelNumber: "2.1", at: now).programs.isEmpty)
        let split = ProgramGuideDecoder()
        split.feed(Data(packet(mgt, counter: 0) + packet(vct, counter: 1) + packet(stt, counter: 2)))
        split.feed(Data(packet(Array(eit.prefix(12)), pid: 256, counter: 0)))
        split.feed(Data(packet(Array(eit.dropFirst(12)), pid: 256, counter: 1, start: false)))
        precondition(split.snapshot(channelNumber: "2.1", at: now).programs.count == 2)
        let lost = ProgramGuideDecoder()
        lost.feed(Data(packet(mgt, counter: 0) + packet(vct, counter: 1) + packet(stt, counter: 2)))
        lost.feed(Data(packet(Array(eit.prefix(12)), pid: 256, counter: 0)))
        lost.feed(Data(packet(Array(eit.dropFirst(12)), pid: 256, counter: 3, start: false)))
        precondition(lost.snapshot(channelNumber: "2.1", at: now).programs.isEmpty)
        let english = text("News"), french = text("Journal", code: "fra")
        let multilingual = [UInt8(2)] + english.dropFirst() + french.dropFirst()
        precondition(ProgramGuideDecoder.decodeText(multilingual, language: "fr") == "Journal")
        precondition(ProgramGuideDecoder.decodeText([1, 102, 114, 97, 1, 0, 0, 1, 233], language: "fr") == "é")
        precondition(ProgramGuideDecoder.decodeText([1, 101, 110, 103, 1, 0, 63, 2, 0, 65], language: "en") == "A")
        precondition(ProgramGuideDecoder.decodeText([1, 101, 110, 103, 1, 1, 0, 1, 1], language: "en") == nil)
        let nowProgram = snapshot.programs[0]
        let expired = BroadcastProgram(sourceID: 77, eventID: 9, title: "Expired", start: now.addingTimeInterval(-3600), end: now.addingTimeInterval(-1))
        let rail = ProgramTimelineWindow(programs: [snapshot.programs[1], expired, nowProgram], at: now)
        precondition(rail.programs.first?.id == nowProgram.id && rail.anchor == nowProgram.start, "Current program must lead without a blank time slot")
        let boundary = ProgramTimelineWindow(programs: snapshot.programs, at: nowProgram.end)
        precondition(boundary.programs.first?.id == snapshot.programs[1].id && boundary.anchor == snapshot.programs[1].start, "The rail must advance when the current program ends")
        let future = ProgramTimelineWindow(programs: [snapshot.programs[1]], at: now)
        precondition(future.anchor == snapshot.programs[1].start, "Do not show empty earlier hours without a current listing")
        let fresh = ProgramGuideDecoder()
        precondition(fresh.snapshot(channelNumber: "2.1", at: now).programs.isEmpty, "A new tune must not reuse another transport")
        // Deterministic malformed input exercises bounds without a tuner.
        var random: UInt32 = 12345
        for _ in 0..<1000 {
            var bytes: [UInt8] = []
            for _ in 0..<188 { random = random &* 1664525 &+ 1013904223; bytes.append(UInt8(random >> 24)) }
            fresh.feed(Data(bytes))
        }
        print("PASS: PSIP discovery, GPS/UTC, channel mapping, current/next, versions, CRC, split sections, continuity, text modes, retune isolation and malformed input")
    }
}
