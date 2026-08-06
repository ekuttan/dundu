import Foundation
#if canImport(EventKit)
import CoreLocation
import EventKit

public enum DunduEventKitError: Error, Sendable {
    case missingPayload
    case reminderNotFound(String)
    case accessNotGranted
}

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

    /// EK calendar identifier of the system default reminders list.
    public func defaultListExternalID() -> String? {
        store.defaultCalendarForNewReminders()?.calendarIdentifier
    }

    // MARK: - Writing (M2)

    /// Applies planned changes in one batch commit. Updates fetch-mutate-save
    /// the existing EKReminder — never construct a fresh one to replace it,
    /// because that drops fields EventKit doesn't expose to us (tags,
    /// subtasks, flags, attachments).
    public func apply(_ planned: [PlannedReminderChange]) async -> [PushResult] {
        var results: [PushResult] = []
        var dirty = false

        for change in planned {
            do {
                switch change.action {
                case .create:
                    guard let payload = change.payload else {
                        throw DunduEventKitError.missingPayload
                    }
                    let reminder = EKReminder(eventStore: store)
                    reminder.calendar = payload.listExternalID
                        .flatMap { store.calendar(withIdentifier: $0) }
                        ?? store.defaultCalendarForNewReminders()
                    Self.apply(payload, to: reminder)
                    try store.save(reminder, commit: false)
                    dirty = true
                    results.append(PushResult(
                        localID: change.localID,
                        externalID: reminder.calendarItemExternalIdentifier ?? reminder.calendarItemIdentifier
                    ))

                case .update(let externalID):
                    guard let payload = change.payload else {
                        throw DunduEventKitError.missingPayload
                    }
                    guard let reminder = fetchByExternalID(externalID) else {
                        throw DunduEventKitError.reminderNotFound(externalID)
                    }
                    Self.apply(payload, to: reminder)
                    try store.save(reminder, commit: false)
                    dirty = true
                    results.append(PushResult(localID: change.localID, externalID: externalID))

                case .delete(let externalID):
                    if let reminder = fetchByExternalID(externalID) {
                        try store.remove(reminder, commit: false)
                        dirty = true
                    }
                    // Already gone remotely is success, not an error.
                    results.append(PushResult(localID: change.localID, externalID: externalID))
                }
            } catch {
                results.append(PushResult(
                    localID: change.localID,
                    error: String(describing: error)
                ))
            }
        }

        if dirty {
            do {
                try store.commit()
            } catch {
                // The batch failed as a whole; report it on every change that
                // thought it succeeded.
                results = results.map {
                    $0.error == nil
                        ? PushResult(localID: $0.localID, externalID: $0.externalID, error: String(describing: error))
                        : $0
                }
            }
        }

        return results
    }

    private func fetchByExternalID(_ externalID: String) -> EKReminder? {
        let matches = store.calendarItems(withExternalIdentifier: externalID)
            .compactMap { $0 as? EKReminder }
        // External IDs are not guaranteed unique; keep the most recently
        // modified and let the sync pass reconcile the rest.
        return matches.max {
            ($0.lastModifiedDate ?? .distantPast) < ($1.lastModifiedDate ?? .distantPast)
        }
    }

    private static func apply(_ payload: ReminderWritePayload, to reminder: EKReminder) {
        reminder.title = payload.title
        reminder.notes = payload.notes
        reminder.url = payload.url
        reminder.priority = payload.priority

        if let due = payload.dueDate {
            var components: Set<Calendar.Component> = [.year, .month, .day]
            if payload.hasTime {
                components.formUnion([.hour, .minute])
            }
            reminder.dueDateComponents = Calendar.current.dateComponents(components, from: due)
        } else {
            reminder.dueDateComponents = nil
        }

        if payload.isCompleted {
            // Setting isCompleted stamps completionDate; prefer our own.
            reminder.isCompleted = true
            if let completedAt = payload.completedAt {
                reminder.completionDate = completedAt
            }
        } else {
            reminder.isCompleted = false
        }

        // M2 owns the alarm set for items Dundu pushes. The field-level diff
        // that preserves foreign alarms arrives with M3's three-way merge.
        for alarm in reminder.alarms ?? [] {
            reminder.removeAlarm(alarm)
        }
        for offset in payload.alarmOffsets {
            reminder.addAlarm(EKAlarm(relativeOffset: offset))
        }
        if let location = payload.locationAlarm {
            let structured = EKStructuredLocation(title: location.title)
            structured.geoLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)
            structured.radius = location.radius
            let alarm = EKAlarm()
            alarm.structuredLocation = structured
            alarm.proximity = location.proximity == .leave ? .leave : .enter
            reminder.addAlarm(alarm)
        }
    }

    // MARK: - SyncBridge

    public func pull() async throws -> [RemoteChange] {
        // M3 turns snapshots into partitioned changes against the mappings.
        []
    }

    public func push(_ changes: [LocalChange]) async throws -> [PushResult] {
        // The typed entry point is `apply(_:)`; the protocol path decodes
        // payloads the coordinator queued.
        var planned: [PlannedReminderChange] = []
        for change in changes {
            let payload = change.payload.flatMap {
                try? JSONDecoder().decode(ReminderWritePayload.self, from: $0)
            }
            let action: PlannedReminderChange.Action? = switch change.kind {
            case .create: .create
            case .update: change.externalID.map { .update(externalID: $0) }
            case .delete: change.externalID.map { .delete(externalID: $0) }
            }
            guard let action else { continue }
            planned.append(PlannedReminderChange(
                localID: change.localID, action: action, payload: payload, localModifiedAt: Date()
            ))
        }
        return await apply(planned)
    }

    /// Fires on `EKEventStoreChanged`. No payload — it means "refetch".
    /// Consumers debounce by 1 second; echo suppression is structural, since
    /// our own writes read back as remote-equals-base and plan to nothing.
    public func observeChanges() -> AsyncStream<Void> {
        let store = self.store
        return AsyncStream { continuation in
            let token = ObserverToken(NotificationCenter.default.addObserver(
                forName: .EKEventStoreChanged, object: store, queue: nil
            ) { _ in
                continuation.yield()
            })
            continuation.onTermination = { _ in
                token.cancel()
            }
        }
    }

    /// Sendable box for a NotificationCenter observer token so the stream's
    /// termination handler can remove it.
    private final class ObserverToken: @unchecked Sendable {
        private let observer: any NSObjectProtocol
        init(_ observer: any NSObjectProtocol) { self.observer = observer }
        func cancel() { NotificationCenter.default.removeObserver(observer) }
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
            created: reminder.creationDate,
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
