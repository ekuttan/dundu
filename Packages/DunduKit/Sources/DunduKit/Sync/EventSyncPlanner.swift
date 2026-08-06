import Foundation

/// The event-side sync brain. Unlike EventKit's full-fetch-and-diff, Google
/// delivers deltas through sync tokens — so this planner reasons about
/// changes, not state. The prime directive from spec edge 4: an item merely
/// absent from a response is never a deletion; only an explicit `cancelled`
/// status deletes.
public enum EventSyncPlanner {
    // MARK: - Inputs

    public struct LocalState: Sendable, Equatable {
        public var localID: UUID
        public var isTombstoned: Bool
        public var modifiedAt: Date
        public var payload: EventWritePayload

        public init(localID: UUID, isTombstoned: Bool, modifiedAt: Date, payload: EventWritePayload) {
            self.localID = localID
            self.isTombstoned = isTombstoned
            self.modifiedAt = modifiedAt
            self.payload = payload
        }
    }

    public struct RemoteDelta: Sendable, Equatable {
        public var eventID: String
        public var etag: String?
        public var updated: Date?
        public var cancelled: Bool
        /// Nil for cancelled tombstone stubs.
        public var payload: EventWritePayload?
        /// The full wire event, for pull-only extras (attendees, conference).
        public var wire: GEvent

        public init(eventID: String, etag: String?, updated: Date?, cancelled: Bool, payload: EventWritePayload?, wire: GEvent) {
            self.eventID = eventID
            self.etag = etag
            self.updated = updated
            self.cancelled = cancelled
            self.payload = payload
            self.wire = wire
        }
    }

    public struct MappingView: Sendable, Equatable {
        public var localID: UUID
        public var eventID: String
        public var etag: String?
        public var base: EventWritePayload?
        public var localModifiedAt: Date?

        public init(localID: UUID, eventID: String, etag: String? = nil, base: EventWritePayload? = nil, localModifiedAt: Date? = nil) {
            self.localID = localID
            self.eventID = eventID
            self.etag = etag
            self.base = base
            self.localModifiedAt = localModifiedAt
        }
    }

    // MARK: - Outputs

    public struct RemoteInsert: Sendable, Equatable {
        public var localID: UUID
        /// Deterministic from the local UUID — retries are idempotent.
        public var eventID: String
        public var payload: EventWritePayload
        public var localModifiedAt: Date
    }

    public struct RemotePatch: Sendable, Equatable {
        public var localID: UUID
        public var eventID: String
        public var etag: String?
        public var payload: EventWritePayload
        public var localModifiedAt: Date
    }

    public struct RemoteDelete: Sendable, Equatable {
        public var localID: UUID
        public var eventID: String
    }

    public enum LocalWrite: Sendable, Equatable {
        case createFromRemote(RemoteDelta)
        case apply(localID: UUID, payload: EventWritePayload, delta: RemoteDelta)
        case tombstone(localID: UUID)
    }

    public struct Plan: Sendable {
        public var inserts: [RemoteInsert] = []
        public var patches: [RemotePatch] = []
        public var deletes: [RemoteDelete] = []
        public var localWrites: [LocalWrite] = []
        /// Deltas for clean pairs: refresh etag/base bookkeeping only.
        public var refreshes: [(localID: UUID, delta: RemoteDelta)] = []
        public var orphanedMappingIDs: [UUID] = []

        public var isEmpty: Bool {
            inserts.isEmpty && patches.isEmpty && deletes.isEmpty
                && localWrites.isEmpty && orphanedMappingIDs.isEmpty
        }
    }

    // MARK: - Planning

    public static func plan(
        locals: [LocalState],
        deltas: [RemoteDelta],
        mappings: [MappingView],
        now: Date = Date()
    ) -> Plan {
        var plan = Plan()

        let localsByID = Dictionary(locals.map { ($0.localID, $0) }, uniquingKeysWith: { a, _ in a })
        let mappingsByEventID = Dictionary(mappings.map { ($0.eventID, $0) }, uniquingKeysWith: { a, _ in a })
        let mappingsByLocalID = Dictionary(mappings.map { ($0.localID, $0) }, uniquingKeysWith: { a, _ in a })

        // Newest delta per event id wins when a page carries several.
        var deltasByEventID: [String: RemoteDelta] = [:]
        for delta in deltas {
            if let existing = deltasByEventID[delta.eventID] {
                if (delta.updated ?? .distantPast) >= (existing.updated ?? .distantPast) {
                    deltasByEventID[delta.eventID] = delta
                }
            } else {
                deltasByEventID[delta.eventID] = delta
            }
        }

        // 1. Remote deltas drive pulls, merges, and remote deletions.
        for delta in deltasByEventID.values {
            let mapping = mappingsByEventID[delta.eventID]

            if delta.cancelled {
                if let mapping {
                    if let local = localsByID[mapping.localID], !local.isTombstoned {
                        plan.localWrites.append(.tombstone(localID: mapping.localID))
                    } else {
                        plan.orphanedMappingIDs.append(mapping.localID)
                    }
                }
                // Cancelled with no mapping: never knew it, nothing to do.
                continue
            }

            guard let remotePayload = delta.payload else { continue }

            guard let mapping, let local = localsByID[mapping.localID] else {
                if mapping == nil {
                    plan.localWrites.append(.createFromRemote(delta))
                }
                // Mapping with no local item: purge finished remotely below.
                continue
            }

            if local.isTombstoned {
                plan.deletes.append(RemoteDelete(localID: local.localID, eventID: delta.eventID))
                continue
            }

            let base = mapping.base
            let localChanged = base.map { local.payload != $0 } ?? false
            let remoteChanged = base.map { remotePayload != $0 } ?? true

            switch (localChanged, remoteChanged) {
            case (false, false):
                plan.refreshes.append((local.localID, delta))

            case (false, true):
                plan.localWrites.append(.apply(localID: local.localID, payload: remotePayload, delta: delta))

            case (true, false):
                plan.patches.append(RemotePatch(
                    localID: local.localID, eventID: delta.eventID, etag: delta.etag,
                    payload: local.payload, localModifiedAt: local.modifiedAt
                ))

            case (true, true):
                let merged = merge(
                    base: base, local: local.payload, remote: remotePayload,
                    localModifiedAt: local.modifiedAt, remoteModifiedAt: delta.updated
                )
                if merged != local.payload {
                    plan.localWrites.append(.apply(localID: local.localID, payload: merged, delta: delta))
                }
                if merged != remotePayload {
                    plan.patches.append(RemotePatch(
                        localID: local.localID, eventID: delta.eventID, etag: delta.etag,
                        payload: merged, localModifiedAt: local.modifiedAt
                    ))
                }
                if merged == local.payload && merged == remotePayload {
                    plan.refreshes.append((local.localID, delta))
                }
            }
        }

        // 2. Local changes with no remote delta this round.
        for local in locals {
            let mapping = mappingsByLocalID[local.localID]
            let hadDelta = mapping.map { deltasByEventID[$0.eventID] != nil } ?? false
            guard !hadDelta else { continue }

            switch (mapping, local.isTombstoned) {
            case (nil, true):
                continue

            case (nil, false):
                plan.inserts.append(RemoteInsert(
                    localID: local.localID,
                    eventID: GoogleEventID.from(local.localID),
                    payload: local.payload,
                    localModifiedAt: local.modifiedAt
                ))

            case (let mapping?, true):
                plan.deletes.append(RemoteDelete(localID: local.localID, eventID: mapping.eventID))

            case (let mapping?, false):
                // Dirty when the payload drifted from base. No delta means
                // the remote is unchanged; push wins without a merge.
                if mapping.base.map({ local.payload != $0 }) ?? true {
                    plan.patches.append(RemotePatch(
                        localID: local.localID, eventID: mapping.eventID, etag: mapping.etag,
                        payload: local.payload, localModifiedAt: local.modifiedAt
                    ))
                }
            }
        }

        // 3. Mappings whose local item was purged entirely.
        for mapping in mappings where localsByID[mapping.localID] == nil {
            if let delta = deltasByEventID[mapping.eventID], !delta.cancelled {
                plan.deletes.append(RemoteDelete(localID: mapping.localID, eventID: mapping.eventID))
            } else if deltasByEventID[mapping.eventID] == nil {
                plan.deletes.append(RemoteDelete(localID: mapping.localID, eventID: mapping.eventID))
            }
            plan.orphanedMappingIDs.append(mapping.localID)
        }

        return plan
    }

    // MARK: - Merge

    /// Field-level three-way merge, same discipline as reminders: one-sided
    /// changes win outright, true conflicts fall to the later timestamp with
    /// remote winning ties inside the clock-skew tolerance.
    public static func merge(
        base: EventWritePayload?,
        local: EventWritePayload,
        remote: EventWritePayload,
        localModifiedAt: Date,
        remoteModifiedAt: Date?
    ) -> EventWritePayload {
        let remoteWinsConflicts: Bool = {
            guard let remoteModifiedAt else { return true }
            if abs(localModifiedAt.timeIntervalSince(remoteModifiedAt)) <= ReminderSyncPlanner.clockSkewTolerance {
                return true
            }
            return remoteModifiedAt > localModifiedAt
        }()

        var result = local

        func resolve<T: Equatable>(_ keyPath: WritableKeyPath<EventWritePayload, T>) {
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
        resolve(\.location)
        resolve(\.startAt)
        resolve(\.endAt)
        resolve(\.isAllDay)
        resolve(\.timeZoneID)

        return result
    }
}
