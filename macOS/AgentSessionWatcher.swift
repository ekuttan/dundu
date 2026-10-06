import Foundation
import UserNotifications
import DunduKit

/// Watches the status files Claude Code's hooks write and turns them into a
/// live list, plus a notification when a task finishes or needs you.
///
/// The directory is watched rather than polled: a hook writes a file and the
/// kernel says so. A slow timer runs alongside only so that *time-based*
/// changes — a finished session ageing out of the list — still land.
@Observable
@MainActor
final class AgentSessionWatcher {
    /// One per process, started at launch: the alerts have to fire whether or
    /// not anyone has the panel open.
    static let shared = AgentSessionWatcher()

    private(set) var sessions: [AgentSession] = []

    /// Set when a session is waiting on you, for the notch to peek about.
    var needsAttention: AgentSession? {
        sessions.first { $0.state == .waiting }
    }

    private var source: DispatchSourceFileSystemObject?
    private var directoryHandle: CInt = -1
    private var ticker: Timer?
    private var lastSeen: [AgentSession] = []
    private var notificationsAllowed = false

    func start() {
        guard source == nil else { return }
        Task { await requestNotificationPermission() }
        reload()
        observeDirectory()

        // Sessions expire by the clock, not by anything the hooks do.
        ticker = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.reload() }
        }
    }

    func stop() {
        source?.cancel()
        source = nil
        ticker?.invalidate()
        ticker = nil
    }

    // MARK: - Reading

    private func reload() {
        guard let directory = AgentFolderAccess.liveSessionsDirectory() else {
            sessions = []
            return
        }

        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []

        let found = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> AgentSession? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return AgentSessionReader.session(from: data)
            }

        let visible = AgentSessionReader.visible(found)
        let alerts = AgentSessionReader.alerts(previous: lastSeen, current: visible)
        lastSeen = visible
        sessions = visible

        for session in alerts { notify(session) }
    }

    /// Watching the directory itself: a hook writing or removing a file shows
    /// up as a write to the directory vnode.
    private func observeDirectory() {
        guard let directory = AgentFolderAccess.liveSessionsDirectory() else { return }
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )

        directoryHandle = open(directory.path, O_EVTONLY)
        guard directoryHandle >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: directoryHandle,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor in self?.reload() }
        }
        source.setCancelHandler { [weak self] in
            guard let self, self.directoryHandle >= 0 else { return }
            close(self.directoryHandle)
            self.directoryHandle = -1
        }
        source.resume()
        self.source = source
    }

    // MARK: - Alerts

    private func requestNotificationPermission() async {
        let center = UNUserNotificationCenter.current()
        notificationsAllowed = (try? await center.requestAuthorization(
            options: [.alert, .sound]
        )) ?? false
    }

    private func notify(_ session: AgentSession) {
        guard notificationsAllowed else { return }

        let content = UNMutableNotificationContent()
        switch session.state {
        case .waiting:
            content.title = "\(session.tool.displayName) needs you"
            content.sound = .default
        case .done:
            content.title = "\(session.tool.displayName) finished"
        case .working:
            return
        }
        // The project is what tells two running agents apart; the task is
        // what reminds you which one this was.
        content.subtitle = session.projectName ?? ""
        content.body = session.task ?? ""

        UNUserNotificationCenter.current().add(
            UNNotificationRequest(
                identifier: "agent-\(session.id)-\(session.state.rawValue)",
                content: content,
                trigger: nil
            )
        )
    }
}
