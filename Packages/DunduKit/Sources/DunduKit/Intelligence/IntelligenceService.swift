import Foundation
import SwiftData

/// Picks the provider (model when available, rules otherwise) and runs the
/// ingest pipeline: retrieval, routing with confidence bands, repair
/// candidates, and decision logging.
@MainActor
public enum IntelligenceService {
    public static func makeProvider() -> any IntelligenceProvider {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *), ModelIntelligenceProvider.isAvailable {
            return ModelIntelligenceProvider()
        }
        #endif
        return RulesIntelligenceProvider()
    }

    /// Runs both AI tasks on a newly ingested item (spec §9 trigger 1).
    /// Silent when confident, marked for the Inbox when not. Mutates the
    /// item; the caller owns saving and the follow-up sync. Returns true
    /// when a sync-visible field changed (the item moved lists), so the
    /// caller knows to run another push pass.
    @discardableResult
    public static func processIngested(
        _ item: ReminderItem,
        lists: [ReminderList],
        profile: ProfileContext,
        provider: (any IntelligenceProvider)? = nil,
        now: Date = Date()
    ) async -> Bool {
        let provider = provider ?? makeProvider()

        let listBefore = item.listID
        await routeIngested(item, lists: lists, profile: profile, provider: provider, now: now)
        await repairIngested(item, profile: profile, provider: provider, now: now)
        return item.listID != listBefore
    }

    // MARK: - Routing (Task 1)

    private static func routeIngested(
        _ item: ReminderItem,
        lists: [ReminderList],
        profile: ProfileContext,
        provider: any IntelligenceProvider,
        now: Date
    ) async {
        let liveLists = lists.filter { $0.tombstonedAt == nil }
        guard !liveLists.isEmpty else { return }
        let defaultList = liveLists.first(where: \.isDefault) ?? liveLists[0]

        let candidates = ContextRetriever.candidates(
            for: [item.title, item.notes ?? ""].joined(separator: " "),
            profile: profile
        ).map(\.business)

        let input = RoutingInput(
            title: item.title,
            notes: item.notes,
            candidateBusinesses: candidates,
            listOptions: liveLists.map {
                RoutingTarget(
                    id: $0.id.uuidString,
                    name: $0.title,
                    role: $0.isDefault ? "default" : nil
                )
            }
        )

        guard var decision = try? await provider.route(input) else { return }

        // Guided generation constrains types, not semantics: an id that is
        // not a real option is treated as low confidence (spec edge 12).
        let validTarget = liveLists.first { $0.id.uuidString == decision.targetID }
        if validTarget == nil {
            decision = RoutingDecision(
                kind: decision.kind,
                targetID: defaultList.id.uuidString,
                confidence: min(decision.confidence, 40),
                reason: decision.reason + " (target was not a real option)"
            )
        }

        item.routingConfidence = decision.confidence
        item.routingReason = decision.reason

        switch ConfidenceBand(confidence: decision.confidence) {
        case .applySilently:
            if let target = validTarget {
                if item.listID != target.id {
                    item.listID = target.id
                    item.modifiedAt = now
                }
            }

        case .applyAndReview:
            // Safe placement in the default list; the Inbox offers the move.
            item.proposedTargetID = validTarget?.id.uuidString
            if item.listID == nil {
                item.listID = defaultList.id
                item.modifiedAt = now
            }
            item.reviewState = .pending

        case .ask:
            item.proposedTargetID = validTarget?.id.uuidString
            item.reviewState = .pending
        }

        DecisionLogger.log(DecisionLogger.Entry(
            kind: "routing",
            itemID: item.id.uuidString,
            title: item.title,
            promptVersion: Prompts.version,
            confidence: decision.confidence,
            outcome: decision.targetID,
            reason: decision.reason,
            at: now
        ))
    }

    // MARK: - Repair (Task 2)

    private static func repairIngested(
        _ item: ReminderItem,
        profile: ProfileContext,
        provider: any IntelligenceProvider,
        now: Date
    ) async {
        let suspects = PhoneticMatcher.suspects(in: item.title, people: profile.allPeople)
        guard !suspects.isEmpty else { return }

        let input = RepairInput(originalTitle: item.title, candidates: suspects)
        guard let suggestion = try? await provider.repair(input),
              suggestion.looksGarbled,
              suggestion.suggestedTitle != item.title
        else { return }

        // Never auto-applied — stored for the Inbox card, always asked.
        item.suggestedTitle = suggestion.suggestedTitle
        item.repairConfidence = suggestion.confidence
        item.reviewState = .pending

        DecisionLogger.log(DecisionLogger.Entry(
            kind: "repair",
            itemID: item.id.uuidString,
            title: item.title,
            promptVersion: Prompts.version,
            confidence: suggestion.confidence,
            outcome: suggestion.suggestedTitle,
            reason: suggestion.changedTokens.joined(separator: ", "),
            at: now
        ))
    }
}

// MARK: - Decision logging

/// Every decision with its inputs, as JSON lines in Application Support —
/// so the confidence bands get tuned against real behavior instead of
/// intuition (spec §8 and M18).
public enum DecisionLogger {
    public struct Entry: Codable, Sendable {
        public var kind: String
        public var itemID: String
        public var title: String
        public var promptVersion: String
        public var confidence: Int
        public var outcome: String
        public var reason: String
        public var at: Date
    }

    public static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Dundu", isDirectory: true)
            .appendingPathComponent("decisions.jsonl")
    }

    public static func log(_ entry: Entry) {
        guard var data = try? JSONEncoder().encode(entry) else { return }
        data.append(0x0A)
        let url = fileURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}
