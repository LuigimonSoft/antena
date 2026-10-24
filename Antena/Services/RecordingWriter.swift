import Foundation

/// Shared with the USB pipe reader. Only an explicit start opens a disk file.
final class RecordingWriter: @unchecked Sendable {
    private let lock = NSLock()
    private var handle: FileHandle?
    private var failure: String?
    func start(_ url: URL) throws {
        lock.lock(); defer { lock.unlock() }
        guard handle == nil else { throw CocoaError(.fileWriteFileExists) }
        let fd = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        failure = nil
    }
    func append(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        guard let handle else { return }
        do { try handle.write(contentsOf: data) }
        catch {
            failure = error.localizedDescription
            try? handle.close(); self.handle = nil
        }
    }
    func takeFailure() -> String? {
        lock.lock(); defer { lock.unlock() }
        let result = failure; failure = nil; return result
    }
    func stop() -> String? {
        lock.lock(); defer { lock.unlock() }
        var result = failure; failure = nil
        do { try handle?.synchronize(); try handle?.close() }
        catch { result = error.localizedDescription }
        handle = nil
        return result
    }
}
