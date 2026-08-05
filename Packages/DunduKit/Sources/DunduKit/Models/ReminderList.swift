import Foundation
import SwiftData

/// A reminders list. Maps to an `EKCalendar` for reminders on the Apple side.
/// Not in the spec's model table explicitly, but `ReminderItem.listID` and the
/// Lists screen need something to point at.
@Model
public final class ReminderList {
    public var id: UUID = UUID()
    public var title: String = ""
    public var colorHex: String = "#007AFF"
    public var sortOrder: Double = 0
    /// Where unrouted new items land.
    public var isDefault: Bool = false
    public var syncEnabled: Bool = true
    /// EventKit `calendarIdentifier` of the mapped list, if synced.
    public var externalID: String?
    public var tombstonedAt: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        colorHex: String = "#007AFF",
        sortOrder: Double = 0,
        isDefault: Bool = false,
        syncEnabled: Bool = true,
        externalID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.colorHex = colorHex
        self.sortOrder = sortOrder
        self.isDefault = isDefault
        self.syncEnabled = syncEnabled
        self.externalID = externalID
    }
}
