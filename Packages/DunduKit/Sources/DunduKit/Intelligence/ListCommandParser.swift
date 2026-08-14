import Foundation

/// Pulls "…add it to the Hoomans list" out of dictated text and turns it into
/// a target list plus a title with the instruction removed.
///
/// Deliberately conservative. Saying a list's name in passing — "buy a gift
/// for the hoomans" — must not file the reminder, so a bare name never
/// counts: there has to be either a filing verb ("add to", "put in", "move
/// to") or the word "list" right after the name.
public enum ListCommandParser {
    public struct Target: Sendable, Equatable {
        public let id: UUID
        public let name: String

        public init(id: UUID, name: String) {
            self.id = id
            self.name = name
        }
    }

    public struct Match: Sendable, Equatable {
        /// Nil when nothing was said about a list.
        public let listID: UUID?
        /// The title with the filing instruction taken out.
        public let title: String

        public init(listID: UUID?, title: String) {
            self.listID = listID
            self.title = title
        }
    }

    /// Verbs that mean "file this somewhere". Longest first so "add it to"
    /// wins over "add" and doesn't leave "it to" behind in the title.
    private static let verbs = [
        "add it to", "add this to", "add to",
        "put it in", "put this in", "put it on", "put in",
        "move it to", "move this to", "move to",
        "save it to", "save to",
        "file it under", "file under",
    ]

    public static func parse(_ text: String, lists: [Target]) -> Match {
        // Longest name first: with both "Work" and "Work Admin", the more
        // specific one has to be tried before the shorter one matches inside it.
        let ordered = lists.sorted { $0.name.count > $1.name.count }

        for list in ordered where !list.name.trimmingCharacters(in: .whitespaces).isEmpty {
            let name = NSRegularExpression.escapedPattern(for: list.name)
            let verbAlternatives = verbs
                .map { NSRegularExpression.escapedPattern(for: $0) }
                .joined(separator: "|")

            // Either a filing verb before the name, or the word "list" after
            // it. "to the X list" is covered by both and matches once.
            let patterns = [
                #"(?:^|[\s,;.])(?:\#(verbAlternatives))\s+(?:the\s+)?\#(name)(?:\s+list)?\b"#,
                #"(?:^|[\s,;.])(?:to|in|on)\s+(?:the\s+)?\#(name)\s+list\b"#,
                #"(?:^|[\s,;.])\#(name)\s+list\b"#,
            ]

            for pattern in patterns {
                guard let regex = try? NSRegularExpression(
                    pattern: pattern, options: [.caseInsensitive]
                ) else { continue }
                let range = NSRange(text.startIndex..., in: text)
                guard let hit = regex.firstMatch(in: text, range: range),
                      let hitRange = Range(hit.range, in: text) else { continue }

                var stripped = text
                stripped.removeSubrange(hitRange)
                return Match(listID: list.id, title: tidy(stripped))
            }
        }

        return Match(listID: nil, title: tidy(text))
    }

    /// Removes the debris the excision leaves: doubled spaces, a space in
    /// front of punctuation, and stray leading/trailing separators.
    private static func tidy(_ text: String) -> String {
        var result = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+([,;.!?])"#, with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        while let first = result.first, ",;.".contains(first) {
            result.removeFirst()
            result = result.trimmingCharacters(in: .whitespaces)
        }
        while let last = result.last, ",;".contains(last) {
            result.removeLast()
            result = result.trimmingCharacters(in: .whitespaces)
        }
        return result
    }
}
