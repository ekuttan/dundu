import Foundation

/// Reads the AI coding transcripts already on this Mac and rolls them into
/// per-tool summaries.
///
/// The transcripts are large — gigabytes across thousands of append-only
/// files, with single sessions over 100 MB — so two things are load-bearing.
/// Files are streamed a chunk at a time rather than read whole, and each
/// file's digest is cached against its size and modification date, so a
/// refresh re-parses only what actually changed. In steady use that is the
/// one session currently being written.
public actor AgentActivityReader {
    public struct Progress: Sendable {
        public var parsed: Int
        public var total: Int
        public var reused: Int
    }

    private struct CacheEntry: Codable {
        var modified: Date
        var size: Int
        var digest: SessionDigest
    }

    /// Supplied by the caller rather than derived from the home directory:
    /// a sandboxed app's home is its container, so only the host knows where
    /// the real transcript folders are and whether it may read them.
    private let roots: [AgentTool: URL]
    private let cacheURL: URL
    private var cache: [String: CacheEntry] = [:]
    private var loadedCache = false

    public init(roots: [AgentTool: URL], cacheURL: URL? = nil) {
        self.roots = roots
        // Application Support rather than a hand-built home path: it is the
        // right place on both platforms, and on iOS there is no home to ask
        // for anyway.
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        self.cacheURL = cacheURL
            ?? support?.appending(path: "Dundu/agent-activity.json")
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "dundu-agent-activity.json")
    }

    #if os(macOS)
    /// Convenience for callers outside the sandbox — command line tools and
    /// anything run straight from a shell. The app proper is sandboxed and
    /// must be handed user-granted roots instead.
    public static func atDefaultLocations() -> AgentActivityReader {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return AgentActivityReader(roots: [
            .claudeCode: home.appending(path: ".claude/projects"),
            .codex: home.appending(path: ".codex/sessions"),
        ])
    }
    #endif

    /// Whether either tool has anything on this Mac, so the UI can stay out
    /// of the way entirely rather than showing four empty dials.
    public func availableTools() -> [AgentTool] {
        AgentTool.allCases.filter { tool in
            guard let root = roots[tool] else { return false }
            return FileManager.default.fileExists(atPath: root.path)
        }
    }

    public func summaries(
        today: Date = Date(),
        onProgress: (@Sendable (Progress) -> Void)? = nil
    ) async -> [AgentTool: AgentSummary] {
        loadCacheIfNeeded()

        var digests: [AgentTool: [SessionDigest]] = [:]
        let work = AgentTool.allCases.flatMap(transcripts)
        var parsed = 0
        var reused = 0

        for file in work {
            if Task.isCancelled { break }
            let digest = digest(for: file, reusedCount: &reused, parsedCount: &parsed)
            digests[file.tool, default: []].append(digest)
            onProgress?(Progress(parsed: parsed, total: work.count, reused: reused))
        }

        saveCache()

        return digests.reduce(into: [:]) { result, pair in
            result[pair.key] = AgentSummary.rolledUp(
                tool: pair.key, digests: pair.value, today: today
            )
        }
    }

    // MARK: - Files

    private struct Transcript {
        let url: URL
        let tool: AgentTool
        /// Claude files sit one directory below a project slug; Codex records
        /// its working directory inside the file instead.
        let project: String?
    }

    private func transcripts(_ tool: AgentTool) -> [Transcript] {
        guard let root = roots[tool] else { return [] }
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var found: [Transcript] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let project = tool == .claudeCode
                ? Self.readableProject(from: url.deletingLastPathComponent().lastPathComponent)
                : nil
            found.append(Transcript(url: url, tool: tool, project: project))
        }
        return found
    }

    /// Claude encodes a project path as a slug like
    /// `-Users-me-Code-dundu`; the last segment is the part worth showing.
    static func readableProject(from slug: String) -> String {
        slug.split(separator: "-").last.map(String.init) ?? slug
    }

    private func digest(
        for file: Transcript,
        reusedCount: inout Int,
        parsedCount: inout Int
    ) -> SessionDigest {
        let key = file.url.path
        let attributes = try? FileManager.default.attributesOfItem(atPath: key)
        let modified = attributes?[.modificationDate] as? Date ?? .distantPast
        let size = attributes?[.size] as? Int ?? 0

        if let cached = cache[key], cached.size == size,
           abs(cached.modified.timeIntervalSince(modified)) < 1 {
            reusedCount += 1
            return cached.digest
        }

        let sessionID = file.url.deletingPathExtension().lastPathComponent
        let lines = Self.lines(of: file.url)
        let digest: SessionDigest = switch file.tool {
        case .claudeCode:
            AgentLogParser.parseClaudeCode(
                lines: lines, sessionID: sessionID, project: file.project
            )
        case .codex:
            AgentLogParser.parseCodex(lines: lines, sessionID: sessionID)
        }

        cache[key] = CacheEntry(modified: modified, size: size, digest: digest)
        parsedCount += 1
        return digest
    }

    /// Streams the file in chunks. A single transcript can exceed 100 MB, and
    /// reading one into a String costs that much resident memory per file.
    static func lines(of url: URL) -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }

        var lines: [String] = []
        var remainder = Data()
        let newline = UInt8(ascii: "\n")

        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            remainder.append(chunk)
            while let index = remainder.firstIndex(of: newline) {
                let slice = remainder[remainder.startIndex..<index]
                if let line = String(data: slice, encoding: .utf8), !line.isEmpty {
                    lines.append(line)
                }
                remainder = remainder[remainder.index(after: index)...]
            }
        }
        if !remainder.isEmpty, let line = String(data: remainder, encoding: .utf8), !line.isEmpty {
            lines.append(line)
        }
        return lines
    }

    // MARK: - Cache

    private func loadCacheIfNeeded() {
        guard !loadedCache else { return }
        loadedCache = true
        guard let data = try? Data(contentsOf: cacheURL) else { return }
        cache = (try? JSONDecoder().decode([String: CacheEntry].self, from: data)) ?? [:]
    }

    private func saveCache() {
        let directory = cacheURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }
}
