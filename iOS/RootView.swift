import SwiftUI
import SwiftData
import DunduKit

/// M0 shell: the four surfaces exist as tabs, Today is a working list backed
/// by SwiftData. The real screens land with M6 (UI) and M15 (Inbox).
enum AppTab: Hashable {
    case today, lists, inbox, settings
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @State private var showOnboarding = false
    @State private var selectedTab: AppTab = .today
    @Query(
        filter: #Predicate<ReminderItem> {
            $0.tombstonedAt == nil && $0.reviewStateRaw == "pending"
        }
    ) private var pendingReviews: [ReminderItem]

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayView(inboxCount: pendingReviews.count) {
                selectedTab = .inbox
            }
            .tabItem { Label("Today", systemImage: "sun.max") }
            .tag(AppTab.today)
            ListsView()
                .tabItem { Label("Lists", systemImage: "list.bullet") }
                .tag(AppTab.lists)
            InboxView()
                .tabItem { Label("Inbox", systemImage: "tray") }
                .tag(AppTab.inbox)
                .badge(pendingReviews.count)
            SettingsPlaceholderView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
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
        .task {
            // Inbox notifications reconcile after every sync pass: trigger 2
            // fires for urgent garbles, trigger 3 stays scheduled or drops.
            let syncs = NotificationCenter.default.notifications(
                named: ReminderSyncService.syncDidFinish
            )
            for await _ in syncs {
                await InboxNotifier.reconcile(context: context)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await ReminderSyncService.syncNow(context: context) }
            }
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
                    NavigationLink {
                        ProfileContextView()
                    } label: {
                        Label("Profile context", systemImage: "brain")
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    RootView()
}
