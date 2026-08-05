import Foundation
import Testing
@testable import DunduKit

@Suite("Push planning")
struct ReminderPushPlannerTests {
    private func item(
        id: UUID = UUID(),
        title: String = "Item",
        tombstoned: Bool = false,
        modifiedAt: Date = Date(timeIntervalSince1970: 2000)
    ) -> ReminderPushPlanner.ItemState {
        ReminderPushPlanner.ItemState(
            localID: id,
            isTombstoned: tombstoned,
            modifiedAt: modifiedAt,
            payload: ReminderWritePayload(title: title)
        )
    }

    @Test func unmappedItemIsCreated() {
        let state = item()
        let planned = ReminderPushPlanner.plan(items: [state], mappings: [:])
        #expect(planned.count == 1)
        #expect(planned.first?.action == .create)
        #expect(planned.first?.payload?.title == "Item")
    }

    @Test func unmappedTombstoneIsSkipped() {
        let planned = ReminderPushPlanner.plan(items: [item(tombstoned: true)], mappings: [:])
        #expect(planned.isEmpty)
    }

    @Test func mappedTombstoneIsDeleted() {
        let state = item(tombstoned: true)
        let planned = ReminderPushPlanner.plan(
            items: [state],
            mappings: [state.localID: .init(externalID: "ext-1", localModifiedAt: nil)]
        )
        #expect(planned.first?.action == .delete(externalID: "ext-1"))
        #expect(planned.first?.payload == nil)
    }

    @Test func cleanMappedItemIsSkipped() {
        let state = item(modifiedAt: Date(timeIntervalSince1970: 2000))
        let planned = ReminderPushPlanner.plan(
            items: [state],
            mappings: [state.localID: .init(
                externalID: "ext-1",
                localModifiedAt: Date(timeIntervalSince1970: 2000)
            )]
        )
        #expect(planned.isEmpty)
    }

    @Test func dirtyMappedItemIsUpdated() {
        let state = item(modifiedAt: Date(timeIntervalSince1970: 3000))
        let planned = ReminderPushPlanner.plan(
            items: [state],
            mappings: [state.localID: .init(
                externalID: "ext-1",
                localModifiedAt: Date(timeIntervalSince1970: 2000)
            )]
        )
        #expect(planned.first?.action == .update(externalID: "ext-1"))
        #expect(planned.first?.localModifiedAt == Date(timeIntervalSince1970: 3000))
    }

    @Test func mappingWithoutPushTimestampCountsAsDirty() {
        let state = item()
        let planned = ReminderPushPlanner.plan(
            items: [state],
            mappings: [state.localID: .init(externalID: "ext-1", localModifiedAt: nil)]
        )
        #expect(planned.first?.action == .update(externalID: "ext-1"))
    }
}
