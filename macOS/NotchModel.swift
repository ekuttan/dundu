import Foundation
import Observation
import SwiftData
import DunduKit

/// A row the notch can display. Value type so the panel never holds live
/// SwiftData objects.
struct NotchItem: Identifiable, Equatable {
    var id: UUID
    var title: String
    var dueDate: Date?
    var isOverdue: Bool
}

/// What the notch is showing and why. The panel controller owns transitions;
/// views render this.
@Observable
@MainActor
final class NotchModel {
    var uiState: NotchUIState = .hidden
    var items: [NotchItem] = []
    var reduceMotion = false

    var peekTitle: String {
        items.first?.title ?? ""
    }

    var hasContent: Bool { !items.isEmpty }

    /// Reloads due reminders from the store, most overdue first (spec: the
    /// peek shows count and the most urgent title).
    func refresh(context: ModelContext, now: Date = Date()) {
        if ProcessInfo.processInfo.environment["DUNDU_NOTCH_DEMO"] == "1" {
            items = [
                NotchItem(id: UUID(), title: "Call the accountant", dueDate: now.addingTimeInterval(-1800), isOverdue: true),
                NotchItem(id: UUID(), title: "Send the deck", dueDate: now.addingTimeInterval(-300), isOverdue: true),
                NotchItem(id: UUID(), title: "Pick up the car", dueDate: now.addingTimeInterval(3600), isOverdue: false),
            ]
            return
        }

        let due = (try? context.fetch(FetchDescriptor<ReminderItem>(
            predicate: #Predicate { $0.tombstonedAt == nil && !$0.isCompleted }
        ))) ?? []

        items = due
            .filter { ($0.dueDate.map { $0 <= now }) ?? false }
            .sorted { ($0.dueDate ?? .distantPast) < ($1.dueDate ?? .distantPast) }
            .prefix(5)
            .map { NotchItem(id: $0.id, title: $0.title, dueDate: $0.dueDate, isOverdue: true) }
    }
}
