import SwiftUI
import SwiftData
import DunduKit

/// Reminders grouped by list, with filters, visible completion, and native swipe actions.
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
    @State private var selectedListID: UUID?
    @State private var editingReminder: ReminderItem?
    @State private var showingNew = false
    @State private var showingCompleted = false
    /// The list a dragged reminder is currently hovering over.
    @State private var dropTargetID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            if lists.count > 1 {
                filterRow
            }

            // A real List, not a LazyVStack: `.swipeActions` is inert
            // outside one, and a hand-rolled drag gesture would forfeit
            // full-swipe, haptics and the system's own spring.
            List {
                if visibleReminders.isEmpty {
                    QuietEmptyState(
                        glyph: searchText.isEmpty ? "checkmark.circle" : "magnifyingglass",
                        title: searchText.isEmpty ? "All clear" : "Nothing matches",
                        message: searchText.isEmpty && reminders.isEmpty
                            ? "Add your first reminder with +, speak it aloud, or connect Apple Reminders in Settings."
                            : nil
                    )
                    .padding(.top, Tokens.Spacing.xl)
                    .plainRow()
                }

                ForEach(groups, id: \.list?.id) { group in
                    Section {
                        ForEach(group.items) { reminder in
                            ReminderRow(
                                reminder: reminder,
                                lists: lists,
                                onTap: { editingReminder = reminder },
                                onMove: { move(reminder, to: $0) },
                                onDelete: { delete(reminder) }
                            )
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                            .listRowBackground(Tokens.Colors.card)
                            .draggable(reminder.id.uuidString) {
                                Text(reminder.title)
                                    .font(Tokens.Typo.blockTitle)
                                    .padding(Tokens.Spacing.sm)
                            }
                        }
                    } header: {
                        if selectedListID == nil, let list = group.list {
                            groupHeader(list, count: group.items.count)

                        }
                    }
                }

                if !completed.isEmpty {
                    completedSection
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 1)
            .dunduScrollMargins()
        }
        .background(Tokens.Colors.ground)
        .navigationTitle("Reminders")
        .searchable(text: $searchText, prompt: "Search titles and notes")
        .sheet(item: $editingReminder) { ReminderEditView(existing: $0) }
        .sheet(isPresented: $showingNew) {
            ReminderEditView(existing: nil, preferredListID: selectedListID)
        }
    }

    // MARK: - Filter

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Tokens.Spacing.sm) {
                filterChip(title: "All", id: nil)
                ForEach(lists) { list in
                    filterChip(
                        title: list.title,
                        id: list.id
                    )
                }
            }
            .padding(.horizontal, Tokens.Layout.gutter)
            .padding(.bottom, Tokens.Spacing.md)
        }
    }

    private func filterChip(title: String, id: UUID?) -> some View {
        let isOn = selectedListID == id
        let colour = Tokens.Colors.accent
        return Button {
            withAnimation(Tokens.Anim.content) {
                selectedListID = isOn ? nil : id
            }
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isOn ? Tokens.Colors.accent : Tokens.Colors.quiet)
                .padding(.horizontal, Tokens.Spacing.md + 2)
                .frame(minHeight: Tokens.Layout.control)
                .background {
                    Capsule().fill(
                        isOn ? Tokens.Colors.blockFill(colour) : .clear
                    )
                }
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(isOn ? .isSelected : [])
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

    private func groupHeader(_ list: ReminderList, count: Int) -> some View {
        header(list, count: count)
            .background {
                RoundedRectangle(cornerRadius: Tokens.Radius.chip, style: .continuous)
                    .fill(dropTargetID == list.id
                          ? Tokens.Colors.blockFill(Tokens.Colors.accent) : .clear)
                    .padding(.horizontal, Tokens.Spacing.sm)
            }
            .dropDestination(for: String.self) { ids, _ in
                let moved = ids.compactMap(UUID.init(uuidString:))
                    .compactMap { id in reminders.first { $0.id == id } }
                for reminder in moved { move(reminder, to: list) }
                return !moved.isEmpty
            } isTargeted: { targeted in
                withAnimation(Tokens.Anim.content) {
                    dropTargetID = targeted ? list.id : nil
                }
            }
    }

    /// The list's name in plain type, with its count on the right. No dot:
    /// the name is what identifies the list, and a 6pt disc of arbitrary
    /// Reminders colour in front of every heading only added noise.
    private func header(_ list: ReminderList, count: Int) -> some View {
        HStack(spacing: Tokens.Spacing.sm) {
            Text(list.title)
                .font(Tokens.Typo.sectionTitle)
                .foregroundStyle(Tokens.Colors.ink)
            Spacer()
            Text("\(count)")
                .font(Tokens.Typo.caption)
                .monospacedDigit()
                .foregroundStyle(Tokens.Colors.quiet)
        }

    }

    // MARK: - Completed

    @ViewBuilder
    private var completedSection: some View {
        Section {
            if showingCompleted {
                ForEach(completed) { reminder in
                    ReminderRow(reminder: reminder, lists: lists,
                                onTap: { editingReminder = reminder },
                                onMove: { move(reminder, to: $0) },
                                onDelete: { delete(reminder) })
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowBackground(Tokens.Colors.card)
                }
            }
        } header: {
            Button {
                withAnimation(Tokens.Anim.content) { showingCompleted.toggle() }
            } label: {
                HStack(spacing: Tokens.Spacing.sm) {
                    Text("Completed")
                        .font(Tokens.Typo.sectionTitle)
                        .foregroundStyle(Tokens.Colors.ink)
                    Text("\(completed.count)")
                        .font(Tokens.Typo.caption)
                        .monospacedDigit()
                        .foregroundStyle(Tokens.Colors.quiet)
                    Spacer()
                    Image(systemName: showingCompleted ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Tokens.Colors.faint)
                }

                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

        }
    }

    /// Reassigns the list and lets the normal sync pass carry it to Apple
    /// Reminders, exactly as an edit through the sheet would.
    private func move(_ reminder: ReminderItem, to list: ReminderList) {
        guard reminder.listID != list.id else { return }
        withAnimation(Tokens.Anim.content) {
            reminder.listID = list.id
            reminder.modifiedAt = Date()
        }
        try? context.save()
        Task { await ReminderSyncService.syncNow(context: context) }
    }

    private func delete(_ reminder: ReminderItem) {
        withAnimation(Tokens.Anim.content) { context.tombstone(reminder) }
        try? context.save()
        Task { await ReminderSyncService.syncNow(context: context) }
    }
}

/// Separate completion and edit targets, retaining the native swipe and context menus.
struct ReminderRow: View {
    @Environment(\.modelContext) private var context
    let reminder: ReminderItem
    var lists: [ReminderList] = []
    let onTap: () -> Void
    var onMove: (ReminderList) -> Void = { _ in }
    var onDelete: () -> Void = {}

    @State private var showingDatePicker = false
    @State private var pickedDate = Date()

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
        HStack(alignment: .top, spacing: Tokens.Spacing.xs) {
            Button(action: toggle) {
                Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 23, weight: .light))
                    .foregroundStyle(reminder.isCompleted ? Tokens.Colors.accent : Tokens.Colors.faint)
                    .frame(width: Tokens.Layout.control, height: Tokens.Layout.control)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(reminder.isCompleted ? "Reopen reminder" : "Complete reminder")
            Button(action: onTap) {
                HStack(alignment: .top, spacing: Tokens.Spacing.md) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: Tokens.Spacing.xs) {
                            if reminder.priority == .high && !reminder.isCompleted {
                                Text("!!")
                                    .font(.system(size: 14, weight: .bold))
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
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(Tokens.Colors.quiet)
                                .lineLimit(1)
                        }
                        if let detail {
                            HStack(spacing: Tokens.Spacing.xs) {
                                Text(detail)
                                if reminder.locationAlarm != nil {
                                    Image(systemName: "mappin")
                                }
                            }
                            .font(Tokens.Typo.caption)
                            .foregroundStyle(isLate ? Tokens.Colors.overdue : Tokens.Colors.quiet)
                        }
                    }

                    Spacer(minLength: Tokens.Spacing.sm)
                }
                .padding(.vertical, Tokens.Spacing.sm)
                .frame(minHeight: Tokens.Layout.control, alignment: .center)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(Tokens.Spacing.sm)
        .padding(.trailing, Tokens.Spacing.sm)
        // Right: the one action worth a thoughtless flick.
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button(action: toggle) {
                Label(reminder.isCompleted ? "Reopen" : "Done", systemImage: "checkmark")
            }
            .tint(Tokens.Colors.hueDone)
        }
        // Left: rescheduling, filing, removing — everything that needs a beat
        // of thought, with the rarer choices behind the menu.
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                snooze(to: Snooze.tomorrow())
            } label: {
                Label("Tomorrow", systemImage: "sun.horizon")
            }
            .tint(Tokens.Colors.hueTask)

            Button {
                snooze(to: Snooze.nextWeek())
            } label: {
                Label("Next week", systemImage: "calendar")
            }
            .tint(Tokens.Colors.hueTravel)

            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            Button("Later today", systemImage: "clock") { snooze(to: Snooze.laterToday()) }
            Button("Tomorrow", systemImage: "sun.horizon") { snooze(to: Snooze.tomorrow()) }
            Button("This weekend", systemImage: "beach.umbrella") { snooze(to: Snooze.thisWeekend()) }
            Button("Next week", systemImage: "calendar") { snooze(to: Snooze.nextWeek()) }
            Button("Pick a date…", systemImage: "calendar.badge.clock") {
                pickedDate = reminder.dueDate ?? Snooze.tomorrow()
                showingDatePicker = true
            }
            if !lists.isEmpty {
                Divider()
                Menu("Move to", systemImage: "folder") {
                    ForEach(lists) { list in
                        Button(list.title) { onMove(list) }
                            .disabled(list.id == reminder.listID)
                    }
                }
            }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
        }
        .sheet(isPresented: $showingDatePicker) {
            NavigationStack {
                DatePicker("Due", selection: $pickedDate)
                    .datePickerStyle(.graphical)
                    .padding(Tokens.Spacing.lg)
                    .navigationTitle("Pick a date")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showingDatePicker = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Set") {
                                snooze(to: pickedDate, withTime: true)
                                showingDatePicker = false
                            }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func toggle() {
        withAnimation(Tokens.Anim.content) {
            context.setCompleted(reminder, !reminder.isCompleted)
        }
        try? context.save()
        Task { await ReminderSyncService.syncNow(context: context) }
    }

    /// Moves the due date without touching anything else. An item with no due
    /// date gains one — snoozing an undated reminder is how it gets scheduled.
    private func snooze(to date: Date, withTime: Bool? = nil) {
        withAnimation(Tokens.Anim.content) {
            reminder.dueDate = date
            reminder.hasTime = withTime ?? reminder.hasTime
            reminder.modifiedAt = Date()
        }
        try? context.save()
        Task { await ReminderSyncService.syncNow(context: context) }
    }
}

/// Where the snooze presets land. Kept together so Today, the notch and this
/// row can never disagree about what "tomorrow" means.
enum Snooze {
    static func laterToday(from now: Date = Date()) -> Date {
        now.addingTimeInterval(3 * 3600)
    }

    /// Tomorrow at 9am — a date, not "24 hours from now".
    static func tomorrow(from now: Date = Date()) -> Date {
        let calendar = Calendar.current
        let next = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: next) ?? next
    }

    /// The coming Saturday at 9am; if it is already the weekend, the next one.
    static func thisWeekend(from now: Date = Date()) -> Date {
        let calendar = Calendar.current
        let saturday = calendar.nextDate(
            after: now,
            matching: DateComponents(hour: 9, weekday: 7),
            matchingPolicy: .nextTime
        )
        return saturday ?? tomorrow(from: now)
    }

    /// The coming Monday at 9am.
    static func nextWeek(from now: Date = Date()) -> Date {
        let calendar = Calendar.current
        let monday = calendar.nextDate(
            after: now,
            matching: DateComponents(hour: 9, weekday: 2),
            matchingPolicy: .nextTime
        )
        return monday ?? tomorrow(from: now)
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
