import Foundation

/// EventKit bridge — owns Apple Reminders, and only Reminders. Google-backed
/// EK calendars are enumerated at setup and on every sync, and land on the
/// permanent exclusion list so no calendar ever has two sync paths.
///
/// Real implementation lands with M1 (read), M2 (push), M3 (two-way merge).
/// This stub keeps the coordinator wiring honest from day one. EventKit gives
/// no delta feed — `EKEventStoreChanged` means "refetch", so every pull is a
/// full fetch and diff of the mapped lists.
public actor EventKitBridge: SyncBridge {
    public let id: BridgeID = .eventkit

    public init() {}

    public func pull() async throws -> [RemoteChange] {
        // M1: predicateForReminders(in:) over mapped calendars, completed and
        // incomplete, keyed by calendarItemExternalIdentifier.
        []
    }

    public func push(_ changes: [LocalChange]) async throws -> [PushResult] {
        // M2: fetch-mutate-save. Never construct a fresh EKReminder to replace
        // an existing one — that drops fields EventKit doesn't expose to us
        // (tags, subtasks, flags, attachments).
        changes.map { PushResult(localID: $0.localID, error: "EventKit bridge not implemented until M2") }
    }

    public func observeChanges() -> AsyncStream<Void> {
        // M3: EKEventStoreChanged, debounced 1s, with echo suppression via a
        // 3-second set of recently written external IDs.
        AsyncStream { $0.finish() }
    }
}
