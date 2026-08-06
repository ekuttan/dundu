import SwiftUI
import SwiftData
import DunduKit

/// Today: overdue and due-today reminders up top, the near future below.
/// Events interleave here once the Google bridge lands (M11).
struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query(
        filter: #Predicate<ReminderItem> { $0.tombstonedAt == nil },
        sort: \ReminderItem.dueDate
    ) private var reminders: [ReminderItem]

    @State private var quickAddTitle = ""
    @FocusState private var quickAddFocused: Bool
    @State private var editingReminder: ReminderItem?
    @State private var showingNewSheet = false
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            List {
                if searchText.isEmpty {
                    quickAddRow
                    sections
                } else {
                    searchResults
                }
            }
            .navigationTitle("Today")
            .searchable(text: $searchText, prompt: "Search titles and notes")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $editingReminder) { reminder in
                ReminderEditView(existing: reminder)
            }
            .sheet(isPresented: $showingNewSheet) {
                ReminderEditView(existing: nil)
            }
        }
    }

    // MARK: - Grouping

    private var open: [ReminderItem] {
        reminders.filter { !$0.isCompleted }
    }

    private var overdue: [ReminderItem] {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        return open.filter { ($0.dueDate.map { $0 < startOfToday }) ?? false }
    }

    private var dueToday: [ReminderItem] {
        let calendar = Calendar.current
        return open.filter { ($0.dueDate.map { calendar.isDateInToday($0) }) ?? false }
    }

    private var later: [ReminderItem] {
        let endOfToday = Calendar.current.startOfDay(for: Date()).addingTimeInterval(24 * 3600)
        return open.filter { $0.dueDate == nil || $0.dueDate! >= endOfToday }
    }

    private var completedToday: [ReminderItem] {
        let calendar = Calendar.current
        return reminders.filter {
            $0.isCompleted && ($0.completedAt.map { calendar.isDateInToday($0) } ?? false)
        }
    }

    @ViewBuilder
    private var sections: some View {
        if overdue.isEmpty && dueToday.isEmpty && later.isEmpty && completedToday.isEmpty {
            ContentUnavailableView(
                "Nothing here yet",
                systemImage: "checkmark.circle",
                description: Text("Add a reminder above — it syncs straight to Apple Reminders.")
            )
        }
        reminderSection("Overdue", items: overdue)
        reminderSection("Today", items: dueToday)
        reminderSection("Later", items: later)
        reminderSection("Completed today", items: completedToday)
    }

    @ViewBuilder
    private func reminderSection(_ title: String, items: [ReminderItem]) -> some View {
        if !items.isEmpty {
            Section(title) {
                ForEach(items) { reminder in
                    ReminderRow(reminder: reminder)
                        .contentShape(Rectangle())
                        .onTapGesture { editingReminder = reminder }
                }
                .onDelete { offsets in
                    delete(offsets.map { items[$0] })
                }
            }
        }
    }

    private var searchResults: some View {
        let query = searchText.lowercased()
        let matches = reminders.filter {
            $0.title.lowercased().contains(query)
                || ($0.notes?.lowercased().contains(query) ?? false)
        }
        return Group {
            if matches.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                ForEach(matches) { reminder in
                    ReminderRow(reminder: reminder)
                        .contentShape(Rectangle())
                        .onTapGesture { editingReminder = reminder }
                }
            }
        }
    }

    // MARK: - Quick add

    private var quickAddRow: some View {
        Section {
            HStack(spacing: Tokens.Spacing.sm) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.tint)
                TextField("Add a reminder", text: $quickAddTitle)
                    .focused($quickAddFocused)
                    .onSubmit(quickAdd)
            }
        }
    }

    private func quickAdd() {
        let title = quickAddTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        do {
            let list = try context.defaultList()
            let item = ReminderItem(title: title, listID: list.id)
            item.sortOrder = (reminders.map(\.sortOrder).max() ?? 0) + 1
            context.insert(item)
            try context.save()
            quickAddTitle = ""
            quickAddFocused = true
            Task { await ReminderSyncService.syncNow(context: context) }
        } catch {
            assertionFailure("Quick add failed: \(error)")
        }
    }

    private func delete(_ items: [ReminderItem]) {
        for item in items {
            context.tombstone(item)
        }
        try? context.save()
        Task { await ReminderSyncService.syncNow(context: context) }
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
                Task { await ReminderSyncService.syncNow(context: context) }
            } label: {
                Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(reminder.isCompleted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                HStack(spacing: Tokens.Spacing.xs) {
                    if reminder.priority == .high {
                        Text("!!")
                            .font(.caption.bold())
                            .foregroundStyle(Tokens.Colors.overdue)
                    }
                    Text(reminder.title)
                        .strikethrough(reminder.isCompleted)
                        .foregroundStyle(reminder.isCompleted ? .secondary : .primary)
                }
                if let due = reminder.dueDate {
                    Text(reminder.hasTime ? Formatters.relativeTime(to: due) : due.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(due < Date() && !reminder.isCompleted ? Tokens.Colors.overdue : .secondary)
                }
            }
        }
    }
}
