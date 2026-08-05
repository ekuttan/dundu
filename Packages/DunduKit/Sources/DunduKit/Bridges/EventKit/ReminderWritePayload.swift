import Foundation

/// The fields Dundu writes to EventKit — exactly the model-table fields and
/// nothing else. EventKit carries more (tags, subtasks, flags); those are
/// never touched, which is why updates fetch-mutate-save instead of
/// rebuilding reminders.
public struct ReminderWritePayload: Codable, Sendable, Equatable {
    public var title: String
    public var notes: String?
    public var dueDate: Date?
    public var hasTime: Bool
    public var priority: Int
    public var isCompleted: Bool
    public var completedAt: Date?
    public var url: URL?
    public var alarmOffsets: [Double]
    public var locationAlarm: LocationAlarm?
    /// EK calendar identifier of the target list. Nil means the system
    /// default reminders list.
    public var listExternalID: String?

    public init(
        title: String,
        notes: String? = nil,
        dueDate: Date? = nil,
        hasTime: Bool = false,
        priority: Int = 0,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        url: URL? = nil,
        alarmOffsets: [Double] = [],
        locationAlarm: LocationAlarm? = nil,
        listExternalID: String? = nil
    ) {
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.hasTime = hasTime
        self.priority = priority
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.url = url
        self.alarmOffsets = alarmOffsets
        self.locationAlarm = locationAlarm
        self.listExternalID = listExternalID
    }
}

/// What the planner decided to do for one reminder. Pure data — the planner
/// never touches EventKit, which is what makes it testable.
public struct PlannedReminderChange: Sendable, Equatable {
    public enum Action: Sendable, Equatable {
        case create
        case update(externalID: String)
        case delete(externalID: String)
    }

    public var localID: UUID
    public var action: Action
    public var payload: ReminderWritePayload?
    /// The item's modifiedAt when planned; stamped onto the mapping after a
    /// successful push so the item stops looking dirty.
    public var localModifiedAt: Date

    public init(localID: UUID, action: Action, payload: ReminderWritePayload?, localModifiedAt: Date) {
        self.localID = localID
        self.action = action
        self.payload = payload
        self.localModifiedAt = localModifiedAt
    }
}

/// Decides what needs pushing by comparing items against their mappings.
public enum ReminderPushPlanner {
    /// A lightweight view of a mapping, so the planner stays independent of
    /// SwiftData types.
    public struct MappingState: Sendable, Equatable {
        public var externalID: String
        public var localModifiedAt: Date?

        public init(externalID: String, localModifiedAt: Date?) {
            self.externalID = externalID
            self.localModifiedAt = localModifiedAt
        }
    }

    public struct ItemState: Sendable, Equatable {
        public var localID: UUID
        public var isTombstoned: Bool
        public var modifiedAt: Date
        public var payload: ReminderWritePayload

        public init(localID: UUID, isTombstoned: Bool, modifiedAt: Date, payload: ReminderWritePayload) {
            self.localID = localID
            self.isTombstoned = isTombstoned
            self.modifiedAt = modifiedAt
            self.payload = payload
        }
    }

    public static func plan(
        items: [ItemState],
        mappings: [UUID: MappingState]
    ) -> [PlannedReminderChange] {
        var changes: [PlannedReminderChange] = []

        for item in items {
            let mapping = mappings[item.localID]

            switch (mapping, item.isTombstoned) {
            case (nil, true):
                // Never reached EventKit; nothing to delete remotely.
                continue

            case (nil, false):
                changes.append(PlannedReminderChange(
                    localID: item.localID,
                    action: .create,
                    payload: item.payload,
                    localModifiedAt: item.modifiedAt
                ))

            case (let mapping?, true):
                changes.append(PlannedReminderChange(
                    localID: item.localID,
                    action: .delete(externalID: mapping.externalID),
                    payload: nil,
                    localModifiedAt: item.modifiedAt
                ))

            case (let mapping?, false):
                // Dirty when the item changed after the last successful push.
                if item.modifiedAt > (mapping.localModifiedAt ?? .distantPast) {
                    changes.append(PlannedReminderChange(
                        localID: item.localID,
                        action: .update(externalID: mapping.externalID),
                        payload: item.payload,
                        localModifiedAt: item.modifiedAt
                    ))
                }
            }
        }

        return changes
    }
}
