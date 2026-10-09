import Foundation

/// The contents of the person's rule and memory files (CLAUDE.md, AGENTS.md, Claude Code
/// memory) at one moment. Saved with each score so the next score can see what changed,
/// which is how an adopted recommendation is detected without the person reporting it.
public struct RuleSnapshot: Codable, Sendable {
    public var taken: Date
    /// Absolute path → file contents.
    public var files: [String: String]

    public init(taken: Date, files: [String: String]) {
        self.taken = taken
        self.files = files
    }
}

public enum RuleFiles {
    static let ruleNames = ["CLAUDE.md", "CLAUDE.local.md", "AGENTS.md", ".claude/CLAUDE.md"]
    static let maxFileBytes = 64_000
    static let maxLinesPerFile = 40

    /// Rule files for every project the person worked in (and its immediate subfolders, e.g. a
    /// web app inside a monorepo), their global CLAUDE.md/AGENTS.md, and Claude Code memory notes.
    public static func discover(scan: ScanResult, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        let fm = FileManager.default
        var found = Set<URL>()
        func add(_ url: URL) {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue,
                  ((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? .max) <= maxFileBytes else { return }
            found.insert(url.standardizedFileURL)
        }
        func addRules(in dir: URL) { ruleNames.forEach { add(dir.appendingPathComponent($0)) } }

        add(home.appendingPathComponent(".claude/CLAUDE.md"))
        add(home.appendingPathComponent(".codex/AGENTS.md"))

        for cwd in Set(scan.sessions.compactMap(\.cwd)) {
            let dir = URL(fileURLWithPath: cwd)
            addRules(in: dir)
            // Don't list the home folder's children: that would touch Desktop/Downloads and
            // trigger macOS privacy prompts for folders that aren't projects.
            guard dir.standardizedFileURL != home.standardizedFileURL,
                  let children = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { continue }
            for child in children where (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                addRules(in: child)
            }
        }

        for source in scan.sources where source.tool == .claudeCode {
            if let projects = try? fm.contentsOfDirectory(at: source.root, includingPropertiesForKeys: nil) {
                for project in projects {
                    let memory = project.appendingPathComponent("memory")
                    for note in (try? fm.contentsOfDirectory(at: memory, includingPropertiesForKeys: nil)) ?? [] where note.pathExtension == "md" {
                        add(note)
                    }
                }
            }
        }
        return found.sorted { $0.path < $1.path }
    }

    public static func snapshot(scan: ScanResult, now: Date = Date()) -> RuleSnapshot {
        var files: [String: String] = [:]
        for url in discover(scan: scan) {
            if let text = try? String(contentsOf: url, encoding: .utf8) { files[url.path] = text }
        }
        return RuleSnapshot(taken: now, files: files)
    }

    /// Markdown for the evidence pack: the current text of every CLAUDE.md / AGENTS.md, so the judge
    /// can assess what the context files cover, how they're structured, and whether they're kept current.
    /// Memory notes are left out; Memory & Knowledge reads them through the sessions.
    public static func contextFilesReport(_ snapshot: RuleSnapshot, maxCharsPerFile: Int = 24_000) -> String {
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd"
        let contextFiles = snapshot.files
            .filter { path, _ in ruleNames.contains { path.hasSuffix("/" + $0) } }
            .sorted { $0.key < $1.key }
        var md = "# Context files\n\n"
        md += "Current text of each CLAUDE.md and AGENTS.md found in the person's projects and home folder, "
        md += "as of \(stamp.string(from: snapshot.taken)). Use it to judge what the files cover, how they are structured, "
        md += "and whether they are current. When a file was last modified, and which sessions wrote or read it, is in overview.md.\n"
        if contextFiles.isEmpty { return md + "\nNo CLAUDE.md or AGENTS.md files were found.\n" }
        for (path, text) in contextFiles {
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count
            let modified = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date)
                .flatMap { $0 }.map { stamp.string(from: $0) } ?? "unknown"
            md += "\n## `\(path)`\n\n\(lines) lines · \(text.count) characters · last modified \(modified)\n\n"
            let body = text.count > maxCharsPerFile
                ? String(text.prefix(maxCharsPerFile)) + "\n… (truncated; \(text.count - maxCharsPerFile) more characters)"
                : text
            md += "````markdown\n\(body)\n````\n"
        }
        return md
    }

    /// Markdown for the evidence pack: what was added or removed in each rule file since the
    /// previous snapshot. Without one (results saved before snapshots existed), lists files
    /// modified since `since` with their current rule lines.
    public static func changesReport(current: RuleSnapshot, previous: RuleSnapshot?, since: Date?) -> String {
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd HH:mm"
        var md = "# Rule and memory file changes since the previous assessment\n\n"
        md += "Lines added to or removed from CLAUDE.md, AGENTS.md and Claude Code memory files. "
        md += "A written rule is preparation; it counts as applied only when a later session shows it being followed.\n"
        var sections: [String] = []

        if let previous {
            md += "\nCompared with the copy saved at \(stamp.string(from: previous.taken)).\n"
            for path in Set(current.files.keys).union(previous.files.keys).sorted() {
                let old = previous.files[path], new = current.files[path]
                switch (old, new) {
                case let (nil, new?):
                    sections.append("## \(path) (new file)\n\n" + lines(prefix: "+", Array(meaningfulLines(new).prefix(maxLinesPerFile))))
                case (_?, nil):
                    sections.append("## \(path) (deleted)\n")
                case let (old?, new?) where old != new:
                    let diff = lineDiff(old: old, new: new)
                    var body = ""
                    if !diff.added.isEmpty { body += "Added:\n" + lines(prefix: "+", Array(diff.added.prefix(maxLinesPerFile))) }
                    if !diff.removed.isEmpty { body += "Removed:\n" + lines(prefix: "-", Array(diff.removed.prefix(maxLinesPerFile))) }
                    sections.append("## \(path) (changed)\n\n" + body)
                default:
                    continue
                }
            }
        } else if let since {
            md += "\nNo earlier copy was kept, so these are files modified since \(stamp.string(from: since)), with their current rule lines.\n"
            for (path, text) in current.files.sorted(by: { $0.key < $1.key }) {
                guard let modified = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date,
                      modified > since else { continue }
                sections.append("## \(path) (modified \(stamp.string(from: modified)))\n\n"
                                + lines(prefix: " ", Array(meaningfulLines(text).prefix(maxLinesPerFile))))
            }
        }
        md += sections.isEmpty ? "\nNo rule or memory file changed.\n" : "\n" + sections.joined(separator: "\n")
        return md
    }

    /// Lines added and removed, order-preserving, counting repeats. Not a minimal diff, but
    /// enough to show which rules appeared or disappeared.
    static func lineDiff(old: String, new: String) -> (added: [String], removed: [String]) {
        let oldLines = meaningfulLines(old), newLines = meaningfulLines(new)
        var remaining = Dictionary(oldLines.map { ($0, 1) }, uniquingKeysWith: +)
        var added: [String] = []
        for line in newLines {
            if let n = remaining[line], n > 0 { remaining[line] = n - 1 } else { added.append(line) }
        }
        var stillNew = Dictionary(newLines.map { ($0, 1) }, uniquingKeysWith: +)
        var removed: [String] = []
        for line in oldLines {
            if let n = stillNew[line], n > 0 { stillNew[line] = n - 1 } else { removed.append(line) }
        }
        return (added, removed)
    }

    static func meaningfulLines(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func lines(prefix: String, _ lines: [String]) -> String {
        lines.map { "\(prefix) \($0.count > 240 ? String($0.prefix(240)) + "…" : $0)" }.joined(separator: "\n") + "\n"
    }
}
