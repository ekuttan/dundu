import Foundation

// MARK: - Wire types (Google Calendar API v3)

public struct GEvent: Codable, Sendable, Equatable {
    public var id: String?
    /// "confirmed", "tentative", "cancelled" — cancelled is how deletions
    /// arrive in a syncToken delta feed.
    public var status: String?
    public var etag: String?
    public var summary: String?
    public var description: String?
    public var location: String?
    public var start: GDateTime?
    public var end: GDateTime?
    public var attendees: [GAttendee]?
    public var hangoutLink: String?
    public var conferenceData: GConferenceData?
    public var recurrence: [String]?
    public var recurringEventId: String?
    public var organizer: GPerson?
    /// RFC3339 modification stamp.
    public var updated: String?

    public init() {}

    public var isCancelled: Bool { status == "cancelled" }

    public var updatedDate: Date? {
        updated.flatMap(GDates.parseTimestamp)
    }

    /// Meet link from structured conference data, falling back to the legacy
    /// hangoutLink field.
    public var conferenceURL: URL? {
        if let uri = conferenceData?.entryPoints?.first(where: { $0.entryPointType == "video" })?.uri {
            return URL(string: uri)
        }
        return hangoutLink.flatMap(URL.init(string:))
    }
}

public struct GDateTime: Codable, Sendable, Equatable {
    /// All-day events: "yyyy-MM-dd".
    public var date: String?
    /// Timed events: RFC3339.
    public var dateTime: String?
    /// Google stores per-event time zones. Keep them.
    public var timeZone: String?

    public init(date: String? = nil, dateTime: String? = nil, timeZone: String? = nil) {
        self.date = date
        self.dateTime = dateTime
        self.timeZone = timeZone
    }
}

public struct GAttendee: Codable, Sendable, Equatable {
    public var email: String?
    public var displayName: String?
    /// "needsAction", "declined", "tentative", "accepted"
    public var responseStatus: String?
    /// True on the entry representing the signed-in account.
    public var `self`: Bool?
}

public struct GConferenceData: Codable, Sendable, Equatable {
    public var entryPoints: [GEntryPoint]?

    public struct GEntryPoint: Codable, Sendable, Equatable {
        public var entryPointType: String?
        public var uri: String?
    }
}

public struct GPerson: Codable, Sendable, Equatable {
    public var email: String?
}

public struct GEventsPage: Codable, Sendable {
    public var items: [GEvent]?
    public var nextPageToken: String?
    public var nextSyncToken: String?
}

// MARK: - The merge payload

/// The fields Dundu writes to Google — the merge operates on exactly these.
/// Attendees, conference data, and recurrence are pull-only in v1 (series
/// edits open Google Calendar).
public struct EventWritePayload: Codable, Sendable, Equatable {
    public var title: String
    public var notes: String?
    public var location: String?
    public var startAt: Date
    public var endAt: Date
    public var isAllDay: Bool
    public var timeZoneID: String

    public init(
        title: String,
        notes: String? = nil,
        location: String? = nil,
        startAt: Date,
        endAt: Date,
        isAllDay: Bool = false,
        timeZoneID: String = TimeZone.current.identifier
    ) {
        self.title = title
        self.notes = notes
        self.location = location
        self.startAt = startAt
        self.endAt = endAt
        self.isAllDay = isAllDay
        self.timeZoneID = timeZoneID
    }

    /// The wire shape for insert/patch.
    public func asGEvent() -> GEvent {
        var event = GEvent()
        event.summary = title
        event.description = notes
        event.location = location
        if isAllDay {
            event.start = GDateTime(date: GDates.dayString(startAt, timeZoneID: timeZoneID))
            event.end = GDateTime(date: GDates.dayString(endAt, timeZoneID: timeZoneID))
        } else {
            event.start = GDateTime(dateTime: GDates.timestampString(startAt), timeZone: timeZoneID)
            event.end = GDateTime(dateTime: GDates.timestampString(endAt), timeZone: timeZoneID)
        }
        return event
    }

    /// Nil when the wire event is missing its times (defensive: Google
    /// guarantees start/end on confirmed events).
    public init?(from event: GEvent) {
        guard let start = event.start, let end = event.end else { return nil }
        let zoneID = start.timeZone ?? TimeZone.current.identifier

        if let startDay = start.date, let endDay = end.date {
            guard let startDate = GDates.parseDay(startDay, timeZoneID: zoneID),
                  let endDate = GDates.parseDay(endDay, timeZoneID: zoneID)
            else { return nil }
            self.init(
                title: event.summary ?? "",
                notes: event.description,
                location: event.location,
                startAt: startDate,
                endAt: endDate,
                isAllDay: true,
                timeZoneID: zoneID
            )
        } else if let startStamp = start.dateTime, let endStamp = end.dateTime {
            guard let startDate = GDates.parseTimestamp(startStamp),
                  let endDate = GDates.parseTimestamp(endStamp)
            else { return nil }
            self.init(
                title: event.summary ?? "",
                notes: event.description,
                location: event.location,
                startAt: startDate,
                endAt: endDate,
                isAllDay: false,
                timeZoneID: zoneID
            )
        } else {
            return nil
        }
    }
}

// MARK: - Dates

public enum GDates {
    // ISO8601DateFormatter is documented thread-safe; the compiler just
    // can't see that through Sendable.
    nonisolated(unsafe) private static let rfc3339Fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    nonisolated(unsafe) private static let rfc3339: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    public static func parseTimestamp(_ string: String) -> Date? {
        rfc3339.date(from: string) ?? rfc3339Fractional.date(from: string)
    }

    public static func timestampString(_ date: Date) -> String {
        rfc3339.string(from: date)
    }

    /// "2026-08-07" interpreted at midnight in the event's zone.
    public static func parseDay(_ string: String, timeZoneID: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: timeZoneID) ?? .current
        return formatter.date(from: string)
    }

    public static func dayString(_ date: Date, timeZoneID: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: timeZoneID) ?? .current
        return formatter.string(from: date)
    }
}

// MARK: - Client-generated event IDs

/// Google accepts client-supplied event ids in base32hex (a-v, 0-9), 5–1024
/// chars. Deriving the id deterministically from the local UUID makes every
/// retry idempotent by construction — a timeout can never create a duplicate
/// (spec edge 5).
public enum GoogleEventID {
    private static let alphabet = Array("0123456789abcdefghijklmnopqrstuv")

    public static func from(_ uuid: UUID) -> String {
        let bytes = withUnsafeBytes(of: uuid.uuid) { Array($0) }
        var bits = 0
        var accumulator = 0
        var output = ""
        for byte in bytes {
            accumulator = (accumulator << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                bits -= 5
                output.append(alphabet[(accumulator >> bits) & 0x1F])
            }
        }
        if bits > 0 {
            output.append(alphabet[(accumulator << (5 - bits)) & 0x1F])
        }
        return output
    }
}
