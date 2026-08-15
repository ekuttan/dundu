import Foundation
import SwiftData

public extension ModelContext {
    /// Collapses reminders that are the same reminder twice, tombstoning the
    /// losers so the deletion propagates to Apple Reminders like any other.
    ///
    /// Runs at the end of every sync pass: duplicates are created by syncing,
    /// so that is exactly where they should be cleaned up. Returns how many
    /// records were retired.
    @discardableResult
    func deduplicateReminders(now: Date = Date()) throws -> Int {
        let items = try fetch(FetchDescriptor<ReminderItem>())
            .filter { $0.tombstonedAt == nil }
        guard items.count > 1 else { return 0 }

        let mappings = try fetch(FetchDescriptor<SyncMapping>())
        var externalByLocal: [UUID: String] = [:]
        for mapping in mappings {
            externalByLocal[mapping.localID] = mapping.externalID
        }

        let candidates = items.map { item in
            ReminderDeduplicator.Candidate(
                localID: item.id,
                externalID: externalByLocal[item.id],
                title: item.title,
                listID: item.listID,
                dueDate: item.dueDate,
                isCompleted: item.isCompleted,
                modifiedAt: item.modifiedAt,
                createdAt: item.createdAt
            )
        }

        let resolutions = ReminderDeduplicator.resolve(candidates)
        guard !resolutions.isEmpty else { return 0 }

        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        var retired = 0
        for resolution in resolutions {
            // A duplicate that carried the completion hands it to the survivor
            // before it goes, so collapsing two copies can never un-finish a
            // task that was actually done.
            let survivor = byID[resolution.keep]
            for id in resolution.drop {
                guard let loser = byID[id] else { continue }
                if loser.isCompleted, let survivor, !survivor.isCompleted {
                    survivor.isCompleted = true
                    survivor.completedAt = loser.completedAt ?? now
                    survivor.modifiedAt = now
                }
                loser.tombstonedAt = now
                loser.modifiedAt = now
                retired += 1
            }
        }
        if retired > 0 { try save() }
        return retired
    }
}
