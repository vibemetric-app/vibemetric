import Foundation

/// Parses Codex rollouts in `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`.
enum CodexParser {
    private static let injectedPrefixes = ["<", "# AGENTS.md", "# Files mentioned", "# Chrome tabs", "# Context from"]
    private static let cmdPattern = try! NSRegularExpression(pattern: #"cmd\s*:\s*"((?:[^"\\]|\\.)*)""#)
    private static let exitPattern = try! NSRegularExpression(pattern: #"(?i)(exit[ _]code)["':\s]+(-?\d+)"#)

    static func parse(file: URL) -> Session? {
        let rows = JSONL.objects(at: file)
        guard !rows.isEmpty else { return nil }
        var s = Session(id: file.deletingPathExtension().lastPathComponent, tool: .codex, file: file, project: "?")
        var pending: [String: Int] = [:]

        for row in rows {
            let time = JSONL.date(row["timestamp"])
            if let t = time {
                if s.start == nil || t < s.start! { s.start = t }
                if s.end == nil || t > s.end! { s.end = t }
            }
            let p = row["payload"] as? [String: Any] ?? [:]
            switch row["type"] as? String {
            case "session_meta":
                if let id = p["id"] as? String { s.id = id }
                if let cwd = p["cwd"] as? String { s.cwd = cwd }
            case "turn_context":
                if let cwd = p["cwd"] as? String, s.cwd == nil { s.cwd = cwd }
                if let model = p["model"] as? String { s.models.insert(model) }
                let approval = p["approval_policy"] as? String ?? "?"
                let sandbox = (p["sandbox_policy"] as? [String: Any])?["type"] as? String ?? "?"
                s.permissionModes.insert("approval=\(approval) sandbox=\(sandbox)")
            case "response_item":
                switch p["type"] as? String {
                case "message":
                    let text = (p["content"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }.joined(separator: "\n")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { continue }
                    switch p["role"] as? String {
                    case "user":
                        if !injectedPrefixes.contains(where: { text.hasPrefix($0) }) {
                            s.events.append(TimelineEvent(time: time, kind: .user(text)))
                        }
                    case "assistant":
                        s.events.append(TimelineEvent(time: time, kind: .assistant(text)))
                    default: continue
                    }
                case "function_call", "custom_tool_call":
                    let name = p["name"] as? String ?? "?"
                    let raw = (p["arguments"] as? String) ?? (p["input"] as? String) ?? ""
                    s.events.append(TimelineEvent(time: time, kind: .tool(name: name, input: summarize(raw), failed: false, result: "")))
                    if let id = p["call_id"] as? String { pending[id] = s.events.count - 1 }
                case "function_call_output", "custom_tool_call_output":
                    guard let id = p["call_id"] as? String, let idx = pending[id],
                          case let .tool(name, input, _, _) = s.events[idx].kind else { continue }
                    let text = outputText(p["output"])
                    let failed = isFailure(text)
                    s.events[idx].kind = .tool(name: name, input: input, failed: failed, result: text.clipped(failed ? 400 : 240))
                default: continue
                }
            case "event_msg":
                switch p["type"] as? String {
                case "turn_aborted": s.events.append(TimelineEvent(time: time, kind: .system("user interrupted the agent")))
                case "context_compacted": s.events.append(TimelineEvent(time: time, kind: .system("context compacted")))
                default: continue
                }
            default: continue
            }
        }
        if let cwd = s.cwd { s.project = URL(fileURLWithPath: cwd).lastPathComponent }
        s.title = s.events.lazy.compactMap { e -> String? in if case let .user(t) = e.kind { return t }; return nil }.first?.clipped(80)
        guard s.userTurns > 0 else { return nil }
        return s
    }

    /// Pulls shell commands out of Codex's JS tool scripts; falls back to the raw argument text.
    private static func summarize(_ raw: String) -> String {
        let range = NSRange(raw.startIndex..., in: raw)
        let cmds = cmdPattern.matches(in: raw, range: range).compactMap { m -> String? in
            Range(m.range(at: 1), in: raw).map { String(raw[$0]).replacingOccurrences(of: "\\\"", with: "\"") }
        }
        return (cmds.isEmpty ? raw : cmds.joined(separator: " ; ")).clipped(300)
    }

    private static func outputText(_ output: Any?) -> String {
        if let s = output as? String { return s }
        if let parts = output as? [[String: Any]] { return parts.compactMap { $0["text"] as? String }.joined(separator: " ") }
        return ""
    }

    private static func isFailure(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        for m in exitPattern.matches(in: text, range: range) {
            if let r = Range(m.range(at: 2), in: text), let code = Int(text[r]), code != 0 { return true }
        }
        return text.contains("Script failed") || text.hasPrefix("Error") || text.contains("\"success\":false")
    }
}
