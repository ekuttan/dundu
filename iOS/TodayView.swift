import SwiftUI
import SwiftData
import DunduKit

/// Today: the day as a timeline, the current moment in large type, and a
/// tray for everything that has no place on a clock.
///
/// The timeline only holds things that happen *at* a time. Reminders without
/// one — most of them — would either crowd the top of the day or vanish, so
/// they live in the tray under the clock where they stay one tap away.
struct TodayView: View {
    /// Home surface for the Inbox: the header's one accent, never a modal.
    var inboxCount: Int = 0
    var onOpenInbox: () -> Void = {}

    @Environment(\.modelContext) private var context
    @Query(
        filter: #Predicate<ReminderItem> { $0.tombstonedAt == nil },
        sort: \ReminderItem.dueDate
    ) private var reminders: [ReminderItem]
    @Query(
        filter: #Predicate<CalendarEvent> { $0.tombstonedAt == nil },
        sort: \CalendarEvent.startAt
    ) private var events: [CalendarEvent]

    @State private var editingReminder: ReminderItem?
    @State private var editingEvent: CalendarEvent?
    @State private var showingAllUnscheduled = false
    /// Days from today. The timeline, tray and clock all follow it.
    @State private var dayOffset = 0

    var body: some View {
        // One clock drives the NOW rule and the big readout. Half a minute is
        // as fine as either needs, and keeps the timeline from re-laying out
        // every second.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            content(now: context.date)
        }
        .background(Tokens.Colors.ground)
        .sheet(item: $editingReminder) { ReminderEditView(existing: $0) }
        .sheet(item: $editingEvent) { EventEditView(event: $0) }
        .sheet(isPresented: $showingAllUnscheduled) { unscheduledSheet }
    }

    private func content(now: Date) -> some View {
        VStack(spacing: 0) {
            dayHeader(now: now)

            deniedBanner

            DayTimeline(
                entries: timelineEntries(now: now),
                now: shownDate(now: now),
                isToday: isToday,
                onTap: open,
                onToggle: toggle,
                onEdit: edit
            )
            .frame(maxHeight: .infinity)
            .padding(.horizontal, Tokens.Layout.gutter)

            if isToday {
                clock(now: now)
            }

            tray
        }
        // Clears the floating bar: this screen doesn't scroll as a whole, so
        // the tray has to stop above it.
        .padding(.bottom, Tokens.Layout.barInset - Tokens.Spacing.lg)
    }

    /// Header doubles as the day pager: the day in large type on the left,
    /// a step either way on the right, and a way back to today that only
    /// appears once you have left it.
    private func dayHeader(now: Date) -> some View {
        ScreenHeader(
            title: Self.headerWeekday(shownDate(now: now), offset: dayOffset),
            subtitle: Self.headerDate(shownDate(now: now))
        ) {
            HStack(spacing: Tokens.Spacing.sm) {
                // Only offered when it does something — on today it would be
                // a button that visibly changes nothing.
                if dayOffset != 0 {
                    Button {
                        withAnimation(Tokens.Anim.content) { dayOffset = 0 }
                    } label: {
                        Text("Today")
                            .font(Tokens.Typo.label)
                            .foregroundStyle(Tokens.Colors.accent)
                            .padding(.horizontal, Tokens.Spacing.md)
                            .padding(.vertical, 9)
                            .background {
                                Capsule().fill(Tokens.Colors.blockFill(Tokens.Colors.accent))
                            }
                    }
                    .buttonStyle(PressableStyle())
                }
                CircleButton(glyph: "chevron.left") { step(-1) }
                CircleButton(glyph: "chevron.right") { step(1) }
            }
        }
    }

    private func step(_ days: Int) {
        withAnimation(Tokens.Anim.content) { dayOffset += days }
    }

    private var isToday: Bool { dayOffset == 0 }

    private func shownDate(now: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: dayOffset, to: now) ?? now
    }

    private static func headerWeekday(_ date: Date, offset: Int) -> String {
        switch offset {
        case 0: "Today"
        case 1: "Tomorrow"
        case -1: "Yesterday"
        default: date.formatted(.dateTime.weekday(.wide))
        }
    }

    /// Under the big "Today" the full date has room to spell itself out.
    private static func headerDate(_ now: Date) -> String {
        now.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    /// `.dateTime.hour(.defaultDigits)` pads to "04:15"; the reference reads
    /// "2:40". The localised template gives the unpadded hour, and the
    /// meridiem comes out because it is drawn separately at a smaller size.
    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("jmm")
        formatter.dateFormat = formatter.dateFormat?
            .replacingOccurrences(of: "a", with: "")
            .trimmingCharacters(in: .whitespaces)
        return formatter
    }()

    /// Locales on a 24-hour clock have no meridiem, so the suffix disappears
    /// there rather than printing an empty box next to the time.
    private static func meridiem(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("j")
        guard formatter.dateFormat?.contains("a") == true else { return "" }
        formatter.dateFormat = "a"
        return formatter.string(from: date)
    }

    // MARK: - Clock

    private func clock(now: Date) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 2) {
            Text(Self.clockFormatter.string(from: now))
                .font(Tokens.Typo.clock(44))
                .foregroundStyle(Tokens.Colors.ink)
            Text(Self.meridiem(now))
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Tokens.Colors.ink)
        }
        .monospacedDigit()
        .padding(.top, Tokens.Spacing.lg)
        .accessibilityElement()
        .accessibilityLabel(Text(now.formatted(date: .omitted, time: .shortened)))
    }

    // MARK: - Timeline contents

    private func timelineEntries(now: Date) -> [TimelineEntry] {
        let calendar = Calendar.current
        var entries: [TimelineEntry] = []

        let shown = shownDate(now: now)
        for event in events where calendar.isDate(event.startAt, inSameDayAs: shown) && !event.isAllDay {
            entries.append(
                TimelineEntry(
                    id: event.id,
                    title: event.title,
                    subtitle: event.location,
                    start: event.startAt,
                    end: event.endAt,
                    kind: .event,
                    glyph: event.conferenceURL == nil ? "calendar" : "video",
                    tint: Tokens.Colors.hueMeeting,
                    joinURL: event.conferenceURL
                )
            )
        }

        for reminder in reminders {
            guard let due = reminder.dueDate,
                  reminder.hasTime,
                  calendar.isDate(due, inSameDayAs: shown) else { continue }
            entries.append(
                TimelineEntry(
                    id: reminder.id,
                    title: reminder.title,
                    subtitle: nil,
                    start: due,
                    // An instant, drawn as the half hour it occupies.
                    end: due.addingTimeInterval(30 * 60),
                    kind: .reminder,
                    glyph: reminder.locationAlarm == nil ? "checkmark.circle" : "mappin",
                    tint: reminder.isCompleted
                        ? Tokens.Colors.hueDone
                        : (due < now ? Tokens.Colors.hueUrgent : Tokens.Colors.hueTask),
                    isCompleted: reminder.isCompleted
                )
            )
        }

        return entries
    }

    // MARK: - Tray

    /// Everything with no place on a clock, most pressing first: overdue,
    /// today's untimed items, all-day events, then undated reminders.
    ///
    /// Undated ones have to be here. Leaving them to Lists would mean adding
    /// a reminder from this screen and watching it disappear — the same way
    /// items used to vanish from the Mac menu bar.
    private var trayItems: [TrayItem] {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        var overdue: [TrayItem] = []
        var today: [TrayItem] = []
        var undated: [TrayItem] = []

        for reminder in reminders where !reminder.isCompleted {
            guard let due = reminder.dueDate else {
                undated.append(TrayItem(reminder: reminder, tint: Tokens.Colors.hueTask,
                                        detail: nil))
                continue
            }
            if due < startOfToday {
                overdue.append(TrayItem(reminder: reminder, tint: Tokens.Colors.hueUrgent,
                                        detail: Formatters.relativeTime(to: due)))
            } else if calendar.isDateInToday(due) && !reminder.hasTime {
                today.append(TrayItem(reminder: reminder, tint: Tokens.Colors.hueTask,
                                      detail: "Today"))
            }
        }

        let allDay = events
            .filter { $0.isAllDay && calendar.isDateInToday($0.startAt) }
            .map { TrayItem(event: $0, tint: Tokens.Colors.hueTravel, detail: "All day") }

        // Newest undated first: the one you just added is the one you want to
        // see, and it is the only reason the tray moves under your thumb.
        undated.sort { ($0.reminder?.createdAt ?? .distantPast) > ($1.reminder?.createdAt ?? .distantPast) }

        return overdue + today + allDay + undated
    }

    private struct TrayItem: Identifiable {
        var reminder: ReminderItem?
        var event: CalendarEvent?
        var tint: Color
        var detail: String?

        init(reminder: ReminderItem, tint: Color, detail: String?) {
            self.reminder = reminder; self.tint = tint; self.detail = detail
        }
        init(event: CalendarEvent, tint: Color, detail: String?) {
            self.event = event; self.tint = tint; self.detail = detail
        }

        var id: UUID { reminder?.id ?? event?.id ?? UUID() }
        var title: String { reminder?.title ?? event?.title ?? "" }
    }

    private let trayVisibleLimit = 6

    @ViewBuilder
    private var tray: some View {
        let items = trayItems
        if !items.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Tokens.Spacing.sm) {
                    ForEach(items.prefix(trayVisibleLimit)) { item in
                        TrayChip(
                            title: item.title,
                            detail: item.detail,
                            glyph: item.event == nil ? "circle" : "calendar",
                            tint: item.tint,
                            isCompleted: item.reminder?.isCompleted ?? false,
                            onToggle: item.reminder.map { reminder in
                                { toggleReminder(reminder) }
                            },
                            onTap: {
                                if let reminder = item.reminder { editingReminder = reminder }
                                if let event = item.event { editingEvent = event }
                            }
                        )
                    }
                    if items.count > trayVisibleLimit {
                        Button {
                            showingAllUnscheduled = true
                        } label: {
                            Text("+\(items.count - trayVisibleLimit)")
                                .font(Tokens.Typo.blockTitle)
                                .foregroundStyle(Tokens.Colors.quiet)
                                .padding(.horizontal, Tokens.Spacing.lg)
                                .padding(.vertical, Tokens.Spacing.md)
                                .cardSurface(radius: Tokens.Radius.block)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .padding(.horizontal, Tokens.Layout.gutter)
                .padding(.vertical, Tokens.Spacing.xs)
            }
            .padding(.top, Tokens.Spacing.lg)
        }
    }

    private var unscheduledSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Tokens.Spacing.sm) {
                    ForEach(trayItems) { item in
                        TrayChip(
                            title: item.title,
                            detail: item.detail,
                            glyph: item.event == nil ? "circle" : "calendar",
                            tint: item.tint,
                            isCompleted: item.reminder?.isCompleted ?? false,
                            onToggle: item.reminder.map { reminder in
                                { toggleReminder(reminder) }
                            },
                            onTap: {
                                showingAllUnscheduled = false
                                if let reminder = item.reminder { editingReminder = reminder }
                                if let event = item.event { editingEvent = event }
                            }
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(Tokens.Layout.gutter)
            }
            .background(Tokens.Colors.ground)
            .navigationTitle("Unscheduled")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Actions

    // MARK: - Denied state

    /// A line, not a wall — the app works standalone without Apple sync.
    @ViewBuilder
    private var deniedBanner: some View {
        let status = EventKitBridge.accessStatus()
        if status == .denied || status == .restricted || status == .writeOnly {
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack(spacing: Tokens.Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Apple Reminders sync is off — tap to allow")
                        .font(Tokens.Typo.label)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Tokens.Colors.dueSoon)
                .padding(.horizontal, Tokens.Spacing.lg)
                .padding(.vertical, Tokens.Spacing.md)
                .cardSurface(
                    Tokens.Colors.blockFill(Tokens.Colors.dueSoon),
                    radius: Tokens.Radius.block
                )
                .padding(.horizontal, Tokens.Layout.gutter)
            }
            .buttonStyle(PressableStyle())
        }
    }

    // MARK: - Mutations

    /// A meeting you can join is a thing you join. Tapping it opens the call
    /// rather than a form about the call — the edit sheet is still there on a
    /// long press, where the rarer intent belongs.
    private func open(_ entry: TimelineEntry) {
        if let reminder = reminders.first(where: { $0.id == entry.id }) {
            editingReminder = reminder
        } else if let event = events.first(where: { $0.id == entry.id }) {
            if let url = event.conferenceURL {
                UIApplication.shared.open(url)
            } else {
                editingEvent = event
            }
        }
    }

    private func edit(_ entry: TimelineEntry) {
        if let event = events.first(where: { $0.id == entry.id }) {
            editingEvent = event
        } else if let reminder = reminders.first(where: { $0.id == entry.id }) {
            editingReminder = reminder
        }
    }

    private func toggle(_ entry: TimelineEntry) {
        guard let reminder = reminders.first(where: { $0.id == entry.id }) else { return }
        toggleReminder(reminder)
    }

    private func toggleReminder(_ reminder: ReminderItem) {
        withAnimation(Tokens.Anim.content) {
            context.setCompleted(reminder, !reminder.isCompleted)
        }
        try? context.save()
        Task { await ReminderSyncService.syncNow(context: context) }
    }
}
