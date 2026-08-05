import Foundation
import SwiftData

/// A reminder in Dundu's own store. Synced two-way with Apple Reminders
/// through the EventKit bridge.
///
/// CloudKit constraints shape this model: every property has a default or is
/// optional, and there is no `@Attribute(.unique)` — uniqueness on external
/// IDs is enforced in store code.
///
/// The spec's `isDeleted` tombstone flag is `tombstonedAt` here, because
/// `isDeleted` collides with `PersistentModel.isDeleted`. A non-nil date is
/// the tombstone; purge after 30 days.
@Model
public final class ReminderItem {
    public var id: UUID = UUID()
    public var title: String = ""
    public var notes: String?
    public var listID: UUID?
    public var dueDate: Date?
    /// False means all-day.
    public var hasTime: Bool = false
    /// 0 none, 1 high, 5 medium, 9 low. Matches EventKit.
    public var priorityRaw: Int = 0
    public var isCompleted: Bool = false
    public var completedAt: Date?
    /// Archived EKRecurrenceRule, round-tripped, never interpreted.
    public var recurrenceData: Data?
    /// Seconds relative to due date.
    public var alarmOffsets: [Double] = []
    public var url: URL?
    public var createdAt: Date = Date()
    /// Bumped on every local field write.
    public var modifiedAt: Date = Date()
    /// Fractional index.
    public var sortOrder: Double = 0
    /// Tombstone. Non-nil means deleted; purge after 30 days.
    public var tombstonedAt: Date?
    public var originRaw: String = ItemOrigin.local.rawValue
    public var reviewStateRaw: String = ReviewState.none.rawValue
    public var locationAlarm: LocationAlarm?

    public init(
        id: UUID = UUID(),
        title: String,
        notes: String? = nil,
        listID: UUID? = nil,
        dueDate: Date? = nil,
        hasTime: Bool = false,
        priority: ItemPriority = .none,
        origin: ItemOrigin = .local
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.listID = listID
        self.dueDate = dueDate
        self.hasTime = hasTime
        self.priorityRaw = priority.rawValue
        self.originRaw = origin.rawValue
        let now = Date()
        self.createdAt = now
        self.modifiedAt = now
    }
}

// MARK: - Typed accessors

extension ReminderItem {
    public var priority: ItemPriority {
        get { ItemPriority(rawValue: priorityRaw) ?? .none }
        set { priorityRaw = newValue.rawValue }
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

extension ReminderItem: Schedulable {
    public var scheduleID: UUID { id }
    public var scheduleTitle: String { title }
    public var scheduleDate: Date? { dueDate }
    public var scheduleIsAllDay: Bool { !hasTime }
    public var scheduleIsDone: Bool { isCompleted || isTombstoned }
}
