import Foundation
import Testing
@testable import DunduKit

@Suite("Two-way sync planning")
struct ReminderSyncPlannerTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func payload(_ title: String, completed: Bool = false, notes: String? = nil) -> ReminderWritePayload {
        ReminderWritePayload(title: title, notes: notes, isCompleted: completed)
    }

    private func local(
        id: UUID = UUID(),
        _ payload: ReminderWritePayload,
        tombstoned: Bool = false,
        modifiedAt: Date? = nil
    ) -> ReminderPushPlanner.ItemState {
        ReminderPushPlanner.ItemState(
            localID: id, isTombstoned: tombstoned,
            modifiedAt: modifiedAt ?? now, payload: payload
        )
    }

    private func remote(
        _ externalID: String,
        _ payload: ReminderWritePayload,
        lastModified: Date? = nil
    ) -> ReminderSyncPlanner.RemoteState {
        ReminderSyncPlanner.RemoteState(
            externalID: externalID, lastModified: lastModified ?? now, payload: payload
        )
    }

    // MARK: - Partition rows

    @Test func localOnlyCreatesRemote() {
        let item = local(payload("New local"))
        let plan = ReminderSyncPlanner.plan(locals: [item], remotes: [], mappings: [], now: now)
        #expect(plan.remoteChanges.map(\.action) == [.create])
        #expect(plan.localWrites.isEmpty)
    }

    @Test func remoteOnlyCreatesLocal() {
        let state = remote("ext-1", payload("New remote"))
        let plan = ReminderSyncPlanner.plan(locals: [], remotes: [state], mappings: [], now: now)
        #expect(plan.localWrites == [.createFromRemote(state)])
        #expect(plan.remoteChanges.isEmpty)
    }

    @Test func cleanPairOnlyRefreshes() {
        let base = payload("Same")
        let item = local(base)
        let plan = ReminderSyncPlanner.plan(
            locals: [item],
            remotes: [remote("ext-1", base)],
            mappings: [.init(localID: item.localID, externalID: "ext-1", base: base)],
            now: now
        )
        #expect(plan.isEmpty)
        #expect(plan.refreshes.count == 1)
    }

    @Test func onlyLocalChangedPushes() {
        let base = payload("Original")
        let item = local(payload("Edited locally"))
        let plan = ReminderSyncPlanner.plan(
            locals: [item],
            remotes: [remote("ext-1", base)],
            mappings: [.init(localID: item.localID, externalID: "ext-1", base: base)],
            now: now
        )
        #expect(plan.remoteChanges.map(\.action) == [.update(externalID: "ext-1")])
        #expect(plan.remoteChanges.first?.payload?.title == "Edited locally")
        #expect(plan.localWrites.isEmpty)
    }

    @Test func onlyRemoteChangedPulls() {
        let base = payload("Original")
        let item = local(base)
        let state = remote("ext-1", payload("Edited remotely"))
        let plan = ReminderSyncPlanner.plan(
            locals: [item],
            remotes: [state],
            mappings: [.init(localID: item.localID, externalID: "ext-1", base: base)],
            now: now
        )
        #expect(plan.localWrites == [.apply(localID: item.localID, payload: state.payload, remote: state)])
        #expect(plan.remoteChanges.isEmpty)
    }

    @Test func bothChangedDifferentFieldsMergesWithoutConflict() {
        let base = ReminderWritePayload(title: "Original", notes: "base notes")
        let item = local(ReminderWritePayload(title: "Local title", notes: "base notes"))
        let state = remote("ext-1", ReminderWritePayload(title: "Original", notes: "remote notes"))
        let plan = ReminderSyncPlanner.plan(
            locals: [item],
            remotes: [state],
            mappings: [.init(localID: item.localID, externalID: "ext-1", base: base)],
            now: now
        )
        // Merged result: local title + remote notes, pushed and pulled.
        let expected = ReminderWritePayload(title: "Local title", notes: "remote notes")
        #expect(plan.remoteChanges.first?.payload == expected)
        if case .apply(_, let payload, _)? = plan.localWrites.first {
            #expect(payload == expected)
        } else {
            Issue.record("Expected a local apply")
        }
    }

    @Test func remoteMissingTombstonesLocal() {
        let item = local(payload("Was synced"))
        let plan = ReminderSyncPlanner.plan(
            locals: [item],
            remotes: [],
            mappings: [.init(localID: item.localID, externalID: "ext-gone", base: item.payload)],
            now: now
        )
        #expect(plan.localWrites == [.tombstone(localID: item.localID)])
    }

    @Test func localTombstoneDeletesRemote() {
        let item = local(payload("Deleted here"), tombstoned: true)
        let plan = ReminderSyncPlanner.plan(
            locals: [item],
            remotes: [remote("ext-1", payload("Deleted here"))],
            mappings: [.init(localID: item.localID, externalID: "ext-1", base: item.payload)],
            now: now
        )
        #expect(plan.remoteChanges.map(\.action) == [.delete(externalID: "ext-1")])
    }

    @Test func bothGoneDropsMapping() {
        let item = local(payload("Gone"), tombstoned: true)
        let plan = ReminderSyncPlanner.plan(
            locals: [item],
            remotes: [],
            mappings: [.init(localID: item.localID, externalID: "ext-1", base: item.payload)],
            now: now
        )
        #expect(plan.orphanedMappingIDs == [item.localID])
        #expect(plan.localWrites.isEmpty)
        #expect(plan.remoteChanges.isEmpty)
    }

    @Test func duplicateExternalIDsKeepMostRecentlyModified() {
        let older = remote("dup", payload("Older"), lastModified: now.addingTimeInterval(-100))
        let newer = remote("dup", payload("Newer"), lastModified: now)
        let plan = ReminderSyncPlanner.plan(locals: [], remotes: [older, newer], mappings: [], now: now)
        #expect(plan.localWrites == [.createFromRemote(newer)])
    }

    @Test func echoSuppressionOurWriteComesBackClean() {
        // After we push, EK bumps lastModified — but the payload equals the
        // base we stored, so the pass must plan nothing.
        let pushed = payload("Pushed by us")
        let item = local(pushed, modifiedAt: now.addingTimeInterval(-10))
        let plan = ReminderSyncPlanner.plan(
            locals: [item],
            remotes: [remote("ext-1", pushed, lastModified: now)],
            mappings: [.init(
                localID: item.localID, externalID: "ext-1", base: pushed,
                localModifiedAt: item.modifiedAt,
                remoteModifiedAt: now.addingTimeInterval(-10)
            )],
            now: now
        )
        #expect(plan.isEmpty)
    }

    // MARK: - Merge rules

    @Test func conflictLaterModificationWins() {
        let base = payload("Base")
        let merged = ReminderSyncPlanner.merge(
            base: base,
            local: payload("Local edit"),
            remote: payload("Remote edit"),
            localModifiedAt: now,
            remoteModifiedAt: now.addingTimeInterval(60),
            now: now
        )
        #expect(merged.title == "Remote edit")

        let mergedLocalWins = ReminderSyncPlanner.merge(
            base: base,
            local: payload("Local edit"),
            remote: payload("Remote edit"),
            localModifiedAt: now,
            remoteModifiedAt: now.addingTimeInterval(-60),
            now: now
        )
        #expect(mergedLocalWins.title == "Local edit")
    }

    @Test func conflictTieWithinSkewToleranceRemoteWins() {
        let merged = ReminderSyncPlanner.merge(
            base: payload("Base"),
            local: payload("Local edit"),
            remote: payload("Remote edit"),
            localModifiedAt: now,
            remoteModifiedAt: now.addingTimeInterval(1.5),
            now: now
        )
        #expect(merged.title == "Remote edit")
    }

    @Test func completionBeatsUncompletionInConflict() {
        // Both sides changed completion differently from base: done wins,
        // even though remote is later and says not-done.
        let base = payload("Task", completed: false)
        var localDone = payload("Task", completed: true)
        localDone.completedAt = now
        var remoteEdit = payload("Task renamed", completed: false)
        remoteEdit.notes = "changed"

        // Local completed (changed), remote changed other fields AND stayed
        // uncompleted — one-sided completion change, completion propagates.
        let merged = ReminderSyncPlanner.merge(
            base: base,
            local: localDone,
            remote: remoteEdit,
            localModifiedAt: now,
            remoteModifiedAt: now.addingTimeInterval(60),
            now: now
        )
        #expect(merged.isCompleted)
        #expect(merged.title == "Task renamed")
    }

    @Test func cleanUncompleteFromRemoteStillPropagates() {
        // Base and local both completed; remote unchecked it. That is a
        // one-sided change and must pull through — the special rule only
        // guards genuine conflicts.
        var base = payload("Task", completed: true)
        base.completedAt = now.addingTimeInterval(-100)
        let merged = ReminderSyncPlanner.merge(
            base: base,
            local: base,
            remote: payload("Task", completed: false),
            localModifiedAt: now,
            remoteModifiedAt: now,
            now: now
        )
        #expect(!merged.isCompleted)
        #expect(merged.completedAt == nil)
    }

    @Test func noBaseConflictingCompletionResolvesDone() {
        var localDone = payload("Task", completed: true)
        localDone.completedAt = now
        let merged = ReminderSyncPlanner.merge(
            base: nil,
            local: localDone,
            remote: payload("Task", completed: false),
            localModifiedAt: now,
            remoteModifiedAt: now.addingTimeInterval(60),
            now: now
        )
        #expect(merged.isCompleted)
    }
}

// MARK: - The echo

/// The duplicate engine, pinned.
///
/// Device A creates a reminder and pushes it to EventKit, recording its own
/// mapping. CloudKit replicates the *item* to device B, which has no mapping
/// for it. On device B the item is an unmapped local and device A's push is
/// an unmapped remote — and before this, the planner's two independent loops
/// both fired: push a second EKReminder, and ingest a second local copy.
/// Observed live as three "Proposal to Kalpa" rows created minutes apart.
@Suite("Sync planning — the push/ingest echo")
struct ReminderEchoTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func payload(_ title: String, completed: Bool = false) -> ReminderWritePayload {
        ReminderWritePayload(title: title, notes: nil, isCompleted: completed)
    }

    private func local(_ payload: ReminderWritePayload, id: UUID = UUID()) -> ReminderPushPlanner.ItemState {
        ReminderPushPlanner.ItemState(
            localID: id, isTombstoned: false, modifiedAt: now, payload: payload
        )
    }

    private func remote(_ externalID: String, _ payload: ReminderWritePayload) -> ReminderSyncPlanner.RemoteState {
        ReminderSyncPlanner.RemoteState(
            externalID: externalID, lastModified: now, payload: payload
        )
    }

    @Test func anUnmappedPairIsIntroducedRatherThanDuplicated() {
        let item = local(payload("Proposal to Kalpa"))
        let echo = remote("ek-1", payload("Proposal to Kalpa"))
        let plan = ReminderSyncPlanner.plan(locals: [item], remotes: [echo], mappings: [], now: now)

        #expect(plan.adoptions.count == 1)
        #expect(plan.adoptions.first?.localID == item.localID)
        #expect(plan.adoptions.first?.remote.externalID == "ek-1")
        // Neither side gets a second copy.
        #expect(plan.remoteChanges.isEmpty)
        #expect(plan.localWrites.isEmpty)
    }

    /// Same title but genuinely different content is two reminders. Joining
    /// them would silently discard one, which is worse than a duplicate.
    @Test func differingPayloadsAreStillTwoReminders() {
        let item = local(payload("Proposal to Kalpa"))
        let other = remote("ek-2", payload("Proposal to Kalpa", completed: true))
        let plan = ReminderSyncPlanner.plan(locals: [item], remotes: [other], mappings: [], now: now)

        #expect(plan.adoptions.isEmpty)
        #expect(plan.remoteChanges.map(\.action) == [.create])
        #expect(plan.localWrites.count == 1)
    }

    /// One remote can only be claimed once, or two local copies both adopt it
    /// and the second silently loses its own identity.
    @Test func oneRemoteIsAdoptedByOnlyOneLocal() {
        let first = local(payload("Brush"))
        let second = local(payload("Brush"))
        let echo = remote("ek-3", payload("Brush"))
        let plan = ReminderSyncPlanner.plan(locals: [first, second], remotes: [echo], mappings: [], now: now)

        #expect(plan.adoptions.count == 1)
        // The one left over is a real local-only item and still gets pushed.
        #expect(plan.remoteChanges.map(\.action) == [.create])
    }

    @Test func aLocalWithNoRemoteCounterpartStillPushes() {
        let item = local(payload("Only here"))
        let plan = ReminderSyncPlanner.plan(locals: [item], remotes: [], mappings: [], now: now)
        #expect(plan.adoptions.isEmpty)
        #expect(plan.remoteChanges.map(\.action) == [.create])
    }

    @Test func aRemoteWithNoLocalCounterpartStillIngests() {
        let incoming = remote("ek-4", payload("From Reminders"))
        let plan = ReminderSyncPlanner.plan(locals: [], remotes: [incoming], mappings: [], now: now)
        #expect(plan.adoptions.isEmpty)
        #expect(plan.localWrites.count == 1)
    }

    /// A tombstoned local must not adopt anything — it is on its way out.
    @Test func aTombstonedLocalDoesNotAdopt() {
        var item = local(payload("Going away"))
        item = ReminderPushPlanner.ItemState(
            localID: item.localID, isTombstoned: true, modifiedAt: now, payload: item.payload
        )
        let echo = remote("ek-5", payload("Going away"))
        let plan = ReminderSyncPlanner.plan(locals: [item], remotes: [echo], mappings: [], now: now)

        #expect(plan.adoptions.isEmpty)
        #expect(plan.localWrites.count == 1)
    }
}
