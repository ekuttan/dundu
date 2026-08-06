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

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.md) {
            TextField("Quick add…", text: $quickAddTitle)
                .textFieldStyle(.roundedBorder)
                .onSubmit(addReminder)

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
            // The Mac has no onboarding screen, so the access ask lives here:
            // first open of the menu bar extra triggers the system dialog.
            if EventKitBridge.accessStatus() == .notDetermined {
                _ = try? await ReminderSyncService.bridge.requestFullAccess()
            }
            await ReminderSyncService.syncNow(context: context)
            for await _ in await ReminderSyncService.bridge.observeChanges() {
                try? await Task.sleep(for: ReminderSyncService.changeDebounce)
                await ReminderSyncService.syncNow(context: context)
            }
        }
    }

    private func addReminder() {
        let title = quickAddTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        do {
            let list = try context.defaultList()
            let item = ReminderItem(title: title, listID: list.id)
            item.sortOrder = (openReminders.last?.sortOrder ?? 0) + 1
            context.insert(item)
            try context.save()
            quickAddTitle = ""
            Task { await ReminderSyncService.syncNow(context: context) }
        } catch {
            assertionFailure("Quick add failed: \(error)")
        }
    }
}
