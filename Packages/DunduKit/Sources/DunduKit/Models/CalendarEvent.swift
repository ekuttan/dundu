import Foundation
import SwiftData

/// A calendar event in Dundu's own store. Synced two-way with Google Calendar
/// through the Google bridge. Apple-side calendars backed by Google are
/// excluded from EventKit sync so no event ever has two paths.
@Model
public final class CalendarEvent {
    public var id: UUID = UUID()
    public var calendarID: UUID?
    public var title: String = ""
    public var notes: String?
    public var location: String?
    public var startAt: Date = Date()
    public var endAt: Date = Date()
    public var isAllDay: Bool = false
    /// Google stores per-event time zones. Keep them; never normalize to the
    /// device zone.
    public var timeZoneID: String = TimeZone.current.identifier
    public var attendees: [AttendeeRecord] = []
    /// Extracted from `conferenceData` or `hangoutLink`.
    public var conferenceURL: URL?
    /// Raw RRULE strings, round-tripped, never interpreted.
    public var recurrenceRules: [String] = []
    /// Set on instances of a recurring series.
    public var recurringEventID: String?
    public var organizerEmail: String?
    public var myResponseStatusRaw: String = AttendeeRecord.ResponseStatus.needsAction.rawValue
    public var createdAt: Date = Date()
    public var modifiedAt: Date = Date()
    /// Tombstone. Non-nil means deleted; purge after 30 days.
    public var tombstonedAt: Date?
    public var originRaw: String = ItemOrigin.local.rawValue
    public var reviewStateRaw: String = ReviewState.none.rawValue

    public init(
        id: UUID = UUID(),
        calendarID: UUID? = nil,
        title: String,
        startAt: Date,
        endAt: Date,
        isAllDay: Bool = false,
        timeZoneID: String = TimeZone.current.identifier,
        origin: ItemOrigin = .local
    ) {
        self.id = id
        self.calendarID = calendarID
        self.title = title
        self.startAt = startAt
        self.endAt = endAt
        self.isAllDay = isAllDay
        self.timeZoneID = timeZoneID
        self.originRaw = origin.rawValue
        let now = Date()
        self.createdAt = now
        self.modifiedAt = now
    }
}

// MARK: - Typed accessors

extension CalendarEvent {
    public var myResponseStatus: AttendeeRecord.ResponseStatus {
        get { AttendeeRecord.ResponseStatus(rawValue: myResponseStatusRaw) ?? .needsAction }
        set { myResponseStatusRaw = newValue.rawValue }
    }

    public var origin: ItemOrigin {
        get { ItemOrigin(rawValue: originRaw) ?? .local }
        set { originRaw = newValue.rawValue }
    }

    public var reviewState: ReviewState {
        get { ReviewState(rawValue: reviewStateRaw) ?? .none }
        set { reviewStateRaw = newValue.rawValue }
    }

    public var isTombstoned: Bool { tombstonedAt != nil }
}

// MARK: - Schedulable

extension CalendarEvent: Schedulable {
    public var scheduleID: UUID { id }
    public var scheduleTitle: String { title }
    public var scheduleDate: Date? { startAt }
    public var scheduleIsAllDay: Bool { isAllDay }
    public var scheduleIsDone: Bool { isTombstoned }
}
