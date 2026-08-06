import SwiftUI
import SwiftData
import DunduKit

/// The SwiftUI face of the notch panel. Renders whichever state the model is
/// in; the AppKit controller owns geometry, hover, and hit testing.
struct NotchView: View {
    let model: NotchModel
    let geometry: NotchGeometry
    let onComplete: (NotchItem) -> Void
    let onSnooze: (NotchItem, SnoozeOption) -> Void

    private var animation: Animation {
        model.reduceMotion ? Tokens.Anim.reduceMotionFallback : Tokens.Anim.notchSpring
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
            Text("\(model.items.count)")
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
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Expanded

    private var expandedPanel: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
            Color.clear.frame(height: geometry.notchRect.height)

            HStack {
                Text(model.items.isEmpty ? "All clear" : "Due now")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, Tokens.Spacing.lg)

            ForEach(model.items.prefix(5)) { item in
                NotchRow(item: item, onComplete: onComplete, onSnooze: onSnooze)
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
        .transition(.move(edge: .top).combined(with: .opacity))
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
    let onComplete: (NotchItem) -> Void
    let onSnooze: (NotchItem, SnoozeOption) -> Void

    var body: some View {
        HStack(spacing: Tokens.Spacing.sm) {
            Button {
                onComplete(item)
            } label: {
                Image(systemName: "circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Text(item.title)
                .font(.callout)
                .lineLimit(1)

            Spacer()

            if let due = item.dueDate {
                Text(Formatters.relativeTime(to: due))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(item.isOverdue ? Tokens.Colors.overdue : .secondary)
            }

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
        .padding(.vertical, Tokens.Spacing.xs)
    }
}
