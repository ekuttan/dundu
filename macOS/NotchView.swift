import SwiftUI
import SwiftData
import DunduKit

/// The SwiftUI face of the notch panel. Renders whichever state the model is
/// in; the AppKit controller owns geometry, hover, and hit testing.
struct NotchView: View {
    let model: NotchModel
    let geometry: NotchGeometry
    let onComplete: (NotchItem) -> Void
    let onUndo: (NotchItem) -> Void
    let onSnooze: (NotchItem, SnoozeOption) -> Void
    let onQuickAdd: (String) -> Void
    let onQuickAddFocus: (Bool) -> Void
    let onOpenSettings: () -> Void

    @State private var quickAddTitle = ""
    @State private var showQuickAdd = false
    @FocusState private var quickAddFocused: Bool

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
                .combined(with: .scale(scale: 0.85, anchor: .top))
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
                expandedPanel
            }
            Spacer(minLength: 0)
        }
        .frame(width: NotchGeometry.expandedSize.width, alignment: .top)
        .animation(animation, value: model.uiState)
    }

    // MARK: - Peek

    private var peekPill: some View {
        HStack(spacing: Tokens.Spacing.sm) {
            Circle()
                .fill(Tokens.Colors.overdue)
                .frame(width: 6, height: 6)
            Text("\(model.activeCount)")
                .font(.caption.bold().monospacedDigit())
            Text(model.peekTitle)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, Tokens.Spacing.md)
        .frame(
            width: min(geometry.notchRect.width + 24, NotchGeometry.expandedSize.width),
            height: geometry.notchRect.height + NotchGeometry.peekDrop - geometry.notchRect.height
        )
        .frame(height: geometry.notchRect.height + NotchGeometry.peekDrop, alignment: .bottom)
        .background(
            UnevenRoundedRectangle(
                bottomLeadingRadius: 12, bottomTrailingRadius: 12
            )
            .fill(.black)
        )
        .transition(appearTransition)
    }

    // MARK: - Expanded

    private var expandedPanel: some View {
        // Due rows take priority; upcoming fills whatever space remains.
        let due = Array(model.items.prefix(4))
        let upcoming = Array(model.upcoming.prefix(5 - due.count))

        return VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
            Color.clear.frame(height: geometry.notchRect.height)

            HStack {
                Text(due.isEmpty ? (upcoming.isEmpty ? "All clear" : "Next up") : "Due now")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                if model.inboxCount > 0 {
                    // The Inbox surface on the Mac: a dot, not a modal.
                    HStack(spacing: Tokens.Spacing.xs) {
                        Circle()
                            .fill(Tokens.Colors.dueSoon)
                            .frame(width: 6, height: 6)
                        Text("\(model.inboxCount)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Button {
                    withAnimation(animation) { showQuickAdd.toggle() }
                    if showQuickAdd {
                        quickAddFocused = true
                    } else {
                        onQuickAddFocus(false)
                    }
                } label: {
                    Image(systemName: showQuickAdd ? "xmark.circle" : "plus.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Quick add a reminder")
                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Open Dundu settings")
            }
            .padding(.horizontal, Tokens.Spacing.lg)

            if showQuickAdd {
                TextField("Quick add…", text: $quickAddTitle)
                    .textFieldStyle(.roundedBorder)
                    .focused($quickAddFocused)
                    .onSubmit {
                        onQuickAdd(quickAddTitle)
                        quickAddTitle = ""
                        showQuickAdd = false
                        onQuickAddFocus(false)
                    }
                    .onExitCommand {
                        quickAddTitle = ""
                        showQuickAdd = false
                        onQuickAddFocus(false)
                    }
                    .onChange(of: quickAddFocused) { _, focused in
                        onQuickAddFocus(focused)
                    }
                    .padding(.horizontal, Tokens.Spacing.lg)
            }

            ForEach(due) { item in
                NotchRow(
                    item: item,
                    isPendingUndo: model.pendingUndo.contains(item.id),
                    onComplete: onComplete,
                    onUndo: onUndo,
                    onSnooze: onSnooze
                )
                .padding(.horizontal, Tokens.Spacing.md)
            }

            if !due.isEmpty && !upcoming.isEmpty {
                Text("Next up")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Tokens.Spacing.lg)
            }

            ForEach(upcoming) { item in
                NotchRow(
                    item: item,
                    isPendingUndo: model.pendingUndo.contains(item.id),
                    onComplete: onComplete,
                    onUndo: onUndo,
                    onSnooze: onSnooze
                )
                .padding(.horizontal, Tokens.Spacing.md)
            }

            Spacer(minLength: Tokens.Spacing.md)
        }
        .frame(
            width: NotchGeometry.expandedSize.width,
            height: NotchGeometry.expandedSize.height + geometry.notchRect.height,
            alignment: .top
        )
        .background(
            UnevenRoundedRectangle(bottomLeadingRadius: 20, bottomTrailingRadius: 20)
                .fill(.black)
        )
        .environment(\.colorScheme, .dark)
        .transition(appearTransition)
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

private struct NotchRow: View {
    let item: NotchItem
    let isPendingUndo: Bool
    let onComplete: (NotchItem) -> Void
    let onUndo: (NotchItem) -> Void
    let onSnooze: (NotchItem, SnoozeOption) -> Void

    var body: some View {
        HStack(spacing: Tokens.Spacing.sm) {
            if item.isMeeting {
                Image(systemName: "video")
                    .foregroundStyle(Tokens.Colors.meeting)
            } else {
                Button {
                    isPendingUndo ? onUndo(item) : onComplete(item)
                } label: {
                    Image(systemName: isPendingUndo ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isPendingUndo ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                }
                .buttonStyle(.plain)
            }

            Text(item.title)
                .font(.callout)
                .strikethrough(isPendingUndo)
                .foregroundStyle(isPendingUndo ? .secondary : .primary)
                .lineLimit(1)

            Spacer()

            if isPendingUndo {
                Button("Undo") { onUndo(item) }
                    .buttonStyle(.plain)
                    .font(.caption.bold())
                    .foregroundStyle(.tint)
            } else {
                if let due = item.dueDate {
                    Text(Formatters.relativeTime(to: due))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(item.isOverdue ? Tokens.Colors.overdue : .secondary)
                }

                if item.isMeeting {
                    // Probably the single most used control in the app.
                    if let url = item.joinURL {
                        Button("Join") {
                            NSWorkspace.shared.open(url)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(Tokens.Colors.meeting)
                    }
                } else {
                    Menu {
                        ForEach(SnoozeOption.allCases) { option in
                            Button(option.rawValue) { onSnooze(item, option) }
                        }
                    } label: {
                        Image(systemName: "zzz")
                            .foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
        }
        .padding(.vertical, Tokens.Spacing.xs)
        .animation(.default, value: isPendingUndo)
    }
}
