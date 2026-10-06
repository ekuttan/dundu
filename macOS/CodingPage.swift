import SwiftUI
import DunduKit

/// Coding activity: which tool, what it is doing right now, what it has
/// burned through, and a year of days behind it.
struct CodingPage: View {
    @Bindable var model: AgentActivityModel
    var watcher = AgentSessionWatcher.shared

    var body: some View {
        VStack(alignment: .leading, spacing: NP.gridGap) {
            NPPageHeader(title: "Coding") {
                if model.available.count + model.needsAccess.count > 1 {
                    NPSegmented(
                        items: AgentTool.allCases,
                        title: { $0.displayName },
                        icon: { Self.icon(for: $0) },
                        selection: $model.selected
                    )
                }
            }

            statusLine

            if !watcher.sessions.isEmpty {
                liveSessions
            }

            if let summary = model.summary {
                stats(summary)
                // Fixed to the grid's own height: letting the card stretch
                // leaves a hand's width of empty card under the last row.
                heatmap(summary).frame(height: 150)
                Spacer(minLength: 0)
            } else if model.isScanning {
                scanning
            } else if !model.needsAccess.isEmpty {
                connectPrompt
            } else {
                NPEmpty(
                    icon: "chevron.left.forwardslash.chevron.right",
                    text: "No \(model.selected.displayName) activity found on this Mac."
                )
            }
        }
        .task { model.refresh() }
    }

    /// "~/.claude" — where the numbers came from, so the card can be
    /// checked against the filesystem.
    static func folderHint(_ tool: AgentTool) -> String {
        "~/" + AgentFolderAccess.defaultPath(for: tool).lastPathComponent
    }

    static func icon(for tool: AgentTool) -> String {
        switch tool {
        case .claudeCode: "sparkle"
        case .codex: "circle.grid.cross"
        }
    }

    // MARK: - Status

    private var isConnected: Bool { !model.needsAccess.contains(model.selected) }

    private var statusLine: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isConnected ? NP.C.good : NP.C.faint)
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    Text(model.summary?.topModel.map(Self.shortModel) ?? model.selected.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NP.C.text)
                    Text("(CLI)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(NP.C.faint)
                }
                Text(syncedLine)
                    .font(NP.F.caption)
                    .foregroundStyle(NP.C.faint)
            }

            Spacer()

            if model.isScanning {
                ProgressView().controlSize(.small).scaleEffect(0.7)
            }
            NPButton(title: "Sync", icon: "arrow.triangle.2.circlepath") {
                model.refresh(force: true)
            }
            if isConnected {
                NPButton(title: "Disconnect", kind: .danger) {
                    model.disconnect(model.selected)
                }
            } else {
                NPButton(title: "Connect", kind: .primary) {
                    model.connect(model.selected)
                }
            }
        }
        .frame(height: 34)
    }

    private var syncedLine: String {
        guard isConnected else { return "Not connected — Dundu cannot see this tool's folder yet" }
        guard let last = model.lastScan else { return "Reading…" }
        // "in 0 sec" is what the relative formatter says about a scan that
        // just finished, which is exactly when this line is most often read.
        if Date().timeIntervalSince(last) < 60 { return "Synced just now" }
        return "Synced \(Formatters.relativeTime(to: last))"
    }

    // MARK: - Live sessions

    private var liveSessions: some View {
        HStack(spacing: NP.gridGap) {
            ForEach(watcher.sessions.prefix(3)) { session in
                NPCard(padding: 9) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(Self.stateColor(session.state))
                                .frame(width: 5, height: 5)
                            Text(Self.stateLabel(session.state).uppercased())
                                .font(NP.F.label)
                                .tracking(0.7)
                                .foregroundStyle(Self.stateColor(session.state))
                            Spacer(minLength: 4)
                            Text(session.projectName ?? "")
                                .font(NP.F.caption)
                                .foregroundStyle(NP.C.faint)
                                .lineLimit(1)
                        }
                        Text(session.task ?? session.projectName ?? "Session")
                            .font(NP.F.row)
                            .foregroundStyle(NP.C.text)
                            .lineLimit(1)
                    }
                }
            }
            if watcher.sessions.count > 3 {
                Text("+\(watcher.sessions.count - 3)")
                    .font(NP.F.caption)
                    .foregroundStyle(NP.C.faint)
                    .frame(width: 30)
            }
        }
        .frame(height: 48)
    }

    static func stateColor(_ state: AgentSessionState) -> Color {
        switch state {
        case .waiting: NP.C.warn
        case .working: NP.C.good
        case .done: NP.C.info
        }
    }

    static func stateLabel(_ state: AgentSessionState) -> String {
        switch state {
        case .waiting: "needs you"
        case .working: "working"
        case .done: "done"
        }
    }

    // MARK: - Stats

    private func stats(_ summary: AgentSummary) -> some View {
        HStack(spacing: NP.gridGap) {
            NPStatCard(
                label: "Tokens burned",
                value: Self.compact(summary.billableTokens),
                caption: summary.topModel.map { "On \(Self.shortModel($0))" } ?? "Across every session"
            )
            NPStatCard(
                label: "Active streak",
                value: "\(summary.currentStreak) days",
                caption: summary.longestStreak > summary.currentStreak
                    ? "Best \(summary.longestStreak) days"
                    : "Consecutive coding",
                valueTint: summary.currentStreak > 0 ? NP.C.ember : NP.C.text
            )
            NPCard(padding: 11) {
                VStack(spacing: 4) {
                    miniRow("Tools", Self.compact(summary.toolCalls))
                    miniRow("Msgs", Self.compact(summary.messages))
                    miniRow("Sessions", "\(summary.sessions)")
                }
                .frame(maxHeight: .infinity)
            }
            .frame(width: 180)
        }
        .frame(height: 86)
    }

    private func miniRow(_ label: String, _ value: String) -> some View {
        HStack {
            NPLabel(label)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(NP.C.text)
        }
    }

    // MARK: - Heatmap

    private func heatmap(_ summary: AgentSummary) -> some View {
        NPCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    NPLabel("Activity heatmap", icon: "flame.fill", tint: NP.C.ember)
                    Spacer()
                    HStack(spacing: 4) {
                        Text("Less").font(NP.F.caption).foregroundStyle(NP.C.faint)
                        ForEach(1...4, id: \.self) { level in
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(YearHeatmap.color(level))
                                .frame(width: 7, height: 7)
                        }
                        Text("More").font(NP.F.caption).foregroundStyle(NP.C.faint)
                        Text("· \(Self.folderHint(model.selected))")
                            .font(NP.F.caption)
                            .foregroundStyle(NP.C.faint)
                    }
                }
                YearHeatmap(dayCounts: summary.dayCounts)
            }
        }
    }

    // MARK: - States

    private var scanning: some View {
        NPCard {
            VStack(alignment: .leading, spacing: 8) {
                NPLabel("Reading transcripts")
                // The first scan walks gigabytes; after that the cache makes
                // it near-instant, so this bar is only ever seen once.
                ProgressView(value: model.progress ?? 0)
                    .controlSize(.small)
                    .tint(NP.C.ember)
                Text("Counts and timestamps only — never your prompts.")
                    .font(NP.F.caption)
                    .foregroundStyle(NP.C.faint)
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }

    /// Dundu is sandboxed and cannot see the transcript folders until it is
    /// pointed at them.
    private var connectPrompt: some View {
        NPCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Connect your coding tools")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(NP.C.text)
                Text("Dundu reads the activity your coding tools already keep on this Mac. Counts and timestamps only — never your prompts.")
                    .font(NP.F.caption)
                    .foregroundStyle(NP.C.dim)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    ForEach(model.needsAccess, id: \.self) { tool in
                        NPButton(
                            title: "Connect \(tool.displayName)",
                            icon: Self.icon(for: tool),
                            kind: .primary
                        ) { model.connect(tool) }
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }

    // MARK: - Formatting

    /// Token counts run to tens of millions, which is unreadable in full and
    /// pointless at that precision.
    static func compact(_ value: Int) -> String {
        switch value {
        case 1_000_000...: String(format: "%.1fM", Double(value) / 1_000_000)
        case 10_000...: String(format: "%.0fk", Double(value) / 1_000)
        case 1_000...: String(format: "%.1fk", Double(value) / 1_000)
        default: "\(value)"
        }
    }

    /// "Claude Opus" reads better than "claude-opus-5-20260101" in 12pt type.
    static func shortModel(_ identifier: String) -> String {
        let trimmed = identifier
            .replacingOccurrences(of: #"-20\d{6}$"#, with: "", options: .regularExpression)
        return trimmed
            .split(separator: "-")
            .map { $0.count <= 2 ? String($0) : $0.capitalized }
            .joined(separator: " ")
    }
}

/// A year of days, GitHub-style: 53 weeks across, seven days down, with the
/// month and weekday rails the reference has.
struct YearHeatmap: View {
    let dayCounts: [String: Int]
    var weeks: Int = 53

    private let cell: CGFloat = 10
    private let gap: CGFloat = 2.6
    private let railWidth: CGFloat = 32

    var body: some View {
        let grid = Self.grid(dayCounts: dayCounts, weeks: weeks)
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 0) {
                // Height pinned: an unconstrained Color.clear is greedy in
                // the free axis and would push the grid to the bottom of the
                // card.
                Color.clear.frame(width: railWidth, height: 11)
                monthRail(columns: grid.count)
            }
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: gap) {
                    ForEach(0..<7, id: \.self) { row in
                        Text(Self.weekdayRail[row])
                            .font(NP.F.caption)
                            .foregroundStyle(NP.C.faint)
                            .frame(width: railWidth - 6, height: cell, alignment: .leading)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                HStack(spacing: gap) {
                    ForEach(Array(grid.enumerated()), id: \.offset) { _, column in
                        VStack(spacing: gap) {
                            ForEach(Array(column.enumerated()), id: \.offset) { _, level in
                                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                    .fill(Self.color(level))
                                    .frame(width: cell, height: cell)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("A year of coding activity")
    }

    /// Only alternate weekdays are labelled — seven labels at this size is a
    /// wall of text next to a chart made of 10pt squares.
    static let weekdayRail = ["", "Mon", "", "Wed", "", "Fri", ""]

    /// A month name over the column where that month starts.
    private func monthRail(columns: Int) -> some View {
        HStack(spacing: gap) {
            ForEach(0..<columns, id: \.self) { index in
                Text(Self.monthLabel(forColumn: index, of: columns))
                    .font(NP.F.caption)
                    .foregroundStyle(NP.C.faint)
                    .fixedSize()
                    .frame(width: cell, height: 11, alignment: .leading)
            }
        }
    }

    /// The label belongs to the first column whose Sunday falls in a new
    /// month, which is how GitHub places them.
    static func monthLabel(
        forColumn index: Int,
        of columns: Int,
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        guard let start = gridStart(weeks: columns, today: today, calendar: calendar),
              let date = calendar.date(byAdding: .day, value: index * 7, to: start)
        else { return "" }
        let month = calendar.component(.month, from: date)
        if index > 0 {
            guard let previous = calendar.date(byAdding: .day, value: (index - 1) * 7, to: start),
                  calendar.component(.month, from: previous) != month
            else { return "" }
        }
        // A label in the last column or two would be clipped by the card.
        guard index < columns - 2 else { return "" }
        return calendar.shortMonthSymbols[month - 1]
    }

    static func gridStart(weeks: Int, today: Date, calendar: Calendar) -> Date? {
        let weekday = calendar.component(.weekday, from: today) - 1
        guard let endOfGrid = calendar.date(byAdding: .day, value: -weekday, to: today) else {
            return nil
        }
        return calendar.date(byAdding: .day, value: -7 * (weeks - 1), to: endOfGrid)
    }

    /// Columns of seven, oldest first, ending on today's week.
    static func grid(
        dayCounts: [String: Int],
        weeks: Int,
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> [[Int]] {
        guard let start = gridStart(weeks: weeks, today: today, calendar: calendar) else { return [] }

        var columns: [[Int]] = []
        for week in 0..<weeks {
            var column: [Int] = []
            for day in 0..<7 {
                guard let date = calendar.date(
                    byAdding: .day, value: week * 7 + day, to: start
                ) else { column.append(0); continue }
                // Days that have not happened yet are blank, not level zero.
                if date > today { column.append(-1); continue }
                let key = ActivityStreak.key(for: date, calendar: calendar)
                column.append(level(for: dayCounts[key] ?? 0))
            }
            columns.append(column)
        }
        return columns
    }

    /// Sessions per day, bucketed. `dayCounts` counts sessions, not
    /// messages: a heavy day is a handful of them, not hundreds, so the top
    /// bucket has to arrive quickly or every day reads as the faintest shade.
    static func level(for count: Int) -> Int {
        switch count {
        case 0: 0
        case 1: 1
        case 2...3: 2
        case 4...6: 3
        default: 4
        }
    }

    static func color(_ level: Int) -> Color {
        switch level {
        case -1: .clear
        case 1: NP.C.ember.opacity(0.28)
        case 2: NP.C.ember.opacity(0.50)
        case 3: NP.C.ember.opacity(0.74)
        case 4: NP.C.ember
        default: Color.white.opacity(0.07)
        }
    }
}
