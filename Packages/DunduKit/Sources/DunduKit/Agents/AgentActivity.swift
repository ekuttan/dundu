import Foundation

/// The AI coding tools Dundu can report on. Each keeps a transcript of its own
/// work on this Mac; none of it leaves the machine, and none of it is prompt
/// text — only counts, models and timestamps.
public enum AgentTool: String, Sendable, Codable, CaseIterable {
    case claudeCode
    case codex

    public var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        }
    }

    public var glyph: String {
        switch self {
        case .claudeCode: "sparkle"
        case .codex: "chevron.left.forwardslash.chevron.right"
        }
    }
}

/// What one session file contributes. Digests are cached per file so a scan
/// only has to read what changed — the transcripts run to gigabytes and are
/// append-only, so re-reading them all on every refresh is not an option.
public struct SessionDigest: Sendable, Codable, Equatable {
    public var sessionID: String
    public var tool: AgentTool
    /// Working directory or project slug, for grouping by what was worked on.
    public var project: String?
    public var inputTokens: Int
    public var outputTokens: Int
    /// Cache reads and writes, kept apart: they dominate the raw totals and
    /// counting them as ordinary usage makes every number look absurd.
    public var cachedTokens: Int
    public var toolCalls: Int
    public var messages: Int
    /// Model identifier to the number of messages it produced.
    public var models: [String: Int]
    public var firstActivity: Date?
    public var lastActivity: Date?
    /// Days this session was active, as yyyy-MM-dd in the local calendar.
    public var activeDays: Set<String>

    public init(
        sessionID: String,
        tool: AgentTool,
        project: String? = nil,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        cachedTokens: Int = 0,
        toolCalls: Int = 0,
        messages: Int = 0,
        models: [String: Int] = [:],
        firstActivity: Date? = nil,
        lastActivity: Date? = nil,
        activeDays: Set<String> = []
    ) {
        self.sessionID = sessionID
        self.tool = tool
        self.project = project
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cachedTokens = cachedTokens
        self.toolCalls = toolCalls
        self.messages = messages
        self.models = models
        self.firstActivity = firstActivity
        self.lastActivity = lastActivity
        self.activeDays = activeDays
    }

    /// What the user did, excluding cache traffic they never asked for.
    public var billableTokens: Int { inputTokens + outputTokens }
}

/// One tool's whole history, rolled up.
public struct AgentSummary: Sendable, Equatable {
    public var tool: AgentTool
    public var sessions: Int
    public var inputTokens: Int
    public var outputTokens: Int
    public var cachedTokens: Int
    public var toolCalls: Int
    public var messages: Int
    public var topModel: String?
    public var lastActive: Date?
    /// yyyy-MM-dd to sessions active on that day — the heatmap's source.
    public var dayCounts: [String: Int]
    public var currentStreak: Int
    public var longestStreak: Int

    public var billableTokens: Int { inputTokens + outputTokens }
    public var activeDays: Int { dayCounts.count }

    public init(
        tool: AgentTool,
        sessions: Int = 0,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        cachedTokens: Int = 0,
        toolCalls: Int = 0,
        messages: Int = 0,
        topModel: String? = nil,
        lastActive: Date? = nil,
        dayCounts: [String: Int] = [:],
        currentStreak: Int = 0,
        longestStreak: Int = 0
    ) {
        self.tool = tool
        self.sessions = sessions
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cachedTokens = cachedTokens
        self.toolCalls = toolCalls
        self.messages = messages
        self.topModel = topModel
        self.lastActive = lastActive
        self.dayCounts = dayCounts
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
    }

    /// Folds session digests into one picture of the tool.
    public static func rolledUp(
        tool: AgentTool,
        digests: [SessionDigest],
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> AgentSummary {
        var summary = AgentSummary(tool: tool, sessions: digests.count)
        var models: [String: Int] = [:]

        for digest in digests {
            summary.inputTokens += digest.inputTokens
            summary.outputTokens += digest.outputTokens
            summary.cachedTokens += digest.cachedTokens
            summary.toolCalls += digest.toolCalls
            summary.messages += digest.messages
            for (model, count) in digest.models { models[model, default: 0] += count }
            if let last = digest.lastActivity {
                summary.lastActive = max(summary.lastActive ?? last, last)
            }
            // A session spanning midnight counts on both days, which is what
            // "did I work that day" means to the person reading it.
            for day in digest.activeDays {
                summary.dayCounts[day, default: 0] += 1
            }
        }

        summary.topModel = models.max { lhs, rhs in
            lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value
        }?.key

        let streaks = ActivityStreak.compute(
            days: Set(summary.dayCounts.keys), today: today, calendar: calendar
        )
        summary.currentStreak = streaks.current
        summary.longestStreak = streaks.longest
        return summary
    }
}

/// Consecutive-day arithmetic over `yyyy-MM-dd` keys.
public enum ActivityStreak {
    public static let dayFormat = "yyyy-MM-dd"

    public static func key(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The run ending today, and the longest run ever.
    ///
    /// Today being idle does not break the streak until tomorrow: a streak
    /// that resets the moment you wake up and haven't worked yet would be
    /// a discouraging lie.
    public static func compute(
        days: Set<String>,
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> (current: Int, longest: Int) {
        guard !days.isEmpty else { return (0, 0) }

        let sorted = days.sorted()
        var longest = 1
        var run = 1
        for index in 1..<max(sorted.count, 1) where sorted.count > 1 {
            run = isNextDay(sorted[index - 1], sorted[index], calendar: calendar) ? run + 1 : 1
            longest = max(longest, run)
        }

        var current = 0
        var cursor = days.contains(key(for: today, calendar: calendar))
            ? today
            : calendar.date(byAdding: .day, value: -1, to: today) ?? today
        while days.contains(key(for: cursor, calendar: calendar)) {
            current += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }

        return (current, max(longest, current))
    }

    private static func isNextDay(_ earlier: String, _ later: String, calendar: Calendar) -> Bool {
        guard let date = date(from: earlier, calendar: calendar),
              let next = calendar.date(byAdding: .day, value: 1, to: date) else { return false }
        return key(for: next, calendar: calendar) == later
    }

    static func date(from key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
