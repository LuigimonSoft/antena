import SwiftUI
import AppKit

struct RecordingsView: View {
    @ObservedObject var session: TunerSession
    @ObservedObject var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.text("Your recordings")).font(.system(size: 26, weight: .bold))
                    Text(L10n.text("Only broadcasts you choose to record are saved.")).foregroundStyle(.secondary)
                }
                Spacer()
                Button(L10n.text("Done")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
            if library.recordings.isEmpty {
                ContentUnavailableView(L10n.text("Your library starts here"), systemImage: "record.circle", description: Text(L10n.text("Click Record while watching a channel. You choose where to save the file.")))
                    .frame(height: 270)
            } else {
                List(library.recordings) { recording in
                    HStack(spacing: 16) {
                        Button { session.playRecording(recording); dismiss() } label: {
                            Image(systemName: "play.rectangle.fill")
                                .font(.system(size: 28)).foregroundStyle(AntenaTheme.cyan)
                                .frame(width: 44, height: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain).help(L10n.text("Play"))
                            .accessibilityLabel(L10n.text("Play") + " " + recording.channel)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(recording.channel).fontWeight(.semibold)
                            Text("\(recording.started.formatted(date: .abbreviated, time: .shortened)) · \(AntenaTheme.time(Int(recording.duration)))")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(recording.url.lastPathComponent).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Button(L10n.text("Play")) { session.playRecording(recording); dismiss() }
                        Button { NSWorkspace.shared.activateFileViewerSelecting([recording.url]) } label: { Image(systemName: "folder") }.help(L10n.text("Show in Finder")).disabled(session.isPreview)
                    }.padding(.vertical, 9)
                }.frame(height: 300)
            }
        }.padding(28).frame(width: 730).preferredColorScheme(.dark)
        .task {
            guard !session.isPreview else { return }
            while !Task.isCancelled {
                library.removeMissingRecordings()
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if !session.isPreview { library.removeMissingRecordings() }
        }
    }
}

#if DEBUG
#Preview("Recordings") {
    AntenaPreview(recordings: true) { session, library in
        RecordingsView(session: session, library: library)
    }
}

#Preview("Empty library") {
    AntenaPreview { session, library in
        RecordingsView(session: session, library: library)
    }
}
#endif
