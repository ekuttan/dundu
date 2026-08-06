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
    @State private var quickDue: QuickDue = .none
    @State private var customDueDate = Date()
    @State private var accessStatus = EventKitBridge.accessStatus()

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.md) {
            if accessStatus != .fullAccess {
                accessBanner
            }

            HStack(spacing: Tokens.Spacing.sm) {
                TextField("Quick add…", text: $quickAddTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addReminder)

                Menu {
                    ForEach(QuickDue.allCases) { option in
                        Button(option.rawValue) { quickDue = option }
                    }
                } label: {
                    Image(systemName: quickDue == .none ? "calendar.badge.plus" : "calendar.badge.clock")
                        .foregroundStyle(quickDue == .none ? .secondary : Color.accentColor)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            if quickDue != .none {
                HStack {
                    if quickDue == .custom {
                        DatePicker("Due", selection: $customDueDate)
                            .datePickerStyle(.compact)
                            .font(.caption)
                    } else {
                        Text("Due \(quickDue.rawValue.lowercased())")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Clear") { quickDue = .none }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if openReminders.isEmpty {
                Text("All clear")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, Tokens.Spacing.lg)
            } else {
                ForEach(openReminders.prefix(5)) { reminder in
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

            Divider()

            HStack {
                SettingsLink {
                    Text("Settings…")
                }
                Spacer()
                Button("Quit Dundu") {
                    NSApplication.shared.terminate(nil)
                }
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
            if let due = quickDue.resolve(customDate: customDueDate) {
                item.dueDate = due
                item.hasTime = true
            }
            context.insert(item)
            try context.save()
            quickAddTitle = ""
            quickDue = .none
            Task { await ReminderSyncService.syncNow(context: context) }
        } catch {
            assertionFailure("Quick add failed: \(error)")
        }
    }
}

/// Due-date presets for the menu bar quick add. Date maths resolves against
/// the actual clock, reusing the snooze arithmetic.
enum QuickDue: String, CaseIterable, Identifiable {
    case none = "No due date"
    case oneHour = "In 1 hour"
    case evening = "This evening"
    case tomorrow = "Tomorrow morning"
    case custom = "Pick date & time"

    var id: String { rawValue }

    func resolve(customDate: Date, now: Date = Date()) -> Date? {
        switch self {
        case .none: nil
        case .oneHour: SnoozeOption.oneHour.resolve(from: now)
        case .evening: SnoozeOption.thisEvening.resolve(from: now)
        case .tomorrow: SnoozeOption.tomorrowMorning.resolve(from: now)
        case .custom: customDate
        }
    }
}
