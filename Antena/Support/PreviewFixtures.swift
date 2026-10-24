#if DEBUG
import SwiftUI

/// Every preview owns an isolated library; no preferences or recordings are written.
struct AntenaPreview<Content: View>: View {
    @StateObject private var library: LibraryStore
    @StateObject private var session: TunerSession
    private let content: (TunerSession, LibraryStore) -> Content

    @MainActor init(recordings: Bool = false, @ViewBuilder content: @escaping (TunerSession, LibraryStore) -> Content) {
        let library = LibraryStore(persistenceEnabled: false)
        if recordings {
            library.recordings = [Recording(path: "/Preview/ICI-Radio-Canada.ts", channel: "ICI Radio-Canada", started: Date(timeIntervalSince1970: 1_792_713_600), duration: 1800)]
        }
        _library = StateObject(wrappedValue: library)
        _session = StateObject(wrappedValue: TunerSession(library: library, preview: true))
        self.content = content
    }
    var body: some View {
        content(session, library)
            .background(AntenaTheme.background)
            .foregroundStyle(.white)
            .preferredColorScheme(.dark)
    }
}
#endif
