import Foundation

struct ToolError: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { description = message }
}
let fileManager = FileManager.default
var projectRoot: URL { URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true) }
func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw ToolError(message) }
}
func write(_ text: String, to url: URL) throws {
    try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
}
func relativePath(_ url: URL, to root: URL = projectRoot) -> String {
    String(url.path.dropFirst(root.path.count + 1))
}
func files(in directory: URL) -> [URL] {
    guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: []) else { return [] }
    return enumerator.compactMap { $0 as? URL }.filter {
        !$0.pathComponents.contains(where: { $0.hasPrefix("._") || $0 == "__pycache__" }) &&
        (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }.sorted { $0.path < $1.path }
}
struct CommandResult {
    var status: Int32
    var output: Data
    var text: String { String(decoding: output, as: UTF8.self) }
}
@discardableResult
func run(_ executable: String, _ arguments: [String], directory: URL? = nil,
         input: Data? = nil, allowFailure: Bool = false) throws -> CommandResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.currentDirectoryURL = directory
    let output = Pipe()
    process.standardOutput = output
    process.standardError = allowFailure ? FileHandle.nullDevice : FileHandle.standardError
    // File-backed stdin avoids blocking while sending a large manifest.
    var inputURL: URL?
    var inputHandle: FileHandle?
    if let input {
        let url = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try input.write(to: url)
        inputURL = url
        inputHandle = try FileHandle(forReadingFrom: url)
        process.standardInput = inputHandle
    }
    defer {
        try? inputHandle?.close()
        if let inputURL { try? fileManager.removeItem(at: inputURL) }
    }
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    if process.terminationStatus != 0 && !allowFailure {
        throw ToolError("Command failed (\(process.terminationStatus)): \(executable) \(arguments.joined(separator: " "))")
    }
    return CommandResult(status: process.terminationStatus, output: data)
}
func withTemporaryDirectory<T>(_ body: (URL) throws -> T) throws -> T {
    let url = fileManager.temporaryDirectory.appendingPathComponent("antena-tools-" + UUID().uuidString)
    try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: url) }
    return try body(url)
}
