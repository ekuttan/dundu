import Foundation
#if canImport(EventKit)
import EventKit

/// EventKit bridge — owns Apple Reminders, and only Reminders. Google-backed
/// EK calendars are enumerated at setup and on every sync, and land on the
/// permanent exclusion list so no calendar ever has two sync paths.
///
/// EventKit gives no delta feed — `EKEventStoreChanged` means "refetch", so
/// every pull is a full fetch and diff of the mapped lists. EKObjects never
/// leave this actor; only value snapshots cross the boundary.
public actor EventKitBridge: SyncBridge {
    public let id: BridgeID = .eventkit

    private let store = EKEventStore()

    public init() {}

    // MARK: - Authorization

    public static func accessStatus() -> ReminderAccessStatus {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .fullAccess: .fullAccess
        case .writeOnly: .writeOnly
        case .restricted: .restricted
        case .authorized: .fullAccess
        @unknown default: .denied
        }
    }

    /// First launch, before any fetch. Returns false when the user declines —
    /// the app keeps working standalone, no Apple sync.
    public func requestFullAccess() async throws -> Bool {
        try await store.requestFullAccessToReminders()
    }

    // MARK: - Reading (M1)

    /// All reminders lists, with Google-backed sources flagged for the
    /// exclusion list.
    public func fetchLists() -> [EKListSnapshot] {
        store.calendars(for: .reminder).map { calendar in
            EKListSnapshot(
                id: calendar.calendarIdentifier,
                title: calendar.title,
                colorHex: calendar.cgColor.flatMap(Self.hexString),
                sourceTitle: calendar.source?.title ?? "",
                isGoogleBacked: Self.isGoogleBacked(calendar),
                allowsModification: calendar.allowsContentModifications
            )
        }
    }

    /// Full fetch of the given lists (all lists when nil), completed and
    /// incomplete both — the diff in M3 needs completed items too.
    public func fetchReminders(inLists listIDs: [String]? = nil) async throws -> [EKReminderSnapshot] {
        let calendars: [EKCalendar]? = listIDs.map { ids in
            ids.compactMap { store.calendar(withIdentifier: $0) }
        }
        let predicate = store.predicateForReminders(in: calendars)

        // Snapshot inside the callback: EKObjects are not Sendable and must
        // not cross the actor boundary.
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { fetched in
                continuation.resume(returning: (fetched ?? []).map(Self.snapshot))
            }
        }
    }

    // MARK: - SyncBridge

    public func pull() async throws -> [RemoteChange] {
        // M3 turns snapshots into partitioned changes against the mappings.
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

    // MARK: - Mapping

    private static func snapshot(_ reminder: EKReminder) -> EKReminderSnapshot {
        var dueDate: Date?
        var hasTime = false
        if let components = reminder.dueDateComponents {
            dueDate = Calendar.current.date(from: components)
            hasTime = components.hour != nil
        }

        var offsets: [Double] = []
        var locationAlarm: LocationAlarm?
        for alarm in reminder.alarms ?? [] {
            if let structured = alarm.structuredLocation, alarm.proximity != .none {
                // Take the first location alarm; any others round-trip via
                // EventKit untouched because we never rewrite whole reminders.
                if locationAlarm == nil {
                    locationAlarm = LocationAlarm(
                        title: structured.title ?? "",
                        latitude: structured.geoLocation?.coordinate.latitude ?? 0,
                        longitude: structured.geoLocation?.coordinate.longitude ?? 0,
                        radius: structured.radius,
                        proximity: alarm.proximity == .leave ? .leave : .enter
                    )
                }
            } else {
                offsets.append(alarm.relativeOffset)
            }
        }

        return EKReminderSnapshot(
            externalID: reminder.calendarItemExternalIdentifier ?? reminder.calendarItemIdentifier,
            localIdentifier: reminder.calendarItemIdentifier,
            listID: reminder.calendar?.calendarIdentifier ?? "",
            title: reminder.title ?? "",
            notes: reminder.notes,
            dueDate: dueDate,
            hasTime: hasTime,
            priority: reminder.priority,
            isCompleted: reminder.isCompleted,
            completedAt: reminder.completionDate,
            url: reminder.url,
            lastModified: reminder.lastModifiedDate,
            alarmOffsets: offsets,
            locationAlarm: locationAlarm,
            hasRecurrence: reminder.hasRecurrenceRules
        )
    }

    private static func isGoogleBacked(_ calendar: EKCalendar) -> Bool {
        guard let source = calendar.source else { return false }
        guard source.sourceType == .calDAV || source.sourceType == .subscribed else { return false }
        let haystack = (source.title + " " + source.sourceIdentifier).lowercased()
        return haystack.contains("google") || haystack.contains("gmail")
    }

    private static func hexString(_ color: CGColor) -> String? {
        guard let rgb = color.converted(
            to: CGColorSpace(name: CGColorSpace.sRGB)!,
            intent: .defaultIntent,
            options: nil
        ), let c = rgb.components, c.count >= 3 else { return nil }
        return String(format: "#%02X%02X%02X", Int(c[0] * 255), Int(c[1] * 255), Int(c[2] * 255))
    }
}

#else

/// tvOS has no Reminders database — EventKit is unavailable there. The tvOS
/// app reads CloudKit instead and never touches this bridge.
public actor EventKitBridge: SyncBridge {
    public let id: BridgeID = .eventkit
    public init() {}
    public func pull() async throws -> [RemoteChange] { [] }
    public func push(_ changes: [LocalChange]) async throws -> [PushResult] {
        changes.map { PushResult(localID: $0.localID, error: "EventKit unavailable on this platform") }
    }
    public func observeChanges() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}

#endif
