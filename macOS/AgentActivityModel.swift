import Foundation
import DunduKit

/// Holds the agent dashboard's state for the notch.
///
/// A cold scan of the transcripts takes tens of seconds, so it never happens
/// on the main actor and never blocks the panel appearing: the view draws
/// whatever it already has, and fills in when the scan lands.
@Observable
@MainActor
final class AgentActivityModel {
    private(set) var summaries: [AgentTool: AgentSummary] = [:]
    var available: [AgentTool] = []
    private(set) var isScanning = false
    var lastScan: Date?
    /// Rough progress for the first run, when there is nothing to show yet.
    private(set) var progress: Double?

    var selected: AgentTool = .claudeCode

    /// Re-reading on every hover would be wasteful — the transcripts only
    /// change while an agent is actually working.
    private let minimumInterval: TimeInterval = 45
    private var inFlight: Task<Void, Never>?

    /// Tools the user has not yet pointed Dundu at. From inside the sandbox
    /// there is no way to tell whether `~/.claude` exists, so every ungranted
    /// tool is offered rather than guessed at.
    var needsAccess: [AgentTool] {
        AgentTool.allCases.filter { AgentFolderAccess.grantedURL(for: $0) == nil }
    }

    /// Opens the folder picker, then scans immediately so the grant visibly
    /// does something.
    func connect(_ tool: AgentTool) {
        guard AgentFolderAccess.requestAccess(for: tool) != nil else { return }
        selected = tool
        refresh(force: true)
    }

    /// Hands the folder grant back. The summary goes with it: leaving the
    /// numbers on screen after disconnecting would suggest Dundu is still
    /// reading, which is the one thing a disconnect has to disprove.
    func disconnect(_ tool: AgentTool) {
        AgentFolderAccess.forget(tool)
        summaries[tool] = nil
        available.removeAll { $0 == tool }
        lastScan = nil
        refresh(force: true)
    }

    var summary: AgentSummary? { summaries[selected] }

    var hasAnything: Bool { !available.isEmpty || !needsAccess.isEmpty }

    func refresh(force: Bool = false) {
        if let lastScan, !force, Date().timeIntervalSince(lastScan) < minimumInterval { return }
        guard inFlight == nil else { return }

        var roots: [AgentTool: URL] = [:]
        for tool in AgentTool.allCases {
            roots[tool] = AgentFolderAccess.grantedURL(for: tool)
        }
        guard !roots.isEmpty else { return }

        isScanning = true
        let reader = AgentActivityReader(roots: roots)
        inFlight = Task {
            let tools = await reader.availableTools()
            let found = await reader.summaries { snapshot in
                Task { @MainActor [weak self] in
                    guard snapshot.total > 0 else { return }
                    self?.progress = Double(snapshot.parsed + snapshot.reused) / Double(snapshot.total)
                }
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.available = tools
                self.summaries = found
                if !tools.contains(self.selected), let first = tools.first {
                    self.selected = first
                }
                self.lastScan = Date()
                self.isScanning = false
                self.progress = nil
                self.inFlight = nil
            }
        }
    }
}
