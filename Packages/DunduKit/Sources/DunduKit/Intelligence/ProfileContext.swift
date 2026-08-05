import Foundation

/// The context that feeds the AI. Small, hand-edited, stored locally as JSON,
/// never synced to any server. Retrieval runs against this before any model
/// call — top candidates only, never the whole profile.
public struct ProfileContext: Codable, Sendable, Equatable {
    public var businesses: [BusinessContext]
    public var updatedAt: Date

    public init(businesses: [BusinessContext] = [], updatedAt: Date = Date()) {
        self.businesses = businesses
        self.updatedAt = updatedAt
    }

    public var isEmpty: Bool { businesses.isEmpty }

    public var allPeople: [PersonRef] {
        businesses.flatMap(\.people)
    }
}

public struct BusinessContext: Codable, Sendable, Equatable {
    public var name: String
    /// "Scoop", "Mangrove", "the DIFC entity"
    public var aliases: [String]
    /// Matches `CalendarRef.role` — routing never targets calendar titles.
    public var calendarRole: String
    public var defaultListID: UUID?
    public var people: [PersonRef]
    /// "investor", "seed", "creator ops"
    public var keywords: [String]

    public init(
        name: String,
        aliases: [String] = [],
        calendarRole: String,
        defaultListID: UUID? = nil,
        people: [PersonRef] = [],
        keywords: [String] = []
    ) {
        self.name = name
        self.aliases = aliases
        self.calendarRole = calendarRole
        self.defaultListID = defaultListID
        self.people = people
        self.keywords = keywords
    }
}

public struct PersonRef: Codable, Sendable, Equatable {
    public var displayName: String
    public var aliases: [String]
    /// Precomputed Double Metaphone keys for garbled-name matching.
    public var phoneticKeys: [String]
    /// Business name or "personal".
    public var affiliation: String

    public init(
        displayName: String,
        aliases: [String] = [],
        phoneticKeys: [String] = [],
        affiliation: String = "personal"
    ) {
        self.displayName = displayName
        self.aliases = aliases
        self.phoneticKeys = phoneticKeys
        self.affiliation = affiliation
    }
}

// MARK: - Local persistence

/// Reads and writes the profile as a JSON file in Application Support.
/// Deliberately not SwiftData: this must never ride along with CloudKit sync.
public struct ProfileContextStore: Sendable {
    private let fileURL: URL

    public init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appendingPathComponent("Dundu", isDirectory: true)
        self.fileURL = base.appendingPathComponent("profile-context.json")
    }

    public func load() -> ProfileContext {
        guard let data = try? Data(contentsOf: fileURL),
              let context = try? JSONDecoder().decode(ProfileContext.self, from: data)
        else { return ProfileContext() }
        return context
    }

    public func save(_ context: ProfileContext) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(context).write(to: fileURL, options: .atomic)
    }
}
