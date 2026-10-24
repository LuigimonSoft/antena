import Foundation

@main
struct RecordingWriterTests {
    static func main() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AntenaWriter-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.ts")
        let writer = RecordingWriter()
        let packet = Data(repeating: 0x47, count: 188)
        writer.append(packet)
        precondition(!FileManager.default.fileExists(atPath: url.path), "Live input must not create files")
        try writer.start(url)
        writer.append(packet); writer.append(packet)
        precondition(writer.stop() == nil)
        let captured = try Data(contentsOf: url)
        precondition(captured == packet + packet)
        writer.append(packet)
        let stopped = try Data(contentsOf: url)
        precondition(stopped.count == 376, "Stopped recording must not grow")
        do {
            try writer.start(url)
            fatalError("Existing recording was overwritten")
        } catch {}
        let second = directory.appendingPathComponent("concurrent.ts")
        try writer.start(second)
        DispatchQueue.concurrentPerform(iterations: 100) { _ in writer.append(packet) }
        precondition(writer.stop() == nil)
        let concurrent = try Data(contentsOf: second)
        precondition(concurrent.count == 18800)
        print("PASS: no implicit files; exact capture; stop; no overwrite; concurrent writes")
    }
}
