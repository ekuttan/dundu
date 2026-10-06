import Foundation
import Testing
@testable import DunduKit

@Suite("Live agent sessions")
struct AgentSessionTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func session(
        _ id: String,
        _ state: AgentSessionState,
        ago: TimeInterval = 0,
        project: String? = nil
    ) -> AgentSession {
        AgentSession(
            id: id, tool: .claudeCode, state: state,
            project: project, task: "do the thing",
            updatedAt: now.addingTimeInterval(-ago)
        )
    }

    // MARK: - What is on screen

    /// Waiting is the only state that asks something of you, so it leads.
    @Test func sessionsWaitingOnYouComeFirst() {
        let visible = AgentSessionReader.visible([
            session("a", .working),
            session("b", .done),
            session("c", .waiting),
        ], now: now)
        #expect(visible.map(\.id) == ["c", "a", "b"])
    }

    @Test func withinAStateTheMostRecentLeads() {
        let visible = AgentSessionReader.visible([
            session("old", .working, ago: 600),
            session("new", .working, ago: 10),
        ], now: now)
        #expect(visible.map(\.id) == ["new", "old"])
    }

    /// A lid closed mid-task leaves "working" behind with no Stop hook ever
    /// running. Those must age out or the list becomes a graveyard.
    @Test func aWorkingSessionAbandonedHoursAgoIsDropped() {
        let visible = AgentSessionReader.visible([
            session("ghost", .working, ago: AgentSessionReader.staleAfter + 60),
            session("live", .working, ago: 30),
        ], now: now)
        #expect(visible.map(\.id) == ["live"])
    }

    @Test func finishedSessionsLingerBrieflyThenGo() {
        let visible = AgentSessionReader.visible([
            session("recent", .done, ago: 60),
            session("yesterday", .done, ago: AgentSessionReader.keepDoneFor + 60),
        ], now: now)
        #expect(visible.map(\.id) == ["recent"])
    }

    // MARK: - Alerts

    @Test func finishingIsWorthAnAlert() {
        let alerts = AgentSessionReader.alerts(
            previous: [session("a", .working)],
            current: [session("a", .done)]
        )
        #expect(alerts.map(\.id) == ["a"])
    }

    @Test func needingInputIsWorthAnAlert() {
        let alerts = AgentSessionReader.alerts(
            previous: [session("a", .working)],
            current: [session("a", .waiting)]
        )
        #expect(alerts.map(\.id) == ["a"])
    }

    /// The alert is the transition, not the state. Re-reading the same file
    /// must not fire the notification again.
    @Test func aSessionAlreadyWaitingDoesNotAlertTwice() {
        let alerts = AgentSessionReader.alerts(
            previous: [session("a", .waiting)],
            current: [session("a", .waiting)]
        )
        #expect(alerts.isEmpty)
    }

    @Test func startingWorkIsNotAnAlert() {
        let alerts = AgentSessionReader.alerts(
            previous: [],
            current: [session("a", .working)]
        )
        #expect(alerts.isEmpty)
    }

    /// A session Dundu has never seen that arrives already finished still
    /// counts — the hook may have landed between two reads.
    @Test func anUnseenSessionThatIsAlreadyDoneStillAlerts() {
        let alerts = AgentSessionReader.alerts(
            previous: [],
            current: [session("a", .done)]
        )
        #expect(alerts.map(\.id) == ["a"])
    }

    // MARK: - Parsing

    @Test func aStatusFileFromTheHookDecodes() {
        let json = """
        {"id":"abc-123","tool":"claudeCode","state":"waiting",
         "project":"/Users/me/Code/dundu","task":"Fix the notch",
         "updatedAt":"2026-10-07T09:30:00Z"}
        """
        let parsed = AgentSessionReader.session(from: Data(json.utf8))
        #expect(parsed?.id == "abc-123")
        #expect(parsed?.state == .waiting)
        #expect(parsed?.projectName == "dundu")
    }

    @Test func rubbishOnDiskIsIgnoredRatherThanFatal() {
        #expect(AgentSessionReader.session(from: Data("{ half written".utf8)) == nil)
    }
}
