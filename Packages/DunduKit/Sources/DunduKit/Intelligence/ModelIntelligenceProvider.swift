import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// On-device Foundation Models provider. Only exists on iOS 26 / macOS 26
/// with Apple Intelligence hardware; everything else runs the rules
/// provider. Retrieval happens before any call — the prompt carries the top
/// candidates only, never the whole profile, to respect the ~4k context.
@available(iOS 26.0, macOS 26.0, *)
public struct ModelIntelligenceProvider: IntelligenceProvider {
    /// The model can go unavailable mid-session (Apple Intelligence turned
    /// off); every call falls back to rules silently rather than erroring.
    private let fallback: RulesIntelligenceProvider

    public init(fallback: RulesIntelligenceProvider = RulesIntelligenceProvider()) {
        self.fallback = fallback
    }

    public static var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    // MARK: - Generable shapes (spec §8)

    @Generable
    struct RoutingDecisionGen {
        @Guide(description: "Whether this belongs on a calendar as an event or in a list as a reminder: 'event' or 'reminder'")
        let kind: String

        @Guide(description: "The id of the target calendar or list, chosen from the provided options")
        let targetID: String

        @Guide(.range(0...100))
        let confidence: Int

        @Guide(description: "One short sentence explaining the choice")
        let reason: String
    }

    @Generable
    struct RepairSuggestionGen {
        let looksGarbled: Bool

        @Guide(.range(0...100))
        let confidence: Int

        @Guide(description: "The corrected title, or the original if no fix is warranted")
        let suggestedTitle: String

        @Guide(description: "Words that were changed")
        let changedTokens: [String]
    }

    // MARK: - Routing

    public func route(_ input: RoutingInput) async throws -> RoutingDecision {
        guard Self.isAvailable else {
            return try await fallback.route(input)
        }
        do {
            let session = LanguageModelSession(instructions: Prompts.routingInstructions)
            let response = try await session.respond(
                to: Prompts.routingPrompt(for: input),
                generating: RoutingDecisionGen.self
            )
            let generated = response.content
            return RoutingDecision(
                kind: ItemKind(rawValue: generated.kind) ?? .reminder,
                targetID: generated.targetID,
                confidence: min(100, max(0, generated.confidence)),
                reason: generated.reason
            )
        } catch {
            return try await fallback.route(input)
        }
    }

    // MARK: - Repair

    public func repair(_ input: RepairInput) async throws -> RepairSuggestion {
        guard Self.isAvailable, !input.candidates.isEmpty else {
            return try await fallback.repair(input)
        }
        do {
            let session = LanguageModelSession(instructions: Prompts.repairInstructions)
            let response = try await session.respond(
                to: Prompts.repairPrompt(for: input),
                generating: RepairSuggestionGen.self
            )
            let generated = response.content
            return RepairSuggestion(
                looksGarbled: generated.looksGarbled,
                confidence: min(100, max(0, generated.confidence)),
                suggestedTitle: generated.suggestedTitle,
                changedTokens: generated.changedTokens
            )
        } catch {
            return try await fallback.repair(input)
        }
    }
}
#endif

/// Every prompt in one place, versioned, because the on-device model gets
/// rebuilt across OS releases and prompts tuned on one build behave
/// differently on the next.
public enum Prompts {
    public static let version = "2026-08-06.1"

    public static let routingInstructions = """
    You route new reminders and events for one person who runs multiple \
    businesses. Given an item and candidate businesses, pick the target \
    list or calendar from the provided options. Only use option ids that \
    were given. If nothing points at a business, choose the default \
    personal option with high confidence. Never invent a business.
    """

    public static func routingPrompt(for input: RoutingInput) -> String {
        var lines = ["Item: \(input.title)"]
        if let notes = input.notes, !notes.isEmpty {
            lines.append("Notes: \(notes)")
        }
        if !input.candidateBusinesses.isEmpty {
            lines.append("Candidate businesses:")
            for business in input.candidateBusinesses.prefix(5) {
                var parts = [business.name]
                if !business.aliases.isEmpty { parts.append("aka \(business.aliases.joined(separator: ", "))") }
                if !business.keywords.isEmpty { parts.append("keywords: \(business.keywords.joined(separator: ", "))") }
                if let listID = business.defaultListID { parts.append("listID: \(listID.uuidString)") }
                lines.append("- " + parts.joined(separator: "; "))
            }
        }
        if !input.listOptions.isEmpty {
            lines.append("List options:")
            for option in input.listOptions {
                lines.append("- id: \(option.id), name: \(option.name)\(option.role == "default" ? " (default)" : "")")
            }
        }
        if !input.calendarOptions.isEmpty {
            lines.append("Calendar options:")
            for option in input.calendarOptions {
                lines.append("- id: \(option.id), name: \(option.name), role: \(option.role ?? "")")
            }
        }
        return lines.joined(separator: "\n")
    }

    public static let repairInstructions = """
    Dictated reminders often mishear names of people and companies. You are \
    given the original text and candidate substitutions found by phonetic \
    matching against the person's real contacts. Judge whether applying a \
    substitution produces a sentence that makes more sense than the \
    original. Never invent replacements that are not in the candidate list. \
    If the original is fine, return it unchanged with looksGarbled false.
    """

    public static func repairPrompt(for input: RepairInput) -> String {
        var lines = ["Original: \(input.originalTitle)", "Candidates:"]
        for candidate in input.candidates.prefix(5) {
            lines.append("- heard \"\(candidate.heard)\", could be \"\(candidate.suggested)\"")
        }
        return lines.joined(separator: "\n")
    }
}
