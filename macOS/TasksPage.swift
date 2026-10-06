import SwiftUI
import DunduKit

/// Everything with a time on it: what is due, what is coming, and a quick
/// way to add to the pile without opening an app.
struct TasksPage: View {
    let model: NotchModel
    let onComplete: (NotchItem) -> Void
    let onUndo: (NotchItem) -> Void
    let onSnooze: (NotchItem, SnoozeOption) -> Void
    let onQuickAdd: (String) -> Void
    let onQuickAddFocus: (Bool) -> Void

    @State private var draft = ""
    @FocusState private var writing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: NP.gridGap) {
            NPPageHeader(
                title: "Tasks",
                subtitle: "\(model.openCount) open · \(model.doneToday) done today"
            ) {
                quickAdd
            }

            HStack(spacing: NP.gridGap) {
                column(
                    label: "Due now",
                    icon: "exclamationmark.circle.fill",
                    tint: model.items.isEmpty ? NP.C.dim : NP.C.bad,
                    items: model.items,
                    empty: "Nothing is overdue."
                )
                column(
                    label: "Next up",
                    icon: "arrow.forward.circle",
                    tint: NP.C.dim,
                    items: model.upcoming,
                    empty: "Nothing scheduled ahead."
                )
                summary
            }
        }
    }

    private var quickAdd: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(NP.C.faint)
            TextField("Add a reminder…", text: $draft)
                .textFieldStyle(.plain)
                .font(NP.F.row)
                .foregroundStyle(NP.C.text)
                .focused($writing)
                .frame(width: 180)
                .onSubmit {
                    onQuickAdd(draft)
                    draft = ""
                    writing = false
                }
                .onExitCommand {
                    draft = ""
                    writing = false
                }
                // The panel is nonactivating, so it only takes key status
                // while this field actually wants it.
                .onChange(of: writing) { _, active in onQuickAddFocus(active) }
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(Capsule().fill(Color(white: 0.12)))
        .overlay(Capsule().strokeBorder(writing ? NP.C.strokeStrong : NP.C.stroke))
    }

    private func column(
        label: String, icon: String, tint: Color, items: [NotchItem], empty: String
    ) -> some View {
        NPCard(padding: 11) {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    NPLabel(label, icon: icon, tint: tint)
                    Spacer()
                    if !items.isEmpty {
                        Text("\(items.count)")
                            .font(NP.F.label)
                            .foregroundStyle(NP.C.faint)
                    }
                }
                if items.isEmpty {
                    NPEmpty(icon: "checkmark", text: empty)
                } else {
                    ForEach(items.prefix(7)) { item in
                        NPTaskRow(
                            item: item,
                            isPendingUndo: model.pendingUndo.contains(item.id),
                            onComplete: onComplete,
                            onUndo: onUndo,
                            onSnooze: onSnooze
                        )
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var summary: some View {
        NPCard(padding: 11) {
            VStack(alignment: .leading, spacing: 8) {
                NPLabel("Today")
                tally("Open", "\(model.openCount)", NP.C.text)
                tally("Overdue", "\(model.overdueCount)", model.overdueCount > 0 ? NP.C.bad : NP.C.text)
                tally("Done", "\(model.doneToday)", NP.C.good)
                tally("To review", "\(model.inboxCount)", model.inboxCount > 0 ? NP.C.warn : NP.C.text)
                if !model.listTallies.isEmpty {
                    Divider().overlay(NP.C.stroke).padding(.vertical, 2)
                    NPLabel("By list")
                    ForEach(model.listTallies.prefix(5)) { entry in
                        tally(entry.name, "\(entry.open)", NP.C.dim)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(width: 170)
    }

    private func tally(_ label: String, _ value: String, _ tint: Color) -> some View {
        HStack {
            Text(label)
                .font(NP.F.row)
                .foregroundStyle(NP.C.dim)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                .foregroundStyle(tint)
        }
    }
}
