import SwiftUI
import SwiftData
import DunduKit

/// The SwiftUI face of the notch panel. Renders whichever state the model is
/// in; the AppKit controller owns geometry, hover, and hit testing.
///
/// Expanded, it is a dark HUD with a floating dock: the panel is the surface
/// you read and the dock is the surface you aim at, and keeping them as two
/// shapes means switching pages never moves the controls.
struct NotchView: View {
    let model: NotchModel
    let geometry: NotchGeometry
    let onComplete: (NotchItem) -> Void
    let onUndo: (NotchItem) -> Void
    let onSnooze: (NotchItem, SnoozeOption) -> Void
    let onQuickAdd: (String) -> Void
    let onQuickAddFocus: (Bool) -> Void
    let onOpenSettings: () -> Void
    let onResolveInbox: (NotchItem, Bool) -> Void

    @State private var agents = AgentActivityModel()
    private let focus = FocusModel.shared
    var watcher = AgentSessionWatcher.shared

    private var animation: Animation {
        model.reduceMotion ? Tokens.Anim.reduceMotionFallback : Tokens.Anim.notchSpring
    }

    /// Drop-in from the notch with a touch of scale — reads as the notch
    /// growing rather than a sheet sliding.
    private var appearTransition: AnyTransition {
        model.reduceMotion
            ? .opacity
            : .move(edge: .top)
                .combined(with: .opacity)
                .combined(with: .scale(scale: 0.97, anchor: .top))
    }

    var body: some View {
        VStack(spacing: 0) {
            switch model.uiState {
            case .hidden:
                Color.clear
                    .frame(height: geometry.notchRect.height)

            case .peek:
                peekPill

            case .expanded:
                expanded
            }
            Spacer(minLength: 0)
        }
        .frame(width: NotchGeometry.expandedSize.width, alignment: .top)
        .animation(animation, value: model.uiState)
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Peek

    /// What drops out of the notch unprompted. One line, one urgency, no
    /// controls: it has to be readable without being aimed at.
    private var peekPill: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(peekTint)
                .frame(width: 6, height: 6)
            Text("\(model.activeCount)")
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .foregroundStyle(NP.C.text)
            Text(model.peekTitle)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(NP.C.dim)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 12)
        .frame(
            width: min(geometry.notchRect.width + 60, NotchGeometry.expandedSize.width),
            height: geometry.notchRect.height + NotchGeometry.peekDrop,
            alignment: .bottom
        )
        .padding(.bottom, 7)
        .background(
            UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 16)
                .fill(.black)
        )
        .transition(appearTransition)
    }

    private var peekTint: Color {
        if watcher.sessions.contains(where: { $0.state == .waiting }) { return NP.C.warn }
        return model.items.contains(where: \.isOverdue) ? NP.C.bad : NP.C.info
    }

    // MARK: - Expanded

    private var expanded: some View {
        VStack(spacing: NotchDock.gap) {
            VStack(alignment: .leading, spacing: 0) {
                // The physical notch eats this strip; nothing may be drawn
                // under it.
                Color.clear.frame(height: geometry.notchRect.height)
                page
                    .padding(.horizontal, NP.gutter)
                    .padding(.top, 14)
                    .padding(.bottom, NP.gutter)
            }
            .frame(
                width: NotchGeometry.expandedSize.width,
                height: model.panelHeight + geometry.notchRect.height,
                alignment: .top
            )
            .background(
                UnevenRoundedRectangle(
                    bottomLeadingRadius: NP.R.panel, bottomTrailingRadius: NP.R.panel
                )
                .fill(NP.C.panel)
            )

            NotchDock(
                page: Binding(
                    get: { model.page },
                    set: { next in withAnimation(Tokens.Anim.content) { model.page = next } }
                ),
                badges: badges,
                isPinned: model.isPinned,
                onPin: { model.isPinned.toggle() },
                onSettings: onOpenSettings
            )
        }
        .transition(appearTransition)
        .task { agents.refresh() }
    }

    private var badges: [NotchPage: Int] {
        [
            .tasks: model.overdueCount,
            .inbox: model.inboxCount,
            .coding: watcher.sessions.filter { $0.state == .waiting }.count,
        ]
    }

    @ViewBuilder
    private var page: some View {
        switch model.page {
        case .dashboard:
            DashboardPage(model: model, agents: agents, focus: focus) { destination in
                withAnimation(Tokens.Anim.content) { model.page = destination }
            }
        case .tasks:
            TasksPage(
                model: model,
                onComplete: onComplete,
                onUndo: onUndo,
                onSnooze: onSnooze,
                onQuickAdd: onQuickAdd,
                onQuickAddFocus: onQuickAddFocus
            )
        case .calendar:
            CalendarPage(model: model)
        case .coding:
            CodingPage(model: agents)
        case .focus:
            FocusPage(focus: focus)
        case .inbox:
            InboxPage(model: model, onResolve: onResolveInbox)
        }
    }
}

enum SnoozeOption: String, CaseIterable, Identifiable {
    case tenMinutes = "10 minutes"
    case oneHour = "1 hour"
    case thisEvening = "This evening"
    case tomorrowMorning = "Tomorrow morning"

    var id: String { rawValue }

    /// Resolved against the actual clock — date maths never goes to a model.
    func resolve(from now: Date = Date(), calendar: Calendar = .current) -> Date {
        switch self {
        case .tenMinutes:
            return now.addingTimeInterval(10 * 60)
        case .oneHour:
            return now.addingTimeInterval(60 * 60)
        case .thisEvening:
            let evening = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: now) ?? now
            return evening > now ? evening : now.addingTimeInterval(60 * 60)
        case .tomorrowMorning:
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        }
    }
}
