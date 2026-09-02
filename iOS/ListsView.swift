import SwiftUI
import SwiftData
import DunduKit

/// Every open reminder, on one screen, grouped by the list it belongs to.
///
/// Lists used to be the screen and reminders lived a tap inside them. That is
/// backwards: the reminders are the content, the lists are just how they're
/// filed. The filter row narrows to one list without hiding anything, and no
/// row is tinted — the only colour on the screen is the selected filter chip
/// and red text for something that is late.
struct ListsView: View {
    /// Collapses the bar while the user is reading.
    var barChrome: BarChrome?
    /// Settings is a sheet, opened from this screen's header — it isn't a
    /// destination worth a quarter of the tab bar.
    var onOpenSettings: () -> Void = {}

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
    /// The list a dragged reminder is currently hovering over.
    @State private var dropTargetID: UUID?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search and settings: the two things you reach for from the
                // top of a screen. Adding and recording live in the corner
                // stack on the tab bar instead.
                ScreenHeader(title: Greeting.now(), subtitle: countLabel) {
                    HStack(spacing: Tokens.Spacing.sm) {
                        CircleButton(glyph: searching ? "xmark" : "magnifyingglass") {
                            withAnimation(Tokens.Anim.content) {
                                searching.toggle()
                                if !searching { searchText = "" }
                            }
                        }
                        CircleButton(glyph: "gearshape", action: onOpenSettings)
                    }
                }

                if searching {
                    searchField
                }

                if lists.count > 1 {
                    filterRow
                }

                // A real List, not a LazyVStack: `.swipeActions` is inert
                // outside one, and a hand-rolled drag gesture would forfeit
                // full-swipe, haptics and the system's own spring.
                List {
                    ScrollProbe().plainRow()
                    if visibleReminders.isEmpty {
                        QuietEmptyState(
                            glyph: searchText.isEmpty ? "checkmark.circle" : "magnifyingglass",
                            title: searchText.isEmpty ? "All clear" : "Nothing matches",
                            message: searchText.isEmpty && reminders.isEmpty
                                ? "Reminders appear after the first sync with Apple Reminders."
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
                                .plainRow()
                                .draggable(reminder.id.uuidString) {
                                    Text(reminder.title)
                                        .font(Tokens.Typo.blockTitle)
                                        .padding(Tokens.Spacing.sm)
                                                            }
                            }
                        } header: {
                            if selectedListID == nil, let list = group.list {
                                groupHeader(list, count: group.items.count)
                                    .plainRow(inset: false)
                            }
                        }
                    }

                    if !completed.isEmpty {
                        completedSection
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 1)
                .clearsFloatingBar()
                .tracksScroll(barChrome)
            }
            .background(Tokens.Colors.ground)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $editingReminder) { ReminderEditView(existing: $0) }
            .sheet(isPresented: $showingNew) {
                ReminderEditView(existing: nil, preferredListID: selectedListID)
            }
        }
    }

    /// The system's search field, in the app's own materials: a soft filled
    /// capsule rather than an outline.
    private var searchField: some View {
        HStack(spacing: Tokens.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Tokens.Colors.quiet)
            TextField("Search titles and notes", text: $searchText)
                .font(Tokens.Typo.body)
                .focused($searchFocused)
                .submitLabel(.search)
        }
        .padding(.horizontal, Tokens.Spacing.md)
        .padding(.vertical, Tokens.Spacing.md)
        .background { Capsule().fill(Tokens.Colors.fill) }
        .padding(.horizontal, Tokens.Layout.gutter)
        .padding(.bottom, Tokens.Spacing.md)
        .onAppear { searchFocused = true }
    }

    // MARK: - Filter

    /// A segmented row of soft capsules. The list's colour used to ride in
    /// front of the name as a dot, which read as debris at this size — the
    /// selected capsule now carries the colour itself, and the unselected
    /// ones carry none at all.
    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Tokens.Spacing.sm) {
                filterChip(title: "All", tint: nil, id: nil)
                ForEach(lists) { list in
                    filterChip(
                        title: list.title,
                        tint: Color(hex: list.colorHex),
                        id: list.id
                    )
                }
            }
            .padding(.horizontal, Tokens.Layout.gutter)
            .padding(.bottom, Tokens.Spacing.md)
        }
    }

    private func filterChip(title: String, tint: Color?, id: UUID?) -> some View {
        let isOn = selectedListID == id
        let colour = tint ?? Tokens.Colors.ink
        return Button {
            withAnimation(Tokens.Anim.content) {
                selectedListID = isOn ? nil : id
            }
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isOn ? colour : Tokens.Colors.quiet)
                .padding(.horizontal, Tokens.Spacing.md + 2)
                .padding(.vertical, 8)
                .background {
                    Capsule().fill(
                        isOn ? Tokens.Colors.blockFill(colour) : Tokens.Colors.fill
                    )
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
        .padding(.horizontal, Tokens.Layout.gutter)
        .padding(.top, Tokens.Spacing.lg)
        .padding(.bottom, Tokens.Spacing.sm)
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
                        .plainRow()
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
                .padding(.horizontal, Tokens.Layout.gutter)
                .padding(.top, Tokens.Spacing.lg)
                .padding(.bottom, Tokens.Spacing.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .plainRow(inset: false)
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

/// A reminder as its own card: a check, the title, and — only when there is
/// one — a due date. Separators are gone; each item is a white block on the
/// grey ground, which is what the current system apps do and what makes a
/// half-swiped row read as a card being pulled aside.
///
/// Tall enough to be a comfortable target, which matters more here than
/// elsewhere: both swipe directions are live, so a short row makes it easy to
/// start a swipe when you meant to tap.
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
            .padding(.horizontal, Tokens.Layout.gutter)
            .padding(.vertical, Tokens.Spacing.md + 2)
            .frame(minHeight: 62)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
