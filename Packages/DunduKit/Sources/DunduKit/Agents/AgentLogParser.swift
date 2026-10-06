import Foundation

/// Turns one session transcript into a digest. Pure: it takes lines and
/// returns numbers, so it can be tested without a gigabyte of real logs.
///
/// Nothing here reads prompt or completion text. Only usage counts, model
/// names, tool-call counts and timestamps are extracted.
public enum AgentLogParser {
    /// Claude Code writes `~/.claude/projects/<slug>/<session>.jsonl`, one
    /// JSON object per line. Assistant messages carry `message.usage`.
    public static func parseClaudeCode(
        lines: [String],
        sessionID: String,
        project: String?,
        calendar: Calendar = .current
    ) -> SessionDigest {
        var digest = SessionDigest(sessionID: sessionID, tool: .claudeCode, project: project)

        for line in lines {
            guard let object = jsonObject(line) else { continue }

            if let stamp = timestamp(object["timestamp"]) {
                digest.firstActivity = min(digest.firstActivity ?? stamp, stamp)
                digest.lastActivity = max(digest.lastActivity ?? stamp, stamp)
                digest.activeDays.insert(ActivityStreak.key(for: stamp, calendar: calendar))
            }

            guard let message = object["message"] as? [String: Any] else { continue }
            if object["type"] as? String == "assistant" { digest.messages += 1 }

            if let model = message["model"] as? String, !model.isEmpty {
                digest.models[model, default: 0] += 1
            }

            if let usage = message["usage"] as? [String: Any] {
                digest.inputTokens += int(usage["input_tokens"])
                digest.outputTokens += int(usage["output_tokens"])
                digest.cachedTokens += int(usage["cache_read_input_tokens"])
                    + int(usage["cache_creation_input_tokens"])
            }

            if let content = message["content"] as? [[String: Any]] {
                digest.toolCalls += content.count { $0["type"] as? String == "tool_use" }
            }
        }

        return digest
    }

    /// Codex writes `~/.codex/sessions/<year>/.../rollout-*.jsonl`.
    ///
    /// Its two token fields are named the opposite way round to how they
    /// behave: `usage` is the per-turn delta and `turn_token_usage` is the
    /// cumulative running total. Summing the cumulative one turns a 90k-token
    /// session into billions, so the last cumulative record wins, with the
    /// per-turn sum as the fallback when no cumulative figure is present.
    public static func parseCodex(
        lines: [String],
        sessionID: String,
        calendar: Calendar = .current
    ) -> SessionDigest {
        var digest = SessionDigest(sessionID: sessionID, tool: .codex)
        var perTurn = (input: 0, output: 0, cached: 0)
        var cumulative: (input: Int, output: Int, cached: Int)?

        for line in lines {
            guard let object = jsonObject(line) else { continue }

            if let stamp = timestamp(object["timestamp"]) {
                digest.firstActivity = min(digest.firstActivity ?? stamp, stamp)
                digest.lastActivity = max(digest.lastActivity ?? stamp, stamp)
                digest.activeDays.insert(ActivityStreak.key(for: stamp, calendar: calendar))
            }

            let payload = object["payload"] as? [String: Any]

            switch object["type"] as? String {
            case "session_meta":
                digest.project = payload?["cwd"] as? String ?? digest.project

            case "turn_context":
                if let model = payload?["model"] as? String, !model.isEmpty {
                    digest.models[model, default: 0] += 1
                }

            case "response_item":
                // Codex records a tool call as a function_call response item.
                if let kind = payload?["type"] as? String,
                   kind == "function_call" || kind == "local_shell_call" {
                    digest.toolCalls += 1
                }

            case "token_usage_record":
                digest.messages += 1
                if let turn = payload?["usage"] as? [String: Any] {
                    perTurn.input += int(turn["input_tokens"])
                    perTurn.output += int(turn["output_tokens"])
                    perTurn.cached += int(turn["cached_input_tokens"])
                        + int(turn["cache_write_input_tokens"])
                }
                if let running = payload?["turn_token_usage"] as? [String: Any] {
                    cumulative = (
                        int(running["input_tokens"]),
                        int(running["output_tokens"]),
                        int(running["cached_input_tokens"])
                            + int(running["cache_write_input_tokens"])
                    )
                }

            default:
                break
            }
        }

        let totals = cumulative ?? perTurn
        digest.inputTokens = totals.input
        digest.outputTokens = totals.output
        digest.cachedTokens = totals.cached
        return digest
    }

    // MARK: - Helpers

    private static func jsonObject(_ line: String) -> [String: Any]? {
        guard !line.isEmpty, let data = line.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func int(_ value: Any?) -> Int {
        (value as? Int) ?? (value as? Double).map(Int.init) ?? 0
    }

    nonisolated(unsafe) private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let isoPlain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static func timestamp(_ value: Any?) -> Date? {
        guard let raw = value as? String else { return nil }
        return iso.date(from: raw) ?? isoPlain.date(from: raw)
    }
}

private extension Array {
    func count(where predicate: (Element) -> Bool) -> Int {
        reduce(0) { predicate($1) ? $0 + 1 : $0 }
    }
}
