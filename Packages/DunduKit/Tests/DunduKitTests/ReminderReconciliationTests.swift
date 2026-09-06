import Foundation
import SwiftData
import Testing
@testable import DunduKit

@Suite("Reminder reconciliation after CloudKit history replay")
@MainActor
struct ReminderReconciliationTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func snapshot(_ id: String, title: String = "Task") -> EKReminderSnapshot {
        .init(externalID: id, localIdentifier: id, listID: "personal", title: title,
              notes: nil, dueDate: nil, hasTime: false, priority: 0,
              isCompleted: false, completedAt: nil, url: nil, lastModified: now,
              created: now, alarmOffsets: [], locationAlarm: nil, hasRecurrence: false)
    }

    private func add(_ context: ModelContext, externalID: String, tombstoned: Bool = false) -> ReminderItem {
        let item = ReminderItem(title: "Task", origin: .eventkit)
        item.eventKitExternalID = externalID
        if tombstoned { item.tombstonedAt = now.addingTimeInterval(-86_400) }
        context.insert(item)
        let mapping = SyncMapping(localID: item.id, bridgeID: "eventkit", externalID: externalID)
        mapping.baseSnapshot = try? JSONEncoder().encode(snapshot(externalID).writePayload)
        context.insert(mapping)
        return item
    }

    @Test func oldTombstoneCannotDeleteARestoredAppleReminder() throws {
        let context = ModelContext(try DunduStore.previewContainer())
        let item = add(context, externalID: "live", tombstoned: true)
        let before = ReminderSyncPlanner.plan(
            locals: [item.syncState(listExternalIDs: [:], fallback: "personal")],
            remotes: [.init(externalID: "live", lastModified: now, payload: snapshot("live").writePayload)],
            mappings: [.init(localID: item.id, externalID: "live")], now: now
        )
        #expect(before.remoteChanges.isEmpty)
        try context.reconcileReminderIdentities(snapshots: [snapshot("live")], listExternalIDs: [:], fallback: "personal", now: now)
        #expect(!item.isTombstoned)
        #expect(item.eventKitDeletionRequestedAt == nil)
    }

    @Test func explicitDeletionStillPropagates() throws {
        let context = ModelContext(try DunduStore.previewContainer())
        let item = add(context, externalID: "live")
        context.tombstone(item, at: now)
        try context.reconcileReminderIdentities(snapshots: [snapshot("live")], listExternalIDs: [:], fallback: "personal", now: now)
        #expect(item.isTombstoned)
        let plan = ReminderSyncPlanner.plan(
            locals: [item.syncState(listExternalIDs: [:], fallback: "personal")],
            remotes: [.init(externalID: "live", lastModified: now, payload: snapshot("live").writePayload)],
            mappings: [.init(localID: item.id, externalID: "live")], now: now
        )
        #expect(plan.remoteChanges.map(\.action) == [.delete(externalID: "live")])
    }

    @Test func identicalCopiesOfOneIdentityConvergeLocally() throws {
        let context = ModelContext(try DunduStore.previewContainer())
        _ = add(context, externalID: "same", tombstoned: true)
        _ = add(context, externalID: "same")
        try context.reconcileReminderIdentities(snapshots: [snapshot("same")], listExternalIDs: [:], fallback: "personal", now: now)
        #expect(try context.fetch(FetchDescriptor<ReminderItem>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<SyncMapping>()).count == 1)
    }

    @Test func distinctAppleIdentitiesWithEqualContentArePreserved() throws {
        let context = ModelContext(try DunduStore.previewContainer())
        _ = add(context, externalID: "one")
        _ = add(context, externalID: "two")
        try context.reconcileReminderIdentities(snapshots: [snapshot("one"), snapshot("two")], listExternalIDs: [:], fallback: "personal", now: now)
        #expect(try context.fetch(FetchDescriptor<ReminderItem>()).count == 2)
        #expect(try context.fetch(FetchDescriptor<SyncMapping>()).count == 2)
    }

    @Test func divergentLocalEditsAreNotDiscarded() throws {
        let context = ModelContext(try DunduStore.previewContainer())
        _ = add(context, externalID: "same")
        let edited = add(context, externalID: "same")
        edited.notes = "An unsynced note"
        try context.reconcileReminderIdentities(snapshots: [snapshot("same")], listExternalIDs: [:], fallback: "personal", now: now)
        #expect(try context.fetch(FetchDescriptor<ReminderItem>()).count == 2)
        #expect(edited.notes == "An unsynced note")
    }

    @Test func obsoleteAssociationDoesNotHideTheLiveReminder() throws {
        let context = ModelContext(try DunduStore.previewContainer())
        let item = add(context, externalID: "deleted-copy")
        context.insert(SyncMapping(localID: item.id, bridgeID: "eventkit", externalID: "live"))
        try context.reconcileReminderIdentities(snapshots: [snapshot("live")], listExternalIDs: [:], fallback: "personal", now: now)
        #expect(item.eventKitExternalID == "live")
        let mappings = try context.fetch(FetchDescriptor<SyncMapping>())
        #expect(mappings.count == 1)
        #expect(mappings.first?.externalID == "live")
    }

    @Test func twoLiveAppleRecordsCannotShareOneLocalItem() throws {
        let context = ModelContext(try DunduStore.previewContainer())
        let item = add(context, externalID: "one")
        context.insert(SyncMapping(localID: item.id, bridgeID: "eventkit", externalID: "two"))
        let snapshots = [snapshot("one"), snapshot("two")]
        try context.reconcileReminderIdentities(snapshots: snapshots, listExternalIDs: [:], fallback: "personal", now: now)
        let mappings = try context.fetch(FetchDescriptor<SyncMapping>())
        let plan = ReminderSyncPlanner.plan(
            locals: [item.syncState(listExternalIDs: [:], fallback: "personal")],
            remotes: snapshots.map { .init(externalID: $0.externalID, lastModified: now, payload: $0.writePayload) },
            mappings: mappings.map { .init(localID: $0.localID, externalID: $0.externalID, base: snapshot($0.externalID).writePayload) }, now: now
        )
        #expect(plan.remoteChanges.isEmpty)
        #expect(plan.localWrites == [.createFromRemote(.init(externalID: "two", lastModified: now, payload: snapshot("two").writePayload))])
    }

    @Test func staleOrphanMappingDoesNotHideAnAppleReminderForever() throws {
        let context = ModelContext(try DunduStore.previewContainer())
        let stale = SyncMapping(localID: UUID(), bridgeID: "eventkit", externalID: "old")
        stale.lastSyncedAt = now.addingTimeInterval(-600)
        let arriving = SyncMapping(localID: UUID(), bridgeID: "eventkit", externalID: "fresh")
        arriving.lastSyncedAt = now
        context.insert(stale)
        context.insert(arriving)
        try context.reconcileReminderIdentities(snapshots: [snapshot("old"), snapshot("fresh")], listExternalIDs: [:], fallback: "personal", now: now)
        let remaining = try context.fetch(FetchDescriptor<SyncMapping>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.externalID == "fresh")
    }
}
