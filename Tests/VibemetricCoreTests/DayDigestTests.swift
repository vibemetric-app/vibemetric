import Foundation
import Testing
@testable import VibemetricCore

/// A session kept open for days is read as that many days of work: one digest per day with activity, while a
/// session from a single day keeps its plain digest.
struct DayDigestTests {
    final class History {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("day-digests-\(UUID())")
        var claude: URL { root.appendingPathComponent(".claude/projects/-Users-me-app") }
        var sources: [TranscriptSource] { TranscriptSource.defaults(home: root) }

        init() throws {
            try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
            // Noon UTC stays on the same calendar day in every time zone from UTC-11 to UTC+11.
            try write("long", turns: [("2026-09-01T12:00:00.000Z", "Plan the export feature."),
                                      ("2026-09-01T12:30:00.000Z", "Write the spec to SPEC.md."),
                                      ("2026-09-03T12:00:00.000Z", "Implement the CSV export."),
                                      ("2026-09-07T12:00:00.000Z", "Add tests for the export.")])
            try write("short", turns: [("2026-09-05T12:00:00.000Z", "Fix the login bug.")])
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        func write(_ id: String, turns: [(String, String)]) throws {
            var lines: [String] = []
            for (i, (time, prompt)) in turns.enumerated() {
                lines.append(#"{"type":"user","cwd":"/Users/me/app","timestamp":"\#(time)","message":{"role":"user","content":"\#(prompt)"}}"#)
                lines.append(#"{"type":"assistant","timestamp":"\#(time)","message":{"model":"claude-opus-5","content":[{"type":"tool_use","id":"t\#(i)","name":"Bash","input":{"command":"npm test"}}]}}"#)
                lines.append(#"{"type":"user","timestamp":"\#(time)","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t\#(i)","content":"ok"}]}}"#)
            }
            try (lines.joined(separator: "\n") + "\n").write(to: claude.appendingPathComponent("\(id).jsonl"), atomically: true, encoding: .utf8)
        }
    }

    private func digests(in dir: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("sessions").path).sorted()
    }

    @Test func aSessionOnSeveralDaysGetsOneDigestPerDay() throws {
        let history = try History()
        let scan = Scanner.scan(sources: history.sources)
        let dir = history.root.appendingPathComponent("pack")
        try EvidencePack.write(scan, to: dir)

        let names = try digests(in: dir)
        #expect(names == ["cc-long-2026-09-01.md", "cc-long-2026-09-03.md", "cc-long-2026-09-07.md", "cc-short.md"])

        let first = try String(contentsOf: dir.appendingPathComponent("sessions/cc-long-2026-09-01.md"), encoding: .utf8)
        #expect(first.contains("- day: 2026-09-01, day 1 of 3 with activity in this session"))
        #expect(first.contains("Write the spec to SPEC.md."))
        #expect(!first.contains("Implement the CSV export."), "Each day holds only its own events")
        #expect(first.contains("- user turns: 2,"), "The header counts that day's turns, not the whole session's")

        let short = try String(contentsOf: dir.appendingPathComponent("sessions/cc-short.md"), encoding: .utf8)
        #expect(!short.contains("- day:"), "A single-day session has no day line")

        let index = try String(contentsOf: dir.appendingPathComponent("sessions.tsv"), encoding: .utf8)
        #expect(index.contains("sessions/cc-long-2026-09-01.md,sessions/cc-long-2026-09-03.md,sessions/cc-long-2026-09-07.md"))
        let overview = try String(contentsOf: dir.appendingPathComponent("overview.md"), encoding: .utf8)
        #expect(overview.contains("2 with digests in `sessions/` (4 digest files"))
        #expect(Assessor.digestCount(dir) == 4)
    }

    @Test func changesListOnlyTheDaysAfterThePreviousScore() throws {
        let history = try History()
        let scan = Scanner.scan(sources: history.sources)
        let since = ISO8601DateFormatter().date(from: "2026-09-04T12:00:00Z")!
        let changes = EvidencePack.changes(since: since, scan: scan, digestPaths: [
            "Claude Code|long": ["sessions/cc-long-2026-09-01.md", "sessions/cc-long-2026-09-03.md", "sessions/cc-long-2026-09-07.md"],
        ])
        #expect(changes.contains("sessions/cc-long-2026-09-07.md"))
        #expect(!changes.contains("cc-long-2026-09-03.md"), "Days before the previous score are not new")
    }

    @Test func dayChunksKeepUntimedEventsWithThePreviousDay() {
        let file = URL(fileURLWithPath: "/tmp/x.jsonl")
        let day1 = ISO8601DateFormatter().date(from: "2026-09-01T12:00:00Z")!
        let day2 = ISO8601DateFormatter().date(from: "2026-09-02T12:00:00Z")!
        var s = Session(id: "s", tool: .claudeCode, file: file, project: "app")
        s.start = day1
        s.end = day2
        s.events = [TimelineEvent(time: day1, kind: .user("a")), TimelineEvent(time: nil, kind: .system("b")),
                    TimelineEvent(time: day2, kind: .user("c"))]
        let chunks = EvidencePack.dayChunks(s)
        #expect(chunks.map { $0.session.events.count } == [2, 1])
        #expect(chunks.map(\.index) == [1, 2])
        #expect(chunks.allSatisfy { $0.count == 2 && $0.dated })
    }

    @Test func aDayThatComesBackLaterStaysOneChunk() {
        let file = URL(fileURLWithPath: "/tmp/x.jsonl")
        let day1 = ISO8601DateFormatter().date(from: "2026-09-01T12:00:00Z")!
        let day2 = ISO8601DateFormatter().date(from: "2026-09-02T12:00:00Z")!
        var s = Session(id: "s", tool: .claudeCode, file: file, project: "app")
        // Folded-in subagent events can send the timeline back to an earlier day.
        s.events = [TimelineEvent(time: day1, kind: .user("a")), TimelineEvent(time: day2, kind: .user("b")),
                    TimelineEvent(time: day1, kind: .system("subagent"))]
        let chunks = EvidencePack.dayChunks(s)
        #expect(chunks.map(\.label) == [EvidencePack.day(day1), EvidencePack.day(day2)], "One chunk per date, in date order")
        #expect(chunks.map { $0.session.events.count } == [2, 1])
    }

    @Test func manyDaysStayWithinTheDigestCap() {
        let file = URL(fileURLWithPath: "/tmp/x.jsonl")
        let start = ISO8601DateFormatter().date(from: "2026-01-01T12:00:00Z")!
        var s = Session(id: "forever", tool: .claudeCode, file: file, project: "app")
        s.events = (0..<(EvidencePack.maxDigests + 40)).map { TimelineEvent(time: start.addingTimeInterval(Double($0) * 86_400), kind: .user("day \($0)")) }
        s.start = s.events.first?.time
        s.end = s.events.last?.time
        let summary = SessionSummary(s)
        let chunks = EvidencePack.dayChunks(s).map { EvidencePack.DigestChunk(summary: summary, day: $0) }
        let since = start.addingTimeInterval(Double(EvidencePack.maxDigests + 30) * 86_400)
        let picked = EvidencePack.selectChunks(chunks, since: since)
        #expect(picked.count == EvidencePack.maxDigests)
        #expect(picked.contains { $0.day.index == chunks.count }, "The latest day is always kept")
        #expect(picked.filter { ($0.day.session.end ?? .distantPast) > since }.count == 9, "Every day since the previous score is kept")
    }
}
