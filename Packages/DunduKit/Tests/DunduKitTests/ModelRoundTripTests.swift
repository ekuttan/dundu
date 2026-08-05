import Foundation
import SwiftData
import Testing
@testable import DunduKit

@Suite("SwiftData model round trips")
@MainActor
struct ModelRoundTripTests {
    private func freshContext() throws -> ModelContext {
        let container = try DunduStore.previewContainer()
        return ModelContext(container)
    }

    @Test func reminderRoundTrip() throws {
        let context = try freshContext()
        let item = ReminderItem(title: "Call the CA about the DIFC filing", priority: .high)
        item.locationAlarm = LocationAlarm(
            title: "Office", latitude: 25.2, longitude: 55.28, proximity: .enter
        )
        item.alarmOffsets = [-3600, 0]
        context.insert(item)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<ReminderItem>())
        #expect(fetched.count == 1)
        let reminder = try #require(fetched.first)
        #expect(reminder.title == "Call the CA about the DIFC filing")
        #expect(reminder.priority == .high)
        #expect(reminder.locationAlarm?.proximity == .enter)
        #expect(reminder.alarmOffsets == [-3600, 0])
        #expect(reminder.origin == .local)
        #expect(!reminder.isTombstoned)
    }

    @Test func eventRoundTrip() throws {
        let context = try freshContext()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let event = CalendarEvent(
            title: "Investor sync",
            startAt: start,
            endAt: start.addingTimeInterval(1800),
            timeZoneID: "Asia/Dubai"
        )
        event.attendees = [AttendeeRecord(email: "joby@example.com", name: "Joby", responseStatus: .accepted)]
        event.conferenceURL = URL(string: "https://meet.google.com/abc-defg-hij")
        context.insert(event)
        try context.save()

        let fetched = try #require(try context.fetch(FetchDescriptor<CalendarEvent>()).first)
        #expect(fetched.timeZoneID == "Asia/Dubai")
        #expect(fetched.attendees.first?.responseStatus == .accepted)
        #expect(fetched.conferenceURL?.host == "meet.google.com")
    }

    @Test func completionMutationBumpsModifiedAt() throws {
        let context = try freshContext()
        let item = ReminderItem(title: "Pick up the car")
        context.insert(item)
        let before = item.modifiedAt

        context.setCompleted(item, true, at: before.addingTimeInterval(60))
        #expect(item.isCompleted)
        #expect(item.completedAt != nil)
        #expect(item.modifiedAt > before)
    }

    @Test func tombstonePurgeAfterThirtyDays() throws {
        let context = try freshContext()
        let now = Date()

        let old = ReminderItem(title: "Old deleted")
        let recent = ReminderItem(title: "Recently deleted")
        context.insert(old)
        context.insert(recent)
        context.tombstone(old, at: now.addingTimeInterval(-31 * 24 * 3600))
        context.tombstone(recent, at: now.addingTimeInterval(-24 * 3600))
        _ = try context.upsertMapping(localID: old.id, bridgeID: .eventkit, externalID: "ext-old")
        try context.save()

        try context.purgeExpiredTombstones(now: now)
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<ReminderItem>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.title == "Recently deleted")
        #expect(try context.fetch(FetchDescriptor<SyncMapping>()).isEmpty)
    }

    @Test func duplicateExternalIDKeepsMostRecentlyModified() throws {
        let context = try freshContext()
        let older = SyncMapping(localID: UUID(), bridgeID: "eventkit", externalID: "dup")
        older.localModifiedAt = Date(timeIntervalSince1970: 1000)
        let newer = SyncMapping(localID: UUID(), bridgeID: "eventkit", externalID: "dup")
        newer.localModifiedAt = Date(timeIntervalSince1970: 2000)
        context.insert(older)
        context.insert(newer)
        try context.save()

        let winner = try context.upsertMapping(localID: UUID(), bridgeID: .eventkit, externalID: "dup")
        try context.save()

        #expect(winner.localModifiedAt == Date(timeIntervalSince1970: 2000))
        #expect(try context.fetch(FetchDescriptor<SyncMapping>()).count == 1)
    }

    @Test func defaultListCreatedOnFirstUse() throws {
        let context = try freshContext()
        let list = try context.defaultList()
        #expect(list.isDefault)

        let again = try context.defaultList()
        #expect(again.id == list.id)
        #expect(try context.fetch(FetchDescriptor<ReminderList>()).count == 1)
    }
}
