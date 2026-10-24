import SwiftUI

struct LanguageSettings: View {
    @AppStorage(L10n.preferenceKey) private var language = "system"
    var body: some View {
        Form {
            Picker(L10n.text("Interface language"), selection: $language) {
                Text(L10n.text("Follow macOS")).tag("system")
                Text("English").tag("en")
                Text("Español").tag("es")
                Text("Français").tag("fr")
            }
            Text(L10n.text("Language changes take effect the next time you open Antena."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(14).frame(width: 460)
    }
}

#if DEBUG
#Preview("Language settings") { LanguageSettings().disabled(true) }
#endif
