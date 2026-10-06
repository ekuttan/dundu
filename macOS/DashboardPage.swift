import SwiftUI
import DunduKit

/// The landing page: one card per thing the panel knows about, each a door
/// into the page that owns it.
struct DashboardPage: View {
    let model: NotchModel
    @Bindable var agents: AgentActivityModel
    var watcher = AgentSessionWatcher.shared
    @Bindable var focus: FocusModel
    @Bindable var system = SystemStats.shared
    let open: (NotchPage) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: NP.gridGap) {
            header

            HStack(spacing: NP.gridGap) {
                tasksCard
                agendaCard
                systemCard
            }
            HStack(spacing: NP.gridGap) {
                codingCard
                focusCard
                inboxCard
            }
        }
        .onAppear { system.subscribe() }
        .onDisappear { system.unsubscribe() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.greeting())
                    .font(NP.F.greeting)
                    .foregroundStyle(NP.C.text)
                Text(Self.today())
                    .font(NP.F.chip)
                    .foregroundStyle(NP.C.dim)
            }
            Spacer()
            HStack(spacing: 6) {
                if model.overdueCount > 0 {
                    NPStatusChip(text: "\(model.overdueCount) due", tint: NP.C.bad)
                }
                if let live = liveSession {
                    NPStatusChip(
                        text: live.state == .waiting ? "agent needs you" : "agent working",
                        tint: live.state == .waiting ? NP.C.warn : NP.C.good
                    )
                }
            }
            .padding(.top, 6)
        }
        .frame(height: 54)
    }

    private var liveSession: AgentSession? {
        watcher.sessions.first { $0.state == .waiting } ?? watcher.sessions.first
    }

    /// Local time of day, not a stored preference — the panel is only ever
    /// looked at on the Mac it is running on.
    static func greeting(for date: Date = Date(), calendar: Calendar = .current) -> String {
        switch calendar.component(.hour, from: date) {
        case 0..<5: "Still up"
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        case 17..<22: "Good evening"
        default: "Good night"
        }
    }

    static func today(_ date: Date = Date()) -> String {
        date.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    // MARK: - Cards

    private var tasksCard: some View {
        Tap({ open(.tasks) }) {
            NPStatCard(
                label: "Tasks",
                icon: "checklist",
                value: "\(model.openCount)",
                caption: model.items.first?.title ?? "Nothing due",
                valueTint: model.overdueCount > 0 ? NP.C.bad : NP.C.text,
                trailing: AnyView(
                    Text(model.overdueCount > 0 ? "\(model.overdueCount) overdue" : "clear")
                        .font(NP.F.caption)
                        .foregroundStyle(model.overdueCount > 0 ? NP.C.bad : NP.C.good)
                )
            )
        }
    }

    private var agendaCard: some View {
        let next = model.agenda.first { ($0.endDate ?? .distantPast) > Date() }
        return Tap({ open(.calendar) }) {
            NPStatCard(
                label: "Next up",
                icon: "calendar",
                value: next.map { Formatters.clockTime($0.dueDate ?? Date()) } ?? "—",
                caption: next?.title ?? "Nothing left today",
                valueTint: next?.isInProgress() == true ? NP.C.good : NP.C.text,
                trailing: next?.isInProgress() == true
                    ? AnyView(Text("now").font(NP.F.caption).foregroundStyle(NP.C.good))
                    : nil
            )
        }
    }

    private var systemCard: some View {
        NPCard {
            VStack(alignment: .leading, spacing: 0) {
                NPLabel("System", icon: "gauge.with.dots.needle.33percent")
                Spacer(minLength: 4)
                HStack(spacing: 0) {
                    NPRing(
                        fraction: system.cpu,
                        label: "\(Int(system.cpu * 100))%",
                        caption: "CPU",
                        tint: system.cpu > 0.8 ? NP.C.bad : NP.C.info
                    )
                    .frame(maxWidth: .infinity)
                    NPRing(
                        fraction: system.memory,
                        label: "\(Int(system.memory * 100))%",
                        caption: "RAM",
                        tint: system.memory > 0.85 ? NP.C.warn : NP.C.info
                    )
                    .frame(maxWidth: .infinity)
                    if let battery = system.battery {
                        NPRing(
                            fraction: battery,
                            label: "\(Int(battery * 100))%",
                            caption: system.isCharging ? "CHG" : "BAT",
                            tint: battery < 0.2 && !system.isCharging ? NP.C.bad : NP.C.good
                        )
                        .frame(maxWidth: .infinity)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var codingCard: some View {
        Tap({ open(.coding) }) {
            NPStatCard(
                label: "Coding",
                icon: "chevron.left.forwardslash.chevron.right",
                value: agents.summary.map { CodingPage.compact($0.billableTokens) } ?? "—",
                caption: codingCaption,
                trailing: agents.summary.map { summary in
                    AnyView(
                        Text("\(summary.currentStreak)d streak")
                            .font(NP.F.caption)
                            .foregroundStyle(NP.C.ember)
                    )
                }
            )
        }
    }

    private var codingCaption: String {
        if let live = watcher.sessions.first {
            return "\(live.task ?? live.projectName ?? "Session") · \(CodingPage.stateLabel(live.state))"
        }
        if agents.summary != nil { return "tokens used" }
        return agents.needsAccess.isEmpty ? "No activity found" : "Not connected"
    }

    private var focusCard: some View {
        Tap({ open(.focus) }) {
            NPStatCard(
                label: "Focus",
                icon: "timer",
                value: focus.pomodoro.isRunning
                    ? FocusModel.clock(focus.pomodoro.remaining)
                    : FocusModel.clock(focus.pomodoro.remaining),
                caption: focus.pomodoro.isRunning
                    ? (focus.pomodoro.isBreak ? "Break running" : "Sprint running")
                    : "Paused · tap to start",
                valueTint: focus.pomodoro.isRunning ? NP.C.good : NP.C.text
            )
        }
    }

    private var inboxCard: some View {
        Tap({ open(.inbox) }) {
            NPStatCard(
                label: "Inbox",
                icon: "tray",
                value: "\(model.inboxCount)",
                caption: model.inboxCount == 0 ? "Nothing to review" : "waiting on you",
                valueTint: model.inboxCount > 0 ? NP.C.warn : NP.C.text,
                trailing: AnyView(
                    Text("\(model.doneToday) done today")
                        .font(NP.F.caption)
                        .foregroundStyle(NP.C.faint)
                )
            )
        }
    }
}

/// A whole card as a button, without the button chrome. Hover lifts it very
/// slightly so the cards read as targets without needing an affordance.
private struct Tap<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: Content

    @State private var hovering = false

    init(_ action: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.action = action
        self.content = content()
    }

    var body: some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: NP.R.card, style: .continuous)
                    .strokeBorder(hovering ? NP.C.strokeStrong : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: NP.R.card, style: .continuous))
            .onTapGesture(perform: action)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
