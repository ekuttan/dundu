import Foundation

/// Mac-side preferences. Raw UserDefaults keys, exposed once so the
/// Settings scene and the panel controller cannot drift apart.
enum MacPrefs {
    static let notchDisplayIDKey = "notchDisplayID"
    static let peeksWhilePresentingKey = "showPeeksWhilePresenting"
    static let peeksDuringFocusKey = "showPeeksDuringFocus"

    /// CGDirectDisplayID of the chosen screen; 0 means automatic (built-in
    /// notch display first, then main).
    static var notchDisplayID: UInt32 {
        get { UInt32(UserDefaults.standard.integer(forKey: notchDisplayIDKey)) }
        set { UserDefaults.standard.set(Int(newValue), forKey: notchDisplayIDKey) }
    }

    /// Spec defaults to suppressing peeks during presentations, sharing, and
    /// Focus; both toggles override toward "show anyway".
    static var showPeeksWhilePresenting: Bool {
        get { UserDefaults.standard.bool(forKey: peeksWhilePresentingKey) }
        set { UserDefaults.standard.set(newValue, forKey: peeksWhilePresentingKey) }
    }

    static var showPeeksDuringFocus: Bool {
        get { UserDefaults.standard.bool(forKey: peeksDuringFocusKey) }
        set { UserDefaults.standard.set(newValue, forKey: peeksDuringFocusKey) }
    }
}
