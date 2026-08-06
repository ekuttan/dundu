import Foundation
import UserNotifications
import SwiftData
import DunduKit

/// The Inbox's two notification triggers (spec §9).
///
/// Trigger 2: a garbled item with confidence over 70 due within 24 hours
/// fires immediately, with action buttons so the fix lands without opening
/// the app. Below that bar it queues silently.
///
/// Trigger 3: one daily batch at a configurable time, skipped when empty,
/// never more than one a day no matter how many items wait.
@MainActor
enum InboxNotifier {
    static let repairCategoryID = "DUNDU_REPAIR"
    static let batchIdentifier = "dundu.inbox.daily"
    static let useSuggestedAction = "USE_SUGGESTED"
    static let keepOriginalAction = "KEEP_ORIGINAL"
    static let openAction = "OPEN"

    /// Item IDs already notified, so trigger 2 fires once per item.
    private static let notifiedKey = "repairNotifiedItemIDs"
    /// Daily batch hour, configurable in settings later. Default 9am.
    static var batchHour: Int {
        let stored = UserDefaults.standard.integer(forKey: "inboxBatchHour")
        return stored == 0 ? 9 : stored
    }

    static func registerCategories() {
        let repair = UNNotificationCategory(
            identifier: repairCategoryID,
            actions: [
                UNNotificationAction(identifier: useSuggestedAction, title: "Use suggested title"),
                UNNotificationAction(identifier: keepOriginalAction, title: "Keep original"),
                UNNotificationAction(identifier: openAction, title: "Open", options: [.foreground]),
            ],
            intentIdentifiers: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([repair])
    }

    /// Runs after every sync pass: fires trigger 2 for qualifying items and
    /// keeps the daily batch scheduled or cancelled to match reality.
    static func reconcile(context: ModelContext, now: Date = Date()) async {
        let pending = (try? context.fetch(FetchDescriptor<ReminderItem>(
            predicate: #Predicate { $0.tombstonedAt == nil && $0.reviewStateRaw == "pending" }
        ))) ?? []

        guard !pending.isEmpty else {
            UNUserNotificationCenter.current().removePendingNotificationRequests(
                withIdentifiers: [batchIdentifier]
            )
            return
        }

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
        }
        guard await center.notificationSettings().authorizationStatus == .authorized else { return }

        // Trigger 2: urgent garbled items, once each.
        var notified = Set(UserDefaults.standard.stringArray(forKey: notifiedKey) ?? [])
        let dayAhead = now.addingTimeInterval(24 * 3600)
        for item in pending {
            guard let suggested = item.suggestedTitle,
                  (item.repairConfidence ?? 0) > 70,
                  let due = item.dueDate, due <= dayAhead,
                  !notified.contains(item.id.uuidString)
            else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Did Siri mishear this?"
            content.body = "\u{201C}\(item.title)\u{201D} \u{2192} \u{201C}\(suggested)\u{201D}"
            content.categoryIdentifier = repairCategoryID
            content.userInfo = ["itemID": item.id.uuidString]
            try? await center.add(UNNotificationRequest(
                identifier: "dundu.repair.\(item.id.uuidString)",
                content: content,
                trigger: nil
            ))
            notified.insert(item.id.uuidString)
        }
        UserDefaults.standard.set(Array(notified), forKey: notifiedKey)

        // Trigger 3: the daily nudge, one identifier so it can never stack.
        let content = UNMutableNotificationContent()
        content.title = "Dundu Inbox"
        content.body = pending.count == 1
            ? "1 suggestion is waiting for you."
            : "\(pending.count) suggestions are waiting for you."
        var components = DateComponents()
        components.hour = batchHour
        try? await center.add(UNNotificationRequest(
            identifier: batchIdentifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        ))
    }

    /// Handles the action buttons without opening the app.
    static func handleAction(identifier: String, itemID: String, container: ModelContainer) async {
        let context = ModelContext(container)
        guard let uuid = UUID(uuidString: itemID),
              let item = (try? context.fetch(FetchDescriptor<ReminderItem>()))?
                  .first(where: { $0.id == uuid })
        else { return }

        switch identifier {
        case useSuggestedAction:
            context.acceptRepair(item)
        case keepOriginalAction:
            context.rejectRepair(item)
        default:
            return
        }
        try? context.save()
        await ReminderSyncService.syncNow(context: context)
    }
}
