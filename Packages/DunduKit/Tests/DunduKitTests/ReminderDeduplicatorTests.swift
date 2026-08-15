import Foundation
import Testing
@testable import DunduKit

@Suite("Duplicate reminders")
struct ReminderDeduplicatorTests {
    private func candidate(
        externalID: String? = nil,
        title: String = "Brush",
        listID: UUID? = nil,
        due: Date? = nil,
        completed: Bool = false,
        modified: TimeInterval = 0,
        created: TimeInterval = 0
    ) -> ReminderDeduplicator.Candidate {
        ReminderDeduplicator.Candidate(
            localID: UUID(),
            externalID: externalID,
            title: title,
            listID: listID,
            dueDate: due,
            isCompleted: completed,
            modifiedAt: Date(timeIntervalSince1970: modified),
            createdAt: Date(timeIntervalSince1970: created)
        )
    }

    /// The two-devices-one-EKReminder case: each Mac and phone minted its own
    /// local record for the same remote reminder.
    @Test func sameExternalIDCollapsesToOne() {
        let old = candidate(externalID: "ek-1", modified: 100, created: 10)
        let new = candidate(externalID: "ek-1", modified: 200, created: 50)
        let resolutions = ReminderDeduplicator.resolve([old, new])

        #expect(resolutions.count == 1)
        #expect(resolutions[0].keep == new.localID)
        #expect(resolutions[0].drop == [old.localID])
    }

    @Test func identicalContentCollapsesEvenWithoutAnExternalID() {
        let list = UUID()
        let due = Date(timeIntervalSince1970: 900_000)
        let first = candidate(title: "Brush", listID: list, due: due, modified: 100, created: 10)
        let second = candidate(title: "Brush", listID: list, due: due, modified: 90, created: 20)
        let resolutions = ReminderDeduplicator.resolve([first, second])

        #expect(resolutions.count == 1)
        #expect(resolutions[0].keep == first.localID)
    }

    @Test func titlesMatchIgnoringCaseAndSurroundingSpace() {
        let list = UUID()
        let a = candidate(title: "Shoe clearner", listID: list, modified: 10)
        let b = candidate(title: "  shoe CLEARNER ", listID: list, modified: 20)
        #expect(ReminderDeduplicator.resolve([a, b]).count == 1)
    }

    /// Losing a completion is worse than re-opening something, so the done
    /// copy wins even when the open one was touched more recently.
    @Test func completedCopyWinsOverAnOpenOne() {
        let done = candidate(externalID: "ek-2", completed: true, modified: 100)
        let open = candidate(externalID: "ek-2", completed: false, modified: 500)
        let resolutions = ReminderDeduplicator.resolve([done, open])

        #expect(resolutions[0].keep == done.localID)
        #expect(resolutions[0].drop == [open.localID])
    }

    @Test func sameTitleInDifferentListsIsNotADuplicate() {
        let a = candidate(title: "Brush", listID: UUID())
        let b = candidate(title: "Brush", listID: UUID())
        #expect(ReminderDeduplicator.resolve([a, b]).isEmpty)
    }

    @Test func sameTitleAtDifferentTimesIsNotADuplicate() {
        let list = UUID()
        let a = candidate(title: "Brush", listID: list, due: Date(timeIntervalSince1970: 0))
        let b = candidate(title: "Brush", listID: list, due: Date(timeIntervalSince1970: 7200))
        #expect(ReminderDeduplicator.resolve([a, b]).isEmpty)
    }

    /// Sub-second drift through EventKit must not make two copies look
    /// distinct, so due dates are compared to the minute.
    @Test func subSecondDriftStillCounts() {
        let list = UUID()
        let a = candidate(title: "Brush", listID: list, due: Date(timeIntervalSince1970: 600.2))
        let b = candidate(title: "Brush", listID: list, due: Date(timeIntervalSince1970: 600.9))
        #expect(ReminderDeduplicator.resolve([a, b]).count == 1)
    }

    @Test func threeCopiesLeaveOneWinnerAndTwoDrops() {
        let group = (0..<3).map { candidate(externalID: "ek-3", modified: Double($0) * 100) }
        let resolutions = ReminderDeduplicator.resolve(group)

        #expect(resolutions.count == 1)
        #expect(resolutions[0].drop.count == 2)
        #expect(resolutions[0].keep == group[2].localID)
    }

    /// An item already matched by external ID must not be pulled into a
    /// second, content-based group as well.
    @Test func externalMatchesAreNotReconsideredByContent() {
        let list = UUID()
        let a = candidate(externalID: "ek-4", title: "Brush", listID: list, modified: 100)
        let b = candidate(externalID: "ek-4", title: "Brush", listID: list, modified: 200)
        let resolutions = ReminderDeduplicator.resolve([a, b])
        #expect(resolutions.count == 1)
        #expect(resolutions.flatMap(\.drop).count == 1)
    }

    @Test func uniqueItemsProduceNoResolutions() {
        let items = [
            candidate(externalID: "ek-5", title: "One"),
            candidate(externalID: "ek-6", title: "Two"),
            candidate(title: "Three"),
        ]
        #expect(ReminderDeduplicator.resolve(items).isEmpty)
    }
}

// MARK: - Regressions

/// These cover the failure that tombstoned 222 completed reminders on a live
/// store: a weekly chore is many completed rows sharing a title, a list and
/// no due date, which the first content pass read as one item duplicated.
@Suite("Duplicate reminders — history is not duplication")
struct ReminderDeduplicatorHistoryTests {
    private func done(_ title: String, list: UUID, created: TimeInterval) -> ReminderDeduplicator.Candidate {
        ReminderDeduplicator.Candidate(
            localID: UUID(), externalID: nil, title: title, listID: list,
            dueDate: nil, isCompleted: true,
            modifiedAt: Date(timeIntervalSince1970: created),
            createdAt: Date(timeIntervalSince1970: created)
        )
    }

    @Test func repeatedCompletionsOfTheSameChoreAreNeverCollapsed() {
        let list = UUID()
        let weeks = (0..<12).map { done("Brush", list: list, created: Double($0) * 604_800) }
        #expect(ReminderDeduplicator.resolve(weeks).isEmpty)
    }

    @Test func aCompletedItemIsNeverMergedIntoAnOpenOneByContent() {
        let list = UUID()
        let finished = done("Brush", list: list, created: 0)
        let fresh = ReminderDeduplicator.Candidate(
            localID: UUID(), externalID: nil, title: "Brush", listID: list,
            dueDate: nil, isCompleted: false,
            modifiedAt: Date(timeIntervalSince1970: 1_000_000),
            createdAt: Date(timeIntervalSince1970: 1_000_000)
        )
        #expect(ReminderDeduplicator.resolve([finished, fresh]).isEmpty)
    }

    /// Undated copies only count when they appeared together — that is the
    /// CloudKit/EventKit race. Added weeks apart, they are two real tasks.
    @Test func undatedCopiesCreatedFarApartAreLeftAlone() {
        let list = UUID()
        let january = ReminderDeduplicator.Candidate(
            localID: UUID(), externalID: nil, title: "Brush", listID: list,
            dueDate: nil, isCompleted: false,
            modifiedAt: Date(timeIntervalSince1970: 0), createdAt: Date(timeIntervalSince1970: 0)
        )
        let march = ReminderDeduplicator.Candidate(
            localID: UUID(), externalID: nil, title: "Brush", listID: list,
            dueDate: nil, isCompleted: false,
            modifiedAt: Date(timeIntervalSince1970: 5_000_000),
            createdAt: Date(timeIntervalSince1970: 5_000_000)
        )
        #expect(ReminderDeduplicator.resolve([january, march]).isEmpty)
    }

    @Test func undatedCopiesFromTheSameSyncStillCollapse() {
        let list = UUID()
        let first = ReminderDeduplicator.Candidate(
            localID: UUID(), externalID: nil, title: "Brush", listID: list,
            dueDate: nil, isCompleted: false,
            modifiedAt: Date(timeIntervalSince1970: 100), createdAt: Date(timeIntervalSince1970: 100)
        )
        let echo = ReminderDeduplicator.Candidate(
            localID: UUID(), externalID: nil, title: "Brush", listID: list,
            dueDate: nil, isCompleted: false,
            modifiedAt: Date(timeIntervalSince1970: 130), createdAt: Date(timeIntervalSince1970: 130)
        )
        #expect(ReminderDeduplicator.resolve([first, echo]).count == 1)
    }
}
