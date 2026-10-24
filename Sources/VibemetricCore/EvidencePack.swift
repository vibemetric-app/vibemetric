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

    /// Digests written per pack when no token budget is given.
    public static let maxDigests = 70
    /// Sessions digested before a token budget trims them; the selection order decides which fit.
    static let maxCandidates = 150
    static let digestCharLimit = 12_000

    /// Context tokens a digest takes once the engine reads it. Measured at about 1.14 characters per token for these
    /// mostly Korean digests, counting the line numbers a file read adds to each line.
    public static func estimatedTokens(_ text: String) -> Int {
        let lines = text.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
        return Int((Double(text.count + 7 * lines) / 1.14).rounded(.up))
    }

    /// The last saved assessment, so the judge can keep scores steady unless new evidence moves them.
    public struct Previous: Sendable {
        public var card: ScoreCard
        public var date: Date
        public init(card: ScoreCard, date: Date) { self.card = card; self.date = date }
    }

    @discardableResult
    /// With `digestTokenBudget`, digests are kept in selection order while their estimated tokens fit the budget,
    /// so the pack holds as many sessions as the engine can read within its share of the context.
    public static func write(_ scan: ScanResult, to dir: URL, now: Date = Date(), previous: Previous? = nil,
                             ruleChanges: String? = nil, contextFiles: RuleSnapshot? = nil,
                             digestTokenBudget: Int? = nil) throws -> URL {
        let fm = FileManager.default
        try? fm.removeItem(at: dir)
        try fm.createDirectory(at: dir.appendingPathComponent("sessions"), withIntermediateDirectories: true)

        // Only the chosen sessions are parsed again in full; everything else comes from the scan's summaries.
        let chosen = select(scan.sessions, since: previous?.date, limit: digestTokenBudget == nil ? maxDigests : maxCandidates)
        var texts = [String?](repeating: nil, count: chosen.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: chosen.count) { i in
            autoreleasepool {
                // A transcript deleted since the scan keeps its index row, without a digest.
                guard let session = Scanner.fullSession(for: chosen[i]) else { return }
                let text = Redactor.scrub(timeline(session))
                lock.lock(); texts[i] = text; lock.unlock()
            }
        }
        var digestPaths: [String: String] = [:]
        var tokens = 0
        for (summary, text) in zip(chosen, texts) {
            guard let text else { continue }
            let cost = estimatedTokens(text)
            if let digestTokenBudget, tokens + cost > digestTokenBudget { continue }
            tokens += cost
            let rel = "sessions/\(slug(summary.tool))-\(summary.id.suffix(12)).md"
            try text.write(to: dir.appendingPathComponent(rel), atomically: true, encoding: .utf8)
            digestPaths[key(summary)] = rel
        }

        try Redactor.scrub(sessionIndex(scan.sessions, digestPaths: digestPaths))
            .write(to: dir.appendingPathComponent("sessions.tsv"), atomically: true, encoding: .utf8)
        try Redactor.scrub(overview(scan, digests: digestPaths.count, now: now))
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

    /// Sessions in priority order, at most `limit`: sessions since the previous score first (up to half the limit),
    /// then signal-rich sessions of every project, then the richest and the most recent overall.
    static func select(_ sessions: [SessionSummary], since: Date? = nil, limit: Int = maxDigests) -> [SessionSummary] {
        var order: [SessionSummary] = []
        var seen = Set<String>()
        func pick(_ s: SessionSummary, upTo cap: Int) {
            guard order.count < cap, seen.insert(key(s)).inserted else { return }
            order.append(s)
        }
        if let since {
            for s in sessions.reversed() where (s.end ?? .distantPast) > since { pick(s, upTo: limit / 2) }
        }
        let byProject = Dictionary(grouping: sessions, by: { "\($0.tool.rawValue)/\($0.project)" })
        // The richest sessions of every project so no project disappears: up to 8 each, fewer when there are many projects.
        let perProject = max(1, min(8, (limit / 2) / max(byProject.count, 1)))
        for (_, group) in byProject.sorted(by: { $0.key < $1.key }) {
            for s in group.sorted(by: { (richness($0), $0.file.path) > (richness($1), $1.file.path) }).prefix(perProject) {
                pick(s, upTo: limit)
            }
        }
        // Then the richest overall, then the most recent, until the limit.
        for s in sessions.sorted(by: { richness($0) > richness($1) }) { pick(s, upTo: limit * 3 / 4) }
        for s in sessions.reversed() { pick(s, upTo: limit) }
        return order
    }

    static func richness(_ s: SessionSummary) -> Int {
        s.signals.tags.count * 10 + min(s.userTurns, 30) + min(s.toolCalls / 5, 20)
    }

    private static func key(_ s: SessionSummary) -> String { "\(s.tool.rawValue)|\(s.id)" }
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
        var run: (time: String, count: Int, guides: [String])?
        func flush() {
            if let r = run {
                lines.append("[\(r.time)] READ ×\(r.count)" + (r.guides.isEmpty ? "" : ": \(r.guides.joined(separator: ", ").clipped(300))"))
            }
            run = nil
        }
        for e in s.events {
            let t = clock(e.time)
            switch e.kind {
            case let .tool(name, input, failed, result):
                // Successful lookups collapse into one READ line that keeps only the guidance files they opened.
                if !failed, isLookup(name: name, input: input) {
                    if run == nil { run = (t, 0, []) }
                    run!.count += 1
                    for guide in guidanceFiles(in: input) where !run!.guides.contains(guide) { run!.guides.append(guide) }
                    continue
                }
                flush()
                // Kept calls show what ran and whether it succeeded; only a failure keeps its error.
                let out = failed && !result.isEmpty ? " → \(result.clipped(200))" : ""
                lines.append("[\(t)] TOOL \(name) \(failed ? "✗" : "✓"): \(input.clipped(220))\(out)")
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

    static let lookupTools: Set<String> = ["Read", "Grep", "Glob", "LS", "ToolSearch", "WebFetch", "WebSearch", "view_image"]
    /// Shell programs that only look at files or state; a command made only of these is a lookup.
    static let lookupCommands: Set<String> = [
        "cd", "cat", "ls", "grep", "rg", "sed", "head", "tail", "find", "wc", "pwd", "echo", "stat", "tree", "jq",
        "nl", "file", "du", "which", "sort", "uniq", "cut", "awk", "diff", "tr", "basename", "dirname", "realpath",
    ]
    static let lookupGitCommands: Set<String> = ["status", "log", "show", "diff", "branch"]
    private static let discardedOutput = try! NSRegularExpression(pattern: #"\d?>\s*/dev/null|\d>&\d"#)

    /// Whether a call only looks things up: a lookup tool, or a shell command whose every piece is a lookup
    /// program and that writes nothing.
    static func isLookup(name: String, input: String) -> Bool {
        if lookupTools.contains(name) { return true }
        guard SignalExtractor.shellTools.contains(name) else { return false }
        // Quoted patterns may hold `|`, `;` or `>` that neither split nor redirect the command.
        let unquoted = withoutQuotedText(input)
        let command = discardedOutput.stringByReplacingMatches(in: unquoted, range: NSRange(unquoted.startIndex..., in: unquoted), withTemplate: "")
        if SignalExtractor.matches(SignalExtractor.shellWrite, command) || command.contains("-delete") || command.contains("-exec") {
            return false
        }
        let pieces = command.components(separatedBy: CharacterSet(charactersIn: "|;&\n")).map { $0.split(whereSeparator: \.isWhitespace) }
        return pieces.contains { !$0.isEmpty } && pieces.allSatisfy { words in
            let words = words.drop { $0.contains("=") && !$0.hasPrefix("-") }
            guard let first = words.first.map({ String($0.split(separator: "/").last ?? $0) }) else { return true }
            if first == "git" {
                var rest = words.dropFirst()
                while let flag = rest.first, flag.hasPrefix("-") { rest = rest.dropFirst(flag == "-C" ? 2 : 1) }
                return rest.first.map { lookupGitCommands.contains(String($0)) } ?? false
            }
            return lookupCommands.contains(first)
        }
    }

    /// The command with single- and double-quoted text replaced by an empty `''`; an unclosed quote runs to the end.
    static func withoutQuotedText(_ command: String) -> String {
        var out = ""
        var quote: Character?
        var escaped = false
        for ch in command {
            if let q = quote {
                if escaped { escaped = false } else if ch == "\\" && q == "\"" { escaped = true } else if ch == q { quote = nil; out += "''" }
            } else if ch == "'" || ch == "\"" {
                quote = ch
            } else {
                out.append(ch)
            }
        }
        return out
    }

    /// Guidance, memory, and skill files named in a lookup, as their last two path components.
    static func guidanceFiles(in input: String) -> [String] {
        input.split(whereSeparator: { $0.isWhitespace || "\"'`,()".contains($0) }).compactMap { word in
            let word = String(word)
            guard SignalExtractor.matches(SignalExtractor.memoryPath, word) else { return nil }
            return word.split(separator: "/").suffix(2).joined(separator: "/")
        }
    }

    static func sessionIndex(_ sessions: [SessionSummary], digestPaths: [String: String]) -> String {
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
        for (project, ss) in Dictionary(grouping: scan.sessions, by: \.project).sorted(by: { ($1.value.count, $0.key) < ($0.value.count, $1.key) }) {
            let tools = Set(ss.map(\.tool.rawValue)).sorted().joined(separator: "+")
            md += "- \(project) [\(tools)]: \(ss.count), \(day(ss.compactMap(\.start).min())) → \(day(ss.compactMap(\.end).max()))\n"
        }

        let modes = scan.sessions.flatMap(\.permissionModes).reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        md += "\n## Permission modes (sessions using each)\n\n" + modes.sorted { ($1.value, $0.key) < ($0.value, $1.key) }.map { "- \($0.key): \($0.value)" }.joined(separator: "\n") + "\n"
        let models = scan.sessions.flatMap(\.models).reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        md += "\n## Models (sessions using each)\n\n" + models.sorted { ($1.value, $0.key) < ($0.value, $1.key) }.map { "- \($0.key): \($0.value)" }.joined(separator: "\n") + "\n"

        md += "\n## Memory and rule files across sessions (chronological)\n\n"
        md += "Shows which sessions wrote a memory/rule/skill file and which later sessions read it or had it injected. Injection alone does not prove use.\n\n"
        var memory: [String: [String]] = [:]
        for s in scan.sessions {
            for use in s.memoryUses {
                let what = switch use.kind {
                case .write: "WRITE by"
                case .read: "read/use by"
                case .injected: "injected into"
                }
                memory[use.path, default: []].append("\(day(use.time)) \(what) \(s.tool.rawValue) \(s.id.suffix(12))")
            }
        }
        for (path, uses) in memory.sorted(by: { ($1.value.count, $0.key) < ($0.value.count, $1.key) }).prefix(40) {
            let deduped = uses.reduce(into: [String]()) { if $0.last != $1 { $0.append($1) } }
            md += "- `\(path)`: " + deduped.prefix(12).joined(separator: "; ") + (deduped.count > 12 ? "; … \(deduped.count - 12) more" : "") + "\n"
        }
        return md
    }

    static func leads(_ sessions: [SessionSummary], digestPaths: [String: String]) -> String {
        let criteria: [(Dimension, (SessionSummary) -> Int)] = [
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
