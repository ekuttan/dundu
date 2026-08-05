import Foundation

// MARK: - Shared enums

/// Where an item originally came from. Stored as a raw string on models so
/// CloudKit-backed SwiftData stays happy (plain String with a default).
public enum ItemOrigin: String, Codable, Sendable, CaseIterable {
    case local
    case eventkit
    case google
    case siriSuspected = "siri_suspected"
    case voiceCapture = "voice_capture"
}

/// Whether the intelligence layer wants the user to look at this item.
public enum ReviewState: String, Codable, Sendable, CaseIterable {
    case none
    case pending
    case resolved
    case dismissed
}

/// Priority values match EventKit: 0 none, 1 high, 5 medium, 9 low.
public enum ItemPriority: Int, Codable, Sendable, CaseIterable {
    case none = 0
    case high = 1
    case medium = 5
    case low = 9
}

// MARK: - LocationAlarm

/// An arrive/leave trigger attached to a reminder. Maps to an `EKAlarm`
/// carrying an `EKStructuredLocation`. Never present on calendar events —
/// Google Calendar has no location trigger concept.
public struct LocationAlarm: Codable, Hashable, Sendable {
    public enum Proximity: String, Codable, Sendable {
        case enter
        case leave
    }

    /// Place name shown in the UI.
    public var title: String
    public var latitude: Double
    public var longitude: Double
    /// Meters. 0 means system default (about 100m).
    public var radius: Double
    public var proximity: Proximity

    public init(title: String, latitude: Double, longitude: Double, radius: Double = 0, proximity: Proximity) {
        self.title = title
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
        self.proximity = proximity
    }
}

// MARK: - AttendeeRecord

public struct AttendeeRecord: Codable, Hashable, Sendable {
    public enum ResponseStatus: String, Codable, Sendable {
        case needsAction
        case accepted
        case declined
        case tentative
    }

    public var email: String
    public var name: String?
    public var responseStatus: ResponseStatus

    public init(email: String, name: String? = nil, responseStatus: ResponseStatus = .needsAction) {
        self.email = email
        self.name = name
        self.responseStatus = responseStatus
    }
}

// MARK: - Schedulable

/// The one shape the notch and the Inbox iterate over. Reminders and events
/// stay separate types; this protocol is the common surface.
public protocol Schedulable {
    var scheduleID: UUID { get }
    var scheduleTitle: String { get }
    /// Due date for reminders, start time for events. Nil means unscheduled.
    var scheduleDate: Date? { get }
    var scheduleIsAllDay: Bool { get }
    /// Completed reminders and past events drop out of scheduling.
    var scheduleIsDone: Bool { get }
}
