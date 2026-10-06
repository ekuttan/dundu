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
    /// List name for a reminder, location or time range for an event.
    var subtitle: String? = nil
    var endDate: Date? = nil

    /// Running now, for the agenda's "live" marker.
    func isInProgress(at now: Date = Date()) -> Bool {
        guard let dueDate, let endDate else { return false }
        return dueDate <= now && endDate > now
    }
}

/// Open items in one list, for the Tasks page's breakdown.
struct ListTally: Identifiable, Equatable {
    var id: UUID
    var name: String
    var open: Int
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
    /// Which dock page the expanded panel is showing.
    var page: NotchPage = .dashboard
    /// Pinned panels ignore the mouse leaving — the user is reading.
    var isPinned = false
    /// Items completed in the notch, inside their 3-second undo window.
    var pendingUndo: Set<UUID> = []
    /// Everything on today's calendar, chronological, for the agenda page.
    private(set) var agenda: [NotchItem] = []
    /// Captures waiting to be reviewed.
    private(set) var inboxItems: [NotchItem] = []
    private(set) var openCount = 0
    private(set) var overdueCount = 0
    private(set) var doneToday = 0
    /// Open items per list, busiest first.
    private(set) var listTallies: [ListTally] = []
    /// When the scheduler should next wake the panel.
    private(set) var nextFire: ScheduledFire?
    /// Open Inbox questions; the expanded panel shows a small dot.
    private(set) var inboxCount = 0

    /// How tall the panel is right now. The reference shrinks the panel to
    /// its content rather than padding every page out to the tallest one, and
    /// the dock rides up with it — so this depends on what the page is
    /// actually showing, not just which page it is.
    var panelHeight: CGFloat {
        switch page {
        case .focus: 350
        case .inbox: 400
        case .coding:
            AgentSessionWatcher.shared.sessions.isEmpty ? 362 : 420
        default: 400
        }
    }

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
                NotchItem(id: UUID(), title: "Pick up the car", dueDate: now.addingTimeInterval(3600), isOverdue: false, subtitle: "Personal"),
                NotchItem(id: UUID(), title: "Design review", dueDate: now.addingTimeInterval(2 * 3600), isOverdue: false, isMeeting: true),
                NotchItem(id: UUID(), title: "Renew the domain", dueDate: now.addingTimeInterval(5 * 3600), isOverdue: false, subtitle: "Work"),
            ]
            items[1].subtitle = "Work"
            let day = Calendar.current.startOfDay(for: now)
            func at(_ hour: Int, _ minute: Int = 0) -> Date {
                Calendar.current.date(byAdding: .minute, value: hour * 60 + minute, to: day) ?? now
            }
            agenda = [
                NotchItem(
                    id: UUID(), title: "Standup", dueDate: at(9, 30), isOverdue: false,
                    isMeeting: true, joinURL: URL(string: "https://meet.google.com/abc-defg-hij"),
                    subtitle: "Engineering", endDate: at(9, 45)
                ),
                NotchItem(
                    id: UUID(), title: "Investor call", dueDate: now.addingTimeInterval(-600),
                    isOverdue: false, isMeeting: true,
                    joinURL: URL(string: "https://meet.google.com/abc-defg-hij"),
                    subtitle: "Zoom", endDate: now.addingTimeInterval(1800)
                ),
                NotchItem(
                    id: UUID(), title: "Design review with the team", dueDate: at(16),
                    isOverdue: false, isMeeting: true,
                    joinURL: URL(string: "https://meet.google.com/abc-defg-hij"),
                    subtitle: "Studio", endDate: at(17)
                ),
            ]
            inboxItems = [
                NotchItem(id: UUID(), title: "Call the vet about Suki", dueDate: nil, isOverdue: false, subtitle: "Personal"),
                NotchItem(id: UUID(), title: "Follow up on the lease", dueDate: now.addingTimeInterval(86_400), isOverdue: false, subtitle: "Work"),
                NotchItem(id: UUID(), title: "Book the flights", dueDate: nil, isOverdue: false, subtitle: "Travel"),
            ]
            inboxCount = inboxItems.count
            agenda.sort { ($0.dueDate ?? .distantPast) < ($1.dueDate ?? .distantPast) }
            listTallies = [
                ListTally(id: UUID(), name: "Work", open: 7),
                ListTally(id: UUID(), name: "Personal", open: 5),
                ListTally(id: UUID(), name: "Travel", open: 2),
            ]
            openCount = 14
            overdueCount = 2
            doneToday = 6
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

        let pending = ((try? context.fetch(FetchDescriptor<ReminderItem>(
            predicate: #Predicate { $0.tombstonedAt == nil && $0.reviewStateRaw == "pending" }
        ))) ?? []).sorted { $0.createdAt > $1.createdAt }
        inboxCount = pending.count

        refreshPages(context: context, open: open, events: events, pending: pending, now: now)
    }

    /// The dock's other pages. Separated from the peek's data because it is
    /// read only while the panel is open, and because the peek must stay
    /// cheap — it runs on a timer all day.
    private func refreshPages(
        context: ModelContext,
        open: [ReminderItem],
        events: [CalendarEvent],
        pending: [ReminderItem],
        now: Date
    ) {
        let lists = (try? context.fetch(FetchDescriptor<ReminderList>())) ?? []
        let names = Dictionary(lists.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })

        openCount = open.count
        overdueCount = open.filter { ($0.dueDate.map { $0 <= now }) ?? false }.count

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: now)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? now

        doneToday = ((try? context.fetch(FetchDescriptor<ReminderItem>(
            predicate: #Predicate { $0.tombstonedAt == nil && $0.isCompleted }
        ))) ?? []).filter { ($0.completedAt.map { $0 >= startOfDay }) ?? false }.count

        listTallies = lists
            .filter { $0.tombstonedAt == nil }
            .map { list in
                ListTally(
                    id: list.id,
                    name: list.title,
                    open: open.count { $0.listID == list.id }
                )
            }
            .filter { $0.open > 0 }
            .sorted { $0.open == $1.open ? $0.name < $1.name : $0.open > $1.open }

        // Already-finished meetings stay on the agenda: the page answers
        // "what is today", not "what is left".
        agenda = ((try? context.fetch(FetchDescriptor<CalendarEvent>(
            predicate: #Predicate { $0.tombstonedAt == nil }
        ))) ?? [])
            .filter { $0.startAt < endOfDay && $0.endAt > startOfDay }
            .sorted { $0.startAt < $1.startAt }
            .map { event in
                NotchItem(
                    id: event.id, title: event.title, dueDate: event.startAt,
                    isOverdue: false, isMeeting: true, joinURL: event.conferenceURL,
                    subtitle: event.isAllDay ? "All day" : event.location,
                    endDate: event.endAt
                )
            }

        inboxItems = pending.prefix(8).map { item in
            NotchItem(
                id: item.id, title: item.title, dueDate: item.dueDate,
                isOverdue: (item.dueDate.map { $0 <= now }) ?? false,
                subtitle: item.listID.flatMap { names[$0] }
            )
        }

        // List names on the task rows: with several lists in play, "Call the
        // vet" and "Call the vet" are only tellable apart by where they live.
        items = items.map { annotate($0, open: open, names: names) }
        upcoming = upcoming.map { annotate($0, open: open, names: names) }
    }

    private func annotate(
        _ item: NotchItem, open: [ReminderItem], names: [UUID: String]
    ) -> NotchItem {
        guard !item.isMeeting else { return item }
        var copy = item
        copy.subtitle = open.first { $0.id == item.id }?.listID.flatMap { names[$0] }
        return copy
    }
}
