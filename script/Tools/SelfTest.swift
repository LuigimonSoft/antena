import Foundation

func toolingSelfTest() throws {
    func rejects(_ name: String, _ body: () throws -> Void) throws {
        var rejected = false
        do { try body() } catch { rejected = true }
        try require(rejected, "Invalid input accepted: " + name)
    }
    let firmwareURL = projectRoot.appendingPathComponent("firmware/xc3028-v27.fw")
    let firmware = try Data(contentsOf: firmwareURL)
    _ = try validateFirmware(firmware)
    try rejects("truncated firmware") { _ = try validateFirmware(firmware.prefix(100)) }
    var changed = firmware
    changed[changed.count - 1] ^= 1
    try rejects("firmware checksum mismatch") { _ = try validateFirmware(changed) }
    try rejects("trailing firmware data") { _ = try validateFirmware(firmware + Data([0])) }
    try rejects("empty firmware") { _ = try validateFirmware(Data()) }
    try require(crc32MPEG(Array("123456789".utf8)) == 0x0376e6e7, "MPEG CRC known vector failed")
    func section(_ bytes: [UInt8]) -> [UInt8] {
        let crc = crc32MPEG(bytes)
        return bytes + [UInt8((crc >> 24) & 255), UInt8((crc >> 16) & 255), UInt8((crc >> 8) & 255), UInt8(crc & 255)]
    }
    func packet(pid: Int, payload: [UInt8], counter: Int = 0, start: Bool = true) -> [UInt8] {
        [0x47, UInt8((pid >> 8) & 31) | (start ? 0x40 : 0), UInt8(pid & 255), 0x10 | UInt8(counter)] + payload + Array(repeating: 0xff, count: 184 - payload.count)
    }
    let pat = section([0, 0xb0, 13, 0, 1, 0xc1, 0, 0, 0, 1, 0xe1, 0])
    let pmt = section([2, 0xb0, 18, 0, 1, 0xc1, 0, 0, 0xe1, 1, 0xf0, 0, 2, 0xe1, 1, 0xf0, 0])
    let inspector = TransportInspector()
    let first = packet(pid: 0, payload: [0] + pat)
    try inspector.packet(first)
    try inspector.packet(first) // Exact duplicate must not count as a new section.
    try inspector.packet(packet(pid: 256, payload: [0] + pmt))
    try require(inspector.programs[1] == 256 && inspector.streams[1]?.first?["codec"] as? String == "MPEG-2 video", "PAT/PMT parsing failed")
    try require(inspector.validatedSections == 2 && inspector.crcErrors == 0, "Section count or duplicate handling failed")
    var broken = pat
    broken[broken.count - 1] ^= 1
    inspector.section(pid: 0, bytes: broken)
    try require(inspector.crcErrors == 1, "Corrupt CRC was accepted")
    try rejects("invalid packet") { try inspector.packet([0]) }
    func exactPacket(pid: Int, payload: [UInt8], counter: Int, start: Bool) -> [UInt8] {
        let padding = 183 - payload.count
        return [0x47, UInt8((pid >> 8) & 31) | (start ? 0x40 : 0), UInt8(pid & 255), 0x30 | UInt8(counter), UInt8(padding)] + Array(repeating: 0xff, count: padding) + payload
    }
    let fragmented = TransportInspector()
    try fragmented.packet(exactPacket(pid: 0, payload: [0] + Array(pat.prefix(7)), counter: 0, start: true))
    try fragmented.packet(exactPacket(pid: 0, payload: Array(pat.dropFirst(7)), counter: 1, start: false))
    try require(fragmented.programs[1] == 256, "Section spanning packets was lost")
    let discontinuous = TransportInspector()
    try discontinuous.packet(exactPacket(pid: 0, payload: [0] + Array(pat.prefix(7)), counter: 0, start: true))
    try discontinuous.packet(exactPacket(pid: 0, payload: Array(pat.dropFirst(7)), counter: 3, start: false))
    try require(discontinuous.programs.isEmpty, "Discontinuous section was accepted")
    let pointer = TransportInspector()
    try pointer.packet(exactPacket(pid: 0, payload: [0] + Array(pat.prefix(7)), counter: 0, start: true))
    try pointer.packet(exactPacket(pid: 0, payload: [UInt8(pat.count - 7)] + Array(pat.dropFirst(7)) + pat, counter: 1, start: true))
    try require(pointer.validatedSections == 2, "Pointer-field section completion failed")
    var channel = Array(repeating: UInt8(0), count: 32)
    channel[1] = 67; channel[3] = 66; channel[5] = 67
    channel[15] = 24; channel[16] = 1; channel[25] = 1
    let vct = section([0xc8, 0xf0, 43, 0, 1, 0xc1, 0, 0, 0, 1] + channel)
    inspector.section(pid: 0x1ffb, bytes: vct)
    try require(inspector.channels[1]?["name"] as? String == "CBC" && inspector.channels[1]?["major"] as? Int == 6 && inspector.channels[1]?["minor"] as? Int == 1, "ATSC VCT decoding failed")
    try withTemporaryDirectory { directory in
        let sample = directory.appendingPathComponent("sample.ts")
        try Data(first + packet(pid: 256, payload: [0] + pmt)).write(to: sample)
        let report = try inspectTransport(at: sample)
        try require(report["packets"] as? Int == 2, "Streaming inspector packet count failed")
        try Data(first + [0]).write(to: sample)
        try rejects("truncated final packet") { _ = try inspectTransport(at: sample) }
        let source = directory.appendingPathComponent("source")
        let target = directory.appendingPathComponent("copy")
        try write("payload", to: source.appendingPathComponent("nested/file"))
        try write("metadata", to: source.appendingPathComponent("nested/._file"))
        try fileManager.createSymbolicLink(atPath: source.appendingPathComponent("link").path, withDestinationPath: "nested/file")
        try copyCleanTree(source: source, destination: target)
        try require(!fileManager.fileExists(atPath: target.appendingPathComponent("nested/._file").path), "AppleDouble metadata copied")
        try require(try fileManager.destinationOfSymbolicLink(atPath: target.appendingPathComponent("link").path) == "nested/file", "Runtime symlink was not preserved")
        try require(!isAntena(source), "Unrelated bundle accepted")
    }
    let project = projectRoot.appendingPathComponent("Antena.xcodeproj/project.pbxproj")
    try generateProject()
    let generated = try Data(contentsOf: project)
    try generateProject()
    try require(try Data(contentsOf: project) == generated, "Project generation is not deterministic")
    try run("/usr/bin/plutil", ["-lint", project.path])
    let publicFiles = try publicSourceFiles()
    try validatePublicSources(publicFiles)
    print("PASS: firmware corruption, MPEG CRC/PAT/PMT/duplicates/truncation, clean staging/symlinks, deterministic project, public source rules")
}
