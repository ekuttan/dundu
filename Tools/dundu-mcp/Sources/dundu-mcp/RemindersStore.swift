import EventKit
import Foundation
import CryptoKit

/// A reminder as it crosses the process boundary. `EKReminder` is neither
/// Sendable nor JSON, so nothing above this layer ever sees one.
struct ReminderSnapshot: Sendable, Codable {
    var id: String
    var externalID: String? = nil
    var title: String
    var notes: String?
    var due: String?
    var list: String
    var isCompleted: Bool
    var priority: Int
}

struct ListSnapshot: Sendable, Codable {
    var id: String
    var title: String
    var isDefault: Bool
}

enum RemindersError: LocalizedError {
    case accessDenied
    case noSuchList(String)
    case noSuchReminder(String)
    case badDate(String)
    case unsafeDuplicate(String)

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            "Reminders access was refused. Grant it in System Settings › Privacy & Security › Reminders, then retry."
        case .noSuchList(let name):
            "No reminders list called “\(name)”. Call list_lists to see what exists."
        case .noSuchReminder(let id):
            "No reminder with id \(id). It may have been completed or deleted already."
        case .badDate(let raw):
            "Couldn't read “\(raw)” as a date. Use ISO 8601 (2026-08-17T09:00:00Z), “2026-08-17 09:00”, or “2026-08-17”."
        case .unsafeDuplicate(let reason):
            "Duplicate cleanup refused: \(reason)"
        }
    }
}

/// Owns the one `EKEventStore`. An actor because `EKEventStore` is not
/// Sendable: keeping it isolated is what lets the rest of the server be
/// ordinary concurrent Swift.
actor RemindersStore {
    private let store = EKEventStore()
    private var hasAccess = false

    /// Asked once per process. macOS shows the prompt the first time this
    /// binary runs; after that TCC answers from its own record.
    func ensureAccess() async throws {
        guard !hasAccess else { return }
        let granted = try await store.requestFullAccessToReminders()
        guard granted else { throw RemindersError.accessDenied }
        hasAccess = true
    }

    func lists() async throws -> [ListSnapshot] {
        try await ensureAccess()
        let defaultID = store.defaultCalendarForNewReminders()?.calendarIdentifier
        return store.calendars(for: .reminder).map {
            ListSnapshot(
                id: $0.calendarIdentifier,
                title: $0.title,
                isDefault: $0.calendarIdentifier == defaultID
            )
        }
    }

    func add(
        title: String,
        notes: String?,
        due: Date?,
        includesTime: Bool,
        listName: String?,
        priority: Int?
    ) async throws -> ReminderSnapshot {
        try await ensureAccess()

        let calendar = try resolveList(named: listName)
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = calendar
        reminder.title = title
        reminder.notes = notes
        if let priority { reminder.priority = priority }
        if let due {
            // A date with no time is an all-day reminder; including the hour
            // is what makes Reminders actually alert at it.
            var units: Set<Calendar.Component> = [.year, .month, .day]
            if includesTime { units.formUnion([.hour, .minute]) }
            reminder.dueDateComponents = Calendar.current.dateComponents(units, from: due)
            if includesTime {
                reminder.addAlarm(EKAlarm(absoluteDate: due))
            }
        }

        try store.save(reminder, commit: true)
        return snapshot(reminder)
    }

    func reminders(listName: String?, includeCompleted: Bool) async throws -> [ReminderSnapshot] {
        try await ensureAccess()

        let calendars = try listName.map { [try resolveList(named: $0)] }
            ?? store.calendars(for: .reminder)
        let predicate = store.predicateForReminders(in: calendars)

        // The completion hands back EKReminders on an arbitrary thread, so
        // they are turned into snapshots before they go anywhere.
        let snapshots: [ReminderSnapshot] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { found in
                let mapped = (found ?? [])
                    .filter { includeCompleted || !$0.isCompleted }
                    .map { reminder in
                        ReminderSnapshot(
                            id: reminder.calendarItemIdentifier,
                            externalID: reminder.calendarItemExternalIdentifier,
                            title: reminder.title ?? "",
                            notes: reminder.notes,
                            due: reminder.dueDateComponents
                                .flatMap { Calendar.current.date(from: $0) }
                                .map(DateText.iso),
                            list: reminder.calendar.title,
                            isCompleted: reminder.isCompleted,
                            priority: reminder.priority
                        )
                    }
                continuation.resume(returning: mapped)
            }
        }

        return snapshots.sorted { lhs, rhs in
            switch (lhs.due, rhs.due) {
            case let (l?, r?): l < r
            case (_?, nil): true
            case (nil, _?): false
            case (nil, nil): lhs.title < rhs.title
            }
        }
    }

    func complete(id: String) async throws -> ReminderSnapshot {
        try await ensureAccess()
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
            throw RemindersError.noSuchReminder(id)
        }
        reminder.isCompleted = true
        try store.save(reminder, commit: true)
        return snapshot(reminder)
    }

    /// Deliberate cleanup of one explicitly selected pair, never a title
    /// sweep. Review first, then submit the returned token to remove only
    /// the selected copy. Any intervening edit invalidates that token.
    func removeDuplicate(
        keepID: String, removeID: String, expectedTitle: String,
        dryRun: Bool, reviewToken: String?
    ) async throws -> DuplicateReview {
        try await ensureAccess()
        guard keepID != removeID,
              let keep = store.calendarItem(withIdentifier: keepID) as? EKReminder,
              let remove = store.calendarItem(withIdentifier: removeID) as? EKReminder else {
            throw RemindersError.unsafeDuplicate("select two different, existing reminders")
        }
        guard keep.title == expectedTitle, remove.title == expectedTitle,
              keep.calendar.calendarIdentifier == remove.calendar.calendarIdentifier,
              keep.notes == remove.notes, keep.url == remove.url,
              keep.location == remove.location, keep.timeZone == remove.timeZone,
              keep.priority == remove.priority,
              // Dundu's historical create path omitted startDateComponents.
              // Allow keeping the richer record when the selected copy
              // has none; never discard a distinct start date.
              (keep.startDateComponents == remove.startDateComponents || remove.startDateComponents == nil),
              keep.dueDateComponents == remove.dueDateComponents,
              !keep.isCompleted, !remove.isCompleted,
              keep.completionDate == nil, remove.completionDate == nil,
              !keep.hasRecurrenceRules, !remove.hasRecurrenceRules,
              (keep.alarms ?? []).isEmpty, (remove.alarms ?? []).isEmpty else {
            let fields: [(String, Bool)] = [
                ("title", keep.title == remove.title && keep.title == expectedTitle),
                ("list", keep.calendar.calendarIdentifier == remove.calendar.calendarIdentifier),
                ("notes", keep.notes == remove.notes), ("URL", keep.url == remove.url),
                ("location", keep.location == remove.location), ("time zone", keep.timeZone == remove.timeZone),
                ("priority", keep.priority == remove.priority),
                ("start date", keep.startDateComponents == remove.startDateComponents),
                ("due date", keep.dueDateComponents == remove.dueDateComponents),
                ("completion", !keep.isCompleted && !remove.isCompleted && keep.completionDate == nil && remove.completionDate == nil),
                ("recurrence", !keep.hasRecurrenceRules && !remove.hasRecurrenceRules),
                ("alarms", (keep.alarms ?? []).isEmpty && (remove.alarms ?? []).isEmpty),
            ]
            let startDetail = keep.startDateComponents == remove.startDateComponents ? "" :
                "; kept start: \(String(describing: keep.startDateComponents)); selected copy start: \(String(describing: remove.startDateComponents))"
            throw RemindersError.unsafeDuplicate("review these fields manually: " + fields.filter { !$0.1 }.map(\.0).joined(separator: ", ") + startDetail)
        }
        guard remove.calendar.allowsContentModifications else {
            throw RemindersError.unsafeDuplicate("the list is read-only")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let record = DuplicateReview(
            kept: snapshot(keep), removed: snapshot(remove),
            keptCreatedAt: keep.creationDate, removedCreatedAt: remove.creationDate,
            keptModifiedAt: keep.lastModifiedDate, removedModifiedAt: remove.lastModifiedDate,
            keptStartDateComponents: keep.startDateComponents.map { String(describing: $0) },
            removedStartDateComponents: remove.startDateComponents.map { String(describing: $0) },
            applied: false, reviewToken: ""
        )
        let digest = SHA256.hash(data: try encoder.encode(record))
            .map { String(format: "%02x", $0) }.joined()
        var result = record
        result.reviewToken = digest
        if !dryRun {
            guard reviewToken == digest else {
                throw RemindersError.unsafeDuplicate("review the current pair first; the token is missing or stale")
            }
            try store.remove(remove, commit: true)
            result.applied = true
        }
        return result
    }

    // MARK: - Helpers

    private func resolveList(named name: String?) throws -> EKCalendar {
        let calendars = store.calendars(for: .reminder)
        guard let name else {
            guard let fallback = store.defaultCalendarForNewReminders() ?? calendars.first else {
                throw RemindersError.noSuchList("default")
            }
            return fallback
        }
        // Case-insensitive so "hoomans" finds "Hoomans" — the name is going
        // to arrive the way somebody said it out loud.
        guard let match = calendars.first(where: {
            $0.title.compare(name, options: .caseInsensitive) == .orderedSame
        }) ?? calendars.first(where: { $0.calendarIdentifier == name }) else {
            throw RemindersError.noSuchList(name)
        }
        return match
    }

    private func snapshot(_ reminder: EKReminder) -> ReminderSnapshot {
        ReminderSnapshot(
            id: reminder.calendarItemIdentifier,
            externalID: reminder.calendarItemExternalIdentifier,
            title: reminder.title ?? "",
            notes: reminder.notes,
            due: reminder.dueDateComponents
                .flatMap { Calendar.current.date(from: $0) }
                .map(DateText.iso),
            list: reminder.calendar.title,
            isCompleted: reminder.isCompleted,
            priority: reminder.priority
        )
    }
}

struct DuplicateReview: Codable, Sendable {
    var kept: ReminderSnapshot
    var removed: ReminderSnapshot
    var keptCreatedAt: Date?
    var removedCreatedAt: Date?
    var keptModifiedAt: Date?
    var removedModifiedAt: Date?
    var keptStartDateComponents: String?
    var removedStartDateComponents: String?
    var applied: Bool
    var reviewToken: String
}

/// Dates in and out. Output is always ISO 8601; input is forgiving, because
/// a model writing "2026-08-17 09:00" means something perfectly clear.
enum DateText {
    nonisolated(unsafe) private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func iso(_ date: Date) -> String { iso8601.string(from: date) }

    /// Returns the date and whether the caller specified a time of day.
    static func parse(_ raw: String) throws -> (date: Date, includesTime: Bool) {
        if let date = iso8601.date(from: raw) { return (date, true) }

        for (format, hasTime) in [("yyyy-MM-dd HH:mm", true),
                                  ("yyyy-MM-dd'T'HH:mm", true),
                                  ("yyyy-MM-dd", false)] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) { return (date, hasTime) }
        }
        throw RemindersError.badDate(raw)
    }
}
