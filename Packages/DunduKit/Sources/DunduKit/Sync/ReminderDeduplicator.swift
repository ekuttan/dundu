import Foundation

/// Finds reminders that are the same reminder twice.
///
/// Two devices each sync with Apple Reminders on their own. Each mints its
/// own local `ReminderItem` for the same `EKReminder`, and CloudKit then
/// replicates both — so the store ends up holding two records that are one
/// task. The mapping table can't prevent it, because each device wrote its
/// mapping before it ever saw the other's.
///
/// Pure logic over snapshots so it can be tested without a store.
public enum ReminderDeduplicator {
    public struct Candidate: Sendable, Equatable {
        public let localID: UUID
        public let externalID: String?
        public let title: String
        public let listID: UUID?
        public let dueDate: Date?
        public let isCompleted: Bool
        public let modifiedAt: Date
        public let createdAt: Date

        public init(
            localID: UUID,
            externalID: String?,
            title: String,
            listID: UUID?,
            dueDate: Date?,
            isCompleted: Bool,
            modifiedAt: Date,
            createdAt: Date
        ) {
            self.localID = localID
            self.externalID = externalID
            self.title = title
            self.listID = listID
            self.dueDate = dueDate
            self.isCompleted = isCompleted
            self.modifiedAt = modifiedAt
            self.createdAt = createdAt
        }
    }

    public struct Resolution: Sendable, Equatable {
        /// The record to keep.
        public let keep: UUID
        /// The records to tombstone, all of them duplicates of `keep`.
        public let drop: [UUID]
    }

    /// How close together two undated copies must be created to count as the
    /// same reminder arriving twice. Beyond this they are two real tasks that
    /// happen to share a name.
    static let raceWindow: TimeInterval = 300

    /// Groups by external identity first, then by content. Returns one
    /// resolution per group that actually has duplicates.
    ///
    /// The content pass is deliberately timid. Completed reminders repeat by
    /// nature — the same chore, done every week, is a dozen rows with one
    /// title, one list and no due date — so matching them on content wipes
    /// out history. Only open items are ever considered, and even then a
    /// shared title is not enough on its own.
    public static func resolve(_ candidates: [Candidate]) -> [Resolution] {
        var resolutions: [Resolution] = []
        var claimed: Set<UUID> = []

        // 1. Same external identifier is the same reminder, full stop. This is
        // the two-devices-one-EKReminder case, and it is unambiguous.
        for (_, group) in Dictionary(grouping: candidates.filter { $0.externalID != nil }, by: { $0.externalID! })
        where group.count > 1 {
            let resolution = pick(group)
            resolutions.append(resolution)
            claimed.formUnion([resolution.keep] + resolution.drop)
        }

        // 2. Then content: same title, list and due date. Needed because an
        // item created locally on one device and pushed to EventKit can come
        // back to the other device before its mapping arrives, so the two
        // copies never share an external ID.
        let remaining = candidates.filter { !claimed.contains($0.localID) && !$0.isCompleted }
        for (_, group) in Dictionary(grouping: remaining, by: Fingerprint.init) where group.count > 1 {
            for cluster in corroborate(group) where cluster.count > 1 {
                resolutions.append(pick(cluster))
            }
        }

        return resolutions
    }

    /// A shared fingerprint is suspicion, not proof. Copies with a due date
    /// are taken at their word: agreeing on title, list *and* an exact minute
    /// is not coincidence. Undated copies have to have been created within
    /// minutes of each other, which is the sync race that produces them —
    /// two undated "Brush" reminders added weeks apart are two real tasks.
    private static func corroborate(_ group: [Candidate]) -> [[Candidate]] {
        if group.first?.dueDate != nil { return [group] }

        var clusters: [[Candidate]] = []
        for candidate in group.sorted(by: { $0.createdAt < $1.createdAt }) {
            if let index = clusters.indices.last,
               let last = clusters[index].last,
               candidate.createdAt.timeIntervalSince(last.createdAt) <= raceWindow {
                clusters[index].append(candidate)
            } else {
                clusters.append([candidate])
            }
        }
        return clusters
    }

    /// Keeps the most recently modified, breaking ties on the oldest record —
    /// the original, rather than the copy that chased it.
    ///
    /// A completed copy always wins over an open one: completion is the more
    /// destructive state to lose, and re-opening a task is cheaper than
    /// discovering you did it twice.
    private static func pick(_ group: [Candidate]) -> Resolution {
        let winner = group.sorted { lhs, rhs in
            if lhs.isCompleted != rhs.isCompleted { return lhs.isCompleted }
            if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt > rhs.modifiedAt }
            return lhs.createdAt < rhs.createdAt
        }[0]

        return Resolution(
            keep: winner.localID,
            drop: group.filter { $0.localID != winner.localID }.map(\.localID)
        )
    }

    /// What "the same task" means when there is no external ID to go on.
    /// Titles are compared case- and whitespace-insensitively; due dates to
    /// the minute, since a round trip through EventKit can shift sub-second.
    private struct Fingerprint: Hashable {
        let title: String
        let listID: UUID?
        let dueMinute: Int?

        init(_ candidate: Candidate) {
            title = candidate.title
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            listID = candidate.listID
            dueMinute = candidate.dueDate.map { Int($0.timeIntervalSince1970 / 60) }
        }
    }
}
