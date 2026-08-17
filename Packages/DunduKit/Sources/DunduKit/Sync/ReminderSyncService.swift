import Foundation
import SwiftData

/// The full two-way Reminders sync pass (M3). Runs on the main actor with a
/// re-entrancy guard so two passes never overlap; a pass requested while one
/// runs is coalesced into a single re-run.
///
/// EventKit owns Reminders; Google-backed EK calendars are auto-excluded on
/// every pass, not just at setup, so a Google account added to iOS Settings
/// later never creates a second sync path.
@MainActor
public enum ReminderSyncService {
    /// One EKEventStore for the whole app.
    public static let bridge = EventKitBridge()

    private static var isSyncing = false
    private static var rerunRequested = false

    /// Debounce for EKEventStoreChanged, per spec.
    public static let changeDebounce: Duration = .seconds(1)

    /// Posted on the main thread after every completed sync pass, so
    /// schedulers can recompute their next fire date.
    public static let syncDidFinish = Notification.Name("DunduReminderSyncDidFinish")

    // MARK: - Entry point

    public static func syncNow(context: ModelContext) async {
        guard EventKitBridge.accessStatus() == .fullAccess else { return }

        if isSyncing {
            rerunRequested = true
            return
        }
        isSyncing = true
        defer { isSyncing = false }

        repeat {
            rerunRequested = false
            do {
                try await runPass(context: context)
            } catch {
                // A failed pass is retried on the next trigger; sync must
                // never crash the app over a transient store error.
                #if DEBUG
                print("[dundu] sync pass failed: \(error)")
                #endif
            }
        } while rerunRequested

        NotificationCenter.default.post(name: syncDidFinish, object: nil)
    }

    // MARK: - The pass

    private static func runPass(context: ModelContext) async throws {
        let now = Date()

        // 1. Lists: import EK lists, auto-exclude Google-backed ones.
        let ekLists = await bridge.fetchLists()
        let syncedListIDs = try reconcileLists(ekLists, context: context)

        // 2. Full remote fetch of synced lists — EventKit has no delta feed.
        let snapshots = try await bridge.fetchReminders(inLists: Array(syncedListIDs))

        // 3. Load local state.
        let localLists = try context.fetch(FetchDescriptor<ReminderList>())
        let listExternalIDs = Dictionary(
            localLists.compactMap { list in list.externalID.map { (list.id, $0) } },
            uniquingKeysWith: { a, _ in a }
        )
        let listsByExternalID = Dictionary(
            localLists.compactMap { list in list.externalID.map { ($0, list) } },
            uniquingKeysWith: { a, _ in a }
        )
        let defaultListExternalID = try context.defaultList().externalID

        let items = try context.fetch(FetchDescriptor<ReminderItem>())
        let itemsByID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let mappings = try context.fetch(FetchDescriptor<SyncMapping>(
            predicate: #Predicate { $0.bridgeID == "eventkit" }
        ))
        let mappingsByLocalID = Dictionary(mappings.map { ($0.localID, $0) }, uniquingKeysWith: { a, _ in a })

        // 4. Plan.
        let locals = items.map { item in
            ReminderPushPlanner.ItemState(
                localID: item.id,
                isTombstoned: item.isTombstoned,
                modifiedAt: item.modifiedAt,
                payload: item.writePayload(listExternalIDs: listExternalIDs, fallback: defaultListExternalID)
            )
        }
        let remotes = snapshots.map { snapshot in
            ReminderSyncPlanner.RemoteState(
                externalID: snapshot.externalID,
                lastModified: snapshot.lastModified,
                created: snapshot.created,
                payload: snapshot.writePayload
            )
        }
        let mappingViews = mappings.map { mapping in
            ReminderSyncPlanner.MappingView(
                localID: mapping.localID,
                externalID: mapping.externalID,
                base: mapping.baseSnapshot.flatMap { try? JSONDecoder().decode(ReminderWritePayload.self, from: $0) },
                localModifiedAt: mapping.localModifiedAt,
                remoteModifiedAt: mapping.remoteModifiedAt
            )
        }

        let plan = ReminderSyncPlanner.plan(locals: locals, remotes: remotes, mappings: mappingViews, now: now)

        // 5. Remote writes in one batch commit.
        if !plan.remoteChanges.isEmpty {
            let results = await bridge.apply(plan.remoteChanges)
            let plannedByLocalID = Dictionary(
                plan.remoteChanges.map { ($0.localID, $0) }, uniquingKeysWith: { a, _ in a }
            )
            for result in results where result.succeeded {
                guard let change = plannedByLocalID[result.localID] else { continue }
                switch change.action {
                case .create, .update:
                    guard let externalID = result.externalID else { continue }
                    let mapping = try context.upsertMapping(
                        localID: result.localID, bridgeID: .eventkit, externalID: externalID
                    )
                    mapping.localID = result.localID
                    mapping.localModifiedAt = change.localModifiedAt
                    mapping.lastSyncedAt = now
                    mapping.baseSnapshot = change.payload.flatMap { try? JSONEncoder().encode($0) }
                    // If the pushed payload was a merge, land it locally too;
                    // the localWrites below handle that case.

                case .delete:
                    if let mapping = mappingsByLocalID[result.localID] {
                        context.delete(mapping)
                    }
                }
            }
        }

        // 6. Local writes.
        var ingestedItems: [ReminderItem] = []
        for write in plan.localWrites {
            switch write {
            case .createFromRemote(let remote):
                // Heuristic, honestly a heuristic: bare, fresh, spoken-looking
                // items get flagged as probable dictation (spec §8).
                let dictated = SiriOriginDetector.looksDictated(
                    title: remote.payload.title,
                    notes: remote.payload.notes,
                    url: remote.payload.url,
                    remoteCreatedAt: remote.created,
                    now: now
                )
                let item = ReminderItem(
                    title: remote.payload.title,
                    origin: dictated ? .siriSuspected : .eventkit
                )
                apply(remote.payload, to: item, listsByExternalID: listsByExternalID)
                item.modifiedAt = now
                context.insert(item)
                ingestedItems.append(item)
                let mapping = try context.upsertMapping(
                    localID: item.id, bridgeID: .eventkit, externalID: remote.externalID
                )
                mapping.localID = item.id
                mapping.localModifiedAt = item.modifiedAt
                mapping.remoteModifiedAt = remote.lastModified
                mapping.lastSyncedAt = now
                mapping.baseSnapshot = try? JSONEncoder().encode(remote.payload)

            case .apply(let localID, let payload, let remote):
                guard let item = itemsByID[localID] else { continue }
                apply(payload, to: item, listsByExternalID: listsByExternalID)
                item.modifiedAt = now
                if let mapping = mappingsByLocalID[localID] {
                    mapping.localModifiedAt = item.modifiedAt
                    mapping.remoteModifiedAt = remote.lastModified
                    mapping.lastSyncedAt = now
                    mapping.baseSnapshot = try? JSONEncoder().encode(payload)
                }

            case .tombstone(let localID):
                guard let item = itemsByID[localID] else { continue }
                context.tombstone(item, at: now)
                if let mapping = mappingsByLocalID[localID] {
                    context.delete(mapping)
                }
            }
        }

        // 7. Bookkeeping for clean pairs and orphans.
        for refresh in plan.refreshes {
            guard let mapping = mappingsByLocalID[refresh.localID] else { continue }
            mapping.remoteModifiedAt = refresh.remote.lastModified
            mapping.lastSyncedAt = now
            if mapping.baseSnapshot == nil {
                mapping.baseSnapshot = try? JSONEncoder().encode(refresh.remote.payload)
            }
        }
        for orphanID in plan.orphanedMappingIDs {
            if let mapping = mappingsByLocalID[orphanID] {
                context.delete(mapping)
            }
        }

        try context.purgeExpiredTombstones(now: now)
        // Deduplication deliberately does NOT run here. It tombstones, and
        // tombstones become deletions in Apple Reminders — an automatic
        // destructive pass that has twice mistaken real reminders for copies
        // and taken hundreds of them with it. It is a deliberate action the
        // user asks for and can see the result of, not something that happens
        // quietly on a timer. See `deduplicateReminders`.
        try context.save()

        // 8. Intelligence on ingest (spec §9 trigger 1): every new remote
        // item runs routing and repair. Silent when confident, queued for
        // the Inbox when not. Runs after save so a crash mid-AI never loses
        // the item itself; a routing move dirties modifiedAt and rides the
        // next pass.
        if !ingestedItems.isEmpty {
            let profile = ProfileContextStore().load()
            let allLists = try context.fetch(FetchDescriptor<ReminderList>())
            var movedAny = false
            for item in ingestedItems {
                let moved = await IntelligenceService.processIngested(
                    item, lists: allLists, profile: profile, now: now
                )
                movedAny = movedAny || moved
            }
            try context.save()
            if movedAny {
                rerunRequested = true
            }
        }
    }

    // MARK: - Lists

    /// Imports EK reminder lists as local `ReminderList` records and returns
    /// the EK identifiers that sync. Google-backed sources land on the
    /// exclusion list every pass (spec edge case 1) unless user-overridden.
    private static func reconcileLists(
        _ ekLists: [EKListSnapshot], context: ModelContext
    ) throws -> Set<String> {
        let exclusions = try context.fetch(FetchDescriptor<ExcludedEKCalendar>())
        var excludedIDs = Set(exclusions.filter { !$0.isUserOverridden }.map(\.ekCalendarID))

        for ekList in ekLists where ekList.isGoogleBacked {
            if let existing = exclusions.first(where: { $0.ekCalendarID == ekList.id }) {
                if !existing.isUserOverridden {
                    excludedIDs.insert(ekList.id)
                }
            } else {
                context.insert(ExcludedEKCalendar(
                    ekCalendarID: ekList.id, title: ekList.title, sourceTitle: ekList.sourceTitle
                ))
                excludedIDs.insert(ekList.id)
            }
        }

        let localLists = try context.fetch(FetchDescriptor<ReminderList>())
        var synced = Set<String>()
        for ekList in ekLists where !excludedIDs.contains(ekList.id) {
            synced.insert(ekList.id)
            if let existing = localLists.first(where: { $0.externalID == ekList.id }) {
                if existing.title != ekList.title {
                    existing.title = ekList.title
                }
            } else if let unbound = localLists.first(where: { $0.externalID == nil && $0.isDefault }) {
                // First pass: bind the bootstrap default list to the EK
                // default rather than duplicating it.
                unbound.externalID = ekList.id
                unbound.title = ekList.title
            } else {
                context.insert(ReminderList(
                    title: ekList.title,
                    colorHex: ekList.colorHex ?? "#007AFF",
                    externalID: ekList.id
                ))
            }
        }
        return synced
    }

    // MARK: - Field application

    private static func apply(
        _ payload: ReminderWritePayload,
        to item: ReminderItem,
        listsByExternalID: [String: ReminderList]
    ) {
        item.title = payload.title
        item.notes = payload.notes
        item.dueDate = payload.dueDate
        item.hasTime = payload.hasTime
        item.priorityRaw = payload.priority
        item.isCompleted = payload.isCompleted
        item.completedAt = payload.completedAt
        item.url = payload.url
        item.alarmOffsets = payload.alarmOffsets
        item.locationAlarm = payload.locationAlarm
        if let listExternalID = payload.listExternalID,
           let list = listsByExternalID[listExternalID] {
            item.listID = list.id
        }
    }
}

// MARK: - Payload builders

extension ReminderItem {
    /// The item's syncable fields as a write payload.
    public func writePayload(
        listExternalIDs: [UUID: String], fallback: String?
    ) -> ReminderWritePayload {
        ReminderWritePayload(
            title: title,
            notes: notes,
            dueDate: dueDate,
            hasTime: hasTime,
            priority: priorityRaw,
            isCompleted: isCompleted,
            completedAt: completedAt,
            url: url,
            alarmOffsets: alarmOffsets,
            locationAlarm: locationAlarm,
            listExternalID: listID.flatMap { listExternalIDs[$0] } ?? fallback
        )
    }
}

extension EKReminderSnapshot {
    /// The snapshot's syncable fields, shaped for comparison against local
    /// payloads and base snapshots.
    public var writePayload: ReminderWritePayload {
        ReminderWritePayload(
            title: title,
            notes: notes,
            dueDate: dueDate,
            hasTime: hasTime,
            priority: priority,
            isCompleted: isCompleted,
            completedAt: completedAt,
            url: url,
            alarmOffsets: alarmOffsets,
            locationAlarm: locationAlarm,
            listExternalID: listID
        )
    }
}
