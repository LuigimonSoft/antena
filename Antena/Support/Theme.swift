import SwiftUI

enum AntenaTheme {
    static let background = Color(red: 0.035, green: 0.045, blue: 0.09)
    static let cyan = Color(red: 0.42, green: 0.88, blue: 0.98)
    static let muted = Color(red: 0.64, green: 0.67, blue: 0.77)
    static let colors: [Color] = [.init(red: 0.13, green: 0.29, blue: 0.72), .init(red: 0.62, green: 0.12, blue: 0.20), .init(red: 0.19, green: 0.43, blue: 0.35), .init(red: 0.39, green: 0.20, blue: 0.65)]
    static func color(_ index: Int) -> Color { colors[abs(index) % colors.count] }
    static func time(_ seconds: Int) -> String { String(format: "%02d:%02d", seconds / 60, seconds % 60) }
}
struct CapsuleAction: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 18).padding(.vertical, 12)
            .foregroundStyle(prominent ? Color.black : Color.white)
            .background(prominent ? Color.white : Color.white.opacity(configuration.isPressed ? 0.25 : 0.13), in: RoundedRectangle(cornerRadius: 10))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}
