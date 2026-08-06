import AppKit
import Intents

/// Decides whether automatic peeks should stay quiet right now. Full screen
/// video is the complaint you get first, so the checks run before every
/// peek raise; hover still works, suppression only stops Dundu volunteering.
@MainActor
enum PeekSuppression {
    struct Verdict {
        var suppressed: Bool
        var reason: String?
    }

    static func evaluate(on screen: NSScreen?) -> Verdict {
        if !MacPrefs.showPeeksWhilePresenting {
            if isDisplayCaptured(screen) {
                return Verdict(suppressed: true, reason: "screen shared")
            }
            if hasFullScreenForeignWindow(on: screen) {
                return Verdict(suppressed: true, reason: "full screen app")
            }
        }
        if !MacPrefs.showPeeksDuringFocus, isFocusActive {
            return Verdict(suppressed: true, reason: "focus")
        }
        return Verdict(suppressed: false, reason: nil)
    }

    /// Screen sharing / recording / mirroring of the panel's display.
    private static func isDisplayCaptured(_ screen: NSScreen?) -> Bool {
        guard let screen,
              let number = screen.deviceDescription[
                  NSDeviceDescriptionKey("NSScreenNumber")
              ] as? NSNumber else { return false }
        let displayID = CGDirectDisplayID(number.uint32Value)
        return CGDisplayIsInMirrorSet(displayID) != 0
    }

    /// A foreign window at base level covering the whole screen means a
    /// full-screen app (video, Keynote, a game) owns the display.
    private static func hasFullScreenForeignWindow(on screen: NSScreen?) -> Bool {
        guard let screen else { return false }
        // CGWindow coordinates are top-left based; compare sizes only plus a
        // small tolerance, which is enough to identify "covers this screen".
        let screenSize = screen.frame.size
        let ownPID = ProcessInfo.processInfo.processIdentifier

        let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] ?? []

        for window in windows {
            guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = window[kCGWindowOwnerPID as String] as? Int, pid != ownPID,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let width = bounds["Width"], let height = bounds["Height"]
            else { continue }
            if abs(width - screenSize.width) < 2 && abs(height - screenSize.height) < 2 {
                return true
            }
        }
        return false
    }

    /// Focus state through the Intents framework. Reads as false until the
    /// user grants focus-status authorization (requested at startup).
    private static var isFocusActive: Bool {
        guard INFocusStatusCenter.default.authorizationStatus == .authorized else {
            return false
        }
        return INFocusStatusCenter.default.focusStatus.isFocused ?? false
    }

    static func requestFocusAuthorizationIfNeeded() {
        if INFocusStatusCenter.default.authorizationStatus == .notDetermined {
            INFocusStatusCenter.default.requestAuthorization { _ in }
        }
    }
}
