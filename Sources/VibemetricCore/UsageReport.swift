import Foundation

extension EvidencePack {
    /// Extra evidence files beside the pack: `rubric.md` always; `usage.tsv` (per-session token use) and
    /// `model-settings.md` when `inputs` lists "usage" or "model_settings". Redacted like the rest of the pack.
    public static func writeSupplementary(_ scan: ScanResult, to dir: URL, inputs: [String]) throws {
        try Assessor.rubric.write(to: dir.appendingPathComponent("rubric.md"), atomically: true, encoding: .utf8)
        if inputs.contains("usage") {
            try Redactor.scrub(UsageReport.tsv(scan.sessions)).write(to: dir.appendingPathComponent("usage.tsv"), atomically: true, encoding: .utf8)
        }
        if inputs.contains("model_settings") {
            try Redactor.scrub(UsageReport.modelSettings(scan)).write(to: dir.appendingPathComponent("model-settings.md"), atomically: true, encoding: .utf8)
        }
    }
}

/// Token usage per session, thread, and model, read straight from the transcripts. Claude Code
/// records usage on every assistant message (subagents in `<session>/subagents/`); Codex records a
/// running total in `token_count` events and the model and effort in each turn context.
public enum UsageReport {
    static let columns = ["tool", "project", "date", "session", "thread", "model", "effort", "input_tokens", "output_tokens",
                          "cache_read_tokens", "cache_write_tokens", "assistant_messages", "user_turns", "tool_calls",
                          "failed_tool_calls", "wall_minutes"]

    public static func tsv(_ sessions: [Session]) -> String {
        var rows: [[String]] = []
        let day = DateFormatter()
        day.dateFormat = "yyyy-MM-dd"
        for s in sessions {
            let date = s.start.map(day.string(from:)) ?? ""
            let minutes = (s.start != nil && s.end != nil) ? String(format: "%.1f", s.end!.timeIntervalSince(s.start!) / 60) : ""
            switch s.tool {
            case .claudeCode:
                let subagents = (try? FileManager.default.contentsOfDirectory(
                    at: s.file.deletingPathExtension().appendingPathComponent("subagents"), includingPropertiesForKeys: nil)) ?? []
                for (file, thread) in [(s.file, "main")] + subagents.filter { $0.pathExtension == "jsonl" }.map({ ($0, "subagent") }) {
                    for (model, u) in claudeUsage(file).sorted(by: { $0.key < $1.key }) {
                        rows.append(["claude-code", s.project, date, String(s.id.prefix(8)), thread, model, "not recorded",
                                     "\(u.input)", "\(u.output)", "\(u.cacheRead)", "\(u.cacheWrite)", "\(u.messages)",
                                     thread == "main" ? "\(s.userTurns)" : "", thread == "main" ? "\(s.toolCalls)" : "",
                                     thread == "main" ? "\(s.failedToolCalls)" : "", thread == "main" ? minutes : ""])
                    }
                }
            case .codex:
                guard let u = codexUsage(s.file) else { continue }
                rows.append(["codex", s.project, date, String(s.id.prefix(8)), "main", u.model ?? "?", u.effort ?? "?",
                             "\(max(u.input - u.cacheRead, 0))", "\(u.output)", "\(u.cacheRead)", "\(u.cacheWrite)", "",
                             "\(s.userTurns)", "\(s.toolCalls)", "\(s.failedToolCalls)", minutes])
            }
        }
        rows.sort { ($0[2], $0[0], $0[3]) < ($1[2], $1[0], $1[3]) }
        return ([columns] + rows).map { $0.joined(separator: "\t") }.joined(separator: "\n") + "\n"
    }

    struct Tokens { var input = 0, output = 0, cacheRead = 0, cacheWrite = 0, messages = 0 }

    static func claudeUsage(_ file: URL) -> [String: Tokens] {
        var byModel: [String: Tokens] = [:]
        for o in JSONL.objects(at: file) {
            guard o["type"] as? String == "assistant",
                  let m = o["message"] as? [String: Any], let model = m["model"] as? String, model != "<synthetic>",
                  let u = m["usage"] as? [String: Any] else { continue }
            var t = byModel[model] ?? Tokens()
            t.input += u["input_tokens"] as? Int ?? 0
            t.output += u["output_tokens"] as? Int ?? 0
            t.cacheRead += u["cache_read_input_tokens"] as? Int ?? 0
            t.cacheWrite += u["cache_creation_input_tokens"] as? Int ?? 0
            t.messages += 1
            byModel[model] = t
        }
        return byModel
    }

    struct CodexTotals { var model: String?, effort: String?, input = 0, output = 0, cacheRead = 0, cacheWrite = 0 }

    static func codexUsage(_ file: URL) -> CodexTotals? {
        var totals = CodexTotals()
        var sawUsage = false
        for o in JSONL.objects(at: file) {
            if o["type"] as? String == "turn_context", let p = o["payload"] as? [String: Any] {
                totals.model = p["model"] as? String ?? totals.model
                totals.effort = p["effort"] as? String ?? totals.effort
            } else if let p = o["payload"] as? [String: Any], p["type"] as? String == "token_count",
                      let info = p["info"] as? [String: Any], let u = info["total_token_usage"] as? [String: Any] {
                // Cumulative: the last event holds the session total.
                totals.input = u["input_tokens"] as? Int ?? 0
                totals.output = u["output_tokens"] as? Int ?? 0
                totals.cacheRead = u["cached_input_tokens"] as? Int ?? 0
                totals.cacheWrite = u["cache_write_input_tokens"] as? Int ?? 0
                sawUsage = true
            }
        }
        return sawUsage ? totals : nil
    }

    /// Model, effort, fast-mode, and subagent keys from Claude Code settings and Codex config. Nothing else is copied.
    public static func modelSettings(_ scan: ScanResult, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String {
        let fm = FileManager.default
        let day = DateFormatter()
        day.dateFormat = "yyyy-MM-dd"
        let interesting = try! NSRegularExpression(pattern: "model|effort|fast|subagent|thinking", options: .caseInsensitive)
        func matches(_ key: String) -> Bool { interesting.firstMatch(in: key, range: NSRange(key.startIndex..., in: key)) != nil }
        func modified(_ url: URL) -> String {
            ((try? fm.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date).map(day.string(from:)) ?? "unknown"
        }

        var md = "# Model and effort settings\n\nOnly model, effort, fast-mode, subagent, and thinking keys are shown.\n"
        var files = [home.appendingPathComponent(".claude/settings.json")]
        for cwd in Set(scan.sessions.compactMap(\.cwd)) {
            for name in ["settings.json", "settings.local.json"] {
                files.append(URL(fileURLWithPath: cwd).appendingPathComponent(".claude/\(name)"))
            }
        }
        for url in Set(files).sorted(by: { $0.path < $1.path }) {
            guard let data = try? Data(contentsOf: url), let root = try? JSONSerialization.jsonObject(with: data) else { continue }
            var lines: [String] = []
            func walk(_ value: Any, _ path: String) {
                if let d = value as? [String: Any] {
                    for (k, v) in d.sorted(by: { $0.key < $1.key }) { walk(v, path.isEmpty ? k : "\(path).\(k)") }
                } else if matches(path) {
                    lines.append("- `\(path)` = `\(value)`")
                }
            }
            walk(root, "")
            if !lines.isEmpty {
                md += "\n## `\(url.path.replacingOccurrences(of: home.path, with: "~"))` (modified \(modified(url)))\n\n" + lines.joined(separator: "\n") + "\n"
            }
        }
        let codex = home.appendingPathComponent(".codex/config.toml")
        if let text = try? String(contentsOf: codex, encoding: .utf8) {
            let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { line in line.contains("=") && matches(String(line.split(separator: "=")[0])) }
            if !lines.isEmpty {
                md += "\n## `~/.codex/config.toml` (modified \(modified(codex)))\n\n" + lines.map { "- `\($0)`" }.joined(separator: "\n") + "\n"
            }
        }
        md += "\nClaude Code transcripts do not record reasoning effort per session; Codex records it per turn (the effort column in usage.tsv).\n"
        return md
    }
}
