import AppKit
import DunduKit

/// One-time, user-granted access to the AI coding transcript folders.
///
/// Dundu is sandboxed, so its idea of home is
/// `~/Library/Containers/app.scoop.dundu.mac/Data` and `~/.claude` simply does
/// not exist from inside. No amount of path spelling gets around that — the
/// only sandbox-legal route is the user pointing at the folder once, which
/// hands back a security-scoped bookmark we can reopen on every launch.
@MainActor
enum AgentFolderAccess {
    /// The real home, not the container's. `homeDirectoryForCurrentUser`
    /// returns the sandbox root, which is useless for showing the user where
    /// their own files are.
    static var realHome: URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir))
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    static func defaultPath(for tool: AgentTool) -> URL {
        switch tool {
        case .claudeCode: realHome.appending(path: ".claude/projects")
        case .codex: realHome.appending(path: ".codex/sessions")
        }
    }

    private static func key(for tool: AgentTool) -> String {
        "agentFolderBookmark.\(tool.rawValue)"
    }

    /// Bookmarks resolved this launch, kept so access stays open. Dropping the
    /// URL stops the security scope and the next read fails.
    private static var open: [AgentTool: URL] = [:]

    static func grantedURL(for tool: AgentTool) -> URL? {
        if let existing = open[tool] { return existing }
        guard let data = UserDefaults.standard.data(forKey: key(for: tool)) else { return nil }

        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return nil }

        guard url.startAccessingSecurityScopedResource() else { return nil }
        if stale { store(url, for: tool) }
        open[tool] = url
        return url
    }

    /// Asks for the folder. Returns nil if the user cancels or picks
    /// something that plainly isn't the right directory.
    static func requestAccess(for tool: AgentTool) -> URL? {
        // The panel belongs to an app with no Dock icon and a nonactivating
        // panel, so it has to be brought forward deliberately or it opens
        // behind everything.
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = defaultPath(for: tool)
        panel.prompt = "Allow"
        panel.message = """
            Choose \(defaultPath(for: tool).path) so Dundu can read \
            \(tool.displayName) activity. Only counts and timestamps are read — \
            never your prompts.
            """

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        guard url.startAccessingSecurityScopedResource() else { return nil }
        store(url, for: tool)
        open[tool] = url
        return url
    }

    static func forget(_ tool: AgentTool) {
        open[tool]?.stopAccessingSecurityScopedResource()
        open[tool] = nil
        UserDefaults.standard.removeObject(forKey: key(for: tool))
    }

    private static func store(_ url: URL, for tool: AgentTool) {
        guard let data = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }
        UserDefaults.standard.set(data, forKey: key(for: tool))
    }
}
