import Foundation

/// Double Metaphone, trimmed to the rules that matter for person and company
/// names. Produces a primary and secondary key so "Christina" matches both
/// the X (ch) and K readings. Keys cap at 4 characters, per the classic
/// algorithm.
///
/// This is deliberately not a museum-grade port: the exotic rules (Italian
/// -CCIA-, Polish -CZ-, etc.) are omitted, the ones Siri actually trips over
/// (soft/hard C and G, TH, PH, silent initials, W/Y glides) are kept.
public enum Phonetics {
    public static let keyLength = 4

    public struct Keys: Equatable, Sendable {
        public let primary: String
        public let secondary: String

        public func matches(_ other: Keys) -> Bool {
            primary == other.primary
                || primary == other.secondary
                || secondary == other.primary
                || (secondary == other.secondary && !secondary.isEmpty)
        }
    }

    public static func doubleMetaphone(_ word: String) -> Keys {
        let letters = Array(word.uppercased().unicodeScalars
            .filter { CharacterSet.uppercaseLetters.contains($0) }
            .map { Character($0) })
        guard !letters.isEmpty else { return Keys(primary: "", secondary: "") }

        var primary = ""
        var secondary = ""
        func add(_ p: String, _ s: String? = nil) {
            primary += p
            secondary += s ?? p
        }

        func isVowel(_ index: Int) -> Bool {
            guard index >= 0, index < letters.count else { return false }
            return "AEIOUY".contains(letters[index])
        }
        func at(_ index: Int) -> Character? {
            guard index >= 0, index < letters.count else { return nil }
            return letters[index]
        }
        func slice(_ range: Range<Int>) -> String {
            let lower = max(0, range.lowerBound)
            let upper = min(letters.count, range.upperBound)
            guard lower < upper else { return "" }
            return String(letters[lower..<upper])
        }

        var i = 0

        // Silent initial pairs: GN-, KN-, PN-, WR-, PS-.
        if ["GN", "KN", "PN", "WR", "PS"].contains(slice(0..<2)) {
            i = 1
        }
        // Initial X sounds like S ("Xavier").
        if letters[i] == "X" {
            add("S")
            i += 1
        }

        while i < letters.count, primary.count < Self.keyLength || secondary.count < Self.keyLength {
            let c = letters[i]
            defer { i += 1 }

            // Collapse doubles (except C, handled below for CC).
            if i > 0, letters[i - 1] == c, c != "C" {
                continue
            }

            switch c {
            case "A", "E", "I", "O", "U", "Y":
                // Vowels (and glide Y) only register at the start of a word.
                if i == 0 { add("A") }

            case "B":
                // Final -MB: silent B ("lamb").
                if !(i == letters.count - 1 && at(i - 1) == "M") {
                    add("P")
                }

            case "C":
                if slice(i..<i + 2) == "CH" {
                    // CH: X reading ("church"), K alternate ("Christina").
                    add("X", "K")
                    i += 1
                } else if slice(i..<i + 3) == "CIA" {
                    add("X")
                } else if let next = at(i + 1), "EIY".contains(next) {
                    add("S", "S")
                } else if slice(i..<i + 2) == "CK" || slice(i..<i + 2) == "CC" {
                    add("K")
                    i += 1
                } else {
                    add("K")
                }

            case "D":
                if slice(i..<i + 2) == "DG", let after = at(i + 2), "EIY".contains(after) {
                    add("J")
                    i += 2
                } else {
                    add("T")
                }

            case "F":
                add("F")

            case "G":
                if slice(i..<i + 2) == "GH" {
                    // GH after a vowel is silent ("Vaughan"); word-initially
                    // it is a hard K ("ghost").
                    if i == 0 || !isVowel(i - 1) {
                        add("K")
                    }
                    i += 1
                } else if slice(i..<i + 2) == "GN" {
                    add("N")
                    i += 1
                } else if let next = at(i + 1), "EIY".contains(next) {
                    // Soft/hard G is genuinely ambiguous in names
                    // ("Gina" vs "Gilbert" vs "Gehrig").
                    add("J", "K")
                } else {
                    add("K")
                }

            case "H":
                // Digraphs (TH, PH, SH, CH, GH) never reach here — their
                // cases consume the H. A lone H sounds before a vowel
                // ("Mahoney"), and is silent otherwise ("Sarah").
                if isVowel(i + 1) {
                    add("H")
                }

            case "J":
                add("J", "H")

            case "K":
                if at(i - 1) != "C" {
                    add("K")
                }

            case "L":
                add("L")

            case "M":
                add("M")

            case "N":
                add("N")

            case "P":
                if slice(i..<i + 2) == "PH" {
                    add("F")
                    i += 1
                } else {
                    add("P")
                }

            case "Q":
                add("K")

            case "R":
                add("R")

            case "S":
                if slice(i..<i + 3) == "SCH" {
                    // "Schmidt" (X) vs "school" (SK).
                    add("X", "SK")
                    i += 2
                } else if slice(i..<i + 2) == "SH" {
                    add("X")
                    i += 1
                } else if slice(i..<i + 3) == "SIO" || slice(i..<i + 3) == "SIA" {
                    add("X", "S")
                } else if slice(i..<i + 2) == "SC", let after = at(i + 2), "EIY".contains(after) {
                    add("S")
                    i += 1
                } else {
                    add("S")
                }

            case "T":
                if slice(i..<i + 3) == "TIO" || slice(i..<i + 3) == "TIA" {
                    add("X")
                } else if slice(i..<i + 2) == "TH" {
                    // "Thomas" is T in most names, theta in words.
                    add("0", "T")
                    i += 1
                } else {
                    add("T")
                }

            case "V":
                add("F")

            case "W":
                // W only sounds before a vowel ("Wade"); otherwise silent.
                if isVowel(i + 1) {
                    add("A", "F")
                }

            case "X":
                add("KS")

            case "Z":
                add("S")

            default:
                break
            }
        }

        return Keys(
            primary: String(primary.prefix(Self.keyLength)),
            secondary: String(secondary.prefix(Self.keyLength))
        )
    }

    /// Phonetic keys for every word-like token in a text, keyed by token.
    public static func tokenKeys(for text: String) -> [(token: String, keys: Keys)] {
        tokens(in: text).map { ($0, doubleMetaphone($0)) }
    }

    /// Word tokens, lowercased, punctuation stripped.
    public static func tokens(in text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
    }

    /// All phonetic keys for a display name (one entry per name part),
    /// deduplicated. This is what gets precomputed into
    /// `PersonRef.phoneticKeys`.
    public static func nameKeys(for name: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for (_, keys) in tokenKeys(for: name) {
            for key in [keys.primary, keys.secondary] where !key.isEmpty && seen.insert(key).inserted {
                result.append(key)
            }
        }
        return result
    }

    /// Small edit distance, used to catch near-miss keys and tokens.
    public static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
