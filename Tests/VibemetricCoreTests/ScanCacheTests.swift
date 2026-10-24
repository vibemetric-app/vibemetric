import Foundation
import Testing
@testable import VibemetricCore

/// The scan cache only saves work: a cached scan must give the same sessions and the same evidence pack
/// as reading every transcript fresh, and must notice new, grown, deleted and subagent transcripts.
@Suite(.serialized)
struct ScanCacheTests {
    /// A temporary `~/.claude/projects` and `~/.codex/sessions` with a few sessions.
    final class History {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("scan-cache-\(UUID())")
        var claude: URL { root.appendingPathComponent(".claude/projects") }
        var codex: URL { root.appendingPathComponent(".codex/sessions") }
        var cache: URL { root.appendingPathComponent("cache.json") }
        var sources: [TranscriptSource] { TranscriptSource.defaults(home: root) }

        init() throws {
            try FileManager.default.createDirectory(at: claude.appendingPathComponent("-Users-me-app"), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: codex.appendingPathComponent("2026/09/02"), withIntermediateDirectories: true)
            try writeClaude("s1", day: "01", prompt: "Fix the login bug. Done when npm test passes.")
            try writeClaude("s2", day: "03", prompt: "Update CLAUDE.md with the release steps.")
            try writeCodex()
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        func claudeFile(_ id: String) -> URL { claude.appendingPathComponent("-Users-me-app/\(id).jsonl") }

        func writeClaude(_ id: String, day: String, prompt: String) throws {
            let lines = [
                #"{"type":"user","cwd":"/Users/me/app","timestamp":"2026-09-\#(day)T10:00:00.000Z","permissionMode":"acceptEdits","message":{"role":"user","content":"\#(prompt)"}}"#,
                #"{"type":"assistant","timestamp":"2026-09-\#(day)T10:00:02.000Z","message":{"model":"claude-opus-5","usage":{"input_tokens":10,"output_tokens":5},"content":[{"type":"tool_use","id":"t1","name":"Edit","input":{"file_path":"/Users/me/app/CLAUDE.md"}},{"type":"tool_use","id":"t2","name":"Bash","input":{"command":"npm test"}}]}}"#,
                #"{"type":"user","timestamp":"2026-09-\#(day)T10:00:03.000Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"ok"},{"type":"tool_result","tool_use_id":"t2","is_error":true,"content":"1 failing"}]}}"#,
            ]
            try (lines.joined(separator: "\n") + "\n").write(to: claudeFile(id), atomically: true, encoding: .utf8)
        }

        func writeCodex() throws {
            let lines = [
                #"{"timestamp":"2026-09-02T09:00:00.000Z","type":"session_meta","payload":{"id":"0199codex","cwd":"/Users/me/api"}}"#,
                #"{"timestamp":"2026-09-02T09:00:01.000Z","type":"turn_context","payload":{"model":"gpt-5-codex","effort":"high"}}"#,
                #"{"timestamp":"2026-09-02T09:00:02.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Add a health check endpoint"}]}}"#,
                #"{"timestamp":"2026-09-02T09:00:03.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":40,"output_tokens":20}}}}"#,
            ]
            try (lines.joined(separator: "\n") + "\n").write(to: codex.appendingPathComponent("2026/09/02/rollout-0199codex.jsonl"),
                                                          atomically: true, encoding: .utf8)
        }

        func append(_ line: String, to file: URL) throws {
            let handle = try FileHandle(forWritingTo: file)
            handle.seekToEndOfFile()
            handle.write(Data((line + "\n").utf8))
            try handle.close()
        }
    }

    /// Every file in a pack, minus the lines that state when it was prepared and how long the scan took.
    private func packContents(_ scan: ScanResult, in dir: URL) throws -> [String: String] {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try EvidencePack.write(scan, to: dir, now: now)
        try EvidencePack.writeSupplementary(scan, to: dir, inputs: ["usage"])
        var files: [String: String] = [:]
        let base = dir.resolvingSymlinksInPath().path
        for case let url as URL in FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)! where url.pathExtension != "" {
            let text = try String(contentsOf: url, encoding: .utf8)
            files[url.resolvingSymlinksInPath().path.replacingOccurrences(of: base, with: "")] = text.split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.hasPrefix("Prepared ") }.joined(separator: "\n")
        }
        return files
    }

    @Test func digestsFillTheTokenBudgetInSelectionOrder() throws {
        let history = try History()
        let scan = Scanner.scan(sources: history.sources)
        let dir = history.root.appendingPathComponent("pack")
        func digests() throws -> [String: Int] {
            let folder = dir.appendingPathComponent("sessions")
            return try Dictionary(uniqueKeysWithValues: FileManager.default.contentsOfDirectory(atPath: folder.path).map {
                ($0, EvidencePack.estimatedTokens(try String(contentsOf: folder.appendingPathComponent($0), encoding: .utf8)))
            })
        }
        try EvidencePack.write(scan, to: dir, digestTokenBudget: 1_000_000)
        let all = try digests()
        #expect(all.count == 3)
        // Only the session continued since the previous score fits: it is chosen first and the rest would overflow.
        let previous = EvidencePack.Previous(card: try JSONDecoder().decode(ScoreCard.self, from: Data(CoreTests.sampleCard.utf8)),
                                             date: ISO8601DateFormatter().date(from: "2026-09-02T12:00:00Z")!)
        try EvidencePack.write(scan, to: dir, previous: previous, digestTokenBudget: try #require(all["cc-s2.md"]))
        #expect(try digests().keys.sorted() == ["cc-s2.md"])
        let index = try String(contentsOf: dir.appendingPathComponent("sessions.tsv"), encoding: .utf8)
        #expect(index.contains("sessions/cc-s2.md") && !index.contains("sessions/cc-s1.md"))
    }

    @Test func cachedScanMatchesAFreshScan() throws {
        let history = try History()
        let fresh = Scanner.scan(sources: history.sources)
        let first = Scanner.scan(sources: history.sources, cache: history.cache)
        let cached = Scanner.scan(sources: history.sources, cache: history.cache)
        #expect(fresh.sessions.count == 3)
        #expect(first.parsedFiles == 3)
        #expect(cached.parsedFiles == 0, "Nothing changed, so nothing is parsed again")
        #expect(cached.sessions == fresh.sessions)

        let packs = history.root.appendingPathComponent("packs")
        let freshPack = try packContents(fresh, in: packs.appendingPathComponent("fresh"))
        let cachedPack = try packContents(cached, in: packs.appendingPathComponent("cached"))
        #expect(freshPack.keys.sorted() == cachedPack.keys.sorted())
        for (name, text) in freshPack { #expect(cachedPack[name] == text, "\(name) differs") }
        #expect(freshPack.keys.contains { $0.hasPrefix("/sessions/") }, "Digests come from the transcripts, parsed again")
        #expect(freshPack["/usage.tsv"]?.contains("gpt-5-codex") == true)
    }

    @Test func onlyNewOrChangedTranscriptsAreParsed() throws {
        let history = try History()
        _ = Scanner.scan(sources: history.sources, cache: history.cache)

        try history.append(#"{"type":"user","timestamp":"2026-09-01T11:00:00.000Z","message":{"role":"user","content":"Also add a test for the logout path."}}"#,
                           to: history.claudeFile("s1"))
        var scan = Scanner.scan(sources: history.sources, cache: history.cache)
        #expect(scan.parsedFiles == 1)
        #expect(scan.sessions.first { $0.id == "s1" }?.userTurns == 2)

        try history.writeClaude("s3", day: "05", prompt: "Write the release notes.")
        scan = Scanner.scan(sources: history.sources, cache: history.cache)
        #expect(scan.parsedFiles == 1)
        #expect(scan.sessions.count == 4)

        // A subagent transcript is folded into its parent, so the parent is parsed again.
        let subagents = history.claudeFile("s2").deletingPathExtension().appendingPathComponent("subagents")
        try FileManager.default.createDirectory(at: subagents, withIntermediateDirectories: true)
        try #"{"type":"user","timestamp":"2026-09-03T10:01:00.000Z","message":{"role":"user","content":"Find the release script"}}"#
            .write(to: subagents.appendingPathComponent("agent-1.jsonl"), atomically: true, encoding: .utf8)
        scan = Scanner.scan(sources: history.sources, cache: history.cache)
        #expect(scan.parsedFiles == 1)
        #expect(scan.sessions.first { $0.id == "s2" }?.childCount == 1)

        try FileManager.default.removeItem(at: history.claudeFile("s3"))
        scan = Scanner.scan(sources: history.sources, cache: history.cache)
        #expect(scan.parsedFiles == 0)
        #expect(!scan.sessions.contains { $0.id == "s3" })
        #expect(scan.sessions == Scanner.scan(sources: history.sources).sessions)
    }

    @Test func aNewVersionStartsOver() throws {
        let history = try History()
        let scan = Scanner.scan(sources: history.sources, cache: history.cache)
        var stale = try #require(ScanCache.load(from: history.cache, version: Scanner.cacheVersion()))
        stale.version = "old"
        stale.save(to: history.cache)
        #expect(Scanner.scan(sources: history.sources, cache: history.cache).parsedFiles == 3)

        try Data("not json".utf8).write(to: history.cache)
        let recovered = Scanner.scan(sources: history.sources, cache: history.cache)
        #expect(recovered.parsedFiles == 3)
        #expect(recovered.sessions == scan.sessions)
    }

    @Test func cacheHoldsNoConversationText() throws {
        let history = try History()
        _ = Scanner.scan(sources: history.sources, cache: history.cache)
        let text = try String(contentsOf: history.cache, encoding: .utf8)
        #expect(!text.contains("Fix the login bug"))
        #expect(!text.contains("1 failing"))
        // The only conversation text is a session's title; for Codex that is the first message, clipped.
        #expect(!text.contains("release steps"))
    }
}
