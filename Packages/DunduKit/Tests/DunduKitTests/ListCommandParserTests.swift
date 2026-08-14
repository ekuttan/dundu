import Foundation
import Testing
@testable import DunduKit

@Suite("Spoken list commands")
struct ListCommandParserTests {
    private let hoomans = ListCommandParser.Target(id: UUID(), name: "Hoomans")
    private let personal = ListCommandParser.Target(id: UUID(), name: "Personal")

    private var lists: [ListCommandParser.Target] { [hoomans, personal] }

    @Test func filingVerbTargetsTheListAndLeavesTheTask() {
        let match = ListCommandParser.parse("Buy dog food add to Hoomans list", lists: lists)
        #expect(match.listID == hoomans.id)
        #expect(match.title == "Buy dog food")
    }

    @Test func worksWithoutTheWordList() {
        let match = ListCommandParser.parse("Book the vet, add it to Hoomans", lists: lists)
        #expect(match.listID == hoomans.id)
        #expect(match.title == "Book the vet")
    }

    @Test func trailingListNameCounts() {
        let match = ListCommandParser.parse("Trim the nails — Hoomans list", lists: lists)
        #expect(match.listID == hoomans.id)
        #expect(match.title == "Trim the nails —")
    }

    /// The whole point of requiring a verb or the word "list": a name used in
    /// passing must not silently move the reminder.
    @Test func bareNameInPassingIsNotACommand() {
        let match = ListCommandParser.parse("Buy a gift for the hoomans", lists: lists)
        #expect(match.listID == nil)
        #expect(match.title == "Buy a gift for the hoomans")
    }

    @Test func nothingSaidAboutAListLeavesTitleUntouched() {
        let match = ListCommandParser.parse("Call the CA about the filing", lists: lists)
        #expect(match.listID == nil)
        #expect(match.title == "Call the CA about the filing")
    }

    @Test func matchingIsCaseInsensitive() {
        let match = ListCommandParser.parse("water the plants, put in personal list", lists: lists)
        #expect(match.listID == personal.id)
        #expect(match.title == "water the plants")
    }

    /// "Work Admin" must win over "Work", or the longer list becomes
    /// unreachable by voice.
    @Test func longerListNameWinsOverAPrefix() {
        let work = ListCommandParser.Target(id: UUID(), name: "Work")
        let workAdmin = ListCommandParser.Target(id: UUID(), name: "Work Admin")
        let match = ListCommandParser.parse(
            "File the VAT return, add to Work Admin list", lists: [work, workAdmin]
        )
        #expect(match.listID == workAdmin.id)
        #expect(match.title == "File the VAT return")
    }

    @Test func emptyListNamesAreIgnored() {
        let blank = ListCommandParser.Target(id: UUID(), name: "  ")
        let match = ListCommandParser.parse("Something to do", lists: [blank])
        #expect(match.listID == nil)
        #expect(match.title == "Something to do")
    }
}
