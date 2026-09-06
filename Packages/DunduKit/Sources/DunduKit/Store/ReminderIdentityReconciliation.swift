import Foundation
import SwiftData

extension ModelContext {
    /// Reconcile bookkeeping using observed Apple identities. Content is only
    /// used to confirm copies already linked to the SAME external identity;
    /// matching titles, or even matching payloads with different IDs, never
    /// authorize consolidation. No EventKit writes are performed here.
    @MainActor
    func reconcileReminderIdentities(
        snapshots: [EKReminderSnapshot], listExternalIDs: [UUID: String],
        fallback: String?, now: Date
    ) throws {
        let remoteGroups = Dictionary(grouping: snapshots, by: \.externalID)
        // An ambiguous Apple external ID cannot establish identity safely.
        let remotes = remoteGroups.compactMapValues { $0.count == 1 ? $0.first : nil }
        let items = try fetch(FetchDescriptor<ReminderItem>())
        let mappings = try fetch(FetchDescriptor<SyncMapping>(
            predicate: #Predicate { $0.bridgeID == "eventkit" }
        ))
        let mappingsByLocal = Dictionary(grouping: mappings, by: \.localID)
        let localIDs = Set(items.map(\.id))
        for mapping in mappings where !localIDs.contains(mapping.localID) && remotes[mapping.externalID] != nil {
            // Give independently delivered CloudKit records time to arrive.
            // An older dangling association must not hide an Apple reminder
            // forever. Dropping bookkeeping lets the planner import it;
            // the missing local record never authorizes an Apple deletion.
            if let syncedAt = mapping.lastSyncedAt, syncedAt < now.addingTimeInterval(-300) {
                delete(mapping)
            }
        }
        let lists = try fetch(FetchDescriptor<ReminderList>())
        let listsByExternal = Dictionary(
            lists.compactMap { list in list.externalID.map { ($0, list) } },
            uniquingKeysWith: { a, _ in a }
        )

        for item in items {
            let owned = mappingsByLocal[item.id, default: []]
            let liveIDs = Set(owned.map(\.externalID).filter { remotes[$0] != nil })
            // A stale mapping may point the same local UUID at a deleted
            // remote as well as a live one. Prefer the sole observed identity.
            if liveIDs.count == 1, let liveID = liveIDs.first,
               item.eventKitExternalID == nil || remotes[item.eventKitExternalID ?? ""] == nil,
               let mapping = owned.first(where: { $0.externalID == liveID }) {
                item.rememberIdentity(mapping)
            }

            // CloudKit can replay tombstones from before a data restore. The
            // current Apple record wins unless this client recorded a fresh,
            // explicit deletion request. Never send that old deletion back.
            if item.isTombstoned, item.eventKitDeletionRequestedAt == nil,
               let externalID = item.eventKitExternalID, let remote = remotes[externalID] {
                ReminderSyncService.apply(remote.writePayload, to: item, listsByExternalID: listsByExternal)
                item.tombstonedAt = nil
                item.modifiedAt = now
                item.eventKitBaseSnapshot = try JSONEncoder().encode(remote.writePayload)
                for mapping in owned where mapping.externalID == externalID {
                    mapping.baseSnapshot = item.eventKitBaseSnapshot
                    mapping.localModifiedAt = now
                }
            }
        }

        let groups = Dictionary(grouping: items.filter { $0.eventKitExternalID != nil }, by: { $0.eventKitExternalID! })
        for (externalID, copies) in groups {
            guard remotes[externalID] != nil else { continue }
            let ordered = copies.sorted {
                if $0.isTombstoned != $1.isTombstoned { return !$0.isTombstoned }
                if $0.modifiedAt != $1.modifiedAt { return $0.modifiedAt > $1.modifiedAt }
                return $0.id.uuidString < $1.id.uuidString
            }
            guard let winner = ordered.first else { continue }
            let payload = winner.writePayload(listExternalIDs: listExternalIDs, fallback: fallback)
            // Retain divergent edits for review, rather than losing fields.
            guard copies.allSatisfy({
                $0.eventKitDeletionRequestedAt == nil &&
                $0.writePayload(listExternalIDs: listExternalIDs, fallback: fallback) == payload
            }) || copies.count == 1 else { continue }

            let losingIDs = Set(ordered.dropFirst().map(\.id)).subtracting([winner.id])
            for mapping in mappings where losingIDs.contains(mapping.localID) && !mapping.isDeleted {
                delete(mapping)
            }
            for loser in ordered.dropFirst() { delete(loser) }

            // A local item can represent one Apple identity. Detach any
            // other associations; a still-live second Apple record will be
            // imported as its own item by the planner, never deleted.
            for mapping in mappings where mapping.localID == winner.id &&
                mapping.externalID != externalID && !mapping.isDeleted {
                delete(mapping)
            }
            let mapping = try upsertMapping(localID: winner.id, bridgeID: .eventkit, externalID: externalID)
            mapping.localID = winner.id
            mapping.baseSnapshot = winner.eventKitBaseSnapshot ?? mapping.baseSnapshot
            mapping.localModifiedAt = winner.modifiedAt
        }
        try save()
    }
}
