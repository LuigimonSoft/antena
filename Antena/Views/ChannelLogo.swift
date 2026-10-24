import SwiftUI
import AppKit

/// Image data is cached by URL; video playback never uses this disk cache.
struct ChannelLogo: View {
    let channel: Channel
    @State private var downloaded: NSImage?
    private static let memory = NSCache<NSString, NSImage>()
    var body: some View {
        Group {
            if let asset = channel.logoAsset, NSImage(named: asset) != nil {
                Image(asset).resizable().scaledToFit()
            } else if let downloaded {
                Image(nsImage: downloaded).resizable().scaledToFit()
            } else {
                Text(channel.callSign ?? channel.name).font(.system(size: 22, weight: .heavy)).minimumScaleFactor(0.5).lineLimit(1)
            }
        }
        .padding(7)
        .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 7))
        .foregroundStyle(.black)
        .accessibilityLabel(L10n.format("Logo for %@", channel.name))
        .task(id: channel.logoURL) { await load() }
    }
    @MainActor private func load() async {
        downloaded = nil
        guard !PreviewEnvironment.isActive else { return }
        guard channel.logoAsset == nil, let raw = channel.logoURL, let url = URL(string: raw), url.scheme == "https",
              let host = url.host, ["upload.wikimedia.org", "thumb.wikimedia.org"].contains(host) else { return }
        if let image = Self.memory.object(forKey: raw as NSString) { downloaded = image; return }
        do {
            let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard !Task.isCancelled, (response as? HTTPURLResponse)?.statusCode == 200,
                  data.count <= 5_000_000, let image = NSImage(data: data) else { return }
            Self.memory.setObject(image, forKey: raw as NSString)
            downloaded = image
        } catch { /* The station name remains available if a logo cannot be fetched. */ }
    }
}

#if DEBUG
#Preview("Logos") {
    HStack(spacing: 20) {
        ForEach(Array(Channel.montreal.prefix(4))) { channel in
            ChannelLogo(channel: channel).frame(width: 140, height: 65)
        }
    }.padding(24).background(AntenaTheme.background)
}
#endif
