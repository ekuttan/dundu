import Foundation

/// Value snapshot of an EKReminder. Snapshots are what cross the actor
/// boundary — EKObjects never leave the bridge. This same shape becomes the
/// `baseSnapshot` payload in M3's three-way merge.
public struct EKReminderSnapshot: Sendable, Codable, Equatable {
    /// `calendarItemExternalIdentifier` — stable across devices, but Apple
    /// documents it is not guaranteed unique. Duplicates are a conflict.
    public var externalID: String
    /// `calendarItemIdentifier` — local to this device, always unique here.
    public var localIdentifier: String
    /// `calendarIdentifier` of the containing list.
    public var listID: String
    public var title: String
    public var notes: String?
    public var dueDate: Date?
    public var hasTime: Bool
    public var priority: Int
    public var isCompleted: Bool
    public var completedAt: Date?
    public var url: URL?
    public var lastModified: Date?
    /// Seconds relative to due date, location alarms excluded.
    public var alarmOffsets: [Double]
    /// First location alarm, if any. The rest round-trip untouched.
    public var locationAlarm: LocationAlarm?
    public var hasRecurrence: Bool
}

/// Value snapshot of an EKCalendar for reminders.
public struct EKListSnapshot: Sendable, Codable, Equatable, Identifiable {
    /// `calendarIdentifier`.
    public var id: String
    public var title: String
    public var colorHex: String?
    public var sourceTitle: String
    /// CalDAV or subscribed source backed by Google. Calendars like this get
    /// auto-excluded from EventKit sync — the Google bridge owns that data.
    public var isGoogleBacked: Bool
    public var allowsModification: Bool
}

/// Authorization state, mirrored into our own enum so views don't need to
/// import EventKit.
public enum ReminderAccessStatus: Sendable, Equatable {
    case notDetermined
    case denied
    case fullAccess
    case writeOnly
    case restricted
}
