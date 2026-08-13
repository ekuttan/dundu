import SwiftUI
import SwiftData
import DunduKit

/// One screen, everything Dundu wants to ask about. Each card holds the
/// original text, the proposed change, and the reason. Accept, edit, dismiss.
///
/// Most pressing first: something already overdue with a pending question is
/// the one worth answering now.
struct InboxView: View {
    @Environment(\.modelContext) private var context
    @Query(
        filter: #Predicate<ReminderItem> {
            $0.tombstonedAt == nil && $0.reviewStateRaw == "pending"
        }
    ) private var pendingItems: [ReminderItem]
    @Query(
        filter: #Predicate<ReminderList> { $0.tombstonedAt == nil }
    ) private var lists: [ReminderList]

    @State private var editingReminder: ReminderItem?

    private var sorted: [ReminderItem] {
        pendingItems.sorted { lhs, rhs in
            switch (lhs.dueDate, rhs.dueDate) {
            case let (l?, r?): return l < r
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return lhs.createdAt > rhs.createdAt
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(
                glyph: "tray",
                title: "Inbox",
                subtitle: pendingItems.isEmpty ? nil
                    : (pendingItems.count == 1 ? "1 question" : "\(pendingItems.count) questions")
            )

            ScrollView {
                LazyVStack(spacing: Tokens.Spacing.md) {
                    if pendingItems.isEmpty {
                        QuietEmptyState(
                            glyph: "tray",
                            title: "All clear",
                            message: "Routing questions and dictation fixes land here when Dundu isn't sure."
                        )
                        .padding(.top, Tokens.Spacing.xxl)
                    }
                    ForEach(sorted) { item in
                        InboxCard(
                            item: item,
                            lists: lists,
                            onEdit: { editingReminder = item },
                            afterAction: syncSoon
                        )
                    }
                }
                .padding(.horizontal, Tokens.Spacing.xl)
                .padding(.vertical, Tokens.Spacing.md)
            }
        }
        .background(Tokens.Colors.paper)
        .sheet(item: $editingReminder) { ReminderEditView(existing: $0) }
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

    private var isLate: Bool {
        guard let due = item.dueDate else { return false }
        return due < Date()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.md) {
            header
            if let suggested = item.suggestedTitle {
                question(
                    glyph: "waveform",
                    title: "Did you mean “\(suggested)”?",
                    detail: item.repairConfidence.map { "Sounds alike · \($0)% sure" },
                    accept: "Use suggested",
                    reject: "Keep original",
                    onAccept: { context.acceptRepair(item); afterAction() },
                    onReject: { context.rejectRepair(item); afterAction() }
                )
            }
            if let target = proposedList {
                question(
                    glyph: "arrow.turn.down.right",
                    title: "Move to “\(target.title)”?",
                    detail: item.routingReason,
                    accept: "Move it",
                    reject: "Keep here",
                    onAccept: { context.acceptRouting(item); afterAction() },
                    onReject: { context.rejectRouting(item); afterAction() }
                )
            }
            footer
        }
        .padding(Tokens.Spacing.lg)
        .background {
            RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous)
                .fill(Tokens.Colors.paper)
                .overlay {
                    RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous)
                        .stroke(Tokens.Colors.hairline, lineWidth: 1)
                }
        }
    }

    /// What the item actually says right now, before anything is accepted.
    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: Tokens.Spacing.xs) {
                if item.origin == .siriSuspected {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Tokens.Colors.quiet)
                }
                Text(item.title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Tokens.Colors.ink)
            }
            HStack(spacing: Tokens.Spacing.sm) {
                if let due = item.dueDate {
                    Text(Formatters.relativeTime(to: due))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(isLate ? Tokens.Colors.overdue : Tokens.Colors.quiet)
                }
                if item.locationAlarm != nil {
                    Label("Location", systemImage: "mappin")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Tokens.Colors.quiet)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Edit", action: onEdit)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Tokens.Colors.quiet)
            Spacer()
            Button("Dismiss") {
                context.dismissAllReviews(item)
                afterAction()
            }
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(Tokens.Colors.quiet)
        }
        .buttonStyle(.plain)
    }

    /// One question: what Dundu thinks, why, and the two answers. The accept
    /// button is the only filled thing on the card — a question should have
    /// exactly one obvious answer to reach for.
    @ViewBuilder
    private func question(
        glyph: String,
        title: String,
        detail: String?,
        accept: String,
        reject: String,
        onAccept: @escaping () -> Void,
        onReject: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
            HStack(alignment: .top, spacing: Tokens.Spacing.sm) {
                Image(systemName: glyph)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Tokens.Colors.quiet)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Tokens.Colors.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail {
                        Text(detail)
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(Tokens.Colors.quiet)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            HStack(spacing: Tokens.Spacing.sm) {
                Button(action: onAccept) {
                    Text(accept)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Tokens.Colors.paper)
                        .padding(.horizontal, Tokens.Spacing.lg)
                        .padding(.vertical, Tokens.Spacing.sm)
                        .background(Capsule().fill(Tokens.Colors.ink))
                }
                .buttonStyle(PressableStyle())

                Button(action: onReject) {
                    Text(reject)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Tokens.Colors.ink)
                        .padding(.horizontal, Tokens.Spacing.lg)
                        .padding(.vertical, Tokens.Spacing.sm)
                        .background(Capsule().stroke(Tokens.Colors.hairline, lineWidth: 1))
                }
                .buttonStyle(PressableStyle())
            }
            .padding(.leading, 24)
        }
    }
}
