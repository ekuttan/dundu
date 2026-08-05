import Foundation
import SwiftData

/// One-way push, local store as truth (M2). Collects dirty reminders, plans
/// changes against the mappings, applies them through the bridge, and stamps
/// the mappings so items stop looking dirty. M3 replaces the entry point with
/// the full two-way pass; the planner and bridge writes carry over.
@MainActor
public enum EventKitPushService {
    /// Shared bridge instance — one EKEventStore for the whole app.
    public static let bridge = EventKitBridge()

    /// Pushes everything pending. Returns the number of changes applied.
    /// Silently does nothing without full access — the app works standalone.
    @discardableResult
    public static func pushPending(context: ModelContext) async throws -> Int {
        guard EventKitBridge.accessStatus() == .fullAccess else { return 0 }

        // Resolve the default list's EK identifier once, storing it for
        // stable routing of future pushes.
        let defaultList = try context.defaultList()
        if defaultList.externalID == nil {
            defaultList.externalID = await bridge.defaultListExternalID()
        }

        let lists = try context.fetch(FetchDescriptor<ReminderList>())
        let listExternalIDs = Dictionary(
            lists.compactMap { list in list.externalID.map { (list.id, $0) } },
            uniquingKeysWith: { first, _ in first }
        )

        let items = try context.fetch(FetchDescriptor<ReminderItem>())
        let mappings = try context.fetch(FetchDescriptor<SyncMapping>(
            predicate: #Predicate { $0.bridgeID == "eventkit" }
        ))
        let mappingsByLocalID = Dictionary(
            mappings.map { ($0.localID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let itemStates = items.map { item in
            ReminderPushPlanner.ItemState(
                localID: item.id,
                isTombstoned: item.isTombstoned,
                modifiedAt: item.modifiedAt,
                payload: payload(for: item, listExternalIDs: listExternalIDs, fallback: defaultList.externalID)
            )
        }
        let mappingStates = mappingsByLocalID.mapValues {
            ReminderPushPlanner.MappingState(externalID: $0.externalID, localModifiedAt: $0.localModifiedAt)
        }

        let planned = ReminderPushPlanner.plan(items: itemStates, mappings: mappingStates)
        guard !planned.isEmpty else { return 0 }

        let results = await bridge.apply(planned)
        let plannedByLocalID = Dictionary(
            planned.map { ($0.localID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var applied = 0
        for result in results where result.succeeded {
            guard let change = plannedByLocalID[result.localID] else { continue }
            applied += 1

            switch change.action {
            case .create, .update:
                guard let externalID = result.externalID else { continue }
                let mapping = try context.upsertMapping(
                    localID: result.localID, bridgeID: .eventkit, externalID: externalID
                )
                mapping.localID = result.localID
                mapping.localModifiedAt = change.localModifiedAt
                mapping.lastSyncedAt = Date()
                mapping.baseSnapshot = change.payload.flatMap { try? JSONEncoder().encode($0) }

            case .delete:
                if let mapping = mappingsByLocalID[result.localID] {
                    context.delete(mapping)
                }
            }
        }

        try context.save()
        return applied
    }

    private static func payload(
        for item: ReminderItem,
        listExternalIDs: [UUID: String],
        fallback: String?
    ) -> ReminderWritePayload {
        ReminderWritePayload(
            title: item.title,
            notes: item.notes,
            dueDate: item.dueDate,
            hasTime: item.hasTime,
            priority: item.priorityRaw,
            isCompleted: item.isCompleted,
            completedAt: item.completedAt,
            url: item.url,
            alarmOffsets: item.alarmOffsets,
            locationAlarm: item.locationAlarm,
            listExternalID: item.listID.flatMap { listExternalIDs[$0] } ?? fallback
        )
    }
}
