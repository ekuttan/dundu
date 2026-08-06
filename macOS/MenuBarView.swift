import SwiftUI
import SwiftData
import DunduKit

/// The menu bar extra: upcoming items at a glance, quick add, quit.
/// Settings and the main window arrive in later milestones.
struct MenuBarView: View {
    @Environment(\.modelContext) private var context
    @Query(
        filter: #Predicate<ReminderItem> { $0.tombstonedAt == nil && !$0.isCompleted },
        sort: \ReminderItem.sortOrder
    ) private var openReminders: [ReminderItem]

    @State private var quickAddTitle = ""
    /// The concrete due date that will be saved — resolved the moment a
    /// preset is picked, so what you see is exactly what gets stored.
    @State private var quickDueDate: Date?
    @State private var editingDueDate = false
    @State private var accessStatus = EventKitBridge.accessStatus()

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.md) {
            if accessStatus != .fullAccess {
                accessBanner
            }

            VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
            HStack(spacing: Tokens.Spacing.sm) {
                TextField("Quick add…", text: $quickAddTitle)
                    .textFieldStyle(.plain)
                    .onSubmit(addReminder)

                Menu {
                    Button("In 1 hour (\(Self.timeLabel(SnoozeOption.oneHour.resolve())))") {
                        setDue(SnoozeOption.oneHour.resolve())
                    }
                    Button("This evening (\(Self.timeLabel(SnoozeOption.thisEvening.resolve())))") {
                        setDue(SnoozeOption.thisEvening.resolve())
                    }
                    Button("Tomorrow morning (\(Self.timeLabel(SnoozeOption.tomorrowMorning.resolve())))") {
                        setDue(SnoozeOption.tomorrowMorning.resolve())
                    }
                    Divider()
                    Button("Pick date & time…") {
                        setDue(SnoozeOption.oneHour.resolve())
                        editingDueDate = true
                    }
                } label: {
                    Image(systemName: quickDueDate == nil ? "calendar.badge.plus" : "calendar.badge.clock")
                        .foregroundStyle(quickDueDate == nil ? .secondary : Color.accentColor)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Add a due date to the new reminder")
            }

            if let due = quickDueDate {
                HStack(spacing: Tokens.Spacing.sm) {
                    if editingDueDate {
                        // Field style: inline steppers, no popover — popovers
                        // misbehave inside menu bar windows.
                        DatePicker("", selection: Binding(
                            get: { due },
                            set: { quickDueDate = $0 }
                        ))
                        .datePickerStyle(.field)
                        .labelsHidden()
                    } else {
                        Button {
                            editingDueDate = true
                        } label: {
                            Label("Due \(Self.dueLabel(due))", systemImage: "calendar")
                                .font(.caption.bold())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, Tokens.Spacing.sm)
                        .padding(.vertical, 3)
                        .foregroundStyle(Self.dueColor(due))
                        .background(Self.dueColor(due).opacity(0.16), in: Capsule())
                        .help("Edit the due date")
                    }
                    Spacer()
                    Button {
                        quickDueDate = nil
                        editingDueDate = false
                    } label: {
                        Label("Remove", systemImage: "xmark.circle.fill")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Remove the due date — the reminder saves without one")
                }
                .font(.caption)
            }
            }
            .padding(Tokens.Spacing.sm)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: Tokens.Radius.card))

            if openReminders.isEmpty {
                Text("All clear")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, Tokens.Spacing.lg)
            } else {
                ScrollView {
                LazyVStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                ForEach(visibleReminders) { reminder in
                    HStack(spacing: Tokens.Spacing.sm) {
                        Button {
                            context.setCompleted(reminder, true)
                            try? context.save()
                            Task { await ReminderSyncService.syncNow(context: context) }
                        } label: {
                            Image(systemName: "circle")
                        }
                        .buttonStyle(.plain)

                        Text(reminder.title)
                            .lineLimit(1)

                        Spacer()

                        if let due = reminder.dueDate {
                            Text(Formatters.relativeTime(to: due))
                                .font(.caption)
                                .foregroundStyle(due < Date() ? Tokens.Colors.overdue : .secondary)
                        }
                    }
                }
                }
                }
                .frame(maxHeight: 260)
            }

            Divider()

            HStack {
                Spacer()
                Menu {
                    SettingsLink {
                        Text("Settings…")
                    }
                    Divider()
                    Button("Quit Dundu") {
                        NSApplication.shared.terminate(nil)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .padding(Tokens.Spacing.lg)
        .frame(width: 320)
        .task {
            accessStatus = EventKitBridge.accessStatus()
            await ReminderSyncService.syncNow(context: context)
            for await _ in await ReminderSyncService.bridge.observeChanges() {
                try? await Task.sleep(for: ReminderSyncService.changeDebounce)
                await ReminderSyncService.syncNow(context: context)
            }
        }
    }

    // MARK: - Access banner

    /// Sync being off is shown, not hidden — a banner with the fix, never a
    /// wall. The app keeps working standalone either way.
    private var accessBanner: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
            Label("Apple Reminders sync is off", systemImage: "exclamationmark.triangle")
                .font(.caption.bold())
                .foregroundStyle(.orange)
            Button(accessStatus == .notDetermined ? "Allow access" : "Open System Settings") {
                if accessStatus == .notDetermined {
                    Task {
                        _ = try? await ReminderSyncService.bridge.requestFullAccess()
                        accessStatus = EventKitBridge.accessStatus()
                        await ReminderSyncService.syncNow(context: context)
                    }
                } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
                    NSWorkspace.shared.open(url)
                }
            }
            .font(.caption)
        }
        .padding(Tokens.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
    }

    // MARK: - Quick add

    private func addReminder() {
        let title = quickAddTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        do {
            let list = try context.defaultList()
            let item = ReminderItem(title: title, listID: list.id)
            item.sortOrder = (openReminders.last?.sortOrder ?? 0) + 1
            if let due = quickDueDate {
                item.dueDate = due
                item.hasTime = true
            }
            context.insert(item)
            try context.save()
            quickAddTitle = ""
            quickDueDate = nil
            editingDueDate = false
            Task { await ReminderSyncService.syncNow(context: context) }
        } catch {
            assertionFailure("Quick add failed: \(error)")
        }
    }
}

extension MenuBarView {
    /// Due-soonest first, then newest — a just-added item is always visible,
    /// and the whole list scrolls instead of cutting off at five.
    private var visibleReminders: [ReminderItem] {
        openReminders.sorted {
            let a = $0.dueDate ?? .distantFuture
            let b = $1.dueDate ?? .distantFuture
            if a != b { return a < b }
            return $0.createdAt > $1.createdAt
        }
    }

    /// Urgency at a glance: red past, orange today, blue tomorrow, green later.
    static func dueColor(_ date: Date, now: Date = Date()) -> Color {
        if date < now { return Tokens.Colors.overdue }
        if Calendar.current.isDateInToday(date) { return Tokens.Colors.dueSoon }
        if Calendar.current.isDateInTomorrow(date) { return .blue }
        return .green
    }

    private func setDue(_ date: Date) {
        quickDueDate = date
        editingDueDate = false
    }

    /// "6:00 PM"
    static func timeLabel(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// "today 6:00 PM", "tomorrow 9:00 AM", "Sat 9 Aug, 3:00 PM"
    static func dueLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        let time = timeLabel(date)
        if calendar.isDateInToday(date) { return "today \(time)" }
        if calendar.isDateInTomorrow(date) { return "tomorrow \(time)" }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) + ", " + time
    }
}
