import Foundation
import SwiftData
import Testing
@testable import DunduKit

@Suite("Rules routing")
struct RulesRoutingTests {
    private let provider = RulesIntelligenceProvider()

    private let scoopListID = UUID()
    private let defaultListID = UUID()

    private var businesses: [BusinessContext] {
        [
            BusinessContext(
                name: "Scoop",
                aliases: ["the app"],
                calendarRole: "work_a",
                defaultListID: scoopListID,
                people: [PersonRef(displayName: "Joby", phoneticKeys: Phonetics.nameKeys(for: "Joby"), affiliation: "Scoop")],
                keywords: ["investor"]
            )
        ]
    }

    private var listOptions: [RoutingTarget] {
        [
            RoutingTarget(id: defaultListID.uuidString, name: "Reminders", role: "default"),
            RoutingTarget(id: scoopListID.uuidString, name: "Scoop", role: nil),
        ]
    }

    @Test func emptyContextDefaultsToPersonalSilently() async throws {
        let decision = try await provider.route(RoutingInput(
            title: "Buy milk", listOptions: listOptions
        ))
        #expect(decision.targetID == defaultListID.uuidString)
        #expect(ConfidenceBand(confidence: decision.confidence) == .applySilently)
    }

    @Test func directBusinessNameRoutesSilently() async throws {
        let decision = try await provider.route(RoutingInput(
            title: "Prepare the Scoop investor update",
            candidateBusinesses: businesses,
            listOptions: listOptions
        ))
        #expect(decision.targetID == scoopListID.uuidString)
        #expect(ConfidenceBand(confidence: decision.confidence) == .applySilently)
    }

    @Test func personMentionLandsInReviewBand() async throws {
        let decision = try await provider.route(RoutingInput(
            title: "Send Joby the deck",
            candidateBusinesses: businesses,
            listOptions: listOptions
        ))
        #expect(decision.targetID == scoopListID.uuidString)
        #expect(ConfidenceBand(confidence: decision.confidence) == .applyAndReview)
    }

    @Test func businessWithoutListFallsToAskBand() async throws {
        var withoutList = businesses
        withoutList[0].defaultListID = nil
        let decision = try await provider.route(RoutingInput(
            title: "Prepare the Scoop investor update",
            candidateBusinesses: withoutList,
            listOptions: listOptions
        ))
        #expect(decision.targetID == defaultListID.uuidString)
        #expect(ConfidenceBand(confidence: decision.confidence) == .ask)
    }

    @Test func repairAppliesCandidatesWithoutModel() async throws {
        let suggestion = try await provider.repair(RepairInput(
            originalTitle: "Send the deck to Vivien",
            candidates: [RepairCandidate(heard: "vivien", suggested: "Vivian")]
        ))
        #expect(suggestion.looksGarbled)
        #expect(suggestion.suggestedTitle == "Send the deck to Vivian")
        #expect(suggestion.changedTokens == ["vivien"])
        // Rules confidence stays in the ask band — no model judged it.
        #expect(suggestion.confidence < 85)
    }
}

@Suite("Ingest pipeline")
@MainActor
struct IngestPipelineTests {
    private func makeContext() throws -> (ModelContext, ReminderList, ReminderList) {
        let container = try DunduStore.previewContainer()
        let context = ModelContext(container)
        let defaultList = ReminderList(title: "Reminders", isDefault: true)
        let scoopList = ReminderList(title: "Scoop")
        context.insert(defaultList)
        context.insert(scoopList)
        try context.save()
        return (context, defaultList, scoopList)
    }

    private func profile(scoopListID: UUID) -> ProfileContext {
        ProfileContext(businesses: [
            BusinessContext(
                name: "Scoop",
                calendarRole: "work_a",
                defaultListID: scoopListID,
                people: [PersonRef(displayName: "Vivian", phoneticKeys: Phonetics.nameKeys(for: "Vivian"), affiliation: "Scoop")]
            )
        ])
    }

    @Test func confidentRoutingMovesSilently() async throws {
        let (context, defaultList, scoopList) = try makeContext()
        let item = ReminderItem(title: "Scoop board meeting prep", listID: defaultList.id, origin: .eventkit)
        context.insert(item)

        let moved = await IntelligenceService.processIngested(
            item,
            lists: [defaultList, scoopList],
            profile: profile(scoopListID: scoopList.id),
            provider: RulesIntelligenceProvider()
        )

        #expect(moved)
        #expect(item.listID == scoopList.id)
        #expect(item.reviewState == .none)
        #expect(item.routingConfidence.map { $0 >= 85 } == true)
    }

    @Test func weakSignalQueuesForInbox() async throws {
        let (context, defaultList, scoopList) = try makeContext()
        let item = ReminderItem(title: "Call Vivian back", listID: defaultList.id, origin: .eventkit)
        context.insert(item)

        let moved = await IntelligenceService.processIngested(
            item,
            lists: [defaultList, scoopList],
            profile: profile(scoopListID: scoopList.id),
            provider: RulesIntelligenceProvider()
        )

        #expect(!moved)
        #expect(item.listID == defaultList.id)
        #expect(item.reviewState == .pending)
        #expect(item.proposedTargetID == scoopList.id.uuidString)
    }

    @Test func garbledTitleGetsSuggestionNeverApplied() async throws {
        let (context, defaultList, scoopList) = try makeContext()
        let item = ReminderItem(title: "Send the report to Vivien", listID: defaultList.id, origin: .eventkit)
        context.insert(item)

        await IntelligenceService.processIngested(
            item,
            lists: [defaultList, scoopList],
            profile: profile(scoopListID: scoopList.id),
            provider: RulesIntelligenceProvider()
        )

        #expect(item.title == "Send the report to Vivien")
        #expect(item.suggestedTitle == "Send the report to Vivian")
        #expect(item.reviewState == .pending)
    }
}
