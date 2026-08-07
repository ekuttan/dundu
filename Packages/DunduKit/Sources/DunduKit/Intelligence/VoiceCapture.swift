import Foundation

// MARK: - Captured actions

/// One action pulled out of a voice note. The model (or rules fallback)
/// marks roughly what was said; Swift resolves dates and places — a model
/// is never trusted with "next Thursday".
public struct CapturedAction: Sendable, Equatable, Identifiable {
    public var id = UUID()
    public var title: String
    /// The spoken deadline phrase ("tomorrow evening"), unresolved.
    public var duePhrase: String?
    /// Resolved by RelativeDateParser against the real clock.
    public var resolvedDue: Date?
    public var hasTime: Bool = false
    /// "enter", "leave", or nil.
    public var locationProximity: String?
    public var locationName: String?
    public var confidence: Int = 50

    public init(title: String) {
        self.title = title
    }
}

/// Splitting is its own capability so the capture pipeline works on any
/// hardware: the model splits well, the rules fallback splits conservatively
/// — and nothing saves without confirmation either way.
public protocol CaptureSplitting: Sendable {
    func split(_ transcript: String) async throws -> [CapturedAction]
}

// MARK: - Chunking

/// A rambling two-minute note can outrun the model's input budget. Chunk at
/// sentence boundaries around 1,500 characters and merge results downstream.
public enum TranscriptChunker {
    public static let targetChunkSize = 1500

    public static func chunks(of transcript: String) -> [String] {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > targetChunkSize else {
            return trimmed.isEmpty ? [] : [trimmed]
        }

        var sentences: [String] = []
        var current = ""
        for character in trimmed {
            current.append(character)
            if ".!?".contains(character) {
                sentences.append(current)
                current = ""
            }
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty {
            sentences.append(current)
        }

        var chunks: [String] = []
        var buffer = ""
        for sentence in sentences {
            if buffer.count + sentence.count > targetChunkSize && !buffer.isEmpty {
                chunks.append(buffer.trimmingCharacters(in: .whitespaces))
                buffer = ""
            }
            buffer += sentence
        }
        if !buffer.trimmingCharacters(in: .whitespaces).isEmpty {
            chunks.append(buffer.trimmingCharacters(in: .whitespaces))
        }
        return chunks
    }

    /// Near-identical titles across chunk boundaries collapse to one.
    public static func dedupe(_ actions: [CapturedAction]) -> [CapturedAction] {
        var kept: [CapturedAction] = []
        for action in actions {
            let isDuplicate = kept.contains { existing in
                let a = existing.title.lowercased()
                let b = action.title.lowercased()
                return a == b || (min(a.count, b.count) >= 12 && Phonetics.editDistance(a, b) <= 3)
            }
            if !isDuplicate {
                kept.append(action)
            }
        }
        return kept
    }
}

// MARK: - Relative date resolution

/// "Tomorrow evening" is ambiguous to a model with no clock; it is exact
/// arithmetic here. Handles the phrases dictation actually produces —
/// today/tonight/tomorrow with day parts, weekday names with optional
/// "next", "in N minutes/hours/days", and "at N (am|pm)".
public enum RelativeDateParser {
    public struct Resolution: Sendable, Equatable {
        public var date: Date
        public var hasTime: Bool
    }

    static let dayParts: [(phrase: String, hour: Int)] = [
        ("morning", 9), ("noon", 12), ("afternoon", 15), ("evening", 18), ("night", 21),
    ]
    static let weekdays = [
        "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4,
        "thursday": 5, "friday": 6, "saturday": 7,
    ]

    public static func resolve(
        _ phrase: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Resolution? {
        let text = phrase.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // "in 20 minutes" / "in 2 hours" / "in 3 days"
        if let match = text.firstMatch(of: /in (\d+) (minute|hour|day)s?/) {
            let amount = Int(match.1) ?? 0
            switch match.2 {
            case "minute": return Resolution(date: now.addingTimeInterval(TimeInterval(amount * 60)), hasTime: true)
            case "hour": return Resolution(date: now.addingTimeInterval(TimeInterval(amount * 3600)), hasTime: true)
            default:
                let day = calendar.date(byAdding: .day, value: amount, to: now) ?? now
                return Resolution(date: calendar.startOfDay(for: day).addingTimeInterval(9 * 3600), hasTime: false)
            }
        }

        // Base day: today / tonight / tomorrow / (next) weekday / "before X".
        var baseDay: Date?
        var defaultHour = 9
        var hasTime = false

        if text.contains("tonight") {
            baseDay = calendar.startOfDay(for: now)
            defaultHour = 21
            hasTime = true
        } else if text.contains("today") {
            baseDay = calendar.startOfDay(for: now)
        } else if text.contains("tomorrow") {
            baseDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
        } else {
            for (name, weekday) in weekdays where text.contains(name) {
                let todayWeekday = calendar.component(.weekday, from: now)
                var delta = (weekday - todayWeekday + 7) % 7
                if delta == 0 { delta = 7 } // "Thursday" said on Thursday means next week
                if text.contains("next ") && delta <= 7 && weekday <= todayWeekday {
                    delta += 0 // "next Thursday" from Friday is already next week's
                }
                baseDay = calendar.date(byAdding: .day, value: delta, to: calendar.startOfDay(for: now))
                break
            }
        }

        // Day part adjusts the default hour.
        for part in dayParts where text.contains(part.phrase) {
            defaultHour = part.hour
            hasTime = true
            if baseDay == nil {
                // "this evening" with no day word means today (or slips to
                // tomorrow if that hour already passed).
                let candidate = calendar.startOfDay(for: now).addingTimeInterval(TimeInterval(defaultHour * 3600))
                baseDay = candidate > now
                    ? calendar.startOfDay(for: now)
                    : calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
            }
            break
        }

        // "at 5" / "at 5:30 pm" / "5pm"
        if let match = text.firstMatch(of: /(?:at )?(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b/),
           text.contains("at ") || match.3 != nil {
            var hour = Int(match.1) ?? 0
            let minute = match.2.flatMap { Int($0) } ?? 0
            if match.3 == "pm" && hour < 12 { hour += 12 }
            if match.3 == "am" && hour == 12 { hour = 0 }
            if match.3 == nil && hour <= 7 { hour += 12 } // "at 5" usually means 5pm
            if (0...23).contains(hour) {
                defaultHour = hour
                hasTime = true
                if baseDay == nil {
                    let candidate = calendar.startOfDay(for: now)
                        .addingTimeInterval(TimeInterval(hour * 3600 + minute * 60))
                    baseDay = candidate > now
                        ? calendar.startOfDay(for: now)
                        : calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
                }
                guard let day = baseDay else { return nil }
                return Resolution(
                    date: day.addingTimeInterval(TimeInterval(hour * 3600 + minute * 60)),
                    hasTime: true
                )
            }
        }

        guard let day = baseDay else { return nil }
        return Resolution(
            date: day.addingTimeInterval(TimeInterval(defaultHour * 3600)),
            hasTime: hasTime
        )
    }
}

// MARK: - Rules splitter

/// No model: split conservatively on sentence boundaries and "and" joints
/// where both sides read like commands. Everything goes to confirm cards
/// anyway, so a missed split is editable, not lost.
public struct RulesCaptureSplitter: CaptureSplitting {
    static let actionVerbs: Set<String> = [
        "call", "ring", "phone", "text", "message", "email", "send", "share",
        "buy", "get", "pick", "collect", "order", "book", "schedule", "plan",
        "pay", "transfer", "file", "submit", "review", "prepare", "finish",
        "write", "draft", "read", "check", "ask", "tell", "remind", "renew",
        "cancel", "return", "drop", "fix", "clean", "update", "sign",
    ]

    public init() {}

    public func split(_ transcript: String) async throws -> [CapturedAction] {
        var fragments: [String] = []
        for chunk in TranscriptChunker.chunks(of: transcript) {
            // Sentences first.
            let sentences = chunk
                .components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            // Then "and"/"also" joints whose right side starts with a verb.
            for sentence in sentences {
                fragments.append(contentsOf: Self.splitOnJoints(sentence))
            }
        }

        let actions = fragments.map { fragment -> CapturedAction in
            var action = CapturedAction(title: Self.cleanTitle(fragment))
            if let phrase = Self.extractDuePhrase(from: fragment) {
                action.duePhrase = phrase
                if let resolved = RelativeDateParser.resolve(phrase) {
                    action.resolvedDue = resolved.date
                    action.hasTime = resolved.hasTime
                }
            }
            let lowered = fragment.lowercased()
            if let range = lowered.range(of: "when i reach ") ?? lowered.range(of: "when i get to ") {
                action.locationProximity = "enter"
                action.locationName = Self.trailingPlace(String(fragment[range.upperBound...]))
            } else if let range = lowered.range(of: "when i leave ") {
                action.locationProximity = "leave"
                action.locationName = Self.trailingPlace(String(fragment[range.upperBound...]))
            }
            action.confidence = 40 // rules never claims model-grade certainty
            return action
        }

        return TranscriptChunker.dedupe(actions).filter { $0.title.count >= 3 }
    }

    static func splitOnJoints(_ sentence: String) -> [String] {
        var parts: [String] = []
        var remainder = sentence
        for joint in [" and ", " also ", " then "] {
            var pieces: [String] = []
            for piece in remainder.components(separatedBy: joint) {
                let firstWord = piece
                    .trimmingCharacters(in: .whitespaces)
                    .components(separatedBy: " ").first?.lowercased() ?? ""
                if pieces.isEmpty || actionVerbs.contains(firstWord)
                    || firstWord == "remind" || firstWord == "pick" {
                    pieces.append(piece)
                } else {
                    // Not a command start: glue back onto the previous piece.
                    pieces[pieces.count - 1] += joint + piece
                }
            }
            remainder = pieces.first ?? remainder
            if pieces.count > 1 {
                parts = pieces
                break
            }
        }
        return parts.isEmpty ? [sentence] : parts.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    static func cleanTitle(_ fragment: String) -> String {
        var title = fragment.trimmingCharacters(in: .whitespaces)
        for prefix in ["remind me to ", "remember to ", "i need to ", "i have to ", "don't forget to "] {
            if title.lowercased().hasPrefix(prefix) {
                title = String(title.dropFirst(prefix.count))
                break
            }
        }
        return title.prefix(1).uppercased() + title.dropFirst()
    }

    static func extractDuePhrase(from fragment: String) -> String? {
        let lowered = fragment.lowercased()
        let markers = [
            "tomorrow morning", "tomorrow afternoon", "tomorrow evening", "tomorrow night",
            "tomorrow", "tonight", "this morning", "this afternoon", "this evening", "today",
            "next monday", "next tuesday", "next wednesday", "next thursday", "next friday",
            "next saturday", "next sunday",
            "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        ]
        for marker in markers where lowered.contains(marker) {
            // "before Thursday" keeps the qualifier for the parser.
            if lowered.contains("before \(marker)") {
                return "before \(marker)"
            }
            return marker
        }
        if let match = lowered.firstMatch(of: /in \d+ (?:minute|hour|day)s?/) {
            return String(match.0)
        }
        if let match = lowered.firstMatch(of: /at \d{1,2}(?::\d{2})?\s*(?:am|pm)?/) {
            return String(match.0)
        }
        return nil
    }

    static func trailingPlace(_ text: String) -> String {
        let stops = [",", " and ", " then ", " before ", " after ", " to "]
        var place = text
        for stop in stops {
            if let range = place.range(of: stop) {
                place = String(place[..<range.lowerBound])
            }
        }
        return place.trimmingCharacters(in: CharacterSet(charactersIn: " .!?"))
    }
}

#if canImport(FoundationModels)
import FoundationModels

/// The model splitter (iOS 26+ with Apple Intelligence). Extraction only —
/// dates stay phrases for Swift to resolve, and titles echo the spoken words.
@available(iOS 26.0, macOS 26.0, *)
public struct ModelCaptureSplitter: CaptureSplitting {
    private let fallback = RulesCaptureSplitter()

    public init() {}

    @Generable
    struct CapturedActionsGen {
        let items: [CapturedActionGen]
    }

    @Generable
    struct CapturedActionGen {
        @Guide(description: "The action as a short imperative title")
        let title: String
        @Guide(description: "The spoken deadline phrase exactly as said, like 'tomorrow evening' or 'before Thursday', or empty if none")
        let duePhrase: String
        @Guide(description: "Place name if an arrive or leave condition was spoken, else empty")
        let locationName: String
        @Guide(description: "enter, leave, or none")
        let locationProximity: String
        @Guide(.range(0...100))
        let confidence: Int
    }

    public func split(_ transcript: String) async throws -> [CapturedAction] {
        guard SystemLanguageModel.default.availability == .available else {
            return try await fallback.split(transcript)
        }
        do {
            var all: [CapturedAction] = []
            for chunk in TranscriptChunker.chunks(of: transcript) {
                let session = LanguageModelSession(instructions: Prompts.captureInstructions)
                let response = try await session.respond(
                    to: chunk, generating: CapturedActionsGen.self
                )
                for generated in response.content.items {
                    var action = CapturedAction(title: generated.title)
                    if !generated.duePhrase.isEmpty {
                        action.duePhrase = generated.duePhrase
                        if let resolved = RelativeDateParser.resolve(generated.duePhrase) {
                            action.resolvedDue = resolved.date
                            action.hasTime = resolved.hasTime
                        }
                    }
                    if !generated.locationName.isEmpty, generated.locationProximity != "none" {
                        action.locationName = generated.locationName
                        action.locationProximity = generated.locationProximity
                    }
                    action.confidence = generated.confidence
                    all.append(action)
                }
            }
            return TranscriptChunker.dedupe(all)
        } catch {
            return try await fallback.split(transcript)
        }
    }
}
#endif

extension Prompts {
    public static let captureInstructions = """
    A voice note may contain several distinct actions with different \
    deadlines. Extract every action. Keep titles short and imperative, \
    preserving names exactly as spoken. Copy any spoken deadline phrase \
    verbatim into duePhrase — never compute dates yourself. Note arrive or \
    leave conditions with their place name. Do not invent actions that were \
    not spoken.
    """
}

/// Picks the splitter for the current hardware.
@MainActor
public enum CaptureSplitterFactory {
    public static func make() -> any CaptureSplitting {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return ModelCaptureSplitter()
        }
        #endif
        return RulesCaptureSplitter()
    }
}
