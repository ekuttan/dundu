import SwiftUI
import SwiftData
import DunduKit

/// Add/edit sheet for a reminder. Location triggers arrive with M16.
struct ReminderEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(
        filter: #Predicate<ReminderList> { $0.tombstonedAt == nil },
        sort: \ReminderList.sortOrder
    ) private var lists: [ReminderList]

    /// Nil means creating a new reminder.
    let existing: ReminderItem?

    @State private var title = ""
    @State private var notes = ""
    @State private var hasDueDate = false
    @State private var dueDate = Date()
    @State private var hasTime = false
    @State private var priority: ItemPriority = .none
    @State private var listID: UUID?
    @State private var locationAlarm: LocationAlarm?
    @State private var showingLocationPicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    Toggle("Due date", isOn: $hasDueDate.animation())
                    if hasDueDate {
                        DatePicker(
                            "Date",
                            selection: $dueDate,
                            displayedComponents: hasTime ? [.date, .hourAndMinute] : [.date]
                        )
                        Toggle("Time", isOn: $hasTime.animation())
                    }
                }

                Section {
                    if let alarm = locationAlarm {
                        HStack {
                            Label(alarm.title, systemImage: alarm.proximity == .enter
                                ? "arrow.down.right.circle" : "arrow.up.right.circle")
                            Spacer()
                            Text(alarm.proximity == .enter ? "On arrival" : "On leaving")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Button("Remove location alert", role: .destructive) {
                            locationAlarm = nil
                        }
                    } else {
                        Button {
                            showingLocationPicker = true
                        } label: {
                            Label("Add location alert", systemImage: "location")
                        }
                    }
                } footer: {
                    Text("Fired by the system through Apple Reminders — works even when Dundu isn't running.")
                }

                Section {
                    Picker("Priority", selection: $priority) {
                        Text("None").tag(ItemPriority.none)
                        Text("High").tag(ItemPriority.high)
                        Text("Medium").tag(ItemPriority.medium)
                        Text("Low").tag(ItemPriority.low)
                    }
                    Picker("List", selection: $listID) {
                        ForEach(lists) { list in
                            Text(list.title).tag(Optional(list.id))
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? "New Reminder" : "Edit Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: load)
            .sheet(isPresented: $showingLocationPicker) {
                LocationPickerView { alarm in
                    locationAlarm = alarm
                }
            }
        }
    }

    private func load() {
        guard let existing else {
            listID = (try? context.defaultList())?.id
            return
        }
        title = existing.title
        notes = existing.notes ?? ""
        hasDueDate = existing.dueDate != nil
        dueDate = existing.dueDate ?? Date()
        hasTime = existing.hasTime
        priority = existing.priority
        listID = existing.listID
        locationAlarm = existing.locationAlarm
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let item: ReminderItem
        if let existing {
            item = existing
        } else {
            item = ReminderItem(title: trimmed)
            context.insert(item)
        }

        item.title = trimmed
        item.notes = notes.isEmpty ? nil : notes
        item.dueDate = hasDueDate ? dueDate : nil
        item.hasTime = hasDueDate && hasTime
        item.priority = priority
        item.listID = listID ?? (try? context.defaultList())?.id
        item.locationAlarm = locationAlarm
        item.modifiedAt = Date()

        try? context.save()
        dismiss()
        Task { await ReminderSyncService.syncNow(context: context) }
    }
}
