import SwiftUI

struct ProgramTimelineView: View {
    let programs: [BroadcastProgram]
    var collecting = false
    var onDetailsChange: (Bool) -> Void = { _ in }
    @State private var selected: BroadcastProgram?
    private let pixelsPerMinute = 4.0
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            let window = ProgramTimelineWindow(programs: programs, at: now)
            let anchor = window.anchor
            let end = window.end
            let visible = window.programs
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "clock").foregroundStyle(AntenaTheme.cyan)
                    Text(L10n.text("On now & next")).fontWeight(.semibold)
                    Spacer()
                    Text(L10n.text("Broadcast schedule · ATSC")).foregroundStyle(AntenaTheme.muted)
                }.font(.system(size: 11))
                if visible.isEmpty {
                    Text(L10n.text(collecting ? "Reading broadcast schedule…" : "Schedule unavailable"))
                        .font(.system(size: 12)).foregroundStyle(AntenaTheme.muted)
                } else {
                    ScrollView(.horizontal, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 0) {
                                ForEach(0..<12, id: \.self) { tick in
                                    Text(time(anchor.addingTimeInterval(Double(tick) * 1800)))
                                        .font(.system(size: 10, weight: .medium)).monospacedDigit()
                                        .frame(width: 120, alignment: .leading)
                                }
                            }.foregroundStyle(AntenaTheme.muted)
                            ZStack(alignment: .topLeading) {
                                ForEach(visible) { program in
                                    let start = max(anchor, program.start)
                                    let finish = min(end, program.end)
                                    let width = finish.timeIntervalSince(start) / 60 * pixelsPerMinute
                                    Button { selected = program } label: {
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(program.title ?? L10n.text("Title unavailable"))
                                                .font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                            Text("\(time(program.start)) – \(time(program.end))")
                                                .font(.system(size: 10)).foregroundStyle(AntenaTheme.muted).lineLimit(1)
                                        }
                                        .padding(.horizontal, 12).frame(width: max(1, width - 3), height: 58, alignment: .leading)
                                        .background(program.isCurrent(at: now) ? AntenaTheme.cyan.opacity(0.15) : .white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(program.isCurrent(at: now) ? AntenaTheme.cyan.opacity(0.8) : .white.opacity(0.08)))
                                        .clipped()
                                    }.buttonStyle(.plain)
                                        .help(program.title ?? L10n.text("Title unavailable"))
                                        .offset(x: start.timeIntervalSince(anchor) / 60 * pixelsPerMinute)
                                }
                                Rectangle().fill(AntenaTheme.cyan).frame(width: 2, height: 58)
                                    .offset(x: now.timeIntervalSince(anchor) / 60 * pixelsPerMinute)
                                    .allowsHitTesting(false)
                            }.frame(width: 1440, height: 60, alignment: .topLeading)
                        }.padding(.bottom, 5)
                    }
                    .id(visible.first?.id ?? "empty-guide")
                }
            }
        }
        .foregroundStyle(.white)
        .popover(item: $selected) { program in
            VStack(alignment: .leading, spacing: 12) {
                Text(program.title ?? L10n.text("Title unavailable")).font(.headline)
                Text(program.start, format: .dateTime.weekday().day().month().locale(L10n.locale))
                Text("\(time(program.start)) – \(time(program.end))").monospacedDigit()
                Text(L10n.text("Broadcast schedule · ATSC")).font(.caption).foregroundStyle(.secondary)
            }.padding(22).frame(width: 300, alignment: .leading)
        }
        .onChange(of: selected?.id) { _, id in onDetailsChange(id != nil) }
        .onChange(of: programs) { _, updated in
            if let selected { self.selected = updated.first { $0.id == selected.id } }
        }
        .onExitCommand { selected = nil }
        .onDisappear { onDetailsChange(false) }
    }
    private func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute().locale(L10n.locale))
    }
}

struct CurrentProgramView: View {
    let programs: [BroadcastProgram]
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            if let current = programs.first(where: { $0.isCurrent(at: context.date) }) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(current.title ?? L10n.text("Title unavailable"))
                        .font(.system(size: 18, weight: .semibold)).lineLimit(1)
                    HStack(spacing: 10) {
                        Text(current.start, format: .dateTime.hour().minute().locale(L10n.locale))
                        ProgressView(value: current.progress(at: context.date)).tint(AntenaTheme.cyan).frame(maxWidth: 180)
                        Text(current.end, format: .dateTime.hour().minute().locale(L10n.locale))
                    }.font(.system(size: 10)).foregroundStyle(AntenaTheme.muted)
                }
            }
        }
    }
}

#if DEBUG
#Preview("Broadcast timeline · sample data") {
    let start = Date().addingTimeInterval(-900)
    ProgramTimelineView(programs: (0..<6).map {
        BroadcastProgram(sourceID: 1, eventID: $0, title: "Sample program \($0 + 1)", start: start.addingTimeInterval(Double($0) * 1800), end: start.addingTimeInterval(Double($0 + 1) * 1800))
    }).padding(24).frame(width: 1100).background(AntenaTheme.background)
}
#endif
