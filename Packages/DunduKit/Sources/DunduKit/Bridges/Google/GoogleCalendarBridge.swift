import Foundation

/// Google Calendar bridge — talks REST directly, never through EventKit.
/// Real implementation lands with M9 (OAuth + read) and M10 (two-way sync).
///
/// The parts that matter when that day comes:
/// - Delta sync via `syncToken`; HTTP 410 means the token expired, clear it
///   and full-resync without treating missing items as deletions.
/// - Client-generated event IDs on insert so retries are idempotent.
/// - `events.patch` with `If-Match: <etag>`; a 412 means re-pull and merge.
/// - Exponential backoff with jitter on 403 rateLimitExceeded and 429.
/// - Polling, not push — `events.watch` needs a public webhook we don't have.
public actor GoogleCalendarBridge: SyncBridge {
    public let id: BridgeID = .google

    public init() {}

    public func pull() async throws -> [RemoteChange] {
        []
    }

    public func push(_ changes: [LocalChange]) async throws -> [PushResult] {
        changes.map { PushResult(localID: $0.localID, error: "Google bridge not implemented until M9") }
    }

    public func observeChanges() -> AsyncStream<Void> {
        AsyncStream { $0.finish() }
    }
}
