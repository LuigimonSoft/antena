import SwiftUI

struct DashboardView: View {
    @ObservedObject var session: TunerSession
    @ObservedObject var library: LibraryStore
    let watch: () -> Void
    let channels: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 18) {
                    Label(L10n.text("LIVE NOW"), systemImage: "dot.radiowaves.left.and.right")
                        .font(.system(size: 10, weight: .bold)).tracking(2.5).foregroundStyle(AntenaTheme.cyan)
                    HStack(alignment: .center, spacing: 18) {
                        if let channel = session.current {
                            ChannelLogo(channel: channel)
                                .frame(width: 104, height: 60)
                                .fixedSize()
                        }
                        Text(session.current?.name ?? L10n.text("Your TV.\nLive."))
                            .font(.system(size: 53, weight: .bold)).tracking(-2)
                            .lineLimit(1).minimumScaleFactor(0.65)
                    }
                    Text(L10n.format("Channel %@ · %@ · %@", session.current?.number ?? "—", session.current?.localizedLanguage ?? "ATSC", library.city))
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                    if session.isLive { CurrentProgramView(programs: session.guidePrograms) }
                    if session.phase != .playing {
                        Text(session.detail)
                            .font(.system(size: 13)).foregroundStyle(AntenaTheme.muted).lineLimit(3).frame(maxWidth: 350, alignment: .leading)
                    }
                    HStack(spacing: 10) {
                        Button(action: watch) { Label(L10n.text("Watch channel"), systemImage: "play.fill") }.buttonStyle(CapsuleAction(prominent: true))
                        if let channel = session.current {
                            Button { library.toggleFavorite(channel) } label: {
                                Image(systemName: library.channels.first(where: { $0.id == channel.id })?.favorite == true ? "heart.fill" : "heart")
                            }.buttonStyle(CapsuleAction()).help(L10n.text("Favorite"))
                        }
                        Button { session.change(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(CapsuleAction()).help(L10n.text("Previous channel"))
                        Button { session.change(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(CapsuleAction()).help(L10n.text("Next channel"))
                    }.padding(.top, 10)
                }.frame(width: 600, alignment: .leading)
                Spacer(minLength: 0)
                VStack {
                    Spacer()
                    if session.phase == .playing {
                        Button(action: watch) {
                            Label(L10n.text("Expand broadcast"), systemImage: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 11, weight: .medium)).padding(12)
                                .background(.black.opacity(0.35), in: Capsule())
                        }.buttonStyle(.plain)
                    }
                }.padding(.bottom, 30)
            }
            .padding(.horizontal, 44).padding(.top, 30).padding(.bottom, 18)
            .frame(maxHeight: .infinity)
            if session.isLive {
                ProgramTimelineView(programs: session.guidePrograms, collecting: session.guideCollecting, onDetailsChange: { session.guideDetailsPresented = $0 })
                    .padding(.horizontal, 44).padding(.top, 12)
                    .background(AntenaTheme.background.opacity(0.7))
            }
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(L10n.text("Your channels")).font(.system(size: 18, weight: .bold))
                    Text("\(library.channels.count)").font(.system(size: 11, weight: .semibold)).foregroundStyle(AntenaTheme.muted)
                    Spacer()
                    Button(action: channels) { Label(L10n.text("Manage channels"), systemImage: "slider.horizontal.3") }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(AntenaTheme.muted)
                }.padding(.horizontal, 44)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(library.channels) { channel in
                            ChannelCard(channel: channel, selected: session.current?.id == channel.id, playing: session.phase == .playing && session.playbackFile == nil, action: { session.choose(channel) }, favorite: { library.toggleFavorite(channel) })
                        }
                        Button(action: channels) {
                            VStack(spacing: 12) {
                                Image(systemName: "plus").font(.system(size: 24, weight: .light))
                                Text(L10n.text("Add a channel")).font(.system(size: 12, weight: .medium))
                            }.frame(width: 160, height: 128)
                                .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 13))
                                .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [5])))
                                .foregroundStyle(AntenaTheme.muted)
                        }.buttonStyle(.plain).padding(.bottom, 22)
                    }.padding(.horizontal, 44).padding(.vertical, 5)
                }
                HStack(spacing: 22) {
                    Label(session.phase == .playing ? L10n.text("ATSC signal received") : L10n.text("Over-the-air TV · ATSC"), systemImage: "antenna.radiowaves.left.and.right")
                    Spacer()
                    Text(L10n.text("← →  change channel"))
                    Text(L10n.text("F  full screen"))
                    Text(L10n.text("R  record"))
                }.font(.system(size: 10)).foregroundStyle(AntenaTheme.muted.opacity(0.85)).padding(.horizontal, 44).padding(.top, 7)
            }
            .padding(.top, 15).padding(.bottom, 25)
            .background(LinearGradient(colors: [AntenaTheme.background.opacity(0), AntenaTheme.background, AntenaTheme.background], startPoint: .top, endPoint: .bottom))
        }
        .foregroundStyle(.white)
    }
}

#if DEBUG
#Preview("Dashboard") {
    AntenaPreview { session, library in
        ZStack {
            PreviewVideo()
            DashboardView(session: session, library: library, watch: {}, channels: {})
        }
    }.frame(width: 1280, height: 760)
}
#endif
