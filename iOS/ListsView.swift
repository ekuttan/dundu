import SwiftUI
import SwiftData
import DunduKit

/// Lists with open counts; tap through to the list's reminders.
struct ListsView: View {
    @Query(
        filter: #Predicate<ReminderList> { $0.tombstonedAt == nil },
        sort: \ReminderList.sortOrder
    ) private var lists: [ReminderList]
    @Query(
        filter: #Predicate<ReminderItem> { $0.tombstonedAt == nil && !$0.isCompleted }
    ) private var openReminders: [ReminderItem]

    var body: some View {
        NavigationStack {
            List {
                if lists.isEmpty {
                    ContentUnavailableView(
                        "No lists yet",
                        systemImage: "list.bullet",
                        description: Text("Lists appear after the first sync with Apple Reminders.")
                    )
                }
                ForEach(lists) { list in
                    NavigationLink {
                        ListDetailView(list: list)
                    } label: {
                        HStack {
                            Circle()
                                .fill(Color(hex: list.colorHex) ?? .accentColor)
                                .frame(width: 10, height: 10)
                            Text(list.title)
                            if list.isDefault {
                                Text("Default")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.quaternary, in: Capsule())
                            }
                            Spacer()
                            Text("\(count(for: list))")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
            .navigationTitle("Lists")
        }
    }

    private func count(for list: ReminderList) -> Int {
        openReminders.filter { $0.listID == list.id }.count
    }
}

struct ListDetailView: View {
    @Environment(\.modelContext) private var context
    let list: ReminderList

    @Query private var reminders: [ReminderItem]
    @State private var editingReminder: ReminderItem?

    init(list: ReminderList) {
        self.list = list
        let listID = list.id
        _reminders = Query(
            filter: #Predicate<ReminderItem> { $0.tombstonedAt == nil && $0.listID == listID },
            sort: \ReminderItem.sortOrder
        )
    }

    var body: some View {
        List {
            ForEach(reminders.filter { !$0.isCompleted }) { reminder in
                ReminderRow(reminder: reminder)
                    .contentShape(Rectangle())
                    .onTapGesture { editingReminder = reminder }
            }
            .onDelete { offsets in
                let open = reminders.filter { !$0.isCompleted }
                for index in offsets {
                    context.tombstone(open[index])
                }
                try? context.save()
                Task { await ReminderSyncService.syncNow(context: context) }
            }

            let done = reminders.filter(\.isCompleted)
            if !done.isEmpty {
                Section("Completed") {
                    ForEach(done) { reminder in
                        ReminderRow(reminder: reminder)
                    }
                }
            }
        }
        .navigationTitle(list.title)
        .sheet(item: $editingReminder) { reminder in
            ReminderEditView(existing: reminder)
        }
    }
}

extension Color {
    /// "#RRGGBB" convenience for list colors.
    init?(hex: String) {
        var value: UInt64 = 0
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, Scanner(string: cleaned).scanHexInt64(&value) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
