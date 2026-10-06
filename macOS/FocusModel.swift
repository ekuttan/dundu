import Foundation
import Observation
import UserNotifications

/// Pomodoro, countdown, stopwatch and the hydration nudge.
///
/// Everything is held as a *deadline*, never as a number counted down: a
/// menu bar app sleeps with the lid, and a timer that decrements on a tick
/// would come back from an hour's sleep claiming it still had 20 minutes
/// left. The tick only recomputes what the deadlines already decided.
@Observable
@MainActor
final class FocusModel {
    static let shared = FocusModel()

    struct Countdown: Equatable {
        var label: String
        var length: TimeInterval
        /// Nil while paused; `rest` then holds what is left.
        var endsAt: Date?
        var rest: TimeInterval
        var isBreak = false

        var isRunning: Bool { endsAt != nil }

        init(label: String, length: TimeInterval, isBreak: Bool = false) {
            self.label = label
            self.length = length
            self.rest = length
            self.isBreak = isBreak
        }

        var remaining: TimeInterval {
            endsAt.map { max(0, $0.timeIntervalSinceNow) } ?? rest
        }
    }

    static let workLength: TimeInterval = 25 * 60
    static let breakLength: TimeInterval = 5 * 60

    private(set) var pomodoro = Countdown(label: "Sprint", length: FocusModel.workLength)
    /// Completed sprints today, so the ring means something cumulative.
    private(set) var sprintsDone = 0

    private(set) var countdown: Countdown?
    private(set) var stopwatch: TimeInterval = 0
    private(set) var stopwatchRunning = false
    private var stopwatchStartedAt: Date?
    private var stopwatchBase: TimeInterval = 0

    var hydrationEvery: TimeInterval = 30 * 60
    private(set) var hydrationDue = Date().addingTimeInterval(30 * 60)
    private(set) var glasses = 0

    /// Bumped every tick so views reading `remaining` redraw. Observation
    /// cannot see through a computed property that reads the clock.
    private(set) var tick = 0

    private var ticker: Timer?

    private init() {}

    /// The timer runs whenever anything is counting, panel open or not — a
    /// pomodoro that only advances while you are looking at it is a stopwatch
    /// with extra steps.
    private func syncTicker() {
        let needed = pomodoro.isRunning || countdown?.isRunning == true || stopwatchRunning
        if needed, ticker == nil {
            ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                Task { @MainActor in FocusModel.shared.advance() }
            }
        } else if !needed {
            ticker?.invalidate()
            ticker = nil
        }
    }

    private func advance() {
        tick &+= 1

        if stopwatchRunning, let started = stopwatchStartedAt {
            stopwatch = stopwatchBase + Date().timeIntervalSince(started)
        }

        if pomodoro.isRunning, pomodoro.remaining <= 0 {
            let finished = pomodoro
            if !finished.isBreak { sprintsDone += 1 }
            notify(
                title: finished.isBreak ? "Break over" : "Sprint done",
                body: finished.isBreak ? "Back to it." : "Take five."
            )
            // Work and break alternate on their own; having to press start
            // between them is what makes people abandon the technique.
            var next = Countdown(
                label: finished.isBreak ? "Sprint" : "Break",
                length: finished.isBreak ? Self.workLength : Self.breakLength,
                isBreak: !finished.isBreak
            )
            next.endsAt = Date().addingTimeInterval(next.length)
            pomodoro = next
        }

        if let current = countdown, current.isRunning, current.remaining <= 0 {
            notify(title: current.label, body: "Time's up.")
            countdown = nil
        }

        syncTicker()
    }

    // MARK: - Pomodoro

    func togglePomodoro() {
        if pomodoro.isRunning {
            pomodoro.rest = pomodoro.remaining
            pomodoro.endsAt = nil
        } else {
            pomodoro.endsAt = Date().addingTimeInterval(pomodoro.rest)
        }
        syncTicker()
    }

    func resetPomodoro() {
        pomodoro = Countdown(label: "Sprint", length: Self.workLength)
        syncTicker()
    }

    // MARK: - Countdown

    func startCountdown(label: String, minutes: Int) {
        var fresh = Countdown(label: label, length: TimeInterval(minutes * 60))
        fresh.endsAt = Date().addingTimeInterval(fresh.length)
        countdown = fresh
        syncTicker()
    }

    func cancelCountdown() {
        countdown = nil
        syncTicker()
    }

    // MARK: - Stopwatch

    func toggleStopwatch() {
        if stopwatchRunning {
            stopwatchBase = stopwatch
            stopwatchStartedAt = nil
            stopwatchRunning = false
        } else {
            stopwatchStartedAt = Date()
            stopwatchRunning = true
        }
        syncTicker()
    }

    func resetStopwatch() {
        stopwatchRunning = false
        stopwatchStartedAt = nil
        stopwatchBase = 0
        stopwatch = 0
        syncTicker()
    }

    // MARK: - Hydration

    func drink() {
        glasses += 1
        scheduleHydration()
    }

    /// Handed to the notification centre rather than polled: the nudge has to
    /// arrive on a Mac that has been idle for an hour, and nothing in this
    /// model is running then.
    func scheduleHydration() {
        hydrationDue = Date().addingTimeInterval(hydrationEvery)
        let centre = UNUserNotificationCenter.current()
        centre.removePendingNotificationRequests(withIdentifiers: [Self.hydrationID])
        let content = UNMutableNotificationContent()
        content.title = "Water"
        content.body = "Time for a glass."
        content.sound = .default
        centre.add(UNNotificationRequest(
            identifier: Self.hydrationID,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: hydrationEvery, repeats: true)
        ))
    }

    private static let hydrationID = "dundu.hydration"


    var hydrationRemaining: TimeInterval { max(0, hydrationDue.timeIntervalSinceNow) }

    // MARK: - Formatting

    /// mm:ss, or h:mm:ss once it is worth the extra field.
    static func clock(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// "28m left" — the hydration card wants the coarse version.
    static func coarse(_ interval: TimeInterval) -> String {
        let minutes = Int(interval / 60)
        if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60)m" }
        return "\(max(0, minutes))m"
    }

    // MARK: - Live readouts
    //
    // Each one touches `tick` so that Observation has something stored to
    // watch. A view reading `pomodoro.remaining` directly would register no
    // dependency at all — the clock is not part of the model's state — and
    // would redraw only when the timer was started or stopped.

    var pomodoroClock: String {
        _ = tick
        return Self.clock(pomodoro.remaining)
    }

    var pomodoroFraction: Double {
        _ = tick
        guard pomodoro.length > 0 else { return 0 }
        return 1 - (pomodoro.remaining / pomodoro.length)
    }

    var countdownClock: String? {
        _ = tick
        return countdown.map { Self.clock($0.remaining) }
    }

    var stopwatchClock: String {
        _ = tick
        return Self.clock(stopwatch)
    }

    var hydrationLabel: String {
        _ = tick
        return "\(Self.coarse(hydrationRemaining)) left"
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }
}
