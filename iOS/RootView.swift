import SwiftUI

/// M0 shell: the four surfaces exist as tabs, Today is a working list backed
/// by SwiftData. The real screens land with M6 (UI) and M15 (Inbox).
struct RootView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max") }
            ListsPlaceholderView()
                .tabItem { Label("Lists", systemImage: "list.bullet") }
            InboxPlaceholderView()
                .tabItem { Label("Inbox", systemImage: "tray") }
            SettingsPlaceholderView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

struct ListsPlaceholderView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Lists arrive with M6",
                systemImage: "list.bullet",
                description: Text("Lists with counts, backed by the local store.")
            )
            .navigationTitle("Lists")
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
            ContentUnavailableView(
                "Settings arrive with M6",
                systemImage: "gearshape",
                description: Text("Accounts, synced lists, profile context, notifications.")
            )
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    RootView()
}
