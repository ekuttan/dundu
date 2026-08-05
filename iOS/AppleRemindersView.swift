import SwiftUI
import DunduKit

/// M1: read-only browser over Apple Reminders. Proves the permission flow and
/// that external identifiers behave. Replaced by real sync in M2/M3.
struct AppleRemindersView: View {
    @State private var bridge = EventKitBridge()
    @State private var status = EventKitBridge.accessStatus()
    @State private var lists: [EKListSnapshot] = []
    @State private var reminders: [EKReminderSnapshot] = []
    @State private var isLoading = false
    @State private var loadError: String?

    var body: some View {
        List {
            switch status {
            case .notDetermined:
                Section {
                    Button("Allow access to Apple Reminders") {
                        Task { await requestAccess() }
                    }
                } footer: {
                    Text("Dundu syncs two ways with Apple Reminders. Without access it works standalone.")
                }

            case .denied, .restricted, .writeOnly:
                Section {
                    Label("Access to Reminders is off", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        Link("Open Settings", destination: url)
                    }
                } footer: {
                    Text("Dundu needs full access to sync. Everything else keeps working without it.")
                }

            case .fullAccess:
                if let loadError {
                    Section {
                        Label(loadError, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
                ForEach(lists) { list in
                    Section {
                        let items = reminders.filter { $0.listID == list.id }
                        if items.isEmpty {
                            Text("Empty")
                                .foregroundStyle(.tertiary)
                        }
                        ForEach(items, id: \.localIdentifier) { reminder in
                            VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                                HStack {
                                    Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(.secondary)
                                    Text(reminder.title)
                                        .strikethrough(reminder.isCompleted)
                                }
                                if let due = reminder.dueDate {
                                    Text(Formatters.relativeTime(to: due))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(reminder.externalID)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                        }
                    } header: {
                        HStack {
                            Text(list.title)
                            if list.isGoogleBacked {
                                Text("Google — excluded from sync")
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Apple Reminders")
        .overlay {
            if isLoading { ProgressView() }
        }
        .task { await loadIfAuthorized() }
        .refreshable { await loadIfAuthorized() }
    }

    private func requestAccess() async {
        do {
            _ = try await bridge.requestFullAccess()
        } catch {
            loadError = error.localizedDescription
        }
        status = EventKitBridge.accessStatus()
        await loadIfAuthorized()
    }

    private func loadIfAuthorized() async {
        status = EventKitBridge.accessStatus()
        guard status == .fullAccess else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            lists = await bridge.fetchLists()
            reminders = try await bridge.fetchReminders()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}
