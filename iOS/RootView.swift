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
    /// Capture actions are available in each destination’s native toolbar.
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
        DunduWorkspace(
            selection: $selectedTab,
            inboxCount: pendingReviews.count,
            onAdd: { showingQuickAdd = true },
            onRecord: { showingVoiceCapture = true },
            onSettings: { showingSettings = true }
        )
        .background(Tokens.Colors.ground)
        // Set once, at the root: sheets inherit the environment, so every
        // stock control down to a date picker picks up the accent without
        // each screen restating it.
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
                ScrollView {
                    VStack(alignment: .leading, spacing: Tokens.Spacing.lg) {
                        section("Accounts") {
                            NavigationLink { AppleRemindersView() } label: {
                                SettingsRow(glyph: "checklist", title: "Apple Reminders",
                                            subtitle: "Lists, access, and sync", tint: Tokens.Colors.hueTask)
                            }
                            .buttonStyle(PressableStyle())
                            rowDivider
                            NavigationLink { GoogleAccountsView() } label: {
                                SettingsRow(glyph: "calendar", title: "Google Calendar",
                                            subtitle: "Accounts and calendars", tint: Tokens.Colors.hueMeeting)
                            }
                            .buttonStyle(PressableStyle())
                        }

                        section("Intelligence") {
                            NavigationLink { ProfileContextView() } label: {
                                SettingsRow(glyph: "brain", title: "Profile context",
                                            subtitle: "People, businesses, and aliases", tint: Tokens.Colors.hueTravel)
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
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
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
    var subtitle: String?
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
            VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                Text(title)
                    .font(Tokens.Typo.body)
                    .foregroundStyle(Tokens.Colors.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(Tokens.Typo.caption)
                        .foregroundStyle(Tokens.Colors.quiet)
                }
            }
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
