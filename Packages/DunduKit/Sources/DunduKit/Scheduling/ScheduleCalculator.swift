import Foundation

/// Why the notch wants to appear.
public enum PeekReason: Sendable, Equatable {
    /// A reminder is due. Stays until completed, snoozed, or dismissed.
    case reminderDue(id: UUID, title: String)
    /// A meeting starts soon. Fires `leadTime` ahead of the start.
    case meetingSoon(id: UUID, title: String, startsAt: Date)
}

public struct ScheduledFire: Sendable, Equatable {
    public var date: Date
    public var reason: PeekReason

    public init(date: Date, reason: PeekReason) {
        self.date = date
        self.reason = reason
    }
}

/// Pure next-due / next-meeting calculation. The platform timer (M5) arms
/// itself from these results; nothing here touches a clock or a store.
public enum ScheduleCalculator {
    /// Default lead time before a meeting peek: 5 minutes.
    public static let defaultMeetingLeadTime: TimeInterval = 5 * 60

    /// Reminders currently due and not done, most overdue first.
    public static func dueReminders(_ reminders: [any Schedulable], now: Date) -> [any Schedulable] {
        reminders
            .filter { !$0.scheduleIsDone }
            .filter { ($0.scheduleDate.map { $0 <= now }) ?? false }
            .sorted { ($0.scheduleDate ?? .distantPast) < ($1.scheduleDate ?? .distantPast) }
    }

    /// The next moment the notch should wake up, or nil if nothing is ahead.
    public static func nextFire(
        reminders: [any Schedulable],
        events: [any Schedulable],
        meetingLeadTime: TimeInterval = defaultMeetingLeadTime,
        now: Date
    ) -> ScheduledFire? {
        var candidates: [ScheduledFire] = []

        for reminder in reminders where !reminder.scheduleIsDone && !reminder.scheduleIsAllDay {
            if let due = reminder.scheduleDate, due > now {
                candidates.append(ScheduledFire(
                    date: due,
                    reason: .reminderDue(id: reminder.scheduleID, title: reminder.scheduleTitle)
                ))
            }
        }

        for event in events where !event.scheduleIsDone && !event.scheduleIsAllDay {
            if let start = event.scheduleDate, start.addingTimeInterval(-meetingLeadTime) > now {
                candidates.append(ScheduledFire(
                    date: start.addingTimeInterval(-meetingLeadTime),
                    reason: .meetingSoon(id: event.scheduleID, title: event.scheduleTitle, startsAt: start)
                ))
            }
        }

        return candidates.min { $0.date < $1.date }
    }
}
