import Foundation
import SwiftData

/// Links a local `ReminderItem` to its EventKit counterpart.
///
/// `baseSnapshot` — JSON of field values at last successful sync — is what
/// turns a two-way diff into a three-way merge. Without it you cannot tell
/// which side changed a field, only that they differ.
@Model
public final class SyncMapping {
    public var localID: UUID = UUID()
    /// "eventkit" or "google".
    public var bridgeID: String = ""
    /// `calendarItemExternalIdentifier` for EventKit. Apple documents that it
    /// is not guaranteed unique — duplicates are a conflict, keep the most
    /// recently modified.
    public var externalID: String = ""
    public var baseSnapshot: Data?
    public var remoteModifiedAt: Date?
    public var localModifiedAt: Date?
    public var lastSyncedAt: Date?

    public init(localID: UUID, bridgeID: String, externalID: String) {
        self.localID = localID
        self.bridgeID = bridgeID
        self.externalID = externalID
    }
}

/// Links a local `CalendarEvent` to its Google counterpart.
@Model
public final class EventSyncMapping {
    public var localID: UUID = UUID()
    public var bridgeID: String = ""
    /// Google event `id`. Client-generated on insert so retries after a
    /// timeout are idempotent.
    public var externalID: String = ""
    /// Google only, used for `If-Match` on patch.
    public var etag: String?
    public var baseSnapshot: Data?
    public var remoteModifiedAt: Date?
    public var localModifiedAt: Date?
    public var lastSyncedAt: Date?

    public init(localID: UUID, bridgeID: String, externalID: String, etag: String? = nil) {
        self.localID = localID
        self.bridgeID = bridgeID
        self.externalID = externalID
        self.etag = etag
    }
}
