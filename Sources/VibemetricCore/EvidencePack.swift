import Foundation

/// Writes a compact, redacted digest of the scanned sessions for the assessor to read.
/// The digest lets the assessor cover hundreds of sessions in minutes; raw transcripts
/// stay available for drilling into specific cases.
public enum EvidencePack {
    /// Stable paths also identify our persisted CLI sessions after a result has been deleted.
    public static func savedPacksDirectory(isDev: Bool) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(isDev ? "Vibemetric Dev/packs" : "Vibemetric/packs", isDirectory: true)
    }

    public static let maxDigests = 450
    static let digestCharLimit = 12_000

    /// The last saved assessment, so the judge can keep scores steady unless new evidence moves them.
    public struct Previous: Sendable {
        public var card: ScoreCard
        public var date: Date
        public init(card: ScoreCard, date: Date) { self.card = card; self.date = date }
    }

    @discardableResult
    public static func write(_ scan: ScanResult, to dir: URL, now: Date = Date(), previous: Previous? = nil,
                             ruleChanges: String? = nil, contextFiles: RuleSnapshot? = nil) throws -> URL {
        let fm = FileManager.default
        try? fm.removeItem(at: dir)
        try fm.createDirectory(at: dir.appendingPathComponent("sessions"), withIntermediateDirectories: true)

        let chosen = select(scan.sessions)
        var digestPaths: [String: String] = [:]
        for s in chosen {
            let rel = "sessions/\(slug(s.tool))-\(s.id.suffix(12)).md"
            digestPaths[key(s)] = rel
            try Redactor.scrub(timeline(s)).write(to: dir.appendingPathComponent(rel), atomically: true, encoding: .utf8)
        }

        try Redactor.scrub(sessionIndex(scan.sessions, digestPaths: digestPaths))
            .write(to: dir.appendingPathComponent("sessions.tsv"), atomically: true, encoding: .utf8)
        try Redactor.scrub(overview(scan, digests: chosen.count, now: now))
            .write(to: dir.appendingPathComponent("overview.md"), atomically: true, encoding: .utf8)
        try Redactor.scrub(leads(scan.sessions, digestPaths: digestPaths))
            .write(to: dir.appendingPathComponent("leads.md"), atomically: true, encoding: .utf8)
        try Redactor.scrub(permissionSettings(scan))
            .write(to: dir.appendingPathComponent("settings.md"), atomically: true, encoding: .utf8)
        if let previous {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(previous.card).write(to: dir.appendingPathComponent("previous-card.json"))
            try Redactor.scrub(changes(since: previous.date, scan: scan, digestPaths: digestPaths))
                .write(to: dir.appendingPathComponent("changes.md"), atomically: true, encoding: .utf8)
        }
        if let contextFiles {
            try Redactor.scrub(RuleFiles.contextFilesReport(contextFiles))
                .write(to: dir.appendingPathComponent("context-files.md"), atomically: true, encoding: .utf8)
        }
        if let ruleChanges {
            try Redactor.scrub(ruleChanges).write(to: dir.appendingPathComponent("rule-changes.md"), atomically: true, encoding: .utf8)
        }
        return dir
    }

    /// Sessions and settings that are new or changed since the previous assessment.
    /// This is the only evidence that may justify moving a previous score.
    static func changes(since: Date, scan: ScanResult, digestPaths: [String: String]) -> String {
        var md = "# Changes since the previous assessment (\(stamp(since)))\n\n"
        let changed = scan.sessions.filter { ($0.end ?? .distantPast) > since }
        if changed.isEmpty {
            md += "No sessions were started or continued since then.\n"
        } else {
            md += "Sessions started or continued since then. For a continued session, only events after \(stamp(since)) are new.\n\n"
            for s in changed {
                let started = (s.start ?? .distantPast) > since ? "new" : "continued"
                md += "- \(digestPaths[key(s)] ?? s.file.path) — \(s.project), \(started), last activity \(stamp(s.end)): \(s.title?.clipped(70) ?? "")\n"
            }
        }
        let settings = settingsFiles(scan).filter { (modified($0) ?? .distantPast) > since }
        md += "\n## Settings files changed since then\n\n"
        md += settings.isEmpty ? "None.\n" : settings.map { "- \($0.path) (modified \(stamp(modified($0))); see settings.md)" }.joined(separator: "\n") + "\n"
        return md
    }

    // MARK: Selection

    /// Keeps every session when under the cap; otherwise balances signal-rich, recent, and per-project coverage.
    static func select(_ sessions: [Session]) -> [Session] {
        guard sessions.count > maxDigests else { return sessions }
        var picked: [String: Session] = [:]
        let byProject = Dictionary(grouping: sessions, by: { "\($0.tool.rawValue)/\($0.project)" })
        // Up to 8 richest sessions per project so no project disappears.
        for (_, group) in byProject {
            for s in group.sorted(by: { richness($0) > richness($1) }).prefix(8) { picked[key(s)] = s }
        }
        // Then the richest overall, then the most recent, until the cap.
        for s in sessions.sorted(by: { richness($0) > richness($1) }) where picked.count < maxDigests * 3 / 4 { picked[key(s)] = s }
        for s in sessions.reversed() where picked.count < maxDigests { picked[key(s)] = s }
        return picked.values.sorted { ($0.start ?? .distantPast) < ($1.start ?? .distantPast) }
    }

    static func richness(_ s: Session) -> Int {
        s.signals.tags.count * 10 + min(s.userTurns, 30) + min(s.toolCalls / 5, 20)
    }

    private static func key(_ s: Session) -> String { "\(s.tool.rawValue)|\(s.id)" }
    private static func slug(_ t: AgentTool) -> String { t == .claudeCode ? "cc" : "codex" }

    // MARK: Files

    static func timeline(_ s: Session) -> String {
        var head = "# \(s.title ?? "(untitled)") — \(s.project) (\(s.tool.rawValue))\n\n"
        head += "- session: \(s.id)\n- transcript: \(s.file.path)\n"
        head += "- time: \(stamp(s.start)) → \(stamp(s.end))\n"
        head += "- models: \(s.models.sorted().joined(separator: ", "))\n"
        head += "- permission modes: \(s.permissionModes.sorted().joined(separator: ", "))\n"
        head += "- user turns: \(s.userTurns), tool calls: \(s.toolCalls) (\(s.failedToolCalls) failed), subagents: \(s.childCount)\n"
        head += "- signals: \(s.signals.tags.joined(separator: " "))\n\n## Timeline\n\n"

        var lines: [String] = []
        var run: (name: String, inputs: [String])?
        func flush() {
            if let r = run {
                lines.append(r.inputs.count == 1 ? "TOOL \(r.name): \(r.inputs[0])" : "TOOL \(r.name) ×\(r.inputs.count): \(r.inputs.joined(separator: " | ").clipped(300))")
            }
            run = nil
        }
        for e in s.events {
            let t = clock(e.time)
            switch e.kind {
            case let .tool(name, input, failed, result):
                // Collapse runs of successful read-only lookups so the digest stays skimmable.
                if !failed, ["Read", "Grep", "Glob", "LS", "ToolSearch"].contains(name) {
                    if run?.name == name { run!.inputs.append(input.clipped(80)) } else { flush(); run = (name, [input.clipped(80)]) }
                    continue
                }
                flush()
                let mark = failed ? "✗" : "✓"
                let out = result.isEmpty ? "" : " → \(result.clipped(failed ? 300 : 140))"
                lines.append("[\(t)] TOOL \(name) \(mark): \(input.clipped(220))\(out)")
            case let .user(text):
                flush(); lines.append("[\(t)] USER: \(text.clipped(700))")
            case let .assistant(text):
                flush(); lines.append("[\(t)] AI: \(text.clipped(260))")
            case let .system(text):
                flush(); lines.append("[\(t)] SYS: \(text.clipped(300))")
            }
        }
        flush()

        var body = lines.joined(separator: "\n")
        if body.count > digestCharLimit {
            // Keep every user turn and failure; trim the rest from the middle.
            let keep = lines.enumerated().filter { i, l in
                i < 25 || i >= lines.count - 25 || l.contains("USER:") || l.contains(" ✗:") || l.contains("SYS:")
            }.map(\.element)
            body = keep.joined(separator: "\n").clipLines(digestCharLimit)
            body += "\n\n(… digest trimmed; \(lines.count - keep.count) routine events omitted — see the transcript for full detail)"
        }
        return head + body + "\n"
    }

    static func sessionIndex(_ sessions: [Session], digestPaths: [String: String]) -> String {
        var out = "tool\tsession\tproject\tstart\tend\tuser_turns\ttool_calls\tfailed\tsubagents\tmodels\tpermission_modes\tsignals\tdigest\ttitle\n"
        for s in sessions {
            out += [
                s.tool.rawValue, s.id, s.project, stamp(s.start), stamp(s.end),
                "\(s.userTurns)", "\(s.toolCalls)", "\(s.failedToolCalls)", "\(s.childCount)",
                s.models.sorted().joined(separator: ","), s.permissionModes.sorted().joined(separator: ","),
                s.signals.tags.joined(separator: ","), digestPaths[key(s)] ?? "-", (s.title ?? "").clipped(90),
            ].map { $0.replacingOccurrences(of: "\t", with: " ") }.joined(separator: "\t") + "\n"
        }
        return out
    }

    static func overview(_ scan: ScanResult, digests: Int, now: Date) -> String {
        let tz = TimeZone.current
        var md = "# Overview\n\nPrepared \(stamp(now)) (\(tz.identifier)). Parser scan took \(String(format: "%.1f", scan.duration))s.\n\n"
        md += "Sessions: \(scan.sessions.count) total, \(digests) with digests in `sessions/`.\n\n## By tool\n\n"
        for tool in AgentTool.allCases {
            let ss = scan.sessions(for: tool)
            guard !ss.isEmpty else { md += "- \(tool.rawValue): no records found\n"; continue }
            md += "- \(tool.rawValue): \(ss.count) sessions, \(day(ss.compactMap(\.start).min())) → \(day(ss.compactMap(\.end).max())), \(Set(ss.map(\.project)).count) projects\n"
        }

        md += "\n## Projects (sessions, first → last)\n\n"
        for (project, ss) in Dictionary(grouping: scan.sessions, by: \.project).sorted(by: { $0.value.count > $1.value.count }) {
            let tools = Set(ss.map(\.tool.rawValue)).sorted().joined(separator: "+")
            md += "- \(project) [\(tools)]: \(ss.count), \(day(ss.compactMap(\.start).min())) → \(day(ss.compactMap(\.end).max()))\n"
        }

        let modes = scan.sessions.flatMap(\.permissionModes).reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        md += "\n## Permission modes (sessions using each)\n\n" + modes.sorted { $0.value > $1.value }.map { "- \($0.key): \($0.value)" }.joined(separator: "\n") + "\n"
        let models = scan.sessions.flatMap(\.models).reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        md += "\n## Models (sessions using each)\n\n" + models.sorted { $0.value > $1.value }.map { "- \($0.key): \($0.value)" }.joined(separator: "\n") + "\n"

        md += "\n## Memory and rule files across sessions (chronological)\n\n"
        md += "Shows which sessions wrote a memory/rule/skill file and which later sessions read it or had it injected. Injection alone does not prove use.\n\n"
        var memory: [String: [String]] = [:]
        for s in scan.sessions {
            for e in s.events {
                switch e.kind {
                case let .tool(name, input, _, _) where SignalExtractor.memoryPath.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)) != nil:
                    let shellWrite = SignalExtractor.shellWrite.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)) != nil
                    let verb = SignalExtractor.writeTools.contains(name) || shellWrite ? "WRITE" : "read/use"
                    memory[input.clipped(120), default: []].append("\(day(e.time)) \(verb) by \(s.tool.rawValue) \(s.id.suffix(12))")
                case let .system(text) where text.hasPrefix("memory injected"):
                    for path in text.dropFirst("memory injected: ".count).components(separatedBy: ", ") {
                        memory[path, default: []].append("\(day(e.time)) injected into \(s.tool.rawValue) \(s.id.suffix(12))")
                    }
                default: continue
                }
            }
        }
        for (path, uses) in memory.sorted(by: { $0.value.count > $1.value.count }).prefix(40) {
            let deduped = uses.reduce(into: [String]()) { if $0.last != $1 { $0.append($1) } }
            md += "- `\(path)`: " + deduped.prefix(12).joined(separator: "; ") + (deduped.count > 12 ? "; … \(deduped.count - 12) more" : "") + "\n"
        }
        return md
    }

    static func leads(_ sessions: [Session], digestPaths: [String: String]) -> String {
        let criteria: [(Dimension, (Session) -> Int)] = [
            (.planningSpecs, { $0.signals.specLanguage * 3 + $0.signals.planMode * 2 }),
            (.contextEngineering, { $0.signals.compactions * 3 + $0.signals.memoryInjected + $0.childCount * 2 }),
            (.memory, { $0.signals.memoryWrites * 3 + $0.signals.memoryReads }),
            (.toolIntegration, { $0.failedToolCalls * 2 + $0.signals.permissionDenials * 3 + $0.signals.skills * 2 + $0.signals.hooks }),
            (.taskMapping, { $0.signals.subagents * 3 + $0.childCount * 2 + $0.signals.planMode * 2 }),
            (.feedbackLoops, { $0.signals.failThenRerun * 4 + $0.failedToolCalls }),
            (.testingEvals, { $0.signals.verifyAfterEdit * 2 + $0.signals.browserDriving * 2 + $0.signals.evalLanguage * 3 }),
            (.humanSteering, { $0.signals.corrections * 3 + $0.userTurns / 5 }),
            (.security, { $0.signals.permissionDenials * 3 + $0.signals.hooks + $0.permissionModes.count * 2 }),
            (.efficiencyCost, { max($0.models.count - 1, 0) * 4 + $0.childCount }),
        ]
        var md = "# Leads by dimension\n\nHeuristic pointers only — keyword and counter matches, not evidence. Open the digest and confirm the connected behavior before citing a session.\n"
        for (dim, weight) in criteria {
            md += "\n## \(dim.title)\n\n"
            let ranked = sessions.map { ($0, weight($0)) }.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.prefix(12)
            if ranked.isEmpty { md += "- No heuristic matches. Absence here is not proof of absence.\n"; continue }
            for (s, w) in ranked {
                md += "- \(digestPaths[key(s)] ?? "(no digest) " + s.file.path) — \(s.project), \(day(s.start)), weight \(w): \(s.title?.clipped(70) ?? "")\n"
            }
        }
        return md
    }

    static func settingsFiles(_ scan: ScanResult) -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var files = [home.appendingPathComponent(".claude/settings.json"), home.appendingPathComponent(".claude/settings.local.json")]
        for cwd in Set(scan.sessions.compactMap(\.cwd)).sorted() {
            files.append(URL(fileURLWithPath: cwd).appendingPathComponent(".claude/settings.json"))
            files.append(URL(fileURLWithPath: cwd).appendingPathComponent(".claude/settings.local.json"))
        }
        return files.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func modified(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    /// Only permission-related keys from Claude Code settings; never env, keys, or credentials.
    /// Hooks are shown in full (event, matcher, command) along with the scripts they run,
    /// so the judge can tell what a hook actually enforces, not just that one exists.
    static func permissionSettings(_ scan: ScanResult) -> String {
        var md = "# Permission and hook settings\n\nOnly `permissions`, `hooks`, `sandbox`, and `model` keys are extracted. Other keys are deliberately not read into this file. "
        md += "A file's modification time says when a rule or hook was last changed; a hook only counts as enforcement once a later session shows it firing.\n"
        for file in settingsFiles(scan) {
            guard let data = try? Data(contentsOf: file),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            var kept: [String: Any] = [:]
            for k in ["permissions", "sandbox", "model", "hooks"] { if let v = obj[k] { kept[k] = v } }
            guard !kept.isEmpty, let out = try? JSONSerialization.data(withJSONObject: kept, options: [.prettyPrinted, .sortedKeys]) else { continue }
            md += "\n## \(file.path)\n\nLast modified \(stamp(modified(file))).\n\n```json\n\(String(decoding: out, as: UTF8.self))\n```\n"

            // .../<project>/.claude/settings.json → <project>
            let projectDir = file.deletingLastPathComponent().deletingLastPathComponent()
            for script in hookScripts(obj["hooks"], projectDir: projectDir) {
                guard let text = try? String(contentsOf: script, encoding: .utf8) else { continue }
                md += "\n### Hook script \(script.path) (modified \(stamp(modified(script))))\n\n```\n\(text.count > 6000 ? String(text.prefix(6000)) + "\n… (truncated)" : text)\n```\n"
            }
        }
        return md
    }

    /// Script files referenced by hook commands, e.g. `python3 "$CLAUDE_PROJECT_DIR/.claude/hooks/guard.py"`.
    static func hookScripts(_ hooks: Any?, projectDir: URL) -> [URL] {
        guard let events = hooks as? [String: Any] else { return [] }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var commands: [String] = []
        for case let matchers as [[String: Any]] in events.values {
            for matcher in matchers {
                for hook in matcher["hooks"] as? [[String: Any]] ?? [] {
                    if let c = hook["command"] as? String { commands.append(c) }
                }
            }
        }
        var found: [URL] = []
        for command in commands {
            let expanded = command
                .replacingOccurrences(of: "${CLAUDE_PROJECT_DIR}", with: projectDir.path)
                .replacingOccurrences(of: "$CLAUDE_PROJECT_DIR", with: projectDir.path)
                .replacingOccurrences(of: "~/", with: home + "/")
            for token in expanded.components(separatedBy: CharacterSet(charactersIn: " \"'")) where token.hasPrefix("/") {
                let url = URL(fileURLWithPath: token)
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue,
                   ((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? .max) < 64_000,
                   !found.contains(url) {
                    found.append(url)
                }
            }
        }
        return found
    }

    // MARK: Formatting

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"; return f
    }()
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MM-dd HH:mm"; return f
    }()
    static func stamp(_ d: Date?) -> String { d.map(stampFormatter.string(from:)) ?? "?" }
    static func day(_ d: Date?) -> String { d.map(dayFormatter.string(from:)) ?? "?" }
    static func clock(_ d: Date?) -> String { d.map(clockFormatter.string(from:)) ?? "--" }
}

private extension String {
    func clipLines(_ limit: Int) -> String {
        count <= limit ? self : String(prefix(limit / 2)) + "\n…\n" + String(suffix(limit / 2))
    }
}
