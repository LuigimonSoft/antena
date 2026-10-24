import SwiftUI
import AppKit

struct AboutView: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage).resizable().scaledToFit().frame(width: 88, height: 88)
            VStack(spacing: 7) {
                Text("Antena").font(.system(size: 30, weight: .bold))
                Text(L10n.format("Version %@ (build %@)", ProjectInfo.version, ProjectInfo.build))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Text(L10n.text("Live over-the-air television for macOS"))
                .multilineTextAlignment(.center)
            Divider()
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                GridRow {
                    Text(L10n.text("Created by")).foregroundStyle(.secondary)
                    Link(ProjectInfo.author, destination: ProjectInfo.authorURL)
                }
                GridRow {
                    Text(L10n.text("Project date")).foregroundStyle(.secondary)
                    Text(ProjectInfo.created, format: .dateTime.day().month(.wide).year().locale(L10n.locale))
                }
                GridRow {
                    Text(L10n.text("Platform")).foregroundStyle(.secondary)
                    Text("macOS 27+ · Apple Silicon")
                }
            }.font(.system(size: 13))
            Divider()
            VStack(spacing: 8) {
                Text(L10n.text("Built with Swift, a C userspace USB driver and libVLC."))
                Text(L10n.text("GPL-2.0-only code. VideoLAN, firmware and station logos retain their own terms and credits."))
                Text(L10n.text("Experimental project. Not an official KWorld application."))
            }.font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Link(L10n.text("Author on GitHub"), destination: ProjectInfo.authorURL)
        }
        .padding(28).frame(width: 430)
        .textSelection(.enabled)
    }
}

#if DEBUG
#Preview("About Antena") { AboutView() }
#endif
