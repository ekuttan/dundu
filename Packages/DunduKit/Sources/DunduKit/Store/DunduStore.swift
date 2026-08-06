import Foundation
import SwiftData

/// Container setup and the mutation helpers every surface goes through.
/// Mutations bump `modifiedAt` — the sync engine depends on that.
public enum DunduStore {
    public static let allModels: [any PersistentModel.Type] = [
        ReminderItem.self,
        ReminderList.self,
        CalendarEvent.self,
        CalendarAccount.self,
        CalendarRef.self,
        ExcludedEKCalendar.self,
        SyncMapping.self,
        EventSyncMapping.self,
    ]

    public static var schema: Schema { Schema(allModels) }

    /// The CloudKit private-database container for device-to-device sync.
    public static let cloudKitContainerID = "iCloud.app.scoop.dundu"

    /// The on-disk container, CloudKit-backed when the app is entitled and
    /// signed in. Falls back to a local-only store on any CloudKit setup
    /// failure — Dundu must work without iCloud, not crash over it.
    public static func container() throws -> ModelContainer {
        do {
            let cloud = ModelConfiguration(
                "Dundu", schema: schema, cloudKitDatabase: .private(cloudKitContainerID)
            )
            return try ModelContainer(for: schema, configurations: [cloud])
        } catch {
            let local = ModelConfiguration("Dundu", schema: schema, cloudKitDatabase: .none)
            return try ModelContainer(for: schema, configurations: [local])
        }
    }

    /// In-memory container for tests and previews.
    public static func previewContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }
}

// MARK: - Mutations

extension ModelContext {
    /// Marks a reminder complete or incomplete, stamping timestamps the way
    /// the merge rules expect.
    public func setCompleted(_ item: ReminderItem, _ completed: Bool, at date: Date = Date()) {
        item.isCompleted = completed
        item.completedAt = completed ? date : nil
        item.modifiedAt = date
    }

    /// Tombstones instead of deleting, so the deletion can propagate through
    /// sync. Purge runs separately after 30 days.
    public func tombstone(_ item: ReminderItem, at date: Date = Date()) {
        item.tombstonedAt = date
        item.modifiedAt = date
    }

    public func tombstone(_ event: CalendarEvent, at date: Date = Date()) {
        event.tombstonedAt = date
        event.modifiedAt = date
    }

    /// Deletes tombstones older than 30 days, and their mappings.
    public func purgeExpiredTombstones(now: Date = Date()) throws {
        let cutoff = now.addingTimeInterval(-30 * 24 * 3600)

        // Forced unwrap is unsupported inside #Predicate; nil coalesces to
        // the cutoff itself, which fails the strict comparison.
        let reminders = try fetch(FetchDescriptor<ReminderItem>(
            predicate: #Predicate { ($0.tombstonedAt ?? cutoff) < cutoff }
        ))
        let events = try fetch(FetchDescriptor<CalendarEvent>(
            predicate: #Predicate { ($0.tombstonedAt ?? cutoff) < cutoff }
        ))

        let reminderIDs = Set(reminders.map(\.id))
        let eventIDs = Set(events.map(\.id))

        for mapping in try fetch(FetchDescriptor<SyncMapping>()) where reminderIDs.contains(mapping.localID) {
            delete(mapping)
        }
        for mapping in try fetch(FetchDescriptor<EventSyncMapping>()) where eventIDs.contains(mapping.localID) {
            delete(mapping)
        }
        reminders.forEach(delete)
        events.forEach(delete)
    }

    /// Uniqueness on external IDs is enforced here because CloudKit-backed
    /// SwiftData has no `@Attribute(.unique)`. Returns the surviving mapping
    /// when a duplicate exists: most recently modified wins, the loser is
    /// removed.
    public func upsertMapping(localID: UUID, bridgeID: BridgeID, externalID: String) throws -> SyncMapping {
        let bridge = bridgeID.rawValue
        let existing = try fetch(FetchDescriptor<SyncMapping>(
            predicate: #Predicate { $0.externalID == externalID && $0.bridgeID == bridge }
        ))

        if let winner = existing.max(by: {
            ($0.localModifiedAt ?? .distantPast) < ($1.localModifiedAt ?? .distantPast)
        }) {
            for loser in existing where loser !== winner {
                delete(loser)
            }
            return winner
        }

        let mapping = SyncMapping(localID: localID, bridgeID: bridge, externalID: externalID)
        insert(mapping)
        return mapping
    }

    /// The default list, creating one on first launch so quick add always has
    /// a target.
    public func defaultList() throws -> ReminderList {
        let lists = try fetch(FetchDescriptor<ReminderList>(
            predicate: #Predicate { $0.tombstonedAt == nil }
        ))
        if let preferred = lists.first(where: \.isDefault) ?? lists.first {
            return preferred
        }
        let list = ReminderList(title: "Reminders", isDefault: true)
        insert(list)
        return list
    }
}
