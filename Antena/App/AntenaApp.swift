import SwiftUI
import AppKit

@MainActor
final class AppModel: ObservableObject {
    let library: LibraryStore
    let session: TunerSession
    init() { let store = LibraryStore(persistenceEnabled: !PreviewEnvironment.isActive); library = store; session = TunerSession(library: store) }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static weak var session: TunerSession?
    private var terminationSignal: DispatchSourceSignal?
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !PreviewEnvironment.isActive else { return }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            // terminateLater starts a nested run loop. Schedule outside the main
            // dispatch callback so async cleanup can run on the main actor.
            RunLoop.main.perform(inModes: [.common]) { NSApp.terminate(nil) }
        }
        source.resume()
        terminationSignal = source
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task { @MainActor in
            await Self.session?.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
@main
struct AntenaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.openWindow) private var openWindow
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup("Antena", id: "main") {
            ContentView(session: model.session, library: model.library)
                .environment(\.locale, L10n.locale)
                .onAppear { AppDelegate.session = model.session }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(L10n.text("About Antena")) { openWindow(id: "about") }
            }
            CommandGroup(replacing: .newItem) {
                Button(L10n.text("Open recording…")) { model.session.openRecording() }.keyboardShortcut("o", modifiers: .command)
            }
            CommandMenu(L10n.text("Television")) {
                Button(L10n.text("Next channel")) { model.session.change(1) }.keyboardShortcut(.rightArrow, modifiers: .command)
                Button(L10n.text("Previous channel")) { model.session.change(-1) }.keyboardShortcut(.leftArrow, modifiers: .command)
                Button(L10n.text("Last channel")) { model.session.lastChannel() }.keyboardShortcut("l", modifiers: .command)
                Divider()
                Button(model.session.isRecording ? L10n.text("Stop recording") : L10n.text("Record broadcast…")) { model.session.toggleRecording() }
                    .keyboardShortcut("r", modifiers: .command)
                Button(L10n.text("Toggle captions")) { model.session.toggleCaptions() }.keyboardShortcut("c", modifiers: [.command, .shift])
            }
        }
        Window(L10n.text("About Antena"), id: "about") {
            AboutView().environment(\.locale, L10n.locale)
        }
        .defaultLaunchBehavior(.suppressed)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        Settings { LanguageSettings().environment(\.locale, L10n.locale) }
    }
}
