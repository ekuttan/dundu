import AppKit
import DunduKit

/// Holds the next fire date in a DispatchSourceTimer and pokes its owner
/// when it arrives. Rearmed on every item change, sync pass, and machine
/// wake — the timer itself is the fourth trigger.
@MainActor
final class NotchScheduler {
    private var timer: DispatchSourceTimer?
    private var wakeObserver: NSObjectProtocol?
    private var syncObserver: NSObjectProtocol?

    var onFire: (() -> Void)?

    init() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in NotchPanel.shared?.refresh() }
        }
        syncObserver = NotificationCenter.default.addObserver(
            forName: ReminderSyncService.syncDidFinish, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in NotchPanel.shared?.refresh() }
        }
    }

    /// Arms the timer for the given date, or disarms when nil. A date in the
    /// past fires immediately.
    func rearm(for date: Date?) {
        timer?.cancel()
        timer = nil
        guard let date else { return }

        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + max(0, date.timeIntervalSinceNow))
        source.setEventHandler { [weak self] in
            self?.onFire?()
        }
        source.resume()
        timer = source
    }

    deinit {
        timer?.cancel()
    }
}
