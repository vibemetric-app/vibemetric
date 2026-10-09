import Foundation

/// Parses Claude Code transcripts in `~/.claude/projects/<project>/<session>.jsonl`,
/// folding `<session>/subagents/*.jsonl` children into their parent.
enum ClaudeCodeParser {
    static func parse(file: URL) -> Session? {
        let rows = JSONL.objects(at: file)
        guard !rows.isEmpty else { return nil }
        var session = Session(
            id: file.deletingPathExtension().lastPathComponent,
            tool: .claudeCode,
            file: file,
            project: projectName(fromDirectory: file.deletingLastPathComponent().lastPathComponent)
        )
        var customTitle: String?
        var aiTitle: String?
        appendEvents(from: rows, into: &session, customTitle: &customTitle, aiTitle: &aiTitle)
        session.title = customTitle ?? aiTitle
        if let cwd = session.cwd { session.project = URL(fileURLWithPath: cwd).lastPathComponent }

        let childDir = file.deletingPathExtension().appendingPathComponent("subagents")
        if let children = try? FileManager.default.contentsOfDirectory(at: childDir, includingPropertiesForKeys: nil) {
            for child in children where child.pathExtension == "jsonl" {
                session.childCount += 1
                session.events.append(childSummary(JSONL.objects(at: child), name: child.deletingPathExtension().lastPathComponent))
            }
        }
        guard session.userTurns > 0 || session.toolCalls > 0 else { return nil }
        return session
    }

    /// `-Users-me-Documents-app` → `app`. Only a fallback; `cwd` wins when present.
    static func projectName(fromDirectory dir: String) -> String {
        dir.split(separator: "-").last.map(String.init) ?? dir
    }

    private static func appendEvents(from rows: [[String: Any]], into s: inout Session, customTitle: inout String?, aiTitle: inout String?) {
        var pendingTools: [String: Int] = [:]  // tool_use id → event index

        for row in rows {
            let time = JSONL.date(row["timestamp"])
            if let t = time {
                if s.start == nil || t < s.start! { s.start = t }
                if s.end == nil || t > s.end! { s.end = t }
            }
            if s.cwd == nil, let cwd = row["cwd"] as? String { s.cwd = cwd }

            switch row["type"] as? String {
            case "custom-title":
                customTitle = row["customTitle"] as? String
            case "ai-title":
                aiTitle = row["aiTitle"] as? String
            case "user":
                if let mode = row["permissionMode"] as? String { s.permissionModes.insert(mode) }
                guard let message = row["message"] as? [String: Any] else { continue }
                let origin = (row["origin"] as? [String: Any])?["kind"] as? String
                let isMeta = row["isMeta"] as? Bool ?? false
                if let text = message["content"] as? String {
                    appendUserText(text, origin: origin, isMeta: isMeta, time: time, into: &s)
                } else if let parts = message["content"] as? [[String: Any]] {
                    for part in parts {
                        switch part["type"] as? String {
                        case "tool_result":
                            guard let id = part["tool_use_id"] as? String, let idx = pendingTools[id],
                                  case let .tool(name, input, _, _) = s.events[idx].kind else { continue }
                            let failed = part["is_error"] as? Bool ?? false
                            let text = resultText(part["content"])
                            s.events[idx].kind = .tool(name: name, input: input, failed: failed, result: text.clipped(failed ? 400 : 240))
                        case "text":
                            appendUserText(part["text"] as? String ?? "", origin: origin, isMeta: isMeta, time: time, into: &s)
                        default: continue
                        }
                    }
                }
            case "assistant":
                guard let message = row["message"] as? [String: Any] else { continue }
                if let model = message["model"] as? String, !model.hasPrefix("<") { s.models.insert(model) }
                for part in message["content"] as? [[String: Any]] ?? [] {
                    switch part["type"] as? String {
                    case "text":
                        let text = part["text"] as? String ?? ""
                        if !text.isEmpty { s.events.append(TimelineEvent(time: time, kind: .assistant(text))) }
                    case "tool_use":
                        let name = part["name"] as? String ?? "?"
                        let input = summarize(toolInput: part["input"] as? [String: Any] ?? [:], name: name)
                        s.events.append(TimelineEvent(time: time, kind: .tool(name: name, input: input, failed: false, result: "")))
                        if let id = part["id"] as? String { pendingTools[id] = s.events.count - 1 }
                    default: continue
                    }
                }
            case "system":
                switch row["subtype"] as? String {
                case "compact_boundary": s.events.append(TimelineEvent(time: time, kind: .system("context compacted")))
                case "stop_hook_summary":
                    let blocked = row["preventedContinuation"] as? Bool ?? false
                    s.events.append(TimelineEvent(time: time, kind: .system(blocked ? "stop hook blocked continuation" : "stop hook ran")))
                default: continue
                }
            case "attachment":
                guard let a = row["attachment"] as? [String: Any] else { continue }
                switch a["type"] as? String {
                case "nested_memory":
                    s.events.append(TimelineEvent(time: time, kind: .system("memory injected: \(a["path"] as? String ?? "?")")))
                case "instructions":
                    let paths = (a["files"] as? [[String: Any]] ?? []).compactMap { $0["path"] as? String }
                    s.events.append(TimelineEvent(time: time, kind: .system("memory injected: \(paths.joined(separator: ", "))")))
                case "plan_mode": s.events.append(TimelineEvent(time: time, kind: .system("entered plan mode")))
                case "plan_mode_exit": s.events.append(TimelineEvent(time: time, kind: .system("exited plan mode")))
                case "hook_additional_context":
                    s.events.append(TimelineEvent(time: time, kind: .system("hook \(a["hookName"] as? String ?? "") added context")))
                case "command_permissions":
                    let allowed = (a["allowedTools"] as? [String] ?? []).joined(separator: ", ")
                    s.events.append(TimelineEvent(time: time, kind: .system("permissions allowed: \(allowed)".clipped(200))))
                case "queued_command":
                    if (a["origin"] as? [String: Any])?["kind"] as? String == "human" {
                        appendUserText(a["prompt"] as? String ?? "", origin: "human", isMeta: false, time: time, into: &s)
                    }
                default: continue
                }
            default: continue
            }
        }
    }

    private static func appendUserText(_ text: String, origin: String?, isMeta: Bool, time: Date?, into s: inout Session) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isMeta else { return }
        if trimmed.hasPrefix("[Request interrupted by user") {
            s.events.append(TimelineEvent(time: time, kind: .system("user interrupted the agent")))
        } else if trimmed.hasPrefix("This session is being continued from a previous conversation") {
            s.events.append(TimelineEvent(time: time, kind: .system("resumed from compaction summary")))
        } else if trimmed.hasPrefix("<command-name>") || trimmed.contains("<command-name>") {
            let name = trimmed.components(separatedBy: "<command-name>").last?.components(separatedBy: "</command-name>").first ?? "?"
            let args = trimmed.components(separatedBy: "<command-args>").dropFirst().first?.components(separatedBy: "</command-args>").first ?? ""
            s.events.append(TimelineEvent(time: time, kind: .user("[\(name)] \(args)")))
        } else if origin == "human" || (origin == nil && !trimmed.hasPrefix("<")) {
            s.events.append(TimelineEvent(time: time, kind: .user(trimmed)))
        }
    }

    private static func childSummary(_ rows: [[String: Any]], name: String) -> TimelineEvent {
        var child = Session(id: name, tool: .claudeCode, file: URL(fileURLWithPath: "/"), project: "")
        var t1: String?, t2: String?
        appendEvents(from: rows, into: &child, customTitle: &t1, aiTitle: &t2)
        // Subagent prompts arrive as non-human user text; take the first user-role string.
        let brief = rows.lazy.compactMap { row -> String? in
            guard row["type"] as? String == "user", let m = row["message"] as? [String: Any] else { return nil }
            return m["content"] as? String
        }.first ?? ""
        let tools = Dictionary(grouping: child.events.compactMap { e -> String? in
            if case let .tool(n, _, _, _) = e.kind { return n }; return nil
        }, by: { $0 }).map { "\($0.key)×\($0.value.count)" }.sorted().joined(separator: " ")
        return TimelineEvent(time: child.start, kind: .system(
            "subagent \(name) — brief: \(brief.clipped(300)) — \(child.toolCalls) tool calls (\(child.failedToolCalls) failed): \(tools.clipped(200))"
        ))
    }

    static func resultText(_ content: Any?) -> String {
        if let s = content as? String { return s }
        if let parts = content as? [[String: Any]] {
            return parts.compactMap { $0["text"] as? String }.joined(separator: " ")
        }
        return ""
    }

    static func summarize(toolInput input: [String: Any], name: String) -> String {
        for key in ["command", "file_path", "path", "pattern", "skill", "url", "query", "description", "prompt"] {
            if let v = input[key] as? String {
                var s = v
                if let agent = input["subagent_type"] as? String { s = "[\(agent)] " + s }
                return s.clipped(300)
            }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys]),
              let s = String(data: data, encoding: .utf8) else { return "" }
        return s.clipped(200)
    }
}
