import Foundation
import Observation
import SwiftData
import DunduKit

/// A row the notch can display. Value type so the panel never holds live
/// SwiftData objects.
struct NotchItem: Identifiable, Equatable {
    var id: UUID
    var title: String
    var dueDate: Date?
    var isOverdue: Bool
    /// Meetings render with a countdown and a Join button, no checkbox.
    var isMeeting: Bool = false
    var joinURL: URL? = nil
}

/// What the notch is showing and why. The panel controller owns transitions;
/// views render this.
@Observable
@MainActor
final class NotchModel {
    var uiState: NotchUIState = .hidden
    /// Currently due, most overdue first. Drives the peek.
    var items: [NotchItem] = []
    /// Scheduled ahead, soonest first. Shown when the panel is opened by
    /// hand — the notch answers "what's next" on hover, any time.
    var upcoming: [NotchItem] = []
    var reduceMotion = false
    /// Items completed in the notch, inside their 3-second undo window.
    var pendingUndo: Set<UUID> = []
    /// When the scheduler should next wake the panel.
    private(set) var nextFire: ScheduledFire?
    /// Open Inbox questions; the expanded panel shows a small dot.
    private(set) var inboxCount = 0

    var peekTitle: String {
        items.first(where: { !pendingUndo.contains($0.id) })?.title ?? ""
    }

    /// Items not mid-undo; what the peek counts.
    var activeCount: Int {
        items.filter { !pendingUndo.contains($0.id) }.count
    }

    var hasContent: Bool { activeCount > 0 }

    /// Reloads due reminders from the store, most overdue first (spec: the
    /// peek shows count and the most urgent title), and recomputes the next
    /// fire date for the scheduler.
    func refresh(context: ModelContext, now: Date = Date()) {
        if ProcessInfo.processInfo.environment["DUNDU_NOTCH_DEMO"] == "1" {
            items = [
                NotchItem(
                    id: UUID(), title: "Investor call", dueDate: now.addingTimeInterval(240),
                    isOverdue: false, isMeeting: true,
                    joinURL: URL(string: "https://meet.google.com/abc-defg-hij")
                ),
                NotchItem(id: UUID(), title: "Send the deck", dueDate: now.addingTimeInterval(-300), isOverdue: true),
            ]
            upcoming = [
                NotchItem(id: UUID(), title: "Pick up the car", dueDate: now.addingTimeInterval(3600), isOverdue: false),
                NotchItem(id: UUID(), title: "Design review", dueDate: now.addingTimeInterval(2 * 3600), isOverdue: false, isMeeting: true),
            ]
            return
        }

        let open = (try? context.fetch(FetchDescriptor<ReminderItem>(
            predicate: #Predicate { $0.tombstonedAt == nil && !$0.isCompleted }
        ))) ?? []
        let lead = ScheduleCalculator.defaultMeetingLeadTime
        let dayAhead = now.addingTimeInterval(24 * 3600)
        let events = ((try? context.fetch(FetchDescriptor<CalendarEvent>(
            predicate: #Predicate { $0.tombstonedAt == nil }
        ))) ?? []).filter { !$0.isAllDay && $0.endAt > now && $0.startAt < dayAhead }

        // A meeting inside its lead window (or running) sits with the due
        // items — probably holding the single most used button in the app.
        let imminent = events
            .filter { $0.startAt.addingTimeInterval(-lead) <= now }
            .sorted { $0.startAt < $1.startAt }
            .map { NotchItem(
                id: $0.id, title: $0.title, dueDate: $0.startAt, isOverdue: false,
                isMeeting: true, joinURL: $0.conferenceURL
            ) }

        items = imminent + ScheduleCalculator.dueReminders(open, now: now)
            .prefix(5)
            .map { NotchItem(id: $0.scheduleID, title: $0.scheduleTitle, dueDate: $0.scheduleDate, isOverdue: true) }

        let futureMeetings = events
            .filter { $0.startAt.addingTimeInterval(-lead) > now }
            .map { NotchItem(
                id: $0.id, title: $0.title, dueDate: $0.startAt, isOverdue: false,
                isMeeting: true, joinURL: $0.conferenceURL
            ) }
        let futureReminders = open
            .filter { ($0.dueDate.map { $0 > now }) ?? false }
            .map { NotchItem(id: $0.id, title: $0.title, dueDate: $0.dueDate, isOverdue: false) }

        upcoming = Array((futureMeetings + futureReminders)
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
            .prefix(5))

        nextFire = ScheduleCalculator.nextFire(reminders: open, events: events, now: now)

        inboxCount = ((try? context.fetch(FetchDescriptor<ReminderItem>(
            predicate: #Predicate { $0.tombstonedAt == nil && $0.reviewStateRaw == "pending" }
        ))) ?? []).count
    }
}
