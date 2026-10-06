import SwiftUI
import DunduKit

/// Captures Dundu was not confident about, waiting for a yes or a no.
///
/// The whole point of the Inbox is that it is quick to clear, so each row
/// carries both answers rather than opening anything.
struct InboxPage: View {
    let model: NotchModel
    let onResolve: (NotchItem, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: NP.gridGap) {
            NPPageHeader(
                "Inbox",
                subtitle: model.inboxCount == 0
                    ? "Nothing to review"
                    : "\(model.inboxCount) waiting on you"
            )

            HStack(spacing: NP.gridGap) {
                queue
                aside
            }
        }
    }

    private var queue: some View {
        NPCard(padding: 11) {
            VStack(alignment: .leading, spacing: 4) {
                NPLabel("To review", icon: "tray.full", tint: model.inboxCount > 0 ? NP.C.warn : NP.C.dim)
                if model.inboxItems.isEmpty {
                    NPEmpty(icon: "tray", text: "Inbox zero. Nothing needs a decision.")
                } else {
                    ForEach(model.inboxItems.prefix(7)) { item in
                        row(item)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func row(_ item: NotchItem) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(NP.C.warn)
                .frame(width: 5, height: 5)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(NP.F.row)
                    .foregroundStyle(NP.C.text)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    if let list = item.subtitle, !list.isEmpty {
                        Text(list)
                    }
                    if let due = item.dueDate {
                        if item.subtitle?.isEmpty == false { Text("·") }
                        Text(Formatters.relativeTime(to: due))
                    }
                }
                .font(NP.F.caption)
                .foregroundStyle(NP.C.faint)
            }

            Spacer(minLength: 6)

            NPButton(title: "Keep", icon: "checkmark", kind: .primary) { onResolve(item, true) }
            NPButton(title: "Discard") { onResolve(item, false) }
        }
        .padding(.horizontal, 6)
        .frame(height: 36)
    }

    private var aside: some View {
        NPCard {
            VStack(alignment: .leading, spacing: 8) {
                NPLabel("What this is")
                Text("Anything Dundu captured but could not place with confidence waits here — a dictated line it half-understood, a list it had to guess at.")
                    .font(NP.F.caption)
                    .foregroundStyle(NP.C.dim)
                    .fixedSize(horizontal: false, vertical: true)
                Divider().overlay(NP.C.stroke)
                Text("Keep leaves it where it is. Discard removes it. Either way it stops asking.")
                    .font(NP.F.caption)
                    .foregroundStyle(NP.C.faint)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                HStack {
                    Text("Cleared today")
                        .font(NP.F.caption)
                        .foregroundStyle(NP.C.faint)
                    Spacer()
                    Text("\(model.doneToday)")
                        .font(NP.F.valueSmall)
                        .foregroundStyle(NP.C.text)
                }
            }
        }
        .frame(width: 210)
    }
}
