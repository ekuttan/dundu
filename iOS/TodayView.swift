import SwiftUI
import SwiftData
import DunduKit

/// The working proof that the store round-trips: quick add, complete, delete.
/// Interleaved events and the full Today design arrive with M6.
struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query(
        filter: #Predicate<ReminderItem> { $0.tombstonedAt == nil },
        sort: \ReminderItem.sortOrder
    ) private var reminders: [ReminderItem]

    @State private var quickAddTitle = ""
    @FocusState private var quickAddFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: Tokens.Spacing.sm) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.tint)
                        TextField("Add a reminder", text: $quickAddTitle)
                            .focused($quickAddFocused)
                            .onSubmit(addReminder)
                    }
                }

                if reminders.isEmpty {
                    ContentUnavailableView(
                        "Nothing today",
                        systemImage: "checkmark.circle",
                        description: Text("Add a reminder above to prove the store works.")
                    )
                } else {
                    Section {
                        ForEach(reminders) { reminder in
                            ReminderRow(reminder: reminder)
                        }
                        .onDelete(perform: deleteReminders)
                    }
                }
            }
            .navigationTitle("Today")
        }
    }

    private func addReminder() {
        let title = quickAddTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        do {
            let list = try context.defaultList()
            let item = ReminderItem(title: title, listID: list.id)
            item.sortOrder = (reminders.last?.sortOrder ?? 0) + 1
            context.insert(item)
            try context.save()
            quickAddTitle = ""
            quickAddFocused = true
            pushToEventKit()
        } catch {
            assertionFailure("Quick add failed: \(error)")
        }
    }

    private func deleteReminders(at offsets: IndexSet) {
        for index in offsets {
            context.tombstone(reminders[index])
        }
        try? context.save()
        pushToEventKit()
    }

    private func pushToEventKit() {
        Task { try? await EventKitPushService.pushPending(context: context) }
    }
}

struct ReminderRow: View {
    @Environment(\.modelContext) private var context
    let reminder: ReminderItem

    var body: some View {
        HStack(spacing: Tokens.Spacing.md) {
            Button {
                context.setCompleted(reminder, !reminder.isCompleted)
                try? context.save()
                Task { try? await EventKitPushService.pushPending(context: context) }
            } label: {
                Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(reminder.isCompleted ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                Text(reminder.title)
                    .strikethrough(reminder.isCompleted)
                    .foregroundStyle(reminder.isCompleted ? .secondary : .primary)
                if let due = reminder.dueDate {
                    Text(Formatters.relativeTime(to: due))
                        .font(.caption)
                        .foregroundStyle(due < Date() ? Tokens.Colors.overdue : .secondary)
                }
            }
        }
    }
}
