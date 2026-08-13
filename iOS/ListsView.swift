import SwiftUI
import SwiftData
import DunduKit

/// Every open reminder, on one screen, grouped by the list it belongs to.
///
/// Lists used to be the screen and reminders lived a tap inside them. That is
/// backwards: the reminders are the content, the lists are just how they're
/// filed. The filter row narrows to one list without hiding anything, and no
/// row is tinted — colour here is a 6pt dot for the list and red text for
/// something that is late, nothing more.
struct ListsView: View {
    @Environment(\.modelContext) private var context

    @Query(
        filter: #Predicate<ReminderList> { $0.tombstonedAt == nil },
        sort: \ReminderList.sortOrder
    ) private var lists: [ReminderList]
    @Query(
        filter: #Predicate<ReminderItem> { $0.tombstonedAt == nil },
        sort: \ReminderItem.dueDate
    ) private var reminders: [ReminderItem]

    @State private var searchText = ""
    @State private var searching = false
    @FocusState private var searchFocused: Bool
    @State private var selectedListID: UUID?
    @State private var editingReminder: ReminderItem?
    @State private var showingNew = false
    @State private var showingCompleted = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScreenHeader(glyph: "checklist", title: "Reminders",
                             subtitle: countLabel) {
                    HStack(spacing: Tokens.Spacing.md) {
                        Button {
                            withAnimation(Tokens.Anim.content) {
                                searching.toggle()
                                if !searching { searchText = "" }
                            }
                        } label: {
                            Image(systemName: searching ? "xmark" : "magnifyingglass")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Tokens.Colors.ink)
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(PressableStyle())
                        RoundAccentButton(glyph: "plus") { showingNew = true }
                    }
                }

                if searching {
                    searchField
                }

                if lists.count > 1 {
                    filterRow
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if visibleReminders.isEmpty {
                            QuietEmptyState(
                                glyph: searchText.isEmpty ? "checkmark.circle" : "magnifyingglass",
                                title: searchText.isEmpty ? "All clear" : "Nothing matches",
                                message: searchText.isEmpty && reminders.isEmpty
                                    ? "Reminders appear after the first sync with Apple Reminders."
                                    : nil
                            )
                            .padding(.top, Tokens.Spacing.xxl)
                        }

                        ForEach(groups, id: \.list?.id) { group in
                            if selectedListID == nil, let list = group.list {
                                groupHeader(list, count: group.items.count)
                            }
                            ForEach(group.items) { reminder in
                                ReminderRow(reminder: reminder) { editingReminder = reminder }
                                    .contextMenu {
                                        Button("Delete", systemImage: "trash", role: .destructive) {
                                            delete(reminder)
                                        }
                                    }
                                Divider()
                                    .overlay(Tokens.Colors.hairline)
                                    .padding(.leading, 46)
                            }
                        }

                        if !completed.isEmpty {
                            completedSection
                        }
                    }
                    .padding(.bottom, Tokens.Spacing.xl)
                }
            }
            .background(Tokens.Colors.paper)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $editingReminder) { ReminderEditView(existing: $0) }
            .sheet(isPresented: $showingNew) {
                ReminderEditView(existing: nil, preferredListID: selectedListID)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: Tokens.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Tokens.Colors.quiet)
            TextField("Search titles and notes", text: $searchText)
                .font(Tokens.Typo.body)
                .focused($searchFocused)
                .submitLabel(.search)
        }
        .padding(.horizontal, Tokens.Spacing.md)
        .padding(.vertical, Tokens.Spacing.sm + 2)
        .background {
            RoundedRectangle(cornerRadius: Tokens.Radius.chip, style: .continuous)
                .stroke(Tokens.Colors.hairline, lineWidth: 1)
        }
        .padding(.horizontal, Tokens.Spacing.xl)
        .padding(.bottom, Tokens.Spacing.md)
        .onAppear { searchFocused = true }
    }

    // MARK: - Filter

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Tokens.Spacing.sm) {
                filterChip(title: "All", dot: nil, id: nil)
                ForEach(lists) { list in
                    filterChip(
                        title: list.title,
                        dot: Color(hex: list.colorHex) ?? Tokens.Colors.quiet,
                        id: list.id
                    )
                }
            }
            .padding(.horizontal, Tokens.Spacing.xl)
            .padding(.bottom, Tokens.Spacing.md)
        }
    }

    private func filterChip(title: String, dot: Color?, id: UUID?) -> some View {
        let isOn = selectedListID == id
        return Button {
            withAnimation(Tokens.Anim.content) {
                selectedListID = isOn ? nil : id
            }
        } label: {
            HStack(spacing: 5) {
                if let dot {
                    Circle().fill(dot).frame(width: 6, height: 6)
                }
                Text(title)
                    .font(Tokens.Typo.label)
            }
            .foregroundStyle(isOn ? Tokens.Colors.paper : Tokens.Colors.ink)
            .padding(.horizontal, Tokens.Spacing.md)
            .padding(.vertical, 6)
            .background {
                Capsule()
                    .fill(isOn ? Tokens.Colors.ink : Color.clear)
                    .overlay {
                        Capsule().stroke(
                            isOn ? Color.clear : Tokens.Colors.hairline,
                            lineWidth: 1
                        )
                    }
            }
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: - Grouping

    private var open: [ReminderItem] {
        let query = searchText.lowercased()
        return reminders.filter { reminder in
            guard !reminder.isCompleted else { return false }
            if let selectedListID, reminder.listID != selectedListID { return false }
            guard !query.isEmpty else { return true }
            return reminder.title.lowercased().contains(query)
                || (reminder.notes?.lowercased().contains(query) ?? false)
        }
    }

    private var visibleReminders: [ReminderItem] { open }

    private var completed: [ReminderItem] {
        guard searchText.isEmpty else { return [] }
        return reminders.filter {
            $0.isCompleted && (selectedListID == nil || $0.listID == selectedListID)
        }
    }

    private struct Group {
        var list: ReminderList?
        var items: [ReminderItem]
    }

    /// Filed order, with anything whose list has gone missing collected at the
    /// end rather than dropped.
    private var groups: [Group] {
        guard selectedListID == nil else { return [Group(list: nil, items: open)] }
        var result: [Group] = []
        for list in lists {
            let items = open.filter { $0.listID == list.id }
            if !items.isEmpty { result.append(Group(list: list, items: items)) }
        }
        let known = Set(lists.map(\.id))
        let orphans = open.filter { $0.listID.map { !known.contains($0) } ?? true }
        if !orphans.isEmpty { result.append(Group(list: nil, items: orphans)) }
        return result
    }

    private var countLabel: String? {
        let count = open.count
        guard count > 0 else { return nil }
        return count == 1 ? "1 open" : "\(count) open"
    }

    private func groupHeader(_ list: ReminderList, count: Int) -> some View {
        HStack(spacing: Tokens.Spacing.sm) {
            Circle()
                .fill(Color(hex: list.colorHex) ?? Tokens.Colors.quiet)
                .frame(width: 6, height: 6)
            Text(list.title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Tokens.Colors.quiet)
            Spacer()
            Text("\(count)")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Tokens.Colors.quiet.opacity(0.7))
        }
        .padding(.horizontal, Tokens.Spacing.xl)
        .padding(.top, Tokens.Spacing.lg)
        .padding(.bottom, Tokens.Spacing.sm)
    }

    // MARK: - Completed

    @ViewBuilder
    private var completedSection: some View {
        Button {
            withAnimation(Tokens.Anim.content) { showingCompleted.toggle() }
        } label: {
            HStack(spacing: Tokens.Spacing.sm) {
                Image(systemName: showingCompleted ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                Text("Completed")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Text("\(completed.count)")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .monospacedDigit()
                Spacer()
            }
            .foregroundStyle(Tokens.Colors.quiet)
            .padding(.horizontal, Tokens.Spacing.xl)
            .padding(.top, Tokens.Spacing.xl)
            .padding(.bottom, Tokens.Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        if showingCompleted {
            ForEach(completed) { reminder in
                ReminderRow(reminder: reminder) { editingReminder = reminder }
                Divider()
                    .overlay(Tokens.Colors.hairline)
                    .padding(.leading, 46)
            }
        }
    }

    private func delete(_ reminder: ReminderItem) {
        withAnimation(Tokens.Anim.content) { context.tombstone(reminder) }
        try? context.save()
        Task { await ReminderSyncService.syncNow(context: context) }
    }
}

/// A reminder as a flat row: a check, the title, and — only when there is one
/// — a due date. No fill, no card; the hairline under it is the whole frame.
struct ReminderRow: View {
    @Environment(\.modelContext) private var context
    let reminder: ReminderItem
    let onTap: () -> Void

    private var isLate: Bool {
        guard let due = reminder.dueDate, !reminder.isCompleted else { return false }
        return due < Date()
    }

    private var detail: String? {
        guard let due = reminder.dueDate else { return nil }
        return reminder.hasTime
            ? Formatters.relativeTime(to: due)
            : due.formatted(date: .abbreviated, time: .omitted)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.md) {
                Button(action: toggle) {
                    Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(
                            reminder.isCompleted ? Tokens.Colors.quiet
                                : (isLate ? Tokens.Colors.overdue : Tokens.Colors.ink.opacity(0.35))
                        )
                }
                .buttonStyle(.plain)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 4 }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Tokens.Spacing.xs) {
                        if reminder.priority == .high && !reminder.isCompleted {
                            Text("!!")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(Tokens.Colors.overdue)
                        }
                        Text(reminder.title)
                            .font(Tokens.Typo.body)
                            .foregroundStyle(
                                reminder.isCompleted ? Tokens.Colors.quiet : Tokens.Colors.ink
                            )
                            .strikethrough(reminder.isCompleted, color: Tokens.Colors.quiet)
                            .multilineTextAlignment(.leading)
                    }
                    if let notes = reminder.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(Tokens.Colors.quiet)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: Tokens.Spacing.sm)

                if let detail {
                    Text(detail)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(isLate ? Tokens.Colors.overdue : Tokens.Colors.quiet)
                }
                if reminder.locationAlarm != nil {
                    Image(systemName: "mappin")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Tokens.Colors.quiet)
                }
            }
            .padding(.horizontal, Tokens.Spacing.xl)
            .padding(.vertical, Tokens.Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggle() {
        withAnimation(Tokens.Anim.content) {
            context.setCompleted(reminder, !reminder.isCompleted)
        }
        try? context.save()
        Task { await ReminderSyncService.syncNow(context: context) }
    }
}

extension Color {
    /// "#RRGGBB" convenience for list colors.
    init?(hex: String) {
        var value: UInt64 = 0
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, Scanner(string: cleaned).scanHexInt64(&value) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
