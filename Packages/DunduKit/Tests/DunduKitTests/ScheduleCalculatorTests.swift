import Foundation
import Testing
@testable import DunduKit

private struct Fixture: Schedulable {
    var scheduleID = UUID()
    var scheduleTitle: String
    var scheduleDate: Date?
    var scheduleIsAllDay = false
    var scheduleIsDone = false
}

@Suite("Schedule calculation")
struct ScheduleCalculatorTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func nextFirePicksEarliestAcrossKinds() {
        let reminder = Fixture(scheduleTitle: "Send the deck", scheduleDate: now.addingTimeInterval(1200))
        // Starts at +1000s, but the 5-minute lead time makes it fire at +700s,
        // before the reminder at +1200s.
        let meeting = Fixture(scheduleTitle: "Investor call", scheduleDate: now.addingTimeInterval(1000))

        let fire = ScheduleCalculator.nextFire(reminders: [reminder], events: [meeting], now: now)
        #expect(fire?.date == now.addingTimeInterval(700))
        guard case .meetingSoon(_, let title, let startsAt) = fire?.reason else {
            Issue.record("Expected a meeting peek")
            return
        }
        #expect(title == "Investor call")
        #expect(startsAt == now.addingTimeInterval(1000))
    }

    @Test func completedAndAllDayItemsNeverFire() {
        var done = Fixture(scheduleTitle: "Done", scheduleDate: now.addingTimeInterval(600))
        done.scheduleIsDone = true
        var allDay = Fixture(scheduleTitle: "All day", scheduleDate: now.addingTimeInterval(600))
        allDay.scheduleIsAllDay = true

        let fire = ScheduleCalculator.nextFire(reminders: [done, allDay], events: [], now: now)
        #expect(fire == nil)
    }

    @Test func pastDatesDoNotSchedule() {
        let overdue = Fixture(scheduleTitle: "Overdue", scheduleDate: now.addingTimeInterval(-600))
        let fire = ScheduleCalculator.nextFire(reminders: [overdue], events: [], now: now)
        #expect(fire == nil)
    }

    @Test func dueRemindersSortMostOverdueFirst() {
        let a = Fixture(scheduleTitle: "A", scheduleDate: now.addingTimeInterval(-600))
        let b = Fixture(scheduleTitle: "B", scheduleDate: now.addingTimeInterval(-6000))
        let future = Fixture(scheduleTitle: "Future", scheduleDate: now.addingTimeInterval(600))
        let unscheduled = Fixture(scheduleTitle: "Unscheduled", scheduleDate: nil)

        let due = ScheduleCalculator.dueReminders([a, b, future, unscheduled], now: now)
        #expect(due.map(\.scheduleTitle) == ["B", "A"])
    }

    @Test func customMeetingLeadTime() {
        let meeting = Fixture(scheduleTitle: "Standup", scheduleDate: now.addingTimeInterval(1500))
        let fire = ScheduleCalculator.nextFire(
            reminders: [], events: [meeting], meetingLeadTime: 60, now: now
        )
        #expect(fire?.date == now.addingTimeInterval(1440))
    }
}
