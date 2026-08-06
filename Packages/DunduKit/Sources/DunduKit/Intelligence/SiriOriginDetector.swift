import Foundation

/// EventKit has no creator field, so Siri dictation is inferred, honestly:
/// this is a candidate pool, not a certainty. The repair check runs on
/// everything new anyway; this flag mainly feeds the origin statistics and
/// lets the Inbox say "probably dictated" on a card.
public enum SiriOriginDetector {
    /// How recently the remote item must have been created to plausibly be
    /// a fresh dictation arriving through sync.
    public static let recencyWindow: TimeInterval = 10 * 60

    public static func looksDictated(
        title: String,
        notes: String?,
        url: URL?,
        remoteCreatedAt: Date?,
        now: Date = Date()
    ) -> Bool {
        // Dictations arrive bare: no notes, no URL.
        guard notes?.isEmpty != false, url == nil else { return false }

        // Created within the last few minutes of appearing.
        if let created = remoteCreatedAt {
            guard now.timeIntervalSince(created) <= recencyWindow else { return false }
        }

        return readsAsSpokenText(title)
    }

    /// Spoken text has no punctuation, no digits-heavy tokens, a handful of
    /// words, and no shouty formatting.
    static func readsAsSpokenText(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        // Punctuation (beyond apostrophes) means it was typed or templated.
        let punctuation = CharacterSet(charactersIn: ".,;:!?()[]{}\"#@/\\|<>~`*_-—–")
        if trimmed.rangeOfCharacter(from: punctuation) != nil { return false }

        let words = trimmed.split(separator: " ")
        guard (2...14).contains(words.count) else { return false }

        // Dictation rarely produces digit groups like order numbers.
        let digitHeavy = words.filter { $0.filter(\.isNumber).count >= 3 }
        return digitHeavy.isEmpty
    }
}
