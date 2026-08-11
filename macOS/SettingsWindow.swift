import AppKit
import SwiftUI

/// One way in to Dundu's settings, from the menu bar and from the notch.
///
/// SwiftUI's `Settings` scene is only reachable through `showSettingsWindow:`
/// on the responder chain. An accessory app has no main window, and the notch
/// is a nonactivating panel that never becomes key, so from there the chain
/// can dead-end and the click does nothing at all. The scene is still tried
/// first — when it works, that is the window the user already knows — but a
/// window we own ourselves is the guaranteed path.
@MainActor
enum SettingsWindow {
    private static var owned: NSWindow?

    static func open() {
        // Already showing ours: just bring it forward.
        if let owned {
            NSApp.activate(ignoringOtherApps: true)
            owned.makeKeyAndOrderFront(nil)
            return
        }

        let sent = NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            || NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)

        // The scene opens on the next runloop turn, and an accessory app's
        // window can land behind whatever the user was looking at — so the
        // check and the raise both wait a beat.
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            if sent, let scene = sceneWindow() {
                scene.makeKeyAndOrderFront(nil)
                return
            }
            showOwnWindow()
        }
    }

    /// The `Settings` scene's window, if it opened. Dundu is LSUIElement: the
    /// notch panel and the menu bar extra are both borderless, so a titled
    /// window can only be settings.
    private static func sceneWindow() -> NSWindow? {
        NSApp.windows.first {
            $0 !== owned && $0.isVisible && $0.styleMask.contains(.titled)
        }
    }

    private static func showOwnWindow() {
        let hosting = NSHostingController(rootView: MacSettingsView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "Dundu Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        owned = window

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { owned = nil }
        }

        window.makeKeyAndOrderFront(nil)
    }
}
