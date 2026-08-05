import Foundation

/// Owns all sync passes. A serial actor, so two passes over the same bridge
/// never overlap. Merge rules and the scheduler land with M3; this is the
/// frame they bolt onto.
public actor SyncCoordinator {
    public enum State: Sendable, Equatable {
        case idle
        case syncing(BridgeID)
    }

    private var bridges: [BridgeID: any SyncBridge] = [:]
    public private(set) var state: State = .idle
    public private(set) var lastSyncAt: [BridgeID: Date] = [:]

    public init() {}

    public func register(_ bridge: any SyncBridge) async {
        let id = await bridge.id
        bridges[id] = bridge
    }

    public func registeredBridges() -> [BridgeID] {
        Array(bridges.keys)
    }

    /// Runs one pull-merge-push pass for a single bridge. The real merge
    /// arrives with M3 (reminders) and M10 (events).
    public func sync(_ id: BridgeID) async throws {
        guard let bridge = bridges[id], state == .idle else { return }
        state = .syncing(id)
        defer { state = .idle }

        _ = try await bridge.pull()
        // M3: partition into create/pull/push/merge/tombstone against mappings.
        lastSyncAt[id] = Date()
    }

    public func syncAll() async {
        for id in bridges.keys {
            try? await sync(id)
        }
    }
}
