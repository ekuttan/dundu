import Foundation

/// Swift does the candidate generation; the model only judges. This is the
/// generation half: find title tokens that sound like a profile name but are
/// not that name, and propose the substitution.
public enum PhoneticMatcher {
    /// A token qualifies as a suspect for a name when their phonetic keys
    /// match (or nearly match) while the strings themselves differ.
    public static func suspects(
        in title: String,
        people: [PersonRef]
    ) -> [RepairCandidate] {
        let tokenEntries = Phonetics.tokenKeys(for: title)
        guard !tokenEntries.isEmpty else { return [] }

        var candidates: [RepairCandidate] = []
        var claimedTokens = Set<String>()

        for person in people {
            let nameParts = Phonetics.tokens(in: person.displayName)
                + person.aliases.flatMap { Phonetics.tokens(in: $0) }
            let personKeys = person.phoneticKeys.isEmpty
                ? Phonetics.nameKeys(for: ([person.displayName] + person.aliases).joined(separator: " "))
                : person.phoneticKeys

            for (token, tokenKeys) in tokenEntries {
                // The name spelled correctly is not a suspect, and short
                // function words ("up", "at") never are — too many of them
                // collide with somebody's key.
                guard token.count >= 3 else { continue }
                guard !nameParts.contains(token) else { continue }
                guard !claimedTokens.contains(token) else { continue }

                let phoneticHit = personKeys.contains { key in
                    key == tokenKeys.primary
                        || key == tokenKeys.secondary
                        // Near-miss keys only carry signal when there is
                        // enough key to miss by.
                        || (key.count >= 3 && tokenKeys.primary.count >= 3
                            && Phonetics.editDistance(key, tokenKeys.primary) <= 1)
                }
                // Spelling near-miss backstop for garbles phonetics can't
                // bridge ("Jobi" -> "Joby" is phonetic; "Vivien" -> "Vivian"
                // is both; "Abed" -> "Abid" is spelling).
                let spellingHit = nameParts.contains { part in
                    part.count >= 4 && Phonetics.editDistance(part, token) <= 1
                }

                if phoneticHit || spellingHit {
                    // Suggest the first name part that sounds like the token,
                    // falling back to the display name's first token.
                    let replacement = nameParts.first { part in
                        Phonetics.doubleMetaphone(part).matches(tokenKeys)
                            || Phonetics.editDistance(part, token) <= 1
                    } ?? nameParts.first ?? person.displayName
                    candidates.append(RepairCandidate(
                        heard: token,
                        suggested: matchCase(of: token, to: replacement)
                    ))
                    claimedTokens.insert(token)
                }
            }
        }

        return candidates
    }

    /// "vivien" heard mid-sentence should suggest "Vivian" capitalized the
    /// way the profile spells it — profile capitalization wins.
    private static func matchCase(of heard: String, to replacement: String) -> String {
        replacement.prefix(1).uppercased() + replacement.dropFirst()
    }
}

/// The retrieval step in front of the model: exact alias match, then token
/// overlap, then phonetic — top candidates only, never the whole profile.
/// Doubles as the routing signal for the rules fallback.
public enum ContextRetriever {
    public struct Scored: Sendable, Equatable {
        public var business: BusinessContext
        public var score: Double
    }

    public static func candidates(
        for text: String,
        profile: ProfileContext,
        limit: Int = 5
    ) -> [Scored] {
        let tokens = Set(Phonetics.tokens(in: text))
        guard !tokens.isEmpty, !profile.isEmpty else { return [] }
        let tokenKeys = Phonetics.tokenKeys(for: text)

        var scored: [Scored] = []
        for business in profile.businesses {
            var score = 0.0

            // Exact alias / name hit is the strongest signal.
            let names = [business.name] + business.aliases
            for name in names {
                let parts = Phonetics.tokens(in: name)
                if !parts.isEmpty && Set(parts).isSubset(of: tokens) {
                    score += 10
                }
            }

            // Keyword overlap.
            for keyword in business.keywords {
                let parts = Phonetics.tokens(in: keyword)
                if !parts.isEmpty && Set(parts).isSubset(of: tokens) {
                    score += 4
                }
            }

            // People: exact name part, then phonetic echo.
            for person in business.people {
                let parts = Phonetics.tokens(in: person.displayName)
                    + person.aliases.flatMap { Phonetics.tokens(in: $0) }
                if parts.contains(where: tokens.contains) {
                    score += 6
                } else {
                    let keys = person.phoneticKeys.isEmpty
                        ? Phonetics.nameKeys(for: person.displayName)
                        : person.phoneticKeys
                    let echoes = tokenKeys.contains { _, tk in
                        keys.contains { $0 == tk.primary || $0 == tk.secondary }
                    }
                    if echoes { score += 3 }
                }
            }

            if score > 0 {
                scored.append(Scored(business: business, score: score))
            }
        }

        return scored
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }
}
