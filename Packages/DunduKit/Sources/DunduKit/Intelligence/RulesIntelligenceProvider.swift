import Foundation

/// The no-model path: keyword and phonetic matching in plain Swift. This is
/// the only provider on pre-Apple-Intelligence hardware, and the retrieval
/// half of the pipeline everywhere else — so it has to be genuinely good,
/// not a stub.
public struct RulesIntelligenceProvider: IntelligenceProvider {
    public init() {}

    // MARK: - Routing

    public func route(_ input: RoutingInput) async throws -> RoutingDecision {
        let defaultTarget = input.listOptions.first { $0.role == "default" }
            ?? input.listOptions.first

        // Empty context: default to personal, never guess a business.
        guard !input.candidateBusinesses.isEmpty else {
            return RoutingDecision(
                kind: .reminder,
                targetID: defaultTarget?.id ?? "",
                confidence: 90,
                reason: "No business signal; personal by default."
            )
        }

        let profile = ProfileContext(businesses: input.candidateBusinesses)
        let text = [input.title, input.notes ?? ""].joined(separator: " ")
        let scored = ContextRetriever.candidates(for: text, profile: profile)

        guard let top = scored.first else {
            return RoutingDecision(
                kind: .reminder,
                targetID: defaultTarget?.id ?? "",
                confidence: 88,
                reason: "Nothing points at a business; personal by default."
            )
        }

        // The business's default list has to actually exist in the options.
        let targetID = top.business.defaultListID?.uuidString
        let target = input.listOptions.first { $0.id == targetID }

        guard let target else {
            return RoutingDecision(
                kind: .reminder,
                targetID: defaultTarget?.id ?? "",
                confidence: 45,
                reason: "Looks like \(top.business.name), but it has no list set up."
            )
        }

        // Confidence from signal strength and the gap to the runner-up.
        let runnerUp = scored.dropFirst().first?.score ?? 0
        let confidence: Int
        let reason: String
        if top.score >= 10 && top.score >= runnerUp * 2 {
            confidence = 88
            reason = "Named \(top.business.name) directly."
        } else if top.score >= 6 {
            confidence = 70
            reason = "Mentions people or words tied to \(top.business.name)."
        } else {
            confidence = 55
            reason = "Weak echo of \(top.business.name)."
        }

        return RoutingDecision(
            kind: .reminder,
            targetID: target.id,
            confidence: confidence,
            reason: reason
        )
    }

    // MARK: - Repair

    /// Without a model there is no judgement step, so confidence stays in
    /// the ask-first band and the substitution is offered, never applied.
    public func repair(_ input: RepairInput) async throws -> RepairSuggestion {
        guard !input.candidates.isEmpty else {
            return RepairSuggestion(
                looksGarbled: false,
                confidence: 0,
                suggestedTitle: input.originalTitle
            )
        }

        var suggested = input.originalTitle
        var changed: [String] = []
        for candidate in input.candidates {
            if let range = suggested.range(of: candidate.heard, options: [.caseInsensitive]) {
                suggested.replaceSubrange(range, with: candidate.suggested)
                changed.append(candidate.heard)
            }
        }

        return RepairSuggestion(
            looksGarbled: !changed.isEmpty,
            confidence: changed.isEmpty ? 0 : 60,
            suggestedTitle: suggested,
            changedTokens: changed
        )
    }
}
