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
                NotchItem(id: UUID(), title: "Call the accountant", dueDate: now.addingTimeInterval(-1800), isOverdue: true),
                NotchItem(id: UUID(), title: "Send the deck", dueDate: now.addingTimeInterval(-300), isOverdue: true),
            ]
            upcoming = [
                NotchItem(id: UUID(), title: "Pick up the car", dueDate: now.addingTimeInterval(3600), isOverdue: false),
                NotchItem(id: UUID(), title: "Review the filing", dueDate: now.addingTimeInterval(2 * 3600), isOverdue: false),
            ]
            return
        }

        let open = (try? context.fetch(FetchDescriptor<ReminderItem>(
            predicate: #Predicate { $0.tombstonedAt == nil && !$0.isCompleted }
        ))) ?? []

        items = ScheduleCalculator.dueReminders(open, now: now)
            .prefix(5)
            .map { NotchItem(id: $0.scheduleID, title: $0.scheduleTitle, dueDate: $0.scheduleDate, isOverdue: true) }

        upcoming = open
            .filter { ($0.dueDate.map { $0 > now }) ?? false }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
            .prefix(5)
            .map { NotchItem(id: $0.id, title: $0.title, dueDate: $0.dueDate, isOverdue: false) }

        // Events join in M11; until then the next fire is the next due
        // reminder with a time.
        nextFire = ScheduleCalculator.nextFire(reminders: open, events: [], now: now)

        inboxCount = ((try? context.fetch(FetchDescriptor<ReminderItem>(
            predicate: #Predicate { $0.tombstonedAt == nil && $0.reviewStateRaw == "pending" }
        ))) ?? []).count
    }
}
