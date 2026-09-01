import Foundation

/// Dundu's MCP server: lets Claude put reminders on the user's devices.
///
/// It writes to Apple Reminders through EventKit rather than to Dundu's own
/// store. Reminders is the substrate both already share — iCloud carries it
/// to the phone, and Dundu ingests from EventKit on its next pass, so an item
/// added here arrives everywhere through the ordinary sync path instead of a
/// second process reaching into a sandboxed SwiftData container.
///
/// Transport is newline-delimited JSON-RPC 2.0 on stdin/stdout. Anything
/// written to stdout that is not a response corrupts the stream, so all
/// logging goes to stderr.

let store = RemindersStore()

func log(_ message: String) {
    FileHandle.standardError.write(Data("[dundu-mcp] \(message)\n".utf8))
}

func send(_ payload: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

func respond(id: Any, result: [String: Any]) {
    send(["jsonrpc": "2.0", "id": id, "result": result])
}

func respond(id: Any, error message: String, code: Int = -32603) {
    send(["jsonrpc": "2.0", "id": id, "message": message,
          "error": ["code": code, "message": message]])
}

/// A tool result. `isError` is how MCP reports a failure the model should
/// read and react to, as opposed to a protocol-level error.
func toolResult(_ text: String, isError: Bool = false) -> [String: Any] {
    ["content": [["type": "text", "text": text]], "isError": isError]
}

func json<T: Encodable>(_ value: T) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(value),
          let text = String(data: data, encoding: .utf8) else { return "[]" }
    return text
}

// MARK: - Tools

let toolDefinitions: [[String: Any]] = [
    [
        "name": "add_reminder",
        "description": """
            Add a reminder to Apple Reminders on this Mac. It syncs to the \
            user's iPhone via iCloud and appears in Dundu on the next sync. \
            Use list_lists first if the user names a list you haven't seen.
            """,
        "inputSchema": [
            "type": "object",
            "properties": [
                "title": ["type": "string", "description": "What the reminder says."],
                "notes": ["type": "string", "description": "Optional longer detail."],
                "due": [
                    "type": "string",
                    "description": "Optional due date. ISO 8601 (2026-08-17T09:00:00Z), \"2026-08-17 09:00\", or \"2026-08-17\" for a whole day.",
                ],
                "list": [
                    "type": "string",
                    "description": "Optional list name, e.g. \"Hoomans\". Case-insensitive. Defaults to the user's default list.",
                ],
                "priority": [
                    "type": "integer",
                    "description": "Optional. 1 high, 5 medium, 9 low, 0 none — EventKit's scale.",
                ],
            ],
            "required": ["title"],
        ],
    ],
    [
        "name": "list_reminders",
        "description": "Read reminders from Apple Reminders, soonest due first.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "list": ["type": "string", "description": "Optional list name to limit to."],
                "include_completed": [
                    "type": "boolean",
                    "description": "Defaults to false — open reminders only.",
                ],
            ],
        ],
    ],
    [
        "name": "list_lists",
        "description": "The user's reminder lists, and which one is the default.",
        "inputSchema": ["type": "object", "properties": [:]],
    ],
    [
        "name": "complete_reminder",
        "description": "Mark a reminder done. Takes the id from list_reminders.",
        "inputSchema": [
            "type": "object",
            "properties": ["id": ["type": "string", "description": "Reminder id."]],
            "required": ["id"],
        ],
    ],
]

func call(tool name: String, arguments: [String: Any]) async -> [String: Any] {
    do {
        switch name {
        case "add_reminder":
            guard let title = (arguments["title"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
                return toolResult("add_reminder needs a non-empty title.", isError: true)
            }
            let parsed = try (arguments["due"] as? String).map(DateText.parse)
            let saved = try await store.add(
                title: title,
                notes: arguments["notes"] as? String,
                due: parsed?.date,
                includesTime: parsed?.includesTime ?? false,
                listName: arguments["list"] as? String,
                priority: arguments["priority"] as? Int
            )
            return toolResult("Added to \(saved.list).\n\(json(saved))")

        case "list_reminders":
            let found = try await store.reminders(
                listName: arguments["list"] as? String,
                includeCompleted: arguments["include_completed"] as? Bool ?? false
            )
            return toolResult(found.isEmpty ? "No matching reminders." : json(found))

        case "list_lists":
            return toolResult(json(try await store.lists()))

        case "complete_reminder":
            guard let id = arguments["id"] as? String else {
                return toolResult("complete_reminder needs an id.", isError: true)
            }
            return toolResult("Completed.\n\(json(try await store.complete(id: id)))")

        default:
            return toolResult("Unknown tool: \(name)", isError: true)
        }
    } catch {
        let reason = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        return toolResult(reason, isError: true)
    }
}

// MARK: - Loop

log("ready")

while let line = readLine(strippingNewline: true) {
    guard !line.trimmingCharacters(in: .whitespaces).isEmpty,
          let data = line.data(using: .utf8),
          let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let method = message["method"] as? String else { continue }

    // No id means a notification: act on it, answer nothing.
    guard let id = message["id"] else {
        log("notification: \(method)")
        continue
    }

    switch method {
    case "initialize":
        let params = message["params"] as? [String: Any]
        // Echo the client's protocol version when it names one; guessing a
        // newer version than the client speaks is how handshakes fail.
        let version = (params?["protocolVersion"] as? String) ?? "2024-11-05"
        respond(id: id, result: [
            "protocolVersion": version,
            "capabilities": ["tools": [:] as [String: Any]],
            "serverInfo": ["name": "dundu", "version": "1.0.0"],
        ])

    case "tools/list":
        respond(id: id, result: ["tools": toolDefinitions])

    case "tools/call":
        let params = message["params"] as? [String: Any] ?? [:]
        let name = params["name"] as? String ?? ""
        let arguments = params["arguments"] as? [String: Any] ?? [:]
        log("call \(name)")
        let result = await call(tool: name, arguments: arguments)
        respond(id: id, result: result)

    case "ping":
        respond(id: id, result: [:])

    default:
        respond(id: id, error: "Unsupported method: \(method)", code: -32601)
    }
}

log("stdin closed, exiting")
