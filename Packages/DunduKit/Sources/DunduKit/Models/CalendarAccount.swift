import Foundation
import SwiftData

/// A connected calendar account. Three calendars may sit on three separate
/// Google accounts, so multi-account is built in from the start.
@Model
public final class CalendarAccount {
    public enum Provider: String, Codable, Sendable {
        case google
        case apple
    }

    public var id: UUID = UUID()
    public var providerRaw: String = Provider.google.rawValue
    public var email: String = ""
    /// Keychain item reference for the refresh token. The token itself never
    /// touches this store.
    public var keychainRef: String?
    public var isActive: Bool = true
    public var lastSyncAt: Date?
    /// Per-calendar Google `syncToken`s, keyed by remote calendar ID.
    public var syncTokenStore: [String: String] = [:]

    public init(id: UUID = UUID(), provider: Provider, email: String) {
        self.id = id
        self.providerRaw = provider.rawValue
        self.email = email
    }

    public var provider: Provider {
        get { Provider(rawValue: providerRaw) ?? .google }
        set { providerRaw = newValue.rawValue }
    }
}

/// One calendar inside an account. The `role` field is what the AI routes
/// against — never route against titles, those change.
@Model
public final class CalendarRef {
    public enum Role: String, Codable, Sendable, CaseIterable {
        case personal
        case workA = "work_a"
        case workB = "work_b"
    }

    public var id: UUID = UUID()
    public var accountID: UUID?
    public var remoteCalendarID: String = ""
    public var title: String = ""
    public var colorHex: String = "#34C759"
    public var roleRaw: String = Role.personal.rawValue
    public var isWritable: Bool = true
    public var isDefaultForRole: Bool = false
    public var syncEnabled: Bool = true

    public init(
        id: UUID = UUID(),
        accountID: UUID? = nil,
        remoteCalendarID: String,
        title: String,
        role: Role = .personal
    ) {
        self.id = id
        self.accountID = accountID
        self.remoteCalendarID = remoteCalendarID
        self.title = title
        self.roleRaw = role.rawValue
    }

    public var role: Role {
        get { Role(rawValue: roleRaw) ?? .personal }
        set { roleRaw = newValue.rawValue }
    }
}

/// A Google-backed EventKit calendar that EventKit sync must skip, because the
/// Google bridge owns it. One path per calendar, never both.
@Model
public final class ExcludedEKCalendar {
    public var id: UUID = UUID()
    /// EventKit `calendarIdentifier`.
    public var ekCalendarID: String = ""
    public var title: String = ""
    public var sourceTitle: String = ""
    /// User can override the auto-exclusion in settings.
    public var isUserOverridden: Bool = false
    public var detectedAt: Date = Date()

    public init(ekCalendarID: String, title: String, sourceTitle: String) {
        self.ekCalendarID = ekCalendarID
        self.title = title
        self.sourceTitle = sourceTitle
    }
}
