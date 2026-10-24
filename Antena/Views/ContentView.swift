import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var session: TunerSession
    @ObservedObject var library: LibraryStore
    @State private var dashboard = true
    @State private var controls = true
    @State private var hideTask: Task<Void, Never>?
    @State private var channelSheet = false
    @State private var recordingsSheet = false
    @State private var typedNumber = ""
    @State private var numberTask: Task<Void, Never>?
    private var showChrome: Bool { dashboard || controls || session.phase != .playing }
    var body: some View {
        ZStack {
            AntenaTheme.background
            VideoSurface(session: session)
            if dashboard {
                LinearGradient(stops: [.init(color: AntenaTheme.background.opacity(0.97), location: 0), .init(color: AntenaTheme.background.opacity(0.80), location: 0.34), .init(color: AntenaTheme.background.opacity(0.04), location: 0.72)], startPoint: .leading, endPoint: .trailing)
                    .allowsHitTesting(false)
                LinearGradient(colors: [.clear, AntenaTheme.background.opacity(0.3), AntenaTheme.background], startPoint: .top, endPoint: .bottom).allowsHitTesting(false)
                VStack(spacing: 0) {
                    navigation
                    DashboardView(session: session, library: library, watch: { dashboard = false; activity() }, channels: { channelSheet = true })
                }
            } else if showChrome {
                VStack {
                    navigation
                        .background(LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom))
                    Spacer()
                    PlayerControls(session: session, fullscreen: fullscreen, dashboard: { dashboard = true })
                }.transition(.opacity)
            }
            if [.tuning, .buffering].contains(session.phase), !dashboard {
                VStack(spacing: 15) {
                    ProgressView().controlSize(.large)
                    Text(session.detail).font(.system(size: 14))
                }.padding(30).background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 20))
            }
            if let error = session.error {
                VStack(spacing: 15) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash").font(.system(size: 28)).foregroundStyle(AntenaTheme.cyan)
                    Text(L10n.text("Let’s reconnect")).font(.system(size: 22, weight: .bold))
                    Text(error).font(.system(size: 13)).multilineTextAlignment(.center).foregroundStyle(AntenaTheme.muted).frame(maxWidth: 340)
                    HStack {
                        Button(L10n.text("Retry")) { session.retry() }.buttonStyle(CapsuleAction(prominent: true))
                        Button(L10n.text("Channels")) { channelSheet = true }.buttonStyle(CapsuleAction())
                    }
                }.padding(30).background(AntenaTheme.background.opacity(0.96), in: RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.12)))
            }
            if !typedNumber.isEmpty {
                Text(typedNumber).font(.system(size: 48, weight: .bold, design: .rounded)).padding(25)
                    .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 15)).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(70)
            }
            if let toast = session.toast, showChrome {
                VStack { Spacer(); Text(toast).font(.system(size: 12)).padding(14).background(.ultraThinMaterial, in: Capsule()).onAppear {
                    Task { try? await Task.sleep(for: .seconds(5)); if session.toast == toast { session.toast = nil } }
                }; Spacer().frame(height: dashboard ? 210 : 240) }
            }
            WindowInput(onActivity: activity, onKey: key).frame(width: 0, height: 0)
        }
        .foregroundStyle(.white).preferredColorScheme(.dark)
        .frame(minWidth: 1000, minHeight: 680)
        .animation(.easeInOut(duration: 0.3), value: showChrome)
        .sheet(isPresented: $channelSheet) { ChannelManager(session: session, library: library) }
        .sheet(isPresented: $recordingsSheet) { RecordingsView(session: session, library: library) }
        .task { session.start() }
        .onDisappear { hideTask?.cancel(); numberTask?.cancel() }
    }
    private var navigation: some View {
        HStack(spacing: 32) {
            Button { dashboard = true } label: {
                HStack(spacing: 0) {
                    Text("antena").foregroundStyle(.white)
                    Text(".").foregroundStyle(AntenaTheme.cyan)
                }.font(.system(size: 25, weight: .heavy)).tracking(-1.2)
            }.buttonStyle(.plain).accessibilityLabel(L10n.text("Antena, home"))
            Button { dashboard = true } label: {
                VStack(spacing: 8) { Text(L10n.text("Live")); Capsule().fill(AntenaTheme.cyan).frame(width: 35, height: 2) }
            }.buttonStyle(.plain)
            Button(L10n.text("Channels")) { channelSheet = true }.buttonStyle(.plain).foregroundStyle(AntenaTheme.muted)
            Button(L10n.text("Recordings")) { recordingsSheet = true }.buttonStyle(.plain).foregroundStyle(AntenaTheme.muted)
            Spacer()
            if session.isRecording {
                Label(AntenaTheme.time(session.recordingSeconds), systemImage: "record.circle.fill").foregroundStyle(.pink).monospacedDigit()
            }
            HStack(spacing: 6) {
                Circle().fill(session.phase == .playing ? Color.green : AntenaTheme.muted).frame(width: 5, height: 5)
                Text(session.playbackFile == nil ? L10n.text("USB TUNER") : L10n.text("RECORDING")).tracking(1.5)
            }.font(.system(size: 9, weight: .semibold)).foregroundStyle(AntenaTheme.muted)
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(context.date, format: .dateTime.hour().minute()).monospacedDigit().foregroundStyle(AntenaTheme.muted)
            }
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 44).padding(.top, 30).padding(.bottom, 16)
    }
    private func activity() {
        controls = true; hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled, !dashboard, !channelSheet, !recordingsSheet, !session.guideDetailsPresented else { return }
            controls = false
            NSCursor.setHiddenUntilMouseMoves(true)
        }
    }
    private func fullscreen() { NSApp.keyWindow?.toggleFullScreen(nil); activity() }
    private func key(_ event: NSEvent) -> Bool {
        guard !channelSheet, !recordingsSheet, !session.guideDetailsPresented, event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        switch event.keyCode {
        case 123, 116: session.change(-1)
        case 124, 121: session.change(1)
        case 53:
            if NSApp.keyWindow?.styleMask.contains(.fullScreen) == true { fullscreen() }
            else { dashboard = true }
        default:
            let text = event.charactersIgnoringModifiers?.lowercased() ?? ""
            switch text {
            case "f": fullscreen()
            case "r": session.toggleRecording()
            case "c": session.toggleCaptions()
            case "m": session.muted.toggle()
            case "l": session.lastChannel()
            case "0"..."9", ".":
                typedNumber += text; numberTask?.cancel()
                numberTask = Task {
                    try? await Task.sleep(for: .seconds(1.2)); guard !Task.isCancelled else { return }
                    if let channel = library.channels.first(where: { $0.number == typedNumber || $0.number.split(separator: ".").first.map(String.init) == typedNumber }) { session.choose(channel) }
                    typedNumber = ""
                }
            default: return false
            }
        }
        return true
    }
}

#if DEBUG
#Preview("Home · Montréal") {
    AntenaPreview { session, library in
        ContentView(session: session, library: library)
    }.frame(width: 1280, height: 820)
}
#endif
