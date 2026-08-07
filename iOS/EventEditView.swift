import SwiftUI
import SwiftData
import DunduKit

/// Edit sheet for a calendar event. Writes ride the next Google pass as an
/// If-Match patch. v1 rule: this edits single instances only — series edits
/// belong in Google Calendar (spec §7).
struct EventEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var calendarRefs: [CalendarRef]

    let event: CalendarEvent

    @State private var title = ""
    @State private var location = ""
    @State private var notes = ""
    @State private var startAt = Date()
    @State private var endAt = Date()
    @State private var showingDeleteConfirm = false

    private var calendarRef: CalendarRef? {
        calendarRefs.first { $0.id == event.calendarID }
    }

    private var isWritable: Bool {
        calendarRef?.isWritable ?? false
    }

    var body: some View {
        NavigationStack {
            Form {
                if !isWritable {
                    Section {
                        Label("Read-only calendar — changes won't sync", systemImage: "lock")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    TextField("Title", text: $title)
                    TextField("Location", text: $location)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    if event.isAllDay {
                        DatePicker("Starts", selection: $startAt, displayedComponents: [.date])
                        DatePicker("Ends", selection: $endAt, displayedComponents: [.date])
                    } else {
                        DatePicker("Starts", selection: $startAt)
                        DatePicker("Ends", selection: $endAt)
                    }
                } footer: {
                    if event.recurringEventID != nil {
                        Text("This is one occurrence of a repeating event. Only this occurrence changes; edit the series in Google Calendar.")
                    }
                }

                if !event.attendees.isEmpty {
                    Section("Attendees") {
                        ForEach(event.attendees, id: \.email) { attendee in
                            HStack {
                                Text(attendee.name ?? attendee.email)
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: statusIcon(attendee.responseStatus))
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        }
                    }
                }

                if let url = event.conferenceURL {
                    Section {
                        Link(destination: url) {
                            Label("Join meeting", systemImage: "video")
                        }
                    }
                }

                if isWritable {
                    Section {
                        Button("Delete event", role: .destructive) {
                            showingDeleteConfirm = true
                        }
                    }
                }
            }
            .navigationTitle("Edit Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isWritable || title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: load)
            .confirmationDialog(
                "Delete this event? It will be removed from Google Calendar too.",
                isPresented: $showingDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { deleteEvent() }
            }
        }
    }

    private func statusIcon(_ status: AttendeeRecord.ResponseStatus) -> String {
        switch status {
        case .accepted: "checkmark.circle.fill"
        case .declined: "xmark.circle"
        case .tentative: "questionmark.circle"
        case .needsAction: "circle"
        }
    }

    private func load() {
        title = event.title
        location = event.location ?? ""
        notes = event.notes ?? ""
        startAt = event.startAt
        endAt = event.endAt
    }

    private func save() {
        event.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        event.location = location.isEmpty ? nil : location
        event.notes = notes.isEmpty ? nil : notes
        event.startAt = startAt
        event.endAt = max(endAt, startAt.addingTimeInterval(60))
        event.modifiedAt = Date()
        try? context.save()
        dismiss()
        Task { await GoogleSyncService.syncNow(context: context) }
    }

    private func deleteEvent() {
        context.tombstone(event)
        try? context.save()
        dismiss()
        Task { await GoogleSyncService.syncNow(context: context) }
    }
}
