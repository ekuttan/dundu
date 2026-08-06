import Foundation
import SwiftData
#if canImport(AuthenticationServices)

/// The two-way Google Calendar sync pass (M10). One pass per synced
/// calendar per active account: pull the delta with the stored syncToken,
/// plan against local state and mappings, apply remote writes with etags and
/// idempotent ids, land local writes, store the fresh token.
@MainActor
public enum GoogleSyncService {
    private static let client = GoogleCalendarClient()

    private static var isSyncing = false
    private static var rerunRequested = false

    /// Poll cadence while an app is running (spec §7): 5 minutes.
    public static let pollInterval: Duration = .seconds(300)

    public static let syncDidFinish = Notification.Name("DunduGoogleSyncDidFinish")

    public static func syncNow(context: ModelContext) async {
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
                #if DEBUG
                print("[dundu] google sync failed: \(error)")
                #endif
            }
        } while rerunRequested

        NotificationCenter.default.post(name: syncDidFinish, object: nil)
    }

    // MARK: - The pass

    private static func runPass(context: ModelContext) async throws {
        let accounts = try context.fetch(FetchDescriptor<CalendarAccount>())
            .filter { $0.provider == .google && $0.isActive }
        guard !accounts.isEmpty else { return }

        for account in accounts {
            let accessToken: String
            do {
                accessToken = try await GoogleAccountService.shared.accessToken(for: account.email)
            } catch {
                // Testing mode's 7-day expiry lands here; the account row
                // shows the re-auth ask, sync skips the account until then.
                account.isActive = false
                continue
            }

            let accountID = account.id
            let refs = try context.fetch(FetchDescriptor<CalendarRef>(
                predicate: #Predicate { $0.accountID == accountID }
            )).filter(\.syncEnabled)

            for ref in refs {
                try await syncCalendar(
                    ref: ref, account: account, accessToken: accessToken, context: context
                )
            }
            account.lastSyncAt = Date()
        }

        try context.save()
    }

    private static func syncCalendar(
        ref: CalendarRef,
        account: CalendarAccount,
        accessToken: String,
        context: ModelContext
    ) async throws {
        let now = Date()
        let calendarID = ref.remoteCalendarID

        // 1. Pull the delta; an expired token clears and full-resyncs, and a
        // resync never treats absence as deletion (the planner physically
        // cannot — it only deletes on explicit cancellations).
        let delta: GoogleCalendarClient.EventsDelta
        do {
            delta = try await client.eventChanges(
                calendarID: calendarID,
                syncToken: account.syncTokenStore[calendarID],
                accessToken: accessToken
            )
        } catch GoogleCalendarClient.EventsError.syncTokenExpired {
            account.syncTokenStore[calendarID] = nil
            delta = try await client.eventChanges(
                calendarID: calendarID, syncToken: nil, accessToken: accessToken
            )
        }

        // 2. Local state for this calendar.
        let refID = ref.id
        let events = try context.fetch(FetchDescriptor<CalendarEvent>(
            predicate: #Predicate { $0.calendarID == refID }
        ))
        let eventsByID = Dictionary(events.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let mappings = try context.fetch(FetchDescriptor<EventSyncMapping>(
            predicate: #Predicate { $0.bridgeID == "google" }
        )).filter { mapping in eventsByID[mapping.localID] != nil || delta.events.contains { $0.id == mapping.externalID } }

        let locals = events.map { event in
            EventSyncPlanner.LocalState(
                localID: event.id,
                isTombstoned: event.isTombstoned,
                modifiedAt: event.modifiedAt,
                payload: event.writePayload
            )
        }
        let remoteDeltas = delta.events.compactMap { wire -> EventSyncPlanner.RemoteDelta? in
            guard let id = wire.id else { return nil }
            return EventSyncPlanner.RemoteDelta(
                eventID: id,
                etag: wire.etag,
                updated: wire.updatedDate,
                cancelled: wire.isCancelled,
                payload: EventWritePayload(from: wire),
                wire: wire
            )
        }
        let mappingViews = mappings.map { mapping in
            EventSyncPlanner.MappingView(
                localID: mapping.localID,
                eventID: mapping.externalID,
                etag: mapping.etag,
                base: mapping.baseSnapshot.flatMap { try? JSONDecoder().decode(EventWritePayload.self, from: $0) },
                localModifiedAt: mapping.localModifiedAt
            )
        }
        let mappingsByLocalID = Dictionary(mappings.map { ($0.localID, $0) }, uniquingKeysWith: { a, _ in a })

        let plan = EventSyncPlanner.plan(locals: locals, deltas: remoteDeltas, mappings: mappingViews, now: now)

        // 3. Remote writes.
        for insert in plan.inserts {
            do {
                let created = try await client.insertEvent(
                    calendarID: calendarID, eventID: insert.eventID,
                    payload: insert.payload, accessToken: accessToken
                )
                let mapping = EventSyncMapping(
                    localID: insert.localID, bridgeID: "google",
                    externalID: created.id ?? insert.eventID, etag: created.etag
                )
                mapping.baseSnapshot = try? JSONEncoder().encode(insert.payload)
                mapping.localModifiedAt = insert.localModifiedAt
                mapping.lastSyncedAt = now
                context.insert(mapping)
            } catch {
                continue // Next pass retries; the id keeps it idempotent.
            }
        }

        for patch in plan.patches {
            do {
                let updated = try await client.patchEvent(
                    calendarID: calendarID, eventID: patch.eventID, etag: patch.etag,
                    payload: patch.payload, accessToken: accessToken
                )
                if let mapping = mappingsByLocalID[patch.localID] {
                    mapping.etag = updated.etag
                    mapping.baseSnapshot = try? JSONEncoder().encode(patch.payload)
                    mapping.localModifiedAt = patch.localModifiedAt
                    mapping.lastSyncedAt = now
                }
            } catch GoogleCalendarClient.EventsError.etagConflict {
                // Someone else changed it: leave it; the next delta carries
                // their version and the merge resolves it (spec §7).
                continue
            } catch {
                continue
            }
        }

        for delete in plan.deletes {
            try? await client.deleteEvent(
                calendarID: calendarID, eventID: delete.eventID, accessToken: accessToken
            )
            if let mapping = mappingsByLocalID[delete.localID] {
                context.delete(mapping)
            }
        }

        // 4. Local writes.
        for write in plan.localWrites {
            switch write {
            case .createFromRemote(let delta):
                guard let payload = delta.payload else { continue }
                let event = CalendarEvent(
                    calendarID: ref.id,
                    title: payload.title,
                    startAt: payload.startAt,
                    endAt: payload.endAt,
                    isAllDay: payload.isAllDay,
                    timeZoneID: payload.timeZoneID,
                    origin: .google
                )
                apply(payload, delta: delta, to: event)
                event.modifiedAt = now
                context.insert(event)
                let mapping = EventSyncMapping(
                    localID: event.id, bridgeID: "google",
                    externalID: delta.eventID, etag: delta.etag
                )
                mapping.baseSnapshot = try? JSONEncoder().encode(payload)
                mapping.localModifiedAt = event.modifiedAt
                mapping.remoteModifiedAt = delta.updated
                mapping.lastSyncedAt = now
                context.insert(mapping)

            case .apply(let localID, let payload, let delta):
                guard let event = eventsByID[localID] else { continue }
                apply(payload, delta: delta, to: event)
                event.modifiedAt = now
                if let mapping = mappingsByLocalID[localID] {
                    mapping.etag = delta.etag
                    mapping.baseSnapshot = try? JSONEncoder().encode(payload)
                    mapping.localModifiedAt = event.modifiedAt
                    mapping.remoteModifiedAt = delta.updated
                    mapping.lastSyncedAt = now
                }

            case .tombstone(let localID):
                guard let event = eventsByID[localID] else { continue }
                context.tombstone(event, at: now)
                if let mapping = mappingsByLocalID[localID] {
                    context.delete(mapping)
                }
            }
        }

        // 5. Bookkeeping.
        for refresh in plan.refreshes {
            guard let mapping = mappingsByLocalID[refresh.localID] else { continue }
            mapping.etag = refresh.delta.etag
            mapping.remoteModifiedAt = refresh.delta.updated
            mapping.lastSyncedAt = now
            if mapping.baseSnapshot == nil, let payload = refresh.delta.payload {
                mapping.baseSnapshot = try? JSONEncoder().encode(payload)
            }
        }
        for orphanID in plan.orphanedMappingIDs {
            if let mapping = mappingsByLocalID[orphanID] {
                context.delete(mapping)
            }
        }

        // 6. The fresh token makes the next poll cheap.
        if let token = delta.nextSyncToken {
            account.syncTokenStore[calendarID] = token
        }
    }

    /// Wire fields onto the local event: the merge payload plus the
    /// pull-only extras (attendees, conference link, response status).
    private static func apply(
        _ payload: EventWritePayload,
        delta: EventSyncPlanner.RemoteDelta,
        to event: CalendarEvent
    ) {
        event.title = payload.title
        event.notes = payload.notes
        event.location = payload.location
        event.startAt = payload.startAt
        event.endAt = payload.endAt
        event.isAllDay = payload.isAllDay
        event.timeZoneID = payload.timeZoneID

        let wire = delta.wire
        event.conferenceURL = wire.conferenceURL
        event.recurrenceRules = wire.recurrence ?? []
        event.recurringEventID = wire.recurringEventId
        event.organizerEmail = wire.organizer?.email
        event.attendees = (wire.attendees ?? []).compactMap { attendee in
            guard let email = attendee.email else { return nil }
            return AttendeeRecord(
                email: email,
                name: attendee.displayName,
                responseStatus: AttendeeRecord.ResponseStatus(
                    rawValue: attendee.responseStatus ?? "needsAction"
                ) ?? .needsAction
            )
        }
        if let mine = wire.attendees?.first(where: { $0.`self` == true }),
           let status = mine.responseStatus {
            event.myResponseStatusRaw = status
        }
    }
}

// MARK: - Payload builder

extension CalendarEvent {
    public var writePayload: EventWritePayload {
        EventWritePayload(
            title: title,
            notes: notes,
            location: location,
            startAt: startAt,
            endAt: endAt,
            isAllDay: isAllDay,
            timeZoneID: timeZoneID
        )
    }
}
#endif
