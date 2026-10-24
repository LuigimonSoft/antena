import Foundation

func crc32MPEG(_ bytes: [UInt8]) -> UInt32 {
    var crc: UInt32 = 0xffffffff
    for byte in bytes {
        crc ^= UInt32(byte) << 24
        for _ in 0..<8 { crc = (crc << 1) ^ (crc & 0x80000000 != 0 ? 0x04c11db7 : 0) }
    }
    return crc
}
final class TransportInspector {
    var programs: [Int: Int] = [:]
    var streams: [Int: [[String: Any]]] = [:]
    var channels: [Int: [String: Any]] = [:]
    var buffers: [Int: [UInt8]] = [:]
    var previous: [Int: (counter: Int, packet: [UInt8])] = [:]
    var packets = 0, transportErrors = 0, crcErrors = 0, validatedSections = 0
    func section(pid: Int, bytes: [UInt8]) {
        if crc32MPEG(bytes) != 0 { crcErrors += 1; return }
        validatedSections += 1
        func big(_ offset: Int) -> Int { Int(bytes[offset]) << 8 | Int(bytes[offset + 1]) }
        if bytes[0] == 0 && pid == 0 && bytes.count >= 12 {
            for at in stride(from: 8, to: bytes.count - 4, by: 4) where at + 4 <= bytes.count - 4 {
                let program = big(at)
                if program != 0 { programs[program] = Int(bytes[at + 2] & 31) << 8 | Int(bytes[at + 3]) }
            }
        } else if bytes[0] == 2 && programs.values.contains(pid) && bytes.count >= 16 {
            let number = big(3)
            var at = 12 + (Int(bytes[10] & 15) << 8 | Int(bytes[11]))
            var found: [[String: Any]] = []
            let names = [2: "MPEG-2 video", 0x1b: "H.264 video", 0x81: "AC-3 audio", 0x0f: "AAC audio", 3: "MPEG audio", 4: "MPEG audio"]
            while at + 5 <= bytes.count - 4 {
                let kind = Int(bytes[at])
                let elementaryPID = Int(bytes[at + 1] & 31) << 8 | Int(bytes[at + 2])
                let length = Int(bytes[at + 3] & 15) << 8 | Int(bytes[at + 4])
                if at + 5 + length > bytes.count - 4 { break }
                found.append(["pid": elementaryPID, "type": kind, "codec": names[kind] ?? "other"])
                at += 5 + length
            }
            streams[number] = found
        } else if [0xc8, 0xc9].contains(bytes[0]) && pid == 0x1ffb && bytes.count >= 14 {
            var at = 10
            for _ in 0..<Int(bytes[9]) {
                if at + 32 > bytes.count - 4 { break }
                let channel = Array(bytes[at..<at + 32])
                let program = Int(channel[24]) << 8 | Int(channel[25])
                let units: [UInt16] = stride(from: 0, to: 14, by: 2).map { UInt16(channel[$0]) << 8 | UInt16(channel[$0 + 1]) }
                let name = String(decoding: units, as: UTF16.self).trimmingCharacters(in: CharacterSet(charactersIn: "\0 "))
                channels[program] = ["name": name, "major": Int(channel[14] & 15) << 6 | Int(channel[15] >> 2), "minor": Int(channel[15] & 3) << 8 | Int(channel[16])]
                at += 32 + (Int(channel[30] & 3) << 8 | Int(channel[31]))
            }
        }
    }
    func consume(pid: Int, chunk: ArraySlice<UInt8>) {
        var pending = buffers[pid] ?? []
        pending.append(contentsOf: chunk)
        while pending.count >= 3 {
            if pending[0] == 0xff { pending.removeAll(); break }
            let size = 3 + (Int(pending[1] & 15) << 8 | Int(pending[2]))
            if size < 8 || size > 4096 { pending.removeAll(); break }
            if pending.count < size { break }
            section(pid: pid, bytes: Array(pending.prefix(size)))
            pending.removeFirst(size)
        }
        buffers[pid] = pending
    }
    func packet(_ packet: [UInt8]) throws {
        try require(packet.count == 188 && packet[0] == 0x47, "Packet boundary or sync byte invalid")
        packets += 1
        let pid = Int(packet[1] & 31) << 8 | Int(packet[2])
        if packet[1] & 0x80 != 0 { transportErrors += 1; buffers[pid] = nil; return }
        guard pid == 0 || pid == 0x1ffb || programs.values.contains(pid) else { return }
        let control = (packet[3] >> 4) & 3
        guard control & 1 != 0 else { return }
        let counter = Int(packet[3] & 15)
        if let prior = previous[pid] {
            if prior.counter == counter && prior.packet == packet { return }
            if counter != (prior.counter + 1) % 16 { buffers[pid] = nil }
        }
        previous[pid] = (counter, packet)
        let at = 4 + (control & 2 != 0 ? 1 + Int(packet[4]) : 0)
        guard at < 188 else { return }
        let payload = Array(packet[at...])
        if packet[1] & 0x40 != 0 {
            let pointer = Int(payload[0])
            guard pointer + 1 <= payload.count else { buffers[pid] = nil; return }
            if !(buffers[pid] ?? []).isEmpty && pointer > 0 { consume(pid: pid, chunk: payload[1..<1 + pointer]) }
            buffers[pid] = []
            consume(pid: pid, chunk: payload[(1 + pointer)...])
        } else if !(buffers[pid] ?? []).isEmpty { consume(pid: pid, chunk: payload[...]) }
    }
    func report(file: String) -> [String: Any] {
        ["file": file, "packets": packets, "transport_errors": transportErrors, "crc_errors": crcErrors, "validated_sections": validatedSections,
         "programs": programs.keys.sorted().map { number -> [String: Any] in
             ["program": number, "pmt_pid": programs[number]!, "channel": channels[number].map { $0 as Any } ?? NSNull(), "streams": streams[number] ?? []]
         }]
    }
}
func inspectTransport(at url: URL) throws -> [String: Any] {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    let inspector = TransportInspector()
    // Stream through the file rather than loading a potentially large recording.
    var pending = Data()
    while let data = try handle.read(upToCount: 188 * 1024), !data.isEmpty {
        pending.append(data)
        let whole = pending.count / 188 * 188
        for offset in stride(from: 0, to: whole, by: 188) {
            try inspector.packet(Array(pending[offset..<offset + 188]))
        }
        pending = Data(pending.dropFirst(whole))
    }
    try require(pending.isEmpty, "Packet boundary or sync byte invalid")
    return inspector.report(file: url.path)
}
