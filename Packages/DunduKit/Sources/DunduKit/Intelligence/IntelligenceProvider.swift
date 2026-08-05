import Foundation

/// Everything AI-shaped sits behind this protocol. The Foundation Models
/// implementation arrives in Phase 3 and requires iOS 26 / macOS 26 with
/// Apple Intelligence hardware; the rules-based fallback implements the same
/// protocol and doubles as the retrieval step in front of the model.
public protocol IntelligenceProvider: Sendable {
    func route(_ input: RoutingInput) async throws -> RoutingDecision
    func repair(_ input: RepairInput) async throws -> RepairSuggestion
}

// MARK: - Routing (Task 1)

public struct RoutingInput: Sendable {
    public var title: String
    public var notes: String?
    /// Top candidates from local retrieval — never the whole profile.
    public var candidateBusinesses: [BusinessContext]
    public var calendarOptions: [RoutingTarget]
    public var listOptions: [RoutingTarget]

    public init(
        title: String,
        notes: String? = nil,
        candidateBusinesses: [BusinessContext] = [],
        calendarOptions: [RoutingTarget] = [],
        listOptions: [RoutingTarget] = []
    ) {
        self.title = title
        self.notes = notes
        self.candidateBusinesses = candidateBusinesses
        self.calendarOptions = calendarOptions
        self.listOptions = listOptions
    }
}

public struct RoutingTarget: Sendable, Equatable {
    public var id: String
    public var name: String
    public var role: String?

    public init(id: String, name: String, role: String? = nil) {
        self.id = id
        self.name = name
        self.role = role
    }
}

public enum ItemKind: String, Sendable, Codable {
    case event
    case reminder
}

public struct RoutingDecision: Sendable, Equatable {
    public var kind: ItemKind
    /// Must be validated against real options — guided generation constrains
    /// types, not semantics. A miss is treated as low confidence.
    public var targetID: String
    /// 0...100
    public var confidence: Int
    public var reason: String

    public init(kind: ItemKind, targetID: String, confidence: Int, reason: String) {
        self.kind = kind
        self.targetID = targetID
        self.confidence = confidence
        self.reason = reason
    }
}

/// Confidence bands from the spec. Log every decision so the bands get tuned
/// against real behavior instead of intuition.
public enum ConfidenceBand: Sendable {
    /// 85+: apply silently, show a 24h undo chip.
    case applySilently
    /// 50–84: apply to default target, mark pending, show in Inbox.
    case applyAndReview
    /// <50: do not apply, leave in inbox, ask.
    case ask

    public init(confidence: Int) {
        switch confidence {
        case 85...: self = .applySilently
        case 50...84: self = .applyAndReview
        default: self = .ask
        }
    }
}

// MARK: - Repair (Task 2)

public struct RepairInput: Sendable {
    public var originalTitle: String
    /// Candidate substitutions produced by Swift-side phonetic matching.
    /// The model judges; it never generates names from nothing.
    public var candidates: [RepairCandidate]

    public init(originalTitle: String, candidates: [RepairCandidate] = []) {
        self.originalTitle = originalTitle
        self.candidates = candidates
    }
}

public struct RepairCandidate: Sendable, Equatable {
    /// The token as it appears in the garbled text.
    public var heard: String
    /// The profile name it phonetically resembles.
    public var suggested: String

    public init(heard: String, suggested: String) {
        self.heard = heard
        self.suggested = suggested
    }
}

public struct RepairSuggestion: Sendable, Equatable {
    public var looksGarbled: Bool
    /// 0...100
    public var confidence: Int
    /// The corrected title, or the original if no fix is warranted.
    /// Never auto-applied — always asked.
    public var suggestedTitle: String
    public var changedTokens: [String]

    public init(looksGarbled: Bool, confidence: Int, suggestedTitle: String, changedTokens: [String] = []) {
        self.looksGarbled = looksGarbled
        self.confidence = confidence
        self.suggestedTitle = suggestedTitle
        self.changedTokens = changedTokens
    }
}
