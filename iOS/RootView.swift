import SwiftUI
import SwiftData
import DunduKit

/// The three places you go. Settings is not one of them — it is a thing you
/// visit occasionally to change something, not a destination you switch
/// between, so it opens as a sheet from the Reminders header instead of
/// spending a quarter of the bar.
enum AppTab: Hashable {
    case today, lists, inbox
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @State private var showOnboarding = false
    @State private var showingQuickAdd = false
    @State private var barChrome = BarChrome()
    /// Voice capture used to live in the Reminders header. It belongs with
    /// the other thing you *do*, in the corner stack, reachable from any tab.
    @State private var showingVoiceCapture = false
    @State private var showingSettings = false
    /// Reminders opens first: it is the list you came to check, and Today is
    /// one tap away when you want the shape of the day instead.
    @State private var selectedTab: AppTab = .lists
    @Query(
        filter: #Predicate<ReminderItem> {
            $0.tombstonedAt == nil && $0.reviewStateRaw == "pending"
        }
    ) private var pendingReviews: [ReminderItem]

    var body: some View {
        // The bar floats over the content rather than sitting under it, so
        // the screens run to the bottom edge and scroll beneath it. Each
        // scrolling screen keeps its last row clear with `clearsFloatingBar`.
        ZStack(alignment: .bottom) {
            // All three stay alive so scroll position and in-progress edits
            // survive a tab switch, the way TabView used to give us for free.
            ZStack {
                tab(.today) {
                    TodayView(inboxCount: pendingReviews.count) { selectedTab = .inbox }
                }
                tab(.lists) {
                    ListsView(barChrome: barChrome,
                              onOpenSettings: { showingSettings = true })
                }
                tab(.inbox) { InboxView(barChrome: barChrome) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            DunduTabBar(
                selection: $selectedTab,
                items: [
                    .init(tab: .lists, glyph: "checklist", title: "Reminders"),
                    .init(tab: .today, glyph: "sun.max", title: "Today"),
                    .init(tab: .inbox, glyph: "tray", title: "Inbox", badge: pendingReviews.count),
                ],
                actions: [
                    .init(glyph: "mic.fill", title: "Record") { showingVoiceCapture = true },
                    .init(glyph: "plus", title: "Add", isPrimary: true) { showingQuickAdd = true },
                ],
                chrome: barChrome
            )
        }
        .background(Tokens.Colors.ground)
        // Set once, at the root: sheets inherit the environment, so every
        // stock control down to a date picker comes out rounded and coral
        // without each screen restating it.
        .fontDesign(.rounded)
        .tint(Tokens.Colors.accent)
        .onAppear {
            showOnboarding = !hasOnboarded
        }
        .sheet(isPresented: $showingQuickAdd) { ReminderEditView(existing: nil) }
        .sheet(isPresented: $showingVoiceCapture) { VoiceCaptureView() }
        .sheet(isPresented: $showingSettings) { SettingsView() }
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

/// Opened as a sheet from the Reminders header rather than living in the
/// bar: you come here to change something and then leave.
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var seedResult: InboxScenarios.Outcome?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScreenHeader(title: "Settings") {
                    CircleButton(glyph: "xmark") { dismiss() }
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: Tokens.Spacing.lg) {
                        section("Accounts") {
                            NavigationLink { AppleRemindersView() } label: {
                                SettingsRow(glyph: "checklist", title: "Apple Reminders",
                                            tint: Tokens.Colors.hueTask)
                            }
                            .buttonStyle(PressableStyle())
                            rowDivider
                            NavigationLink { GoogleAccountsView() } label: {
                                SettingsRow(glyph: "calendar", title: "Google Calendar",
                                            tint: Tokens.Colors.hueMeeting)
                            }
                            .buttonStyle(PressableStyle())
                        }

                        section("Intelligence") {
                            NavigationLink { ProfileContextView() } label: {
                                SettingsRow(glyph: "brain", title: "Profile context",
                                            tint: Tokens.Colors.hueTravel)
                            }
                            .buttonStyle(PressableStyle())
                        }

                        section("Testing") {
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
                    }
                    .padding(.horizontal, Tokens.Layout.gutter)
                    .padding(.bottom, Tokens.Spacing.xxl)
                }
            }
            .background(Tokens.Colors.ground)
            .toolbar(.hidden, for: .navigationBar)
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

    /// A label over one card. Rows live *inside* the card and are told apart
    /// by an inset hairline, the way the system's grouped lists read.
    @ViewBuilder
    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
            Text(title)
                .font(Tokens.Typo.label)
                .foregroundStyle(Tokens.Colors.quiet)
                .padding(.leading, Tokens.Spacing.md)
            VStack(spacing: 0) { content() }
                .cardSurface()
        }
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Tokens.Colors.hairline)
            .frame(height: 1)
            .padding(.leading, 60)
    }
}

/// One line inside a settings card: a tinted glyph in a rounded well, the
/// title, and a chevron. No surface of its own — the card is the surface.
struct SettingsRow: View {
    let glyph: String
    let title: String
    let tint: Color
    var showsChevron = true

    var body: some View {
        HStack(spacing: Tokens.Spacing.md) {
            Image(systemName: glyph)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Tokens.Colors.blockFill(tint))
                }
            Text(title)
                .font(Tokens.Typo.body)
                .foregroundStyle(Tokens.Colors.ink)
            Spacer()
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Tokens.Colors.faint)
            }
        }
        .padding(.horizontal, Tokens.Spacing.lg)
        .padding(.vertical, Tokens.Spacing.md + 2)
        .contentShape(Rectangle())
    }
}

#Preview {
    RootView()
}
