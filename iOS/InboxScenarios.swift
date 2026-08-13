import Foundation
import SwiftData
import DunduKit

/// Hand-built Inbox cases, so every shape of question can be seen and tried
/// without waiting for Siri to garble the right name on the right day.
///
/// These are ordinary reminders in the ordinary store — accepting one really
/// renames it and really syncs to Apple Reminders. `clear` removes exactly
/// what was seeded and nothing else.
@MainActor
enum InboxScenarios {
    /// Marks the seeded items so they can be pulled back out again. It
    /// lives in `url` rather than `notes` because notes are shown on every
    /// row, and a test marker under each title is worse than no marker.
    static let marker = URL(string: "dundu-test://scenario")!

    struct Scenario: Identifiable {
        let id = UUID()
        let name: String
        let detail: String
        let build: (UUID?, [ReminderList]) -> ReminderItem
    }

    static let all: [Scenario] = [
        Scenario(
            name: "Garbled name, confident fix",
            detail: "Siri heard a proper noun wrong and the phonetic match is strong."
        ) { listID, _ in
            let item = ReminderItem(
                title: "Call Jobi about the Q3 deck",
                listID: listID,
                dueDate: Date().addingTimeInterval(3 * 3600),
                hasTime: true,
                origin: .siriSuspected
            )
            item.suggestedTitle = "Call Joby about the Q3 deck"
            item.repairConfidence = 91
            item.reviewState = .pending
            item.url = marker
            return item
        },

        Scenario(
            name: "Garbled name, weak fix",
            detail: "A near miss. Low confidence, so it must never apply itself."
        ) { listID, _ in
            let item = ReminderItem(
                title: "Send the deck to Sharuk",
                listID: listID,
                origin: .siriSuspected
            )
            item.suggestedTitle = "Send the deck to Shahrukh"
            item.repairConfidence = 54
            item.reviewState = .pending
            item.url = marker
            return item
        },

        Scenario(
            name: "Garbled and overdue",
            detail: "Past due with a pending repair — this is the case that fires an immediate notification."
        ) { listID, _ in
            let item = ReminderItem(
                title: "Pay the Tejuri invoice",
                listID: listID,
                dueDate: Date().addingTimeInterval(-2 * 3600),
                hasTime: true,
                priority: .high,
                origin: .siriSuspected
            )
            item.suggestedTitle = "Pay the Tejouri invoice"
            item.repairConfidence = 84
            item.reviewState = .pending
            item.url = marker
            return item
        },

        Scenario(
            name: "Routing question",
            detail: "Confident enough to suggest a list, not confident enough to move it silently."
        ) { listID, lists in
            let item = ReminderItem(
                title: "Renew the trade licence",
                listID: listID,
                dueDate: Date().addingTimeInterval(48 * 3600)
            )
            if let target = lists.first(where: { $0.id != listID }) ?? lists.first {
                item.proposedTargetID = target.id.uuidString
            }
            item.routingConfidence = 68
            item.routingReason = "“trade licence” matches the business keywords for this list."
            item.reviewState = .pending
            item.url = marker
            return item
        },

        Scenario(
            name: "Both questions on one item",
            detail: "A repair and a routing suggestion stacked on the same card."
        ) { listID, lists in
            let item = ReminderItem(
                title: "Email Amrita re: DIFC filing",
                listID: listID,
                dueDate: Date().addingTimeInterval(20 * 3600),
                hasTime: true,
                origin: .siriSuspected
            )
            item.suggestedTitle = "Email Amritha re: DIFC filing"
            item.repairConfidence = 77
            if let target = lists.first(where: { $0.id != listID }) ?? lists.first {
                item.proposedTargetID = target.id.uuidString
            }
            item.routingConfidence = 71
            item.routingReason = "“DIFC filing” is a work phrase for this calendar role."
            item.reviewState = .pending
            item.url = marker
            return item
        },

        Scenario(
            name: "Location reminder with a fix",
            detail: "Checks that the card still reads well when the item carries a geofence."
        ) { listID, _ in
            let item = ReminderItem(
                title: "At the office, send Joby the keys",
                listID: listID,
                origin: .siriSuspected
            )
            item.locationAlarm = LocationAlarm(
                title: "Office",
                latitude: 25.2048,
                longitude: 55.2708,
                radius: 150,
                proximity: .enter
            )
            item.suggestedTitle = "At the office, send Jobi the keys"
            item.repairConfidence = 62
            item.reviewState = .pending
            item.url = marker
            return item
        },
    ]

    /// Inserts every scenario. Safe to call twice — the previous batch is
    /// cleared first, so the Inbox never fills with duplicates.
    static func seed(context: ModelContext) {
        clear(context: context)

        let lists = (try? context.fetch(
            FetchDescriptor<ReminderList>(predicate: #Predicate { $0.tombstonedAt == nil })
        )) ?? []
        let defaultID = (try? context.defaultList())?.id

        for scenario in all {
            context.insert(scenario.build(defaultID, lists))
        }
        try? context.save()
    }

    /// Hard-deletes the seeded items rather than tombstoning them: they were
    /// never real, so they have nothing to propagate to Apple Reminders.
    static func clear(context: ModelContext) {
        let seeded = (try? context.fetch(FetchDescriptor<ReminderItem>()))?
            .filter { $0.url == marker } ?? []
        for item in seeded {
            context.delete(item)
        }
        try? context.save()
    }

    static func count(context: ModelContext) -> Int {
        ((try? context.fetch(FetchDescriptor<ReminderItem>()))?
            .filter { $0.url == marker } ?? []).count
    }
}
