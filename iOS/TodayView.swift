import SwiftUI
import SwiftData
import DunduKit

/// Today: overdue and due-today reminders up top, the near future below.
/// Events interleave here once the Google bridge lands (M11).
struct TodayView: View {
    /// Home surface for the Inbox: a banner with the count, never a modal.
    var inboxCount: Int = 0
    var onOpenInbox: () -> Void = {}

    @Environment(\.modelContext) private var context
    @Query(
        filter: #Predicate<ReminderItem> { $0.tombstonedAt == nil },
        sort: \ReminderItem.dueDate
    ) private var reminders: [ReminderItem]
    @Query(
        filter: #Predicate<CalendarEvent> { $0.tombstonedAt == nil },
        sort: \CalendarEvent.startAt
    ) private var events: [CalendarEvent]

    @State private var quickAddTitle = ""
    @FocusState private var quickAddFocused: Bool
    @State private var editingReminder: ReminderItem?
    @State private var editingEvent: CalendarEvent?
    @State private var showingNewSheet = false
    @State private var showingVoiceCapture = false
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            List {
                if searchText.isEmpty {
                    inboxBanner
                    deniedBanner
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
                ToolbarItem(placement: .primaryAction) {
                    // The prominent mic: say it instead of typing it.
                    Button {
                        showingVoiceCapture = true
                    } label: {
                        Image(systemName: "mic.fill")
                    }
                }
            }
            .sheet(item: $editingReminder) { reminder in
                ReminderEditView(existing: reminder)
            }
            .sheet(isPresented: $showingNewSheet) {
                ReminderEditView(existing: nil)
            }
            .sheet(isPresented: $showingVoiceCapture) {
                VoiceCaptureView()
            }
            .sheet(item: $editingEvent) { event in
                EventEditView(event: event)
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

    private var todayEvents: [CalendarEvent] {
        let calendar = Calendar.current
        return events.filter {
            calendar.isDateInToday($0.startAt) && $0.endAt > Date()
        }
    }

    @ViewBuilder
    private var sections: some View {
        if overdue.isEmpty && dueToday.isEmpty && later.isEmpty
            && completedToday.isEmpty && todayEvents.isEmpty {
            ContentUnavailableView(
                "Nothing here yet",
                systemImage: "checkmark.circle",
                description: Text("Add a reminder above — it syncs straight to Apple Reminders.")
            )
        }
        reminderSection("Overdue", items: overdue)
        if !todayEvents.isEmpty {
            Section("Today") {
                ForEach(todayEvents) { event in
                    EventRow(event: event)
                        .contentShape(Rectangle())
                        .onTapGesture { editingEvent = event }
                }
                ForEach(dueToday) { reminder in
                    ReminderRow(reminder: reminder)
                        .contentShape(Rectangle())
                        .onTapGesture { editingReminder = reminder }
                }
            }
        } else {
            reminderSection("Today", items: dueToday)
        }
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

    // MARK: - Inbox banner

    @ViewBuilder
    private var inboxBanner: some View {
        if inboxCount > 0 {
            Section {
                Button(action: onOpenInbox) {
                    HStack {
                        Label(
                            inboxCount == 1
                                ? "1 suggestion in the Inbox"
                                : "\(inboxCount) suggestions in the Inbox",
                            systemImage: "tray.full"
                        )
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    // MARK: - Denied state

    /// A banner with a settings link, not a wall — the app works standalone
    /// without Apple sync.
    @ViewBuilder
    private var deniedBanner: some View {
        let status = EventKitBridge.accessStatus()
        if status == .denied || status == .restricted || status == .writeOnly {
            Section {
                VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                    Label("Apple Reminders sync is off", systemImage: "exclamationmark.triangle")
                        .font(.subheadline.bold())
                        .foregroundStyle(.orange)
                    Text("Dundu still works on its own. Allow Reminders access to sync both ways.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        Link("Open Settings", destination: url)
                            .font(.caption.bold())
                    }
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

/// A calendar event on Today: time, title, and the Join link when the
/// event carries a conference URL.
struct EventRow: View {
    let event: CalendarEvent

    var body: some View {
        HStack(spacing: Tokens.Spacing.md) {
            VStack(alignment: .leading, spacing: 0) {
                Text(Formatters.clockTime(event.startAt, timeZoneID: event.timeZoneID))
                    .font(.caption.bold().monospacedDigit())
                Text(Formatters.clockTime(event.endAt, timeZoneID: event.timeZoneID))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 48, alignment: .leading)

            RoundedRectangle(cornerRadius: 2)
                .fill(Tokens.Colors.meeting)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                Text(event.title)
                    .lineLimit(1)
                if let location = event.location, !location.isEmpty {
                    Text(location)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let url = event.conferenceURL {
                Link("Join", destination: url)
                    .font(.caption.bold())
                    .buttonStyle(.borderedProminent)
                    .tint(Tokens.Colors.meeting)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
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
