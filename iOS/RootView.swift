import SwiftUI
import DunduKit

/// M0 shell: the four surfaces exist as tabs, Today is a working list backed
/// by SwiftData. The real screens land with M6 (UI) and M15 (Inbox).
struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @State private var showOnboarding = false

    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max") }
            ListsView()
                .tabItem { Label("Lists", systemImage: "list.bullet") }
            InboxPlaceholderView()
                .tabItem { Label("Inbox", systemImage: "tray") }
            SettingsPlaceholderView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .onAppear {
            showOnboarding = !hasOnboarded
        }
        .sheet(isPresented: $showOnboarding, onDismiss: {
            Task { await ReminderSyncService.syncNow(context: context) }
        }) {
            OnboardingView()
        }
        .task {
            // Initial pass, then a debounced pass per EKEventStoreChanged.
            // Echo suppression is structural: our own writes plan to nothing.
            await ReminderSyncService.syncNow(context: context)
            for await _ in await ReminderSyncService.bridge.observeChanges() {
                try? await Task.sleep(for: ReminderSyncService.changeDebounce)
                await ReminderSyncService.syncNow(context: context)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await ReminderSyncService.syncNow(context: context) }
            }
        }
    }
}

struct InboxPlaceholderView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Inbox arrives with M15",
                systemImage: "tray",
                description: Text("Routing questions, repair suggestions, and conflicts land here.")
            )
            .navigationTitle("Inbox")
        }
    }
}

struct SettingsPlaceholderView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Accounts") {
                    NavigationLink {
                        AppleRemindersView()
                    } label: {
                        Label("Apple Reminders", systemImage: "checklist")
                    }
                    Label("Google Calendar — arrives with M9", systemImage: "calendar")
                        .foregroundStyle(.tertiary)
                }
                Section("Intelligence") {
                    Label("Profile context — arrives with M12", systemImage: "brain")
                        .foregroundStyle(.tertiary)
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    RootView()
}
