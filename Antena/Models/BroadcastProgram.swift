import Foundation

struct BroadcastProgram: Identifiable, Equatable {
    let sourceID: Int
    let eventID: Int
    let title: String?
    let start: Date
    let end: Date
    var id: String { "\(sourceID)-\(eventID)-\(Int(start.timeIntervalSince1970))" }
    func isCurrent(at date: Date) -> Bool { start <= date && date < end }
    func progress(at date: Date) -> Double {
        min(1, max(0, date.timeIntervalSince(start) / max(1, end.timeIntervalSince(start))))
    }
}

struct ProgramGuideSnapshot {
    var programs: [BroadcastProgram] = []
    var hasClock = false
    var tableCounts: [String: Int] = [:]
    var sourceCount = 0
    var unsupportedTitles = 0
    var crcErrors = 0
}

/// Start the rail at the first non-expired program, never at an empty past slot.
struct ProgramTimelineWindow {
    let anchor: Date
    let end: Date
    let programs: [BroadcastProgram]
    init(programs: [BroadcastProgram], at now: Date) {
        let upcoming = programs.filter { $0.end > now }.sorted { $0.start < $1.start }
        anchor = upcoming.first?.start ?? now
        let cutoff = anchor.addingTimeInterval(6 * 3600)
        end = cutoff
        self.programs = upcoming.filter { $0.start < cutoff }
    }
}
