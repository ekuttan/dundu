import Foundation
import Testing
@testable import DunduKit

@Suite("Google event sync planning")
struct EventSyncPlannerTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func payload(_ title: String, offset: TimeInterval = 0) -> EventWritePayload {
        EventWritePayload(
            title: title,
            startAt: now.addingTimeInterval(3600 + offset),
            endAt: now.addingTimeInterval(5400 + offset),
            timeZoneID: "Asia/Dubai"
        )
    }

    private func local(
        id: UUID = UUID(),
        _ payload: EventWritePayload,
        tombstoned: Bool = false
    ) -> EventSyncPlanner.LocalState {
        EventSyncPlanner.LocalState(
            localID: id, isTombstoned: tombstoned, modifiedAt: now, payload: payload
        )
    }

    private func delta(
        _ eventID: String,
        _ payload: EventWritePayload?,
        cancelled: Bool = false,
        etag: String = "\"etag-1\"",
        updated: Date? = nil
    ) -> EventSyncPlanner.RemoteDelta {
        EventSyncPlanner.RemoteDelta(
            eventID: eventID, etag: etag, updated: updated ?? now,
            cancelled: cancelled, payload: payload, wire: GEvent()
        )
    }

    // MARK: - Delta semantics

    @Test func localOnlyInsertsWithDeterministicID() {
        let item = local(payload("New meeting"))
        let plan = EventSyncPlanner.plan(locals: [item], deltas: [], mappings: [], now: now)
        #expect(plan.inserts.count == 1)
        #expect(plan.inserts.first?.eventID == GoogleEventID.from(item.localID))
        // Same local item always maps to the same id — retries idempotent.
        let again = EventSyncPlanner.plan(locals: [item], deltas: [], mappings: [], now: now)
        #expect(again.inserts.first?.eventID == plan.inserts.first?.eventID)
    }

    @Test func remoteOnlyCreatesLocal() {
        let incoming = delta("g-1", payload("Investor sync"))
        let plan = EventSyncPlanner.plan(locals: [], deltas: [incoming], mappings: [], now: now)
        #expect(plan.localWrites == [.createFromRemote(incoming)])
    }

    @Test func absenceIsNeverDeletion() {
        // A mapped local event with NO delta this round must stay untouched
        // (spec edge 4) — only explicit cancellations delete.
        let item = local(payload("Standing meeting"))
        let plan = EventSyncPlanner.plan(
            locals: [item],
            deltas: [],
            mappings: [.init(localID: item.localID, eventID: "g-1", base: item.payload)],
            now: now
        )
        #expect(plan.isEmpty)
    }

    @Test func cancelledDeltaTombstonesLocal() {
        let item = local(payload("Cancelled meeting"))
        let plan = EventSyncPlanner.plan(
            locals: [item],
            deltas: [delta("g-1", nil, cancelled: true)],
            mappings: [.init(localID: item.localID, eventID: "g-1", base: item.payload)],
            now: now
        )
        #expect(plan.localWrites == [.tombstone(localID: item.localID)])
    }

    @Test func localDirtyWithoutDeltaPatches() {
        let item = local(payload("Renamed locally"))
        let plan = EventSyncPlanner.plan(
            locals: [item],
            deltas: [],
            mappings: [.init(
                localID: item.localID, eventID: "g-1", etag: "\"e\"",
                base: payload("Original name")
            )],
            now: now
        )
        #expect(plan.patches.count == 1)
        #expect(plan.patches.first?.etag == "\"e\"")
        #expect(plan.patches.first?.payload.title == "Renamed locally")
    }

    @Test func remoteDeltaOnCleanLocalPulls() {
        let base = payload("Original")
        let item = local(base)
        let incoming = delta("g-1", payload("Moved by organizer", offset: 1800))
        let plan = EventSyncPlanner.plan(
            locals: [item],
            deltas: [incoming],
            mappings: [.init(localID: item.localID, eventID: "g-1", base: base)],
            now: now
        )
        #expect(plan.localWrites == [.apply(localID: item.localID, payload: incoming.payload!, delta: incoming)])
        #expect(plan.patches.isEmpty)
    }

    @Test func bothChangedMergesFieldLevel() {
        var base = payload("Original")
        base.notes = "agenda"
        var localEdit = base
        localEdit.title = "Local title"
        var remoteEdit = base
        remoteEdit.location = "Room 4"

        let item = local(localEdit)
        let incoming = delta("g-1", remoteEdit)
        let plan = EventSyncPlanner.plan(
            locals: [item],
            deltas: [incoming],
            mappings: [.init(localID: item.localID, eventID: "g-1", base: base)],
            now: now
        )
        // Merged: local title + remote location, flowing both directions.
        #expect(plan.patches.first?.payload.title == "Local title")
        #expect(plan.patches.first?.payload.location == "Room 4")
        if case .apply(_, let merged, _)? = plan.localWrites.first {
            #expect(merged.title == "Local title")
            #expect(merged.location == "Room 4")
        } else {
            Issue.record("Expected a local apply")
        }
    }

    @Test func localTombstoneDeletesRemote() {
        let item = local(payload("Deleted here"), tombstoned: true)
        let plan = EventSyncPlanner.plan(
            locals: [item],
            deltas: [],
            mappings: [.init(localID: item.localID, eventID: "g-1", base: item.payload)],
            now: now
        )
        #expect(plan.deletes.map(\.eventID) == ["g-1"])
    }

    @Test func newestDeltaPerEventWins() {
        let older = delta("g-1", payload("Old title"), updated: now.addingTimeInterval(-100))
        let newer = delta("g-1", payload("New title"), updated: now)
        let plan = EventSyncPlanner.plan(locals: [], deltas: [older, newer], mappings: [], now: now)
        if case .createFromRemote(let winner)? = plan.localWrites.first {
            #expect(winner.payload?.title == "New title")
        } else {
            Issue.record("Expected a create")
        }
    }
}

@Suite("Google event wire format")
struct GoogleEventWireTests {
    @Test func eventIDIsValidBase32Hex() {
        let id = GoogleEventID.from(UUID())
        #expect((5...1024).contains(id.count))
        let allowed = Set("0123456789abcdefghijklmnopqrstuv")
        #expect(id.allSatisfy(allowed.contains))
        // Deterministic.
        let uuid = UUID()
        #expect(GoogleEventID.from(uuid) == GoogleEventID.from(uuid))
        #expect(GoogleEventID.from(UUID()) != GoogleEventID.from(UUID()))
    }

    @Test func timedEventRoundTripsThroughWireFormat() throws {
        let payload = EventWritePayload(
            title: "Standup",
            startAt: Date(timeIntervalSince1970: 1_800_000_000),
            endAt: Date(timeIntervalSince1970: 1_800_001_800),
            timeZoneID: "Asia/Dubai"
        )
        let wire = payload.asGEvent()
        #expect(wire.start?.dateTime != nil)
        #expect(wire.start?.timeZone == "Asia/Dubai")

        var roundTrip = wire
        roundTrip.summary = payload.title
        let back = try #require(EventWritePayload(from: roundTrip))
        #expect(back.startAt == payload.startAt)
        #expect(back.endAt == payload.endAt)
        #expect(!back.isAllDay)
    }

    @Test func allDayEventUsesDateStrings() throws {
        let start = try #require(GDates.parseDay("2026-08-07", timeZoneID: "Asia/Dubai"))
        let payload = EventWritePayload(
            title: "Holiday",
            startAt: start,
            endAt: start.addingTimeInterval(24 * 3600),
            isAllDay: true,
            timeZoneID: "Asia/Dubai"
        )
        let wire = payload.asGEvent()
        #expect(wire.start?.date == "2026-08-07")
        #expect(wire.start?.dateTime == nil)
    }

    @Test func conferenceURLPrefersStructuredData() throws {
        let json = """
        {"id":"g1","status":"confirmed","summary":"Call",
         "start":{"dateTime":"2026-08-07T09:00:00Z"},"end":{"dateTime":"2026-08-07T09:30:00Z"},
         "hangoutLink":"https://legacy.example",
         "conferenceData":{"entryPoints":[
            {"entryPointType":"phone","uri":"tel:+123"},
            {"entryPointType":"video","uri":"https://meet.google.com/abc"}]},
         "attendees":[{"email":"me@x.com","responseStatus":"accepted","self":true}]}
        """
        let event = try JSONDecoder().decode(GEvent.self, from: Data(json.utf8))
        #expect(event.conferenceURL?.absoluteString == "https://meet.google.com/abc")
        #expect(event.attendees?.first?.`self` == true)
        #expect(!event.isCancelled)
    }

    @Test func cancelledStubDecodes() throws {
        let json = """
        {"id":"g2","status":"cancelled","etag":"\\"e\\""}
        """
        let event = try JSONDecoder().decode(GEvent.self, from: Data(json.utf8))
        #expect(event.isCancelled)
        #expect(EventWritePayload(from: event) == nil)
    }
}
