import Foundation

public enum BridgeID: String, Sendable, Codable, CaseIterable {
    case eventkit
    case google
}

/// A change observed on the remote side during a pull.
public struct RemoteChange: Sendable {
    public enum Kind: Sendable {
        case created
        case updated
        case deleted
    }

    public var kind: Kind
    public var externalID: String
    /// Bridge-specific payload, decoded by the coordinator's merge step.
    public var payload: Data?
    public var remoteModifiedAt: Date?

    public init(kind: Kind, externalID: String, payload: Data? = nil, remoteModifiedAt: Date? = nil) {
        self.kind = kind
        self.externalID = externalID
        self.payload = payload
        self.remoteModifiedAt = remoteModifiedAt
    }
}

/// A local mutation queued for push.
public struct LocalChange: Sendable {
    public enum Kind: Sendable {
        case create
        case update
        case delete
    }

    public var kind: Kind
    public var localID: UUID
    public var externalID: String?
    public var payload: Data?

    public init(kind: Kind, localID: UUID, externalID: String? = nil, payload: Data? = nil) {
        self.kind = kind
        self.localID = localID
        self.externalID = externalID
        self.payload = payload
    }
}

public struct PushResult: Sendable {
    public var localID: UUID
    public var externalID: String?
    public var etag: String?
    public var error: String?

    public init(localID: UUID, externalID: String? = nil, etag: String? = nil, error: String? = nil) {
        self.localID = localID
        self.externalID = externalID
        self.etag = etag
        self.error = error
    }

    public var succeeded: Bool { error == nil }
}

/// Both bridges implement the same protocol so the coordinator treats them
/// the same way. EventKit owns Reminders. Google owns Calendar. Neither
/// overlaps.
public protocol SyncBridge: Actor {
    var id: BridgeID { get }
    func pull() async throws -> [RemoteChange]
    func push(_ changes: [LocalChange]) async throws -> [PushResult]
    /// Fires when the remote side reports a change (no payload — it means
    /// "schedule a pull").
    func observeChanges() -> AsyncStream<Void>
}
