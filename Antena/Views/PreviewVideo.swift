import SwiftUI

/// Canvas background only: it never opens a file or a USB device.
struct PreviewVideo: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(colors: [Color(red: 0.02, green: 0.08, blue: 0.22), Color(red: 0.12, green: 0.30, blue: 0.55), AntenaTheme.background], startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().stroke(.white.opacity(0.09), lineWidth: 2)
                    .frame(width: geometry.size.height * 0.8)
                    .position(x: geometry.size.width * 0.78, y: geometry.size.height * 0.43)
                VStack(spacing: 18) {
                    Image(systemName: "tv").font(.system(size: 90, weight: .ultraLight))
                    Text(L10n.text("PREVIEW")).font(.system(size: 12, weight: .semibold)).tracking(4)
                    Text(L10n.text("No tuner connection")).font(.caption)
                }.foregroundStyle(.white.opacity(0.5))
                    .position(x: geometry.size.width * 0.77, y: geometry.size.height * 0.39)
            }
        }.clipped()
    }
}

#if DEBUG
#Preview("Design background") {
    PreviewVideo().frame(width: 960, height: 540)
}
#endif
