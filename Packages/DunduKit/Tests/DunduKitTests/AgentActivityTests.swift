import Foundation
import Testing
@testable import DunduKit

@Suite("Agent transcripts")
struct AgentLogParserTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    // MARK: - Claude Code

    @Test func claudeUsageToolCallsAndModelAreCounted() {
        let lines = [
            #"{"type":"assistant","timestamp":"2026-10-01T09:00:00.000Z","message":{"model":"claude-opus-5","usage":{"input_tokens":100,"output_tokens":20,"cache_read_input_tokens":5000,"cache_creation_input_tokens":300},"content":[{"type":"tool_use"},{"type":"text"}]}}"#,
            #"{"type":"assistant","timestamp":"2026-10-01T09:05:00.000Z","message":{"model":"claude-opus-5","usage":{"input_tokens":50,"output_tokens":10},"content":[{"type":"tool_use"}]}}"#,
        ]
        let digest = AgentLogParser.parseClaudeCode(
            lines: lines, sessionID: "s1", project: "dundu", calendar: calendar
        )

        #expect(digest.inputTokens == 150)
        #expect(digest.outputTokens == 30)
        #expect(digest.toolCalls == 2)
        #expect(digest.messages == 2)
        #expect(digest.topModelIsOpus)
        #expect(digest.activeDays == ["2026-10-01"])
    }

    /// Cache traffic dwarfs real usage. Folding it into the headline number
    /// makes a modest session look like millions of tokens.
    @Test func cacheTokensAreKeptSeparateFromBillable() {
        let lines = [
            #"{"type":"assistant","timestamp":"2026-10-01T09:00:00.000Z","message":{"usage":{"input_tokens":10,"output_tokens":5,"cache_read_input_tokens":900000}}}"#
        ]
        let digest = AgentLogParser.parseClaudeCode(
            lines: lines, sessionID: "s", project: nil, calendar: calendar
        )
        #expect(digest.billableTokens == 15)
        #expect(digest.cachedTokens == 900_000)
    }

    @Test func malformedLinesAreSkippedRatherThanFatal() {
        let lines = ["", "not json at all", "{", #"{"type":"assistant","message":{"usage":{"input_tokens":7}}}"#]
        let digest = AgentLogParser.parseClaudeCode(
            lines: lines, sessionID: "s", project: nil, calendar: calendar
        )
        #expect(digest.inputTokens == 7)
    }

    @Test func aSessionSpanningMidnightCountsOnBothDays() {
        let lines = [
            #"{"type":"assistant","timestamp":"2026-10-01T23:50:00.000Z","message":{"usage":{"input_tokens":1}}}"#,
            #"{"type":"assistant","timestamp":"2026-10-02T00:10:00.000Z","message":{"usage":{"input_tokens":1}}}"#,
        ]
        let digest = AgentLogParser.parseClaudeCode(
            lines: lines, sessionID: "s", project: nil, calendar: calendar
        )
        #expect(digest.activeDays == ["2026-10-01", "2026-10-02"])
    }

    // MARK: - Codex

    /// The format's two token fields are named the opposite way round to how
    /// they behave. Summing `turn_token_usage` — the cumulative one — turned a
    /// 292k-token session into billions on real data.
    @Test func codexTakesTheCumulativeTotalNotTheSumOfIt() {
        let lines = (1...4).map { turn in
            """
            {"type":"token_usage_record","timestamp":"2026-10-01T09:0\(turn):00.000Z","payload":{\
            "usage":{"input_tokens":100,"output_tokens":10},\
            "turn_token_usage":{"input_tokens":\(100 * turn),"output_tokens":\(10 * turn)}}}
            """
        }
        let digest = AgentLogParser.parseCodex(lines: lines, sessionID: "c1", calendar: calendar)

        #expect(digest.inputTokens == 400)
        #expect(digest.outputTokens == 40)
        #expect(digest.messages == 4)
    }

    @Test func codexFallsBackToPerTurnWhenNoCumulativeIsRecorded() {
        let lines = [
            #"{"type":"token_usage_record","payload":{"usage":{"input_tokens":30,"output_tokens":3}}}"#,
            #"{"type":"token_usage_record","payload":{"usage":{"input_tokens":70,"output_tokens":7}}}"#,
        ]
        let digest = AgentLogParser.parseCodex(lines: lines, sessionID: "c", calendar: calendar)
        #expect(digest.inputTokens == 100)
        #expect(digest.outputTokens == 10)
    }

    @Test func codexReadsProjectAndToolCalls() {
        let lines = [
            #"{"type":"session_meta","payload":{"cwd":"/Users/me/Code/dundu"}}"#,
            #"{"type":"response_item","payload":{"type":"function_call"}}"#,
            #"{"type":"response_item","payload":{"type":"local_shell_call"}}"#,
            #"{"type":"response_item","payload":{"type":"message"}}"#,
        ]
        let digest = AgentLogParser.parseCodex(lines: lines, sessionID: "c", calendar: calendar)
        #expect(digest.project == "/Users/me/Code/dundu")
        #expect(digest.toolCalls == 2)
    }
}

private extension SessionDigest {
    var topModelIsOpus: Bool { models["claude-opus-5"] == 2 }
}

@Suite("Activity streaks")
struct ActivityStreakTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func day(_ string: String) -> Date {
        ActivityStreak.date(from: string, calendar: calendar)!
    }

    @Test func consecutiveDaysEndingTodayCount() {
        let days: Set<String> = ["2026-10-04", "2026-10-05", "2026-10-06"]
        let streak = ActivityStreak.compute(days: days, today: day("2026-10-06"), calendar: calendar)
        #expect(streak.current == 3)
        #expect(streak.longest == 3)
    }

    /// A streak that resets the moment you wake up and haven't worked yet
    /// would be a discouraging lie, so today being idle is not a break.
    @Test func anIdleTodayDoesNotBreakYesterdaysStreak() {
        let days: Set<String> = ["2026-10-04", "2026-10-05"]
        let streak = ActivityStreak.compute(days: days, today: day("2026-10-06"), calendar: calendar)
        #expect(streak.current == 2)
    }

    @Test func aTwoDayGapEndsTheStreak() {
        let days: Set<String> = ["2026-10-01", "2026-10-02", "2026-10-06"]
        let streak = ActivityStreak.compute(days: days, today: day("2026-10-06"), calendar: calendar)
        #expect(streak.current == 1)
        #expect(streak.longest == 2)
    }

    @Test func theLongestRunIsFoundAnywhereInHistory() {
        let days: Set<String> = [
            "2026-01-01", "2026-01-02", "2026-01-03", "2026-01-04",
            "2026-09-01",
        ]
        let streak = ActivityStreak.compute(days: days, today: day("2026-10-06"), calendar: calendar)
        #expect(streak.longest == 4)
        #expect(streak.current == 0)
    }

    @Test func noActivityIsZeroNotACrash() {
        let streak = ActivityStreak.compute(days: [], today: day("2026-10-06"), calendar: calendar)
        #expect(streak == (0, 0))
    }

    @Test func monthAndYearBoundariesAreStillConsecutive() {
        let days: Set<String> = ["2025-12-30", "2025-12-31", "2026-01-01"]
        let streak = ActivityStreak.compute(days: days, today: day("2026-01-01"), calendar: calendar)
        #expect(streak.current == 3)
    }
}
