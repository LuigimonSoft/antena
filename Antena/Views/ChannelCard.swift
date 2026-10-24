import SwiftUI

struct ChannelCard: View {
    let channel: Channel
    var selected: Bool
    var playing: Bool = false
    var action: () -> Void
    var favorite: () -> Void
    @State private var hovering = false
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Button(action: action) {
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 13).fill(LinearGradient(colors: [AntenaTheme.color(channel.tint), AntenaTheme.color(channel.tint).opacity(0.35), Color.black], startPoint: .topLeading, endPoint: .bottomTrailing))
                    ChannelLogo(channel: channel)
                        .frame(width: 125, height: 35)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .offset(y: -16)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(channel.number).font(.system(size: 15, weight: .bold, design: .rounded))
                            Spacer()
                            if selected && playing { Label(L10n.text("LIVE"), systemImage: "circle.fill").font(.system(size: 8, weight: .bold)).foregroundStyle(AntenaTheme.cyan) }
                        }
                        Spacer()
                        Text(channel.name).font(.system(size: 19, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                        Text(channel.localizedLanguage).font(.system(size: 11)).foregroundStyle(.white.opacity(0.75))
                    }.padding(15)
                    if selected { Rectangle().fill(AntenaTheme.cyan).frame(height: 3).padding(.horizontal, 13) }
                }
                .frame(height: 128)
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(selected ? AntenaTheme.cyan : .white.opacity(hovering ? 0.6 : 0.10), lineWidth: selected ? 2 : 1))
            }.buttonStyle(.plain).disabled(!channel.canTune)
            HStack {
                Text([channel.standardLabel, channel.receptionSummary].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 10)).foregroundStyle(AntenaTheme.muted)
                Spacer()
                Button(action: favorite) { Image(systemName: channel.favorite ? "heart.fill" : "heart").foregroundStyle(channel.favorite ? AntenaTheme.cyan : AntenaTheme.muted) }
                    .buttonStyle(.plain).help(L10n.text("Add or remove favorite"))
            }
        }
        .frame(width: 224).foregroundStyle(.white)
        .onHover { hovering = $0 }
        .scaleEffect(hovering ? 1.015 : 1)
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

#if DEBUG
#Preview("Channel cards") {
    HStack(spacing: 18) {
        ChannelCard(channel: Channel.montreal[0], selected: true, playing: true, action: {}, favorite: {})
        ChannelCard(channel: Channel.montreal[1], selected: false, action: {}, favorite: {})
        ChannelCard(channel: Channel.montreal[2], selected: false, action: {}, favorite: {})
    }.padding(24).background(AntenaTheme.background).preferredColorScheme(.dark)
}
#endif
