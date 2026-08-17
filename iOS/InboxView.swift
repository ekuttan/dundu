import SwiftUI
import SwiftData
import DunduKit

/// One screen, everything Dundu wants to ask about. Each card holds the
/// original text, the proposed change, and the reason. Accept, edit, dismiss.
///
/// Most pressing first: something already overdue with a pending question is
/// the one worth answering now.
struct InboxView: View {
    /// Collapses the bar while the user is reading.
    var barChrome: BarChrome?
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
                title: "Inbox",
                subtitle: pendingItems.isEmpty ? nil
                    : (pendingItems.count == 1 ? "1 question" : "\(pendingItems.count) questions")
            )

            ScrollView {
                LazyVStack(spacing: 0) {
                    ScrollProbe()
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
                .padding(.horizontal, Tokens.Layout.gutter)
                .padding(.bottom, Tokens.Spacing.md)
            }
            .clearsFloatingBar()
                .tracksScroll(barChrome)
        }
        .background(Tokens.Colors.ground)
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
        .padding(.vertical, Tokens.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Tokens.Colors.hairline)
                .frame(height: 1)
        }
    }

    /// A tinted heading line saying where the item came from, then what it
    /// actually says right now, before anything is accepted — the same shape
    /// the system's own cards use.
    private var header: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
            CardHeader(
                glyph: item.origin == .siriSuspected ? "mic.fill" : "tray",
                title: item.origin == .siriSuspected ? "Dictated" : "Needs a check",
                tint: Tokens.Colors.quiet,
                detail: item.dueDate.map { Formatters.relativeTime(to: $0) },
                detailTint: isLate ? Tokens.Colors.overdue : Tokens.Colors.quiet
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(Tokens.Typo.cardTitle)
                    .foregroundStyle(Tokens.Colors.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if item.locationAlarm != nil {
                    Label("Location", systemImage: "mappin")
                        .font(Tokens.Typo.caption)
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(Tokens.Colors.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail {
                        Text(detail)
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(Tokens.Colors.quiet)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            HStack(spacing: Tokens.Spacing.sm) {
                Button(action: onAccept) {
                    Text(accept)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Tokens.Colors.card)
                        .padding(.horizontal, Tokens.Spacing.lg)
                        .padding(.vertical, Tokens.Spacing.sm + 2)
                        .background(Capsule().fill(Tokens.Colors.ink))
                }
                .buttonStyle(PressableStyle())

                Button(action: onReject) {
                    Text(reject)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Tokens.Colors.quiet)
                        .padding(.horizontal, Tokens.Spacing.sm)
                        .padding(.vertical, Tokens.Spacing.sm + 2)
                }
                .buttonStyle(PressableStyle())
            }
        }
    }
}
