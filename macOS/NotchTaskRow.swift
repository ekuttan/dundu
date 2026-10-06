import SwiftUI
import AppKit
import DunduKit

/// One reminder or meeting, as the panel draws it everywhere.
///
/// Flat by design: no per-row card. The card is the column it sits in, so a
/// list of ten rows reads as one block rather than ten stacked boxes.
struct NPTaskRow: View {
    let item: NotchItem
    var isPendingUndo: Bool = false
    var showsSubtitle: Bool = true
    var onComplete: ((NotchItem) -> Void)?
    var onUndo: ((NotchItem) -> Void)?
    var onSnooze: ((NotchItem, SnoozeOption) -> Void)?

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            marker

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(NP.F.row)
                    .foregroundStyle(isPendingUndo ? NP.C.faint : NP.C.text)
                    .strikethrough(isPendingUndo)
                    .lineLimit(1)
                if showsSubtitle, let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(NP.F.caption)
                        .foregroundStyle(NP.C.faint)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            if isPendingUndo {
                NPButton(title: "Undo") { onUndo?(item) }
            } else {
                if let due = item.dueDate {
                    Text(Formatters.relativeTime(to: due))
                        .font(NP.F.caption.monospacedDigit())
                        .foregroundStyle(item.isOverdue ? NP.C.bad : NP.C.faint)
                }
                if item.isMeeting {
                    if let url = item.joinURL {
                        NPButton(title: "Join", icon: "video.fill", kind: .primary) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                } else if hovering, onSnooze != nil {
                    // Snooze only on hover: four rows each wearing a permanent
                    // menu button is a toolbar, not a list.
                    Menu {
                        ForEach(SnoozeOption.allCases) { option in
                            Button(option.rawValue) { onSnooze?(item, option) }
                        }
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(NP.C.dim)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .frame(width: 16)
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(height: showsSubtitle && item.subtitle != nil ? 34 : 28)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(hovering ? Color.white.opacity(0.05) : .clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    @ViewBuilder
    private var marker: some View {
        if item.isMeeting {
            Image(systemName: "video.fill")
                .font(.system(size: 9))
                .foregroundStyle(NP.C.info)
                .frame(width: 14)
        } else if let onComplete {
            Button {
                isPendingUndo ? onUndo?(item) : onComplete(item)
            } label: {
                Image(systemName: isPendingUndo ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12))
                    .foregroundStyle(isPendingUndo ? NP.C.good : NP.C.faint)
            }
            .buttonStyle(.plain)
            .frame(width: 14)
        } else {
            Circle()
                .fill(item.isOverdue ? NP.C.bad : NP.C.faint)
                .frame(width: 5, height: 5)
                .frame(width: 14)
        }
    }
}

/// What a page shows when it has nothing — one line, centred, never a
/// full-bleed illustration. The panel is 420pt tall; empty states do not get
/// to be the main event.
struct NPEmpty: View {
    let icon: String
    let text: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(NP.C.faint)
            Text(text)
                .font(NP.F.caption)
                .foregroundStyle(NP.C.faint)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
