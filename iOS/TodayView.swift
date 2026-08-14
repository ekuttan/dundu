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
    @State private var showingNewSheet = false
    @State private var showingVoiceCapture = false
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
        .background(Tokens.Colors.paper)
        .sheet(item: $editingReminder) { ReminderEditView(existing: $0) }
        .sheet(item: $editingEvent) { EventEditView(event: $0) }
        .sheet(isPresented: $showingNewSheet) { ReminderEditView(existing: nil) }
        .sheet(isPresented: $showingVoiceCapture) { VoiceCaptureView() }
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
                onToggle: toggle
            )
            .frame(maxHeight: .infinity)

            if isToday {
                clock(now: now)
            }

            tray
        }
        .padding(.bottom, Tokens.Spacing.md)
    }

    /// Header doubles as the day pager: the date in the middle, a day either
    /// side. Returning to today is a tap on the date itself.
    private func dayHeader(now: Date) -> some View {
        HStack(spacing: Tokens.Spacing.sm) {
            pagerButton("chevron.left") { step(-1) }
            Spacer(minLength: 0)
            Button {
                withAnimation(Tokens.Anim.content) { dayOffset = 0 }
            } label: {
                VStack(spacing: 1) {
                    Text(Self.headerDate(shownDate(now: now)))
                        .font(Tokens.Typo.screenTitle)
                        .foregroundStyle(Tokens.Colors.ink)
                    Text(Self.headerWeekday(shownDate(now: now), offset: dayOffset))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(dayOffset == 0 ? Tokens.Colors.quiet : Tokens.Colors.accent)
                }
            }
            .buttonStyle(PressableStyle())
            Spacer(minLength: 0)
            pagerButton("chevron.right") { step(1) }
        }
        .padding(.horizontal, Tokens.Spacing.xl)
        .padding(.vertical, Tokens.Spacing.md)
    }

    private func pagerButton(_ glyph: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: glyph)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Tokens.Colors.ink)
                .frame(width: 40, height: 40)
                .background(Circle().stroke(Tokens.Colors.hairline, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
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

    private static func headerDate(_ now: Date) -> String {
        now.formatted(.dateTime.month(.abbreviated).day())
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
                .font(Tokens.Typo.clock())
                .foregroundStyle(Tokens.Colors.ink)
            Text(Self.meridiem(now))
                .font(Tokens.Typo.clockSuffix)
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
                                .padding(.horizontal, Tokens.Spacing.md)
                                .padding(.vertical, Tokens.Spacing.sm + 2)
                                .background {
                                    RoundedRectangle(cornerRadius: Tokens.Radius.chip, style: .continuous)
                                        .stroke(Tokens.Colors.hairline, lineWidth: 1)
                                }
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .padding(.horizontal, Tokens.Spacing.xl)
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
                .padding(Tokens.Spacing.xl)
            }
            .background(Tokens.Colors.paper)
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
                        .font(.system(size: 12, weight: .semibold))
                    Text("Apple Reminders sync is off — tap to allow")
                        .font(Tokens.Typo.label)
                    Spacer()
                }
                .foregroundStyle(Tokens.Colors.dueSoon)
                .padding(.horizontal, Tokens.Spacing.md)
                .padding(.vertical, Tokens.Spacing.sm)
                .background {
                    RoundedRectangle(cornerRadius: Tokens.Radius.chip, style: .continuous)
                        .fill(Tokens.Colors.blockFill(Tokens.Colors.dueSoon))
                }
                .padding(.horizontal, Tokens.Spacing.xl)
            }
            .buttonStyle(PressableStyle())
        }
    }

    // MARK: - Mutations

    private func open(_ entry: TimelineEntry) {
        if let reminder = reminders.first(where: { $0.id == entry.id }) {
            editingReminder = reminder
        } else if let event = events.first(where: { $0.id == entry.id }) {
            editingEvent = event
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
