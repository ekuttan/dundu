import Foundation
import SwiftData
import Testing
@testable import DunduKit

@Suite("Reminder identity survives partial CloudKit delivery")
@MainActor
struct ReminderIdentityTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let base = ReminderWritePayload(title: "Return the library books", listExternalID: "personal")

    private func state(_ item: ReminderItem) -> ReminderPushPlanner.ItemState {
        item.syncState(listExternalIDs: [:], fallback: "personal")
    }

    @Test func anImportedItemWithoutItsMappingIsNeverCreatedAgain() {
        for origin in [ItemOrigin.eventkit, .siriSuspected] {
            let item = ReminderItem(title: base.title, origin: origin)
            // Routing or an edit means the old payload-equality adoption
            // cannot recognize the echo; origin still proves this isn't new.
            item.notes = "A local edit while the mapping is in transit"
            let remote = ReminderSyncPlanner.RemoteState(externalID: "apple-original", lastModified: now, payload: base)
            let plan = ReminderSyncPlanner.plan(locals: [state(item)], remotes: [remote], mappings: [], now: now)
            #expect(plan.remoteChanges.isEmpty)
            #expect(ReminderPushPlanner.plan(items: [state(item)], mappings: [:]).isEmpty)
        }
    }

    @Test func importedCopyDoesNotExportWhenTheRemoteIsAlreadyClaimed() {
        let original = ReminderItem(title: base.title, origin: .eventkit)
        let copy = ReminderItem(title: base.title, origin: .eventkit)
        let plan = ReminderSyncPlanner.plan(
            locals: [state(original), state(copy)],
            remotes: [.init(externalID: "apple-original", lastModified: now, payload: base)],
            mappings: [.init(localID: original.id, externalID: "apple-original", base: base)], now: now
        )
        #expect(plan.remoteChanges.isEmpty)
        #expect(plan.localWrites.isEmpty)
    }

    @Test func identityArrivesWithAnEditedItemBeforeItsMapping() throws {
        let item = ReminderItem(title: base.title, origin: .eventkit)
        item.eventKitExternalID = "apple-original"
        item.eventKitBaseSnapshot = try JSONEncoder().encode(base)
        item.notes = "An intentional local edit"
        let remote = ReminderSyncPlanner.RemoteState(externalID: "apple-original", lastModified: now, payload: base)
        let plan = ReminderSyncPlanner.plan(locals: [state(item)], remotes: [remote], mappings: [], now: now)
        #expect(plan.adoptions.count == 1)
        #expect(plan.remoteChanges.map(\.action) == [.update(externalID: "apple-original")])
        #expect(plan.remoteChanges.first?.payload?.notes == item.notes)
        #expect(plan.localWrites.isEmpty)

        // The update's echo on the following pass makes no further writes.
        let pushed = try #require(plan.remoteChanges.first?.payload)
        let next = ReminderSyncPlanner.plan(
            locals: [state(item)],
            remotes: [.init(externalID: "apple-original", lastModified: now, payload: pushed)],
            mappings: [.init(localID: item.id, externalID: "apple-original", base: pushed)], now: now
        )
        #expect(next.isEmpty)
    }

    @Test func rememberedIdentityWaitsForEventKitDelivery() {
        let item = ReminderItem(title: base.title, origin: .local)
        item.eventKitExternalID = "not-on-this-device-yet"
        let plan = ReminderSyncPlanner.plan(locals: [state(item)], remotes: [], mappings: [], now: now)
        #expect(plan.isEmpty)
    }

    @Test func mappingArrivingBeforeItsItemDoesNotDeleteAppleReminder() {
        let plan = ReminderSyncPlanner.plan(
            locals: [], remotes: [.init(externalID: "apple-original", lastModified: now, payload: base)],
            mappings: [.init(localID: UUID(), externalID: "apple-original", base: base)], now: now
        )
        #expect(plan.isEmpty)
    }

    @Test func sharedIdentityCannotDeleteTheSurvivingAppleReminder() {
        let survivor = ReminderItem(title: base.title, origin: .eventkit)
        let deletedCopy = ReminderItem(title: base.title, origin: .eventkit)
        deletedCopy.tombstonedAt = now
        let plan = ReminderSyncPlanner.plan(
            locals: [state(survivor), state(deletedCopy)],
            remotes: [.init(externalID: "shared", lastModified: now, payload: base)],
            mappings: [survivor, deletedCopy].map { .init(localID: $0.id, externalID: "shared", base: base) }, now: now
        )
        #expect(plan.isEmpty)
    }

    @Test func repeatedMappingRowsProduceOnlyOneUpdate() {
        let item = ReminderItem(title: base.title, notes: "edited", origin: .eventkit)
        let mapping = ReminderSyncPlanner.MappingView(localID: item.id, externalID: "shared", base: base)
        let plan = ReminderSyncPlanner.plan(
            locals: [state(item)], remotes: [.init(externalID: "shared", lastModified: now, payload: base)],
            mappings: [mapping, mapping], now: now
        )
        #expect(plan.remoteChanges.count == 1)
    }

    @Test func newTypedAndVoiceRemindersStillCreate() {
        for origin in [ItemOrigin.local, .voiceCapture] {
            let item = ReminderItem(title: "New reminder", origin: origin)
            let plan = ReminderSyncPlanner.plan(locals: [state(item)], remotes: [], mappings: [], now: now)
            #expect(plan.remoteChanges.map(\.action) == [.create])
        }
    }

    @Test func identityAndMergeBasePersistWithoutAMappingRecord() throws {
        let container = try DunduStore.previewContainer()
        let context = ModelContext(container)
        let item = ReminderItem(title: base.title, origin: .eventkit)
        let mapping = SyncMapping(localID: item.id, bridgeID: "eventkit", externalID: "apple-original")
        mapping.baseSnapshot = try JSONEncoder().encode(base)
        item.rememberIdentity(mapping)
        context.insert(item)
        try context.save()
        let reader = ModelContext(container)
        let saved = try #require(try reader.fetch(FetchDescriptor<ReminderItem>()).first)
        #expect(saved.eventKitExternalID == "apple-original")
        #expect(state(saved).syncBase == base)
        #expect(try reader.fetch(FetchDescriptor<SyncMapping>()).isEmpty)
    }
}
