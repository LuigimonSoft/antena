import Foundation

/// Shared by the app entry point and the Canvas fixtures.
enum PreviewEnvironment {
    static var isActive: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
}
