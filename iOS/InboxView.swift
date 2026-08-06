import SwiftUI
import SwiftData
import DunduKit

/// One screen, everything Dundu wants to ask about. Cards stacked by
/// urgency; each holds the original text, the proposed change, and the
/// reason. Accept, edit, dismiss.
struct InboxView: View {
    @Environment(\.modelContext) private var context
    @Query(
        filter: #Predicate<ReminderItem> {
            $0.tombstonedAt == nil && $0.reviewStateRaw == "pending"
        },
        sort: \ReminderItem.dueDate
    ) private var pendingItems: [ReminderItem]
    @Query(
        filter: #Predicate<ReminderList> { $0.tombstonedAt == nil }
    ) private var lists: [ReminderList]

    @State private var editingReminder: ReminderItem?

    var body: some View {
        NavigationStack {
            List {
                if pendingItems.isEmpty {
                    ContentUnavailableView(
                        "All clear",
                        systemImage: "tray",
                        description: Text("Routing questions and dictation fixes land here when Dundu isn't sure.")
                    )
                }
                ForEach(pendingItems) { item in
                    Section {
                        InboxCard(
                            item: item,
                            lists: lists,
                            onEdit: { editingReminder = item },
                            afterAction: syncSoon
                        )
                    }
                }
            }
            .navigationTitle("Inbox")
            .sheet(item: $editingReminder) { reminder in
                ReminderEditView(existing: reminder)
            }
        }
    }

    private func syncSoon() {
        try? context.save()
        Task { await ReminderSyncService.syncNow(context: context) }
    }
}

// MARK: - Card

struct InboxCard: View {
    @Environment(\.modelContext) private var context
    let item: ReminderItem
    let lists: [ReminderList]
    var onEdit: () -> Void
    var afterAction: () -> Void

    private var proposedList: ReminderList? {
        item.proposedTargetID
            .flatMap(UUID.init(uuidString:))
            .flatMap { id in lists.first { $0.id == id } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.md) {
            // The original text, always.
            VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                HStack(spacing: Tokens.Spacing.xs) {
                    if item.origin == .siriSuspected {
                        Image(systemName: "mic.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(item.title)
                        .font(.headline)
                }
                if let due = item.dueDate {
                    Text(Formatters.relativeTime(to: due))
                        .font(.caption)
                        .foregroundStyle(due < Date() ? Tokens.Colors.overdue : .secondary)
                }
            }

            // Repair question.
            if let suggested = item.suggestedTitle {
                questionBlock(
                    icon: "waveform.badge.exclamationmark",
                    question: "Did you mean \u{201C}\(suggested)\u{201D}?",
                    accept: "Use suggested",
                    reject: "Keep original",
                    onAccept: {
                        context.acceptRepair(item)
                        afterAction()
                    },
                    onReject: {
                        context.rejectRepair(item)
                        afterAction()
                    }
                )
            }

            // Routing question.
            if let target = proposedList {
                questionBlock(
                    icon: "arrow.turn.down.right",
                    question: "Move to \u{201C}\(target.title)\u{201D}?",
                    detail: item.routingReason,
                    accept: "Move it",
                    reject: "Keep here",
                    onAccept: {
                        context.acceptRouting(item)
                        afterAction()
                    },
                    onReject: {
                        context.rejectRouting(item)
                        afterAction()
                    }
                )
            }

            HStack {
                Button("Edit", action: onEdit)
                    .font(.caption)
                Spacer()
                Button("Dismiss", role: .destructive) {
                    context.dismissAllReviews(item)
                    afterAction()
                }
                .font(.caption)
            }
        }
        .padding(.vertical, Tokens.Spacing.xs)
    }

    @ViewBuilder
    private func questionBlock(
        icon: String,
        question: String,
        detail: String? = nil,
        accept: String,
        reject: String,
        onAccept: @escaping () -> Void,
        onReject: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
            Label(question, systemImage: icon)
                .font(.subheadline)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: Tokens.Spacing.md) {
                Button(accept, action: onAccept)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button(reject, action: onReject)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(Tokens.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
    }
}
