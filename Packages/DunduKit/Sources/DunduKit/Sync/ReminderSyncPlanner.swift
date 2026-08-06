import Foundation

/// The two-way sync brain (M3). Pure functions over value states — no
/// EventKit, no SwiftData — so every partition row and merge rule is
/// unit-testable.
///
/// Change detection is field-based, not timestamp-based: a side "changed"
/// when its payload differs from the `baseSnapshot` taken at last sync.
/// That is also the echo suppression — our own write coming back reads as
/// "remote equals base", which plans to nothing. Timestamps only decide
/// true conflicts, with a 2-second tolerance for clock skew (remote wins
/// ties, because remote may carry an edit from a device we cannot see).
public enum ReminderSyncPlanner {
    public static let clockSkewTolerance: TimeInterval = 2

    // MARK: - Inputs

    public struct RemoteState: Sendable, Equatable {
        public var externalID: String
        public var lastModified: Date?
        /// Remote creation date; only the Siri-origin heuristic reads it.
        public var created: Date?
        public var payload: ReminderWritePayload

        public init(externalID: String, lastModified: Date?, created: Date? = nil, payload: ReminderWritePayload) {
            self.externalID = externalID
            self.lastModified = lastModified
            self.created = created
            self.payload = payload
        }
    }

    public struct MappingView: Sendable, Equatable {
        public var localID: UUID
        public var externalID: String
        public var base: ReminderWritePayload?
        public var localModifiedAt: Date?
        public var remoteModifiedAt: Date?

        public init(
            localID: UUID,
            externalID: String,
            base: ReminderWritePayload? = nil,
            localModifiedAt: Date? = nil,
            remoteModifiedAt: Date? = nil
        ) {
            self.localID = localID
            self.externalID = externalID
            self.base = base
            self.localModifiedAt = localModifiedAt
            self.remoteModifiedAt = remoteModifiedAt
        }
    }

    // MARK: - Outputs

    public enum LocalWrite: Sendable, Equatable {
        /// Remote-only item: create locally with origin `eventkit`.
        case createFromRemote(RemoteState)
        /// Pull remote fields onto an existing local item.
        case apply(localID: UUID, payload: ReminderWritePayload, remote: RemoteState)
        /// Mapping exists but the remote item is gone: remote deletion.
        case tombstone(localID: UUID)
    }

    public struct Plan: Sendable, Equatable {
        /// Writes for the EventKit side, applied through the bridge.
        public var remoteChanges: [PlannedReminderChange]
        /// Writes for the local store.
        public var localWrites: [LocalWrite]
        /// Clean pairs whose mapping still deserves fresh bookkeeping
        /// (base backfill, remote timestamp refresh).
        public var refreshes: [(localID: UUID, remote: RemoteState)]
        /// Mappings whose local item vanished entirely (purged): drop.
        public var orphanedMappingIDs: [UUID]

        public static func == (lhs: Plan, rhs: Plan) -> Bool {
            lhs.remoteChanges == rhs.remoteChanges
                && lhs.localWrites == rhs.localWrites
                && lhs.refreshes.map(\.localID) == rhs.refreshes.map(\.localID)
                && lhs.refreshes.map(\.remote) == rhs.refreshes.map(\.remote)
                && lhs.orphanedMappingIDs == rhs.orphanedMappingIDs
        }

        public var isEmpty: Bool {
            remoteChanges.isEmpty && localWrites.isEmpty && orphanedMappingIDs.isEmpty
        }
    }

    // MARK: - Planning

    public static func plan(
        locals: [ReminderPushPlanner.ItemState],
        remotes: [RemoteState],
        mappings: [MappingView],
        now: Date = Date()
    ) -> Plan {
        let localsByID = Dictionary(locals.map { ($0.localID, $0) }, uniquingKeysWith: { a, _ in a })

        // External IDs are not guaranteed unique. Keep the most recently
        // modified snapshot per ID; the losers get reconciled next pass.
        var remotesByExternalID: [String: RemoteState] = [:]
        for remote in remotes {
            if let existing = remotesByExternalID[remote.externalID] {
                if (remote.lastModified ?? .distantPast) > (existing.lastModified ?? .distantPast) {
                    remotesByExternalID[remote.externalID] = remote
                }
            } else {
                remotesByExternalID[remote.externalID] = remote
            }
        }

        var plan = Plan(remoteChanges: [], localWrites: [], refreshes: [], orphanedMappingIDs: [])
        var mappedLocalIDs = Set<UUID>()
        var mappedExternalIDs = Set<String>()

        for mapping in mappings {
            mappedLocalIDs.insert(mapping.localID)
            mappedExternalIDs.insert(mapping.externalID)

            let local = localsByID[mapping.localID]
            let remote = remotesByExternalID[mapping.externalID]

            switch (local, remote) {
            case (nil, nil):
                plan.orphanedMappingIDs.append(mapping.localID)

            case (nil, .some):
                // Local item purged entirely; finish the deletion remotely.
                plan.remoteChanges.append(PlannedReminderChange(
                    localID: mapping.localID,
                    action: .delete(externalID: mapping.externalID),
                    payload: nil,
                    localModifiedAt: now
                ))

            case (let local?, nil):
                if local.isTombstoned {
                    // Both sides agree it is gone.
                    plan.orphanedMappingIDs.append(mapping.localID)
                } else {
                    // Remote deletion wins over local edits: tombstone.
                    plan.localWrites.append(.tombstone(localID: local.localID))
                }

            case (let local?, let remote?):
                if local.isTombstoned {
                    plan.remoteChanges.append(PlannedReminderChange(
                        localID: local.localID,
                        action: .delete(externalID: mapping.externalID),
                        payload: nil,
                        localModifiedAt: local.modifiedAt
                    ))
                    continue
                }

                let base = mapping.base
                let localChanged = base.map { local.payload != $0 } ?? true
                let remoteChanged = base.map { remote.payload != $0 } ?? true

                switch (localChanged, remoteChanged) {
                case (false, false):
                    plan.refreshes.append((mapping.localID, remote))

                case (true, false):
                    plan.remoteChanges.append(PlannedReminderChange(
                        localID: local.localID,
                        action: .update(externalID: mapping.externalID),
                        payload: local.payload,
                        localModifiedAt: local.modifiedAt
                    ))

                case (false, true):
                    plan.localWrites.append(.apply(
                        localID: local.localID, payload: remote.payload, remote: remote
                    ))

                case (true, true):
                    let merged = merge(
                        base: base,
                        local: local.payload,
                        remote: remote.payload,
                        localModifiedAt: local.modifiedAt,
                        remoteModifiedAt: remote.lastModified,
                        now: now
                    )
                    if merged != local.payload {
                        plan.localWrites.append(.apply(
                            localID: local.localID, payload: merged, remote: remote
                        ))
                    }
                    if merged != remote.payload {
                        plan.remoteChanges.append(PlannedReminderChange(
                            localID: local.localID,
                            action: .update(externalID: mapping.externalID),
                            payload: merged,
                            localModifiedAt: local.modifiedAt
                        ))
                    }
                    if merged == local.payload && merged == remote.payload {
                        plan.refreshes.append((mapping.localID, remote))
                    }
                }
            }
        }

        // Local only, no mapping: create in EventKit.
        for local in locals where !mappedLocalIDs.contains(local.localID) && !local.isTombstoned {
            plan.remoteChanges.append(PlannedReminderChange(
                localID: local.localID,
                action: .create,
                payload: local.payload,
                localModifiedAt: local.modifiedAt
            ))
        }

        // Remote only, no mapping: create locally.
        for remote in remotesByExternalID.values where !mappedExternalIDs.contains(remote.externalID) {
            plan.localWrites.append(.createFromRemote(remote))
        }

        return plan
    }

    // MARK: - Three-way merge

    /// Field-level merge against the base snapshot. One-sided changes win
    /// outright; genuine conflicts fall to the later modification time,
    /// remote winning ties. Completion beats uncompletion in conflicts —
    /// resurrecting a finished task annoys people more than the reverse.
    public static func merge(
        base: ReminderWritePayload?,
        local: ReminderWritePayload,
        remote: ReminderWritePayload,
        localModifiedAt: Date,
        remoteModifiedAt: Date?,
        now: Date = Date()
    ) -> ReminderWritePayload {
        let remoteWinsConflicts: Bool = {
            guard let remoteModifiedAt else { return true }
            if abs(localModifiedAt.timeIntervalSince(remoteModifiedAt)) <= clockSkewTolerance {
                return true
            }
            return remoteModifiedAt > localModifiedAt
        }()

        var result = local

        func resolve<T: Equatable>(_ keyPath: WritableKeyPath<ReminderWritePayload, T>) {
            let localValue = local[keyPath: keyPath]
            let remoteValue = remote[keyPath: keyPath]
            if localValue == remoteValue {
                result[keyPath: keyPath] = localValue
                return
            }
            if let base {
                if localValue == base[keyPath: keyPath] {
                    result[keyPath: keyPath] = remoteValue
                    return
                }
                if remoteValue == base[keyPath: keyPath] {
                    result[keyPath: keyPath] = localValue
                    return
                }
            }
            result[keyPath: keyPath] = remoteWinsConflicts ? remoteValue : localValue
        }

        resolve(\.title)
        resolve(\.notes)
        resolve(\.dueDate)
        resolve(\.hasTime)
        resolve(\.priority)
        resolve(\.url)
        resolve(\.alarmOffsets)
        resolve(\.locationAlarm)
        resolve(\.listExternalID)

        // Completion is special only in a genuine two-sided conflict; a
        // clean one-sided uncomplete must still propagate.
        let localDone = local.isCompleted
        let remoteDone = remote.isCompleted
        if localDone == remoteDone {
            result.isCompleted = localDone
            resolve(\.completedAt)
        } else if let base, localDone == base.isCompleted {
            result.isCompleted = remoteDone
            result.completedAt = remoteDone ? remote.completedAt : nil
        } else if let base, remoteDone == base.isCompleted {
            result.isCompleted = localDone
            result.completedAt = localDone ? local.completedAt : nil
        } else {
            result.isCompleted = true
            result.completedAt = (localDone ? local.completedAt : remote.completedAt) ?? now
        }

        return result
    }
}
