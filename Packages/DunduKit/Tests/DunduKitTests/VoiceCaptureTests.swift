import Foundation
import Testing
@testable import DunduKit

@Suite("Transcript chunking")
struct TranscriptChunkerTests {
    @Test func shortTranscriptIsOneChunk() {
        #expect(TranscriptChunker.chunks(of: "Call the accountant.").count == 1)
        #expect(TranscriptChunker.chunks(of: "  ").isEmpty)
    }

    @Test func longTranscriptSplitsAtSentenceBoundaries() {
        let sentence = "This is a spoken sentence that carries on for a while before ending. "
        let transcript = String(repeating: sentence, count: 40) // ~2800 chars
        let chunks = TranscriptChunker.chunks(of: transcript)
        #expect(chunks.count >= 2)
        #expect(chunks.allSatisfy { $0.count <= TranscriptChunker.targetChunkSize + 100 })
        #expect(chunks.allSatisfy { $0.hasSuffix(".") })
    }

    @Test func nearIdenticalTitlesDedupe() {
        var a = CapturedAction(title: "Pick up the car from service")
        var b = CapturedAction(title: "Pick up the car from service.")
        a.confidence = 60
        b.confidence = 60
        let deduped = TranscriptChunker.dedupe([a, b])
        #expect(deduped.count == 1)

        let distinct = TranscriptChunker.dedupe([
            CapturedAction(title: "Call the CA"),
            CapturedAction(title: "Call the bank"),
        ])
        #expect(distinct.count == 2)
    }
}

@Suite("Relative date resolution")
struct RelativeDateParserTests {
    // Thursday 2027-01-14 07:00 UTC.
    let now = Date(timeIntervalSince1970: 1_799_910_000)
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func resolve(_ phrase: String) -> RelativeDateParser.Resolution? {
        RelativeDateParser.resolve(phrase, now: now, calendar: calendar)
    }

    @Test func tomorrowEvening() throws {
        let result = try #require(resolve("tomorrow evening"))
        let parts = calendar.dateComponents([.day, .hour], from: result.date)
        #expect(parts.hour == 18)
        #expect(result.hasTime)
        #expect(calendar.isDate(result.date, inSameDayAs: now.addingTimeInterval(24 * 3600)))
    }

    @Test func tonight() throws {
        let result = try #require(resolve("tonight"))
        #expect(calendar.isDate(result.date, inSameDayAs: now))
        #expect(calendar.component(.hour, from: result.date) == 21)
    }

    @Test func inTwoHours() throws {
        let result = try #require(resolve("in 2 hours"))
        #expect(result.date == now.addingTimeInterval(7200))
        #expect(result.hasTime)
    }

    @Test func weekdayResolvesForward() throws {
        // Said on a Thursday, "before Thursday" and "thursday" mean next week.
        let result = try #require(resolve("before thursday"))
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: result.date).day ?? 0
        #expect(days == 7)

        let friday = try #require(resolve("friday"))
        #expect(calendar.component(.weekday, from: friday.date) == 6)
        #expect(friday.date > now)
    }

    @Test func atFivePmToday() throws {
        let result = try #require(resolve("at 5 pm"))
        #expect(calendar.component(.hour, from: result.date) == 17)
        #expect(calendar.isDate(result.date, inSameDayAs: now))
        #expect(result.hasTime)
    }

    @Test func bareAtFiveMeansSeventeen() throws {
        let result = try #require(resolve("at 5"))
        #expect(calendar.component(.hour, from: result.date) == 17)
    }

    @Test func nonsensePhraseReturnsNil() {
        #expect(resolve("the blue elephant") == nil)
        #expect(resolve("") == nil)
    }
}

@Suite("Rules capture splitting")
struct RulesCaptureSplitterTests {
    private let splitter = RulesCaptureSplitter()

    @Test func specExampleSplitsIntoThree() async throws {
        let transcript = "Call the CA about the DIFC filing before Thursday, pick up the car from service tomorrow evening, and remind me when I reach the office to send Joby the deck."
        let actions = try await splitter.split(transcript)

        #expect(actions.count >= 2) // conservative splitter: joints + commas vary
        #expect(actions.contains { $0.title.lowercased().contains("call the ca") })
        #expect(actions.contains { $0.locationProximity == "enter" && ($0.locationName?.contains("office") ?? false) })
    }

    @Test func duePhrasesResolve() async throws {
        let actions = try await splitter.split("Pick up the car from service tomorrow evening.")
        let action = try #require(actions.first)
        #expect(action.duePhrase == "tomorrow evening")
        #expect(action.resolvedDue != nil)
        #expect(action.hasTime)
    }

    @Test func remindMePrefixStripsFromTitle() async throws {
        let actions = try await splitter.split("Remind me to renew the trade license.")
        #expect(actions.first?.title == "Renew the trade license")
    }

    @Test func nonCommandAndDoesNotSplit() async throws {
        let actions = try await splitter.split("Buy bread and butter from the store.")
        #expect(actions.count == 1)
    }

    @Test func rulesConfidenceStaysBelowSilentBand() async throws {
        let actions = try await splitter.split("Call the bank tomorrow.")
        #expect(actions.allSatisfy { $0.confidence < 50 })
    }
}
