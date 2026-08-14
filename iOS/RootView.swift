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
    @State private var showingQuickAdd = false
    /// Reminders opens first: it is the list you came to check, and Today is
    /// one tap away when you want the shape of the day instead.
    @State private var selectedTab: AppTab = .lists
    @Query(
        filter: #Predicate<ReminderItem> {
            $0.tombstonedAt == nil && $0.reviewStateRaw == "pending"
        }
    ) private var pendingReviews: [ReminderItem]

    var body: some View {
        VStack(spacing: 0) {
            // All four stay alive so scroll position and in-progress edits
            // survive a tab switch, the way TabView used to give us for free.
            ZStack {
                tab(.today) {
                    TodayView(inboxCount: pendingReviews.count) { selectedTab = .inbox }
                }
                tab(.lists) { ListsView() }
                tab(.inbox) { InboxView() }
                tab(.settings) { SettingsView() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            DunduTabBar(
                selection: $selectedTab,
                items: [
                    .init(tab: .lists, glyph: "checklist", title: "Reminders"),
                    .init(tab: .today, glyph: "sun.max", title: "Today"),
                    .init(tab: .inbox, glyph: "tray", title: "Inbox", badge: pendingReviews.count),
                    .init(tab: .settings, glyph: "gearshape", title: "Settings"),
                ],
                onCentre: { showingQuickAdd = true }
            )
        }
        .background(Tokens.Colors.paper)
        // Set once, at the root: sheets inherit the environment, so every
        // stock control down to a date picker comes out rounded and coral
        // without each screen restating it.
        .fontDesign(.rounded)
        .tint(Tokens.Colors.accent)
        .onAppear {
            showOnboarding = !hasOnboarded
        }
        .sheet(isPresented: $showingQuickAdd) { ReminderEditView(existing: nil) }
        .sheet(isPresented: $showOnboarding, onDismiss: {
            Task { await ReminderSyncService.syncNow(context: context) }
        }) {
            OnboardingView()
        }
        .task {
            // Initial pass, then a debounced pass per EKEventStoreChanged.
            // Echo suppression is structural: our own writes plan to nothing.
            await ReminderSyncService.syncNow(context: context)
            await GoogleSyncService.syncNow(context: context)
            for await _ in await ReminderSyncService.bridge.observeChanges() {
                try? await Task.sleep(for: ReminderSyncService.changeDebounce)
                await ReminderSyncService.syncNow(context: context)
            }
        }
        .task {
            // Google has no push without a webhook, so poll while running.
            while !Task.isCancelled {
                try? await Task.sleep(for: GoogleSyncService.pollInterval)
                await GoogleSyncService.syncNow(context: context)
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
                Task {
                    await ReminderSyncService.syncNow(context: context)
                    await GoogleSyncService.syncNow(context: context)
                }
            }
        }
    }

    /// Keeps every tab mounted, showing only the selected one. Hidden tabs
    /// stop taking hits so their buttons can't be reached through the stack.
    @ViewBuilder
    private func tab<Content: View>(
        _ value: AppTab,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .opacity(selectedTab == value ? 1 : 0)
            .allowsHitTesting(selectedTab == value)
            .accessibilityHidden(selectedTab != value)
    }
}

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @State private var seedResult: InboxScenarios.Outcome?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                    sectionLabel("Accounts")
                    NavigationLink { AppleRemindersView() } label: {
                        SettingsRow(glyph: "checklist", title: "Apple Reminders",
                                    tint: Tokens.Colors.hueTask)
                    }
                    .buttonStyle(PressableStyle())
                    NavigationLink { GoogleAccountsView() } label: {
                        SettingsRow(glyph: "calendar", title: "Google Calendar",
                                    tint: Tokens.Colors.hueMeeting)
                    }
                    .buttonStyle(PressableStyle())

                    sectionLabel("Intelligence")
                    NavigationLink { ProfileContextView() } label: {
                        SettingsRow(glyph: "brain", title: "Profile context",
                                    tint: Tokens.Colors.hueTravel)
                    }
                    .buttonStyle(PressableStyle())

                    sectionLabel("Testing")
                    Menu {
                        Button("Load Inbox test cases", systemImage: "flask") {
                            seedResult = InboxScenarios.seed(context: context)
                        }
                        Button("Remove test cases", systemImage: "trash", role: .destructive) {
                            seedResult = InboxScenarios.clear(context: context)
                        }
                    } label: {
                        SettingsRow(glyph: "flask", title: "Inbox test cases",
                                    tint: Tokens.Colors.hueUrgent, showsChevron: true)
                    }
                    .buttonStyle(PressableStyle())
                }
                .padding(.horizontal, Tokens.Spacing.xl)
                .padding(.vertical, Tokens.Spacing.lg)
            }
            .background(Tokens.Colors.paper)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            // The seeder used to swallow its own failures behind `try?`, so
            // "nothing happened" and "it broke" looked identical.
            .alert(
                seedResult?.title ?? "",
                isPresented: Binding(get: { seedResult != nil },
                                     set: { if !$0 { seedResult = nil } })
            ) {
                Button("OK") { seedResult = nil }
            } message: {
                Text(seedResult?.message ?? "")
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(Tokens.Typo.label)
            .foregroundStyle(Tokens.Colors.quiet)
            .padding(.top, Tokens.Spacing.lg)
            .padding(.leading, Tokens.Spacing.xs)
    }
}

struct SettingsRow: View {
    let glyph: String
    let title: String
    let tint: Color
    var showsChevron = true

    var body: some View {
        HStack(spacing: Tokens.Spacing.md) {
            Image(systemName: glyph)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Tokens.Colors.blockFill(tint)))
            Text(title)
                .font(Tokens.Typo.body)
                .foregroundStyle(Tokens.Colors.ink)
            Spacer()
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Tokens.Colors.hairline)
            }
        }
        .padding(.horizontal, Tokens.Spacing.lg)
        .padding(.vertical, Tokens.Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous)
                .fill(Tokens.Colors.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous)
                        .stroke(Tokens.Colors.hairline, lineWidth: 1)
                }
        }
    }
}

#Preview {
    RootView()
}
