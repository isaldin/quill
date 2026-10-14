import AppKit
import SwiftUI

/// Окна открываются из кода (например, настройки при 401), поэтому это NSWindow, а не SwiftUI-сцены.
@MainActor
final class WindowPresenter {
    private var windows: [String: NSWindow] = [:]

    func show<Content: View>(id: String, title: String, size: NSSize, @ViewBuilder content: () -> Content) {
        if let window = windows[id] {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: content()))
        window.title = title
        window.setContentSize(size)
        window.isReleasedWhenClosed = false
        window.center()
        windows[id] = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
