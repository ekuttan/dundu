import Foundation

/// Where a coding session has got to.
public enum AgentSessionState: String, Sendable, Codable, CaseIterable {
    /// The agent is working and nobody needs to do anything.
    case working
    /// It has stopped and is waiting on you — a permission prompt, a question.
    case waiting
    /// The turn finished.
    case done
}

/// One live coding session, as reported by a hook the agent runs itself.
///
/// Dundu never polls for this. The agent writes a small file when something
/// happens and Dundu reads it, which is why the list can be live without
/// anything watching a process table.
public struct AgentSession: Sendable, Codable, Equatable, Identifiable {
    public var id: String
    public var tool: AgentTool
    public var state: AgentSessionState
    /// Working directory, so two sessions in different repos are tellable
    /// apart at a glance.
    public var project: String?
    /// The opening line of what was asked. Local only — it is on your own
    /// screen, and a list of bare UUIDs would be useless.
    public var task: String?
    public var updatedAt: Date

    public init(
        id: String,
        tool: AgentTool,
        state: AgentSessionState,
        project: String? = nil,
        task: String? = nil,
        updatedAt: Date
    ) {
        self.id = id
        self.tool = tool
        self.state = state
        self.project = project
        self.task = task
        self.updatedAt = updatedAt
    }

    public var projectName: String? {
        project.map { URL(fileURLWithPath: $0).lastPathComponent }
    }
}

/// Reads the status files the hooks write.
public enum AgentSessionReader {
    /// A session left "working" for this long has almost certainly died with
    /// its machine — a crash, a sleep, a closed lid — and no Stop hook ever
    /// ran. Showing it forever would make the list a graveyard.
    public static let staleAfter: TimeInterval = 2 * 3600
    /// Finished sessions are worth seeing for a moment and then gone.
    public static let keepDoneFor: TimeInterval = 10 * 60

    /// Parses one status file's contents.
    public static func session(from data: Data) -> AgentSession? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(AgentSession.self, from: data)
    }

    /// What belongs on screen now: live work first, stale ghosts dropped.
    public static func visible(
        _ sessions: [AgentSession],
        now: Date = Date()
    ) -> [AgentSession] {
        sessions
            .filter { session in
                let age = now.timeIntervalSince(session.updatedAt)
                switch session.state {
                case .working: return age < staleAfter
                case .waiting: return age < staleAfter
                case .done: return age < keepDoneFor
                }
            }
            .sorted { lhs, rhs in
                // Anything waiting on you comes first: it is the only state
                // where the list is asking for something rather than telling.
                if lhs.state != rhs.state {
                    return priority(lhs.state) < priority(rhs.state)
                }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    private static func priority(_ state: AgentSessionState) -> Int {
        switch state {
        case .waiting: 0
        case .working: 1
        case .done: 2
        }
    }

    /// Transitions worth interrupting someone for, comparing a fresh read
    /// against the last one.
    public static func alerts(
        previous: [AgentSession],
        current: [AgentSession]
    ) -> [AgentSession] {
        let before = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0.state) })
        return current.filter { session in
            guard session.state == .done || session.state == .waiting else { return false }
            // Only the change is an event. A session that was already waiting
            // when Dundu last looked has not just started waiting.
            return before[session.id] != session.state
        }
    }
}
