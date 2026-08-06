import Foundation
import Testing
@testable import DunduKit

@Suite("Siri origin heuristic")
struct SiriOriginTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func freshBareSpokenTitleIsSuspected() {
        #expect(SiriOriginDetector.looksDictated(
            title: "call the accountant about the filing",
            notes: nil, url: nil,
            remoteCreatedAt: now.addingTimeInterval(-120), now: now
        ))
    }

    @Test func notesOrURLDisqualify() {
        #expect(!SiriOriginDetector.looksDictated(
            title: "call the accountant",
            notes: "agenda attached", url: nil,
            remoteCreatedAt: now.addingTimeInterval(-120), now: now
        ))
        #expect(!SiriOriginDetector.looksDictated(
            title: "call the accountant",
            notes: nil, url: URL(string: "https://example.com"),
            remoteCreatedAt: now.addingTimeInterval(-120), now: now
        ))
    }

    @Test func oldItemsAreNotSuspected() {
        #expect(!SiriOriginDetector.looksDictated(
            title: "call the accountant",
            notes: nil, url: nil,
            remoteCreatedAt: now.addingTimeInterval(-3600), now: now
        ))
    }

    @Test func punctuationReadsAsTyped() {
        #expect(!SiriOriginDetector.readsAsSpokenText("Q3 report: send to board!"))
        #expect(!SiriOriginDetector.readsAsSpokenText("groceries - milk, eggs"))
    }

    @Test func singleWordAndDigitGroupsAreNotSpoken() {
        #expect(!SiriOriginDetector.readsAsSpokenText("groceries"))
        #expect(!SiriOriginDetector.readsAsSpokenText("pay invoice 48291 today"))
    }
}
