import AppKit
import SwiftUI

struct VideoSurface: NSViewRepresentable {
    let session: TunerSession
    func makeNSView(context: Context) -> NSView {
        if session.isPreview { return NSHostingView(rootView: PreviewVideo()) }
        let view = NSView()
        view.wantsLayer = true; view.layer?.backgroundColor = NSColor.black.cgColor
        session.attach(view)
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {}
}

/// Window-level input keeps working when libVLC adds its own video subview.
struct WindowInput: NSViewRepresentable {
    var onActivity: () -> Void
    var onKey: (NSEvent) -> Bool
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.view = view
        if !PreviewEnvironment.isActive { context.coordinator.install() }
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.activity = onActivity; context.coordinator.key = onKey
        view.window?.acceptsMouseMovedEvents = true
    }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) { coordinator.remove() }
    final class Coordinator {
        weak var view: NSView?
        var activity: (() -> Void)?
        var key: ((NSEvent) -> Bool)?
        private var monitor: Any?
        func install() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .scrollWheel, .keyDown]) { [weak self] event in
                guard let self, let window = self.view?.window, event.window === window else { return event }
                self.activity?()
                if event.type == .keyDown, !(window.firstResponder is NSTextView), self.key?(event) == true { return nil }
                return event
            }
        }
        func remove() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
        deinit { remove() }
    }
}

#if DEBUG
#Preview("Video surface") {
    AntenaPreview { session, _ in
        VideoSurface(session: session)
    }.frame(width: 960, height: 540)
}
#endif
