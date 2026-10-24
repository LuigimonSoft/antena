import SwiftUI

struct PlayerControls: View {
    @ObservedObject var session: TunerSession
    let fullscreen: () -> Void
    let dashboard: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 9) {
                    ForEach(session.library.channels) { channel in
                        Button { session.choose(channel) } label: {
                            HStack(spacing: 8) {
                                Text(channel.number).fontWeight(.bold).foregroundStyle(session.current?.id == channel.id ? Color.black : AntenaTheme.cyan)
                                Text(channel.name)
                            }.font(.system(size: 12)).padding(.horizontal, 13).padding(.vertical, 9)
                                .background(session.current?.id == channel.id ? Color.white : Color.white.opacity(0.13), in: RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(session.current?.id == channel.id ? Color.black : Color.white)
                        }.buttonStyle(.plain).disabled(session.scanning || !channel.canTune)
                    }
                }
            }
            HStack(alignment: .bottom, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 7) {
                        Circle().fill(session.playbackFile == nil ? AntenaTheme.cyan : .white.opacity(0.7)).frame(width: 6, height: 6)
                        Text(session.playbackFile == nil ? L10n.text("LIVE TELEVISION") : L10n.text("YOUR RECORDING")).font(.system(size: 10, weight: .bold)).tracking(2)
                    }.foregroundStyle(AntenaTheme.cyan)
                    Text(session.playbackFile?.deletingPathExtension().lastPathComponent ?? session.current?.name ?? "Antena")
                        .font(.system(size: 32, weight: .bold)).lineLimit(1)
                    if session.isLive { CurrentProgramView(programs: session.guidePrograms) }
                    Text(session.detail).font(.system(size: 12)).foregroundStyle(AntenaTheme.muted)
                }
                Spacer(minLength: 8)
                Button { session.change(-1) } label: { Image(systemName: "chevron.left").frame(width: 14) }.buttonStyle(CapsuleAction()).help(L10n.text("Previous channel (←)"))
                Button { session.change(1) } label: { Image(systemName: "chevron.right").frame(width: 14) }.buttonStyle(CapsuleAction()).help(L10n.text("Next channel (→)"))
                Button { session.toggleRecording() } label: {
                    Label(session.isRecording ? L10n.format("Stop · %@", AntenaTheme.time(session.recordingSeconds)) : L10n.text("Record"), systemImage: session.isRecording ? "stop.fill" : "record.circle")
                        .foregroundStyle(session.isRecording ? Color(red: 1, green: 0.35, blue: 0.43) : .white)
                }.buttonStyle(CapsuleAction()).disabled(!session.isRecording && (session.phase != .playing || !session.isLive)).help(L10n.text("Record or stop (R)"))
            }
            if session.isLive {
                ProgramTimelineView(programs: session.guidePrograms, collecting: session.guideCollecting, onDetailsChange: { session.guideDetailsPresented = $0 })
            }
            HStack(spacing: 18) {
                Button(action: dashboard) { Label(L10n.text("Home"), systemImage: "square.grid.2x2") }.buttonStyle(.plain).help(L10n.text("Back to home (Esc)"))
                Spacer()
                Button { session.muted.toggle() } label: { Image(systemName: session.muted ? "speaker.slash.fill" : "speaker.wave.2.fill") }.buttonStyle(.plain).help(L10n.text("Mute (M)"))
                Slider(value: $session.volume, in: 0...100).frame(width: 85).tint(AntenaTheme.cyan).accessibilityLabel(L10n.text("Volume"))
                Menu {
                    Button(L10n.text("Off")) { session.selectCaption(-1) }
                    ForEach(session.captions) { track in
                        Button { session.selectCaption(track.id) } label: {
                            if session.selectedCaption == track.id { Label(track.name, systemImage: "checkmark") }
                            else { Text(track.name) }
                        }
                    }
                    if session.captions.isEmpty { Text(L10n.text("This broadcast does not offer captions yet")) }
                } label: {
                    Image(systemName: session.selectedCaption >= 0 ? "captions.bubble.fill" : "captions.bubble")
                }.menuStyle(.borderlessButton).fixedSize().help(L10n.text("Subtitles and closed captions (C)")).accessibilityLabel(L10n.text("Captions"))
                Button(action: fullscreen) { Image(systemName: "arrow.up.left.and.arrow.down.right") }.buttonStyle(.plain).help(L10n.text("Full screen (F)"))
            }.font(.system(size: 13)).foregroundStyle(.white.opacity(0.82))
        }
        .padding(.horizontal, 44).padding(.bottom, 30).padding(.top, 80)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.82), .black.opacity(0.96)], startPoint: .top, endPoint: .bottom))
        .foregroundStyle(.white)
    }
}

#if DEBUG
#Preview("Player") {
    AntenaPreview { session, _ in
        ZStack(alignment: .bottom) {
            PreviewVideo()
            PlayerControls(session: session, fullscreen: {}, dashboard: {})
        }
    }.frame(width: 1280, height: 720)
}
#endif
