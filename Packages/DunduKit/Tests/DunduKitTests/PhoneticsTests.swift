import Foundation
import Testing
@testable import DunduKit

@Suite("Phonetic keys")
struct PhoneticsTests {
    private func keys(_ word: String) -> Phonetics.Keys {
        Phonetics.doubleMetaphone(word)
    }

    @Test func classicPairsShareKeys() {
        #expect(keys("Vivian").matches(keys("Vivien")))
        #expect(keys("Smith").matches(keys("Smyth")))
        #expect(keys("Joby").matches(keys("Jobi")))
        #expect(keys("Catherine").matches(keys("Katherine")))
        #expect(keys("Stephen").matches(keys("Steven")))
        #expect(keys("Philip").matches(keys("Filip")))
    }

    @Test func chAmbiguityCoversBothReadings() {
        // "Christina" reads K; the X reading lives in the other key.
        let christina = keys("Christina")
        #expect(christina.primary != christina.secondary)
        #expect(keys("Kristina").matches(christina))
    }

    @Test func silentInitialsDrop() {
        #expect(keys("Knight").matches(keys("Night")))
        #expect(keys("Wright").matches(keys("Right")))
    }

    @Test func unrelatedNamesDoNotCollide() {
        #expect(!keys("Vivian").matches(keys("Michael")))
        #expect(!keys("Joby").matches(keys("Sarah")))
        #expect(!keys("Anand").matches(keys("Priya")))
    }

    @Test func tokensSplitAndLowercase() {
        #expect(Phonetics.tokens(in: "Call Vivien about the DIFC filing!") ==
            ["call", "vivien", "about", "the", "difc", "filing"])
    }

    @Test func nameKeysDeduplicate() {
        let nameKeys = Phonetics.nameKeys(for: "Anna Hannah")
        #expect(nameKeys.count == Set(nameKeys).count)
        #expect(!nameKeys.isEmpty)
    }

    @Test func editDistanceBasics() {
        #expect(Phonetics.editDistance("joby", "jobi") == 1)
        #expect(Phonetics.editDistance("same", "same") == 0)
        #expect(Phonetics.editDistance("", "abc") == 3)
    }
}

@Suite("Phonetic suspects")
struct PhoneticMatcherTests {
    private let people = [
        PersonRef(
            displayName: "Vivian",
            phoneticKeys: Phonetics.nameKeys(for: "Vivian"),
            affiliation: "Scoop"
        ),
        PersonRef(
            displayName: "Joby",
            phoneticKeys: Phonetics.nameKeys(for: "Joby"),
            affiliation: "Scoop"
        ),
    ]

    @Test func misheardNameBecomesSuspect() {
        let suspects = PhoneticMatcher.suspects(in: "Send the deck to Vivien tomorrow", people: people)
        #expect(suspects.contains { $0.heard == "vivien" && $0.suggested == "Vivian" })
    }

    @Test func correctSpellingIsNotASuspect() {
        let suspects = PhoneticMatcher.suspects(in: "Send the deck to Vivian tomorrow", people: people)
        #expect(suspects.isEmpty)
    }

    @Test func spellingNearMissIsCaught() {
        let suspects = PhoneticMatcher.suspects(in: "remind me to call Jobi", people: people)
        #expect(suspects.contains { $0.heard == "jobi" && $0.suggested == "Joby" })
    }

    @Test func unrelatedTitleProducesNothing() {
        let suspects = PhoneticMatcher.suspects(in: "Pick up the car from service", people: people)
        #expect(suspects.isEmpty)
    }
}

@Suite("Context retrieval")
struct ContextRetrieverTests {
    private var profile: ProfileContext {
        ProfileContext(businesses: [
            BusinessContext(
                name: "Scoop",
                aliases: ["the app"],
                calendarRole: "work_a",
                people: [PersonRef(displayName: "Joby", phoneticKeys: Phonetics.nameKeys(for: "Joby"), affiliation: "Scoop")],
                keywords: ["investor", "creator ops"]
            ),
            BusinessContext(
                name: "Mangrove",
                aliases: ["the DIFC entity"],
                calendarRole: "work_b",
                keywords: ["filing", "audit"]
            ),
        ])
    }

    @Test func aliasHitRanksFirst() {
        let hits = ContextRetriever.candidates(for: "Prepare the DIFC entity filing", profile: profile)
        #expect(hits.first?.business.name == "Mangrove")
    }

    @Test func personNameRoutesToTheirBusiness() {
        let hits = ContextRetriever.candidates(for: "Send Joby the deck", profile: profile)
        #expect(hits.first?.business.name == "Scoop")
    }

    @Test func misheardPersonStillEchoesPhonetically() {
        let hits = ContextRetriever.candidates(for: "Send Jobi the deck", profile: profile)
        #expect(hits.first?.business.name == "Scoop")
    }

    @Test func noSignalMeansNoCandidates() {
        let hits = ContextRetriever.candidates(for: "Buy milk", profile: profile)
        #expect(hits.isEmpty)
    }

    @Test func emptyProfileIsEmptyResult() {
        let hits = ContextRetriever.candidates(for: "Send Joby the deck", profile: ProfileContext())
        #expect(hits.isEmpty)
    }
}
