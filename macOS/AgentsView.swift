import SwiftUI
import DunduKit

/// Coding activity in the notch: which tool, what it has used, how long the
/// run is, and a year of days behind it.
struct AgentsView: View {
    @Bindable var model: AgentActivityModel
    var watcher = AgentSessionWatcher.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
            if model.available.count > 1 {
                toolPicker
            }

            // What is happening right now sits above what has happened
            // historically: a session waiting on you is the only thing on
            // this page that is actually asking for something.
            if !watcher.sessions.isEmpty {
                liveSessions
                Divider().opacity(0.25)
            }

            if let summary = model.summary {
                stats(summary)
                YearHeatmap(dayCounts: summary.dayCounts)
                footer(summary)
                // Offered alongside the data, not instead of it: one tool
                // being unconnected is no reason to hide the one that is.
                if !model.needsAccess.isEmpty {
                    connectRow
                }
            } else if model.isScanning {
                scanning
            } else if !model.needsAccess.isEmpty {
                connectPrompt
            } else {
                Text("No Claude Code or Codex activity found on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, Tokens.Spacing.lg)
        .task { model.refresh() }
    }

    /// Dundu is sandboxed and cannot see ~/.claude until it is pointed there.
    private var connectPrompt: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
            Text("Dundu reads activity your coding tools already keep on this Mac. Counts and timestamps only — never your prompts.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Tokens.Spacing.sm) {
                ForEach(model.needsAccess, id: \.self) { tool in
                    Button("Connect \(tool.displayName)") { model.connect(tool) }
                        .controlSize(.small)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var liveSessions: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(watcher.sessions.prefix(3)) { session in
                HStack(spacing: Tokens.Spacing.sm) {
                    Circle()
                        .fill(Self.stateColor(session.state))
                        .frame(width: 6, height: 6)
                    Text(session.task ?? session.projectName ?? "Session")
                        .font(.caption)
                        .lineLimit(1)
                    Spacer(minLength: Tokens.Spacing.xs)
                    Text(Self.stateLabel(session.state))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            if watcher.sessions.count > 3 {
                Text("+\(watcher.sessions.count - 3) more")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    static func stateColor(_ state: AgentSessionState) -> Color {
        switch state {
        case .waiting: Tokens.Colors.dueSoon
        case .working: Tokens.Colors.accent
        case .done: Tokens.Colors.hueDone
        }
    }

    static func stateLabel(_ state: AgentSessionState) -> String {
        switch state {
        case .waiting: "needs you"
        case .working: "working"
        case .done: "done"
        }
    }

    private var connectRow: some View {
        HStack(spacing: Tokens.Spacing.sm) {
            ForEach(model.needsAccess, id: \.self) { tool in
                Button("Connect \(tool.displayName)") { model.connect(tool) }
                    .buttonStyle(.link)
                    .font(.system(size: 9))
            }
            Spacer()
        }
    }

    private var toolPicker: some View {
        HStack(spacing: 4) {
            ForEach(model.available, id: \.self) { tool in
                let isOn = model.selected == tool
                Button {
                    model.selected = tool
                } label: {
                    Text(tool.displayName)
                        .font(.caption.weight(isOn ? .semibold : .regular))
                        .foregroundStyle(isOn ? Color.primary : .secondary)
                        .padding(.horizontal, Tokens.Spacing.sm)
                        .padding(.vertical, 3)
                        .background {
                            if isOn {
                                Capsule().fill(.quaternary)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
            Spacer()
            if model.isScanning {
                ProgressView().controlSize(.mini)
            }
        }
    }

    private func stats(_ summary: AgentSummary) -> some View {
        HStack(alignment: .top, spacing: Tokens.Spacing.md) {
            stat(Self.compact(summary.billableTokens), "tokens")
            stat("\(summary.sessions)", "sessions")
            stat(Self.compact(summary.toolCalls), "tool calls")
            stat("\(summary.currentStreak)", summary.currentStreak == 1 ? "day streak" : "day streak")
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.callout.bold().monospacedDigit())
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func footer(_ summary: AgentSummary) -> some View {
        HStack(spacing: Tokens.Spacing.xs) {
            if let model = summary.topModel {
                Text(Self.shortModel(model))
            }
            if summary.topModel != nil, summary.lastActive != nil {
                Text("·")
            }
            if let last = summary.lastActive {
                Text(Formatters.relativeTime(to: last))
            }
            Spacer()
            Text("\(summary.activeDays) active days")
        }
        .font(.system(size: 9))
        .foregroundStyle(.tertiary)
    }

    private var scanning: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
            Text("Reading transcripts…")
                .font(.caption)
                .foregroundStyle(.secondary)
            // The first scan walks gigabytes; after that the cache makes it
            // near-instant, so this bar is only ever seen once.
            ProgressView(value: model.progress ?? 0)
                .controlSize(.small)
        }
    }

    /// Token counts run to tens of millions, which is unreadable in full and
    /// pointless at that precision.
    static func compact(_ value: Int) -> String {
        switch value {
        case 1_000_000...: String(format: "%.1fM", Double(value) / 1_000_000)
        case 1_000...: String(format: "%.1fk", Double(value) / 1_000)
        default: "\(value)"
        }
    }

    /// "claude-opus-5" reads better than the full identifier in 9pt type.
    static func shortModel(_ identifier: String) -> String {
        identifier
            .replacingOccurrences(of: "claude-", with: "")
            .replacingOccurrences(of: "-20", with: " ")
    }
}

/// A year of days, GitHub-style: 53 weeks across, seven days down.
struct YearHeatmap: View {
    let dayCounts: [String: Int]
    var weeks: Int = 53

    /// Sized so the whole year fits the notch panel's 380pt width.
    private let cell: CGFloat = 4
    private let gap: CGFloat = 1.5

    var body: some View {
        let grid = Self.grid(dayCounts: dayCounts, weeks: weeks)
        HStack(spacing: gap) {
            ForEach(Array(grid.enumerated()), id: \.offset) { _, column in
                VStack(spacing: gap) {
                    ForEach(Array(column.enumerated()), id: \.offset) { _, level in
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(Self.color(level))
                            .frame(width: cell, height: cell)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("A year of coding activity")
    }

    /// Columns of seven, oldest first, ending on today's week.
    static func grid(
        dayCounts: [String: Int],
        weeks: Int,
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> [[Int]] {
        // Start on the Sunday that begins the week `weeks - 1` back, so the
        // last column is the current, possibly partial, week.
        let weekday = calendar.component(.weekday, from: today) - 1
        guard let endOfGrid = calendar.date(byAdding: .day, value: -weekday, to: today),
              let start = calendar.date(byAdding: .day, value: -7 * (weeks - 1), to: endOfGrid)
        else { return [] }

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

    /// Sessions per day, bucketed. A heavy day is several sessions, not
    /// several hundred, so the top bucket arrives quickly.
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
        case 1: Tokens.Colors.hueDone.opacity(0.35)
        case 2: Tokens.Colors.hueDone.opacity(0.55)
        case 3: Tokens.Colors.hueDone.opacity(0.75)
        case 4: Tokens.Colors.hueDone
        default: Color.secondary.opacity(0.15)
        }
    }
}
