import XCTest
@testable import VibemetricCore

final class CoreTests: XCTestCase {
    func testLegacyDimensionIDsDecodeToCurrentIDs() throws {
        // Results saved before the rename store "task_framing"; they must still load.
        let dims = try JSONDecoder().decode([VibemetricCore.Dimension].self, from: Data(#"["task_framing","security"]"#.utf8))
        XCTAssertEqual(dims, [VibemetricCore.Dimension.planningSpecs, .security])
        XCTAssertEqual(String(decoding: try JSONEncoder().encode([VibemetricCore.Dimension.planningSpecs]), as: UTF8.self), #"["planning_specs"]"#)
        XCTAssertThrowsError(try JSONDecoder().decode([VibemetricCore.Dimension].self, from: Data(#"["unknown"]"#.utf8)))
    }

    func testClaudeCodeParserFoldsToolResultsAndSkipsInjectedText() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let project = dir.appendingPathComponent("-Users-me-app")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let lines = [
            #"{"type":"user","cwd":"/Users/me/app","timestamp":"2026-09-01T10:00:00.000Z","permissionMode":"acceptEdits","origin":{"kind":"human"},"message":{"role":"user","content":"Fix the login bug. Done when npm test passes."}}"#,
            #"{"type":"user","isMeta":true,"timestamp":"2026-09-01T10:00:01.000Z","message":{"role":"user","content":"<local-command-caveat>ignore</local-command-caveat>"}}"#,
            #"{"type":"assistant","timestamp":"2026-09-01T10:00:02.000Z","message":{"model":"claude-opus-5","content":[{"type":"tool_use","id":"t1","name":"Edit","input":{"file_path":"/Users/me/app/login.ts"}},{"type":"tool_use","id":"t2","name":"Bash","input":{"command":"npm test"}}]}}"#,
            #"{"type":"user","timestamp":"2026-09-01T10:00:03.000Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"ok"},{"type":"tool_result","tool_use_id":"t2","is_error":true,"content":"1 failing"}]}}"#,
            #"{"type":"ai-title","aiTitle":"Fix login","sessionId":"s1"}"#,
        ]
        let file = project.appendingPathComponent("s1.jsonl")
        try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)

        var s = try XCTUnwrap(ClaudeCodeParser.parse(file: file))
        SignalExtractor.annotate(&s)
        XCTAssertEqual(s.project, "app")
        XCTAssertEqual(s.title, "Fix login")
        XCTAssertEqual(s.userTurns, 1)
        XCTAssertEqual(s.toolCalls, 2)
        XCTAssertEqual(s.failedToolCalls, 1)
        XCTAssertEqual(s.permissionModes, ["acceptEdits"])
        XCTAssertEqual(s.signals.verifyAfterEdit, 1)
        XCTAssertEqual(s.signals.specLanguage, 1)
    }

    func testRedactorRemovesSecrets() {
        let text = "key sk-ant-abcdefghijklmnopqrstuv and https://hooks.slack.com/services/T0/B0/xyz and postgres://u:p@h/db token=abcdef123456" // gitleaks:allow (fake secrets for the redaction test)
        let out = Redactor.scrub(text)
        XCTAssertFalse(out.contains("sk-ant"))
        XCTAssertFalse(out.contains("hooks.slack.com"))
        XCTAssertFalse(out.contains("postgres://"))
        XCTAssertFalse(out.contains("abcdef123456"))
    }

    func testTotalsAndProvisionalRange() throws {
        var card = try JSONDecoder().decode(ScoreCard.self, from: Data(Self.sampleCard.utf8))
        XCTAssertEqual(card.totalLabel, "50")
        XCTAssertEqual(card.dimensions(in: .bottleneck).count, 10)
        card.dimensions[0].score = nil
        card.dimensions[0].status = .notReviewed
        XCTAssertEqual(card.totalLabel, "45–55")
        let md = MarkdownRenderer.render(card)
        XCTAssertTrue(md.contains("## 45–55 / 100"))
        XCTAssertTrue(md.contains("`●●●●●○○○○○`"))
        XCTAssertTrue(md.contains("Not reviewed"))
    }

    func testSchemaIsValidJSON() throws {
        let obj = try JSONSerialization.jsonObject(with: Data(JSONSchema.scoreCard.utf8)) as? [String: Any]
        XCTAssertEqual((obj?["required"] as? [String])?.count, 8)
    }

    func testRubricResourceLoads() {
        XCTAssertTrue(Assessor.rubric.contains("### 10. Efficiency & Cost"))
    }

    static var sampleCard: String {
        let dims = Dimension.allCases.map {
            #"{"dimension":"\#($0.rawValue)","score":5,"status":"scored","headline":"h","reason":"r","evidence":[]}"#
        }.joined(separator: ",")
        return """
        {"language":"en","diagnosis":"d","dimensions":[\(dims)],
         "improvement":{"title":"t","situation":"s","actions":["a","b"],"suggestedInstruction":null,"signOfSuccess":"x","tryItOn":"y"},
         "roadmap":[{"stage":1,"change":"c","result":"r"}],
         "scope":{"assessedAt":"2026-09-28","timeZone":"UTC","recordDates":[],"sessionsExamined":1,"tasksCheckedInDetail":1,"elapsedMinutes":0,"limits":[]}}
        """
    }
}

final class StabilityTests: XCTestCase {
    private func card(_ scores: [Int?], reasons: [String?] = []) throws -> ScoreCard {
        var c = try JSONDecoder().decode(ScoreCard.self, from: Data(CoreTests.sampleCard.utf8))
        for (i, s) in scores.enumerated() {
            c.dimensions[i].score = s
            c.dimensions[i].status = s == nil ? .notReviewed : .scored
            c.dimensions[i].changeReason = i < reasons.count ? reasons[i] : nil
        }
        return c
    }

    func testCardsWithoutChangeReasonStillDecode() throws {
        let c = try JSONDecoder().decode(ScoreCard.self, from: Data(CoreTests.sampleCard.utf8))
        XCTAssertNil(c.dimensions[0].changeReason)
    }

    func testCompareFlagsUnexplainedMoves() throws {
        let before = try card([6, 7, 7, 9, 8, 6, 7, 3, 8, 4])
        let after = try card([4, 7, 7, 9, 8, 6, 7, 3, 7, 5],
                             reasons: [nil, nil, nil, nil, nil, nil, nil, nil, nil, nil])
        var withReason = after
        withReason.dimensions[9].changeReason = "A 2026-09-30 session shows the guard hook blocking a push to main."

        let changes = ScoreChanges.compare(withReason, to: before)
        XCTAssertEqual(changes.map(\.dimension), [.planningSpecs, .security, .efficiencyCost])
        XCTAssertEqual(changes.map(\.delta), [-2, -1, 1])
        XCTAssertEqual(changes.map(\.isUnexplained), [true, true, false])
        XCTAssertEqual(ScoreChanges.totalDelta(withReason, to: before), -2)

        let md = MarkdownRenderer.render(withReason, previous: before, previousDate: "Sep 29")
        XCTAssertTrue(md.contains("### Changes since the previous assessment (Sep 29)"))
        XCTAssertTrue(md.contains("| Planning & Specs | 6 → 4 | No new evidence cited; likely scoring variation. |"))
        XCTAssertTrue(md.contains("blocking a push to main"))
    }

    func testNoChangesReportsSo() throws {
        let c = try card([5, 5, 5, 5, 5, 5, 5, 5, 5, 5])
        XCTAssertTrue(ScoreChanges.compare(c, to: c).isEmpty)
        XCTAssertTrue(MarkdownRenderer.render(c, previous: c).contains("No dimension changed."))
    }

    func testHookScriptsAreResolvedFromProjectDir() throws {
        let project = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let hooksDir = project.appendingPathComponent(".claude/hooks")
        try FileManager.default.createDirectory(at: hooksDir, withIntermediateDirectories: true)
        let script = hooksDir.appendingPathComponent("guard-bash.py")
        try "print('block push to main')".write(to: script, atomically: true, encoding: .utf8)
        let hooks: [String: Any] = ["PreToolUse": [["matcher": "Bash", "hooks": [["type": "command",
            "command": "python3 \"$CLAUDE_PROJECT_DIR/.claude/hooks/guard-bash.py\""]]]]]
        XCTAssertEqual(EvidencePack.hookScripts(hooks, projectDir: project).map(\.lastPathComponent), ["guard-bash.py"])
    }
}

final class RelativeDateTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    func testFormats() {
        let now = date(2026, 9, 29, 16, 0)
        let en = Locale(identifier: "en_US")
        func f(_ d: Date) -> String { RelativeDate.format(d, now: now, calendar: cal, locale: en) }
        XCTAssertEqual(f(date(2026, 9, 29, 14, 30)), "Today 2:30pm")
        XCTAssertEqual(f(date(2026, 9, 29, 9, 5)), "Today 9:05am")
        XCTAssertEqual(f(date(2026, 9, 28, 13, 15)), "Yesterday 1:15pm")
        XCTAssertEqual(f(date(2026, 9, 28, 23, 50)), "Yesterday 11:50pm")
        XCTAssertEqual(f(date(2026, 9, 27, 13, 30)), "2 days ago 1:30pm")
        XCTAssertEqual(f(date(2026, 9, 26, 10, 0)), "3 days ago")
        XCTAssertEqual(f(date(2026, 9, 23, 10, 0)), "6 days ago")
        XCTAssertEqual(f(date(2026, 9, 22, 10, 0)), "Sep 22")
        XCTAssertEqual(f(date(2025, 12, 31, 10, 0)), "Dec 31, 2025")
        XCTAssertEqual(f(date(2026, 9, 30, 1, 0)), "Sep 30") // future (clock skew)
    }
}

final class AutoScheduleTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }()

    private func at(_ d: Int, _ h: Int, _ m: Int) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 9, day: d, hour: h, minute: m))!
    }

    func testDueOnlyAfterTodaysSlotAndOnlyOnce() {
        let s = AutoSchedule() // 2:00pm
        XCTAssertFalse(s.isDue(now: at(29, 13, 59), lastResultAt: nil, lastAttemptAt: nil, calendar: cal))
        XCTAssertTrue(s.isDue(now: at(29, 14, 0), lastResultAt: nil, lastAttemptAt: nil, calendar: cal))
        // Catch-up: the Mac woke at 5pm and nothing ran since 2pm.
        XCTAssertTrue(s.isDue(now: at(29, 17, 0), lastResultAt: at(29, 10, 11), lastAttemptAt: at(28, 14, 0), calendar: cal))
        // Already attempted today (ran, skipped, or failed): don't loop.
        XCTAssertFalse(s.isDue(now: at(29, 17, 0), lastResultAt: nil, lastAttemptAt: at(29, 14, 0), calendar: cal))
        // A manual score after 2pm counts as today's score.
        XCTAssertFalse(s.isDue(now: at(29, 17, 0), lastResultAt: at(29, 15, 30), lastAttemptAt: nil, calendar: cal))
        XCTAssertFalse(AutoSchedule(enabled: false).isDue(now: at(29, 17, 0), lastResultAt: nil, lastAttemptAt: nil, calendar: cal))
    }

    func testNextRun() {
        let s = AutoSchedule(minuteOfDay: 9 * 60 + 30)
        XCTAssertEqual(s.next(after: at(29, 8, 0), calendar: cal), at(29, 9, 30))
        XCTAssertEqual(s.next(after: at(29, 9, 30), calendar: cal), at(30, 9, 30))
        XCTAssertNil(AutoSchedule(enabled: false).next(after: at(29, 8, 0), calendar: cal))
    }
}

final class FollowUpTests: XCTestCase {
    func testLineDiffFindsAddedAndRemovedRules() {
        let old = "# Rules\n- Use pnpm\n- Never push to main\n"
        let new = "# Rules\n- Use pnpm\n- List yes/no acceptance checks before any change\n"
        let d = RuleFiles.lineDiff(old: old, new: new)
        XCTAssertEqual(d.added, ["- List yes/no acceptance checks before any change"])
        XCTAssertEqual(d.removed, ["- Never push to main"])
    }

    func testChangesReportShowsOnlyChangedFiles() {
        let t = Date(timeIntervalSince1970: 1_790_000_000)
        let before = RuleSnapshot(taken: t, files: ["/p/a/CLAUDE.md": "one\ntwo", "/p/b/CLAUDE.md": "same"])
        let after = RuleSnapshot(taken: t.addingTimeInterval(60), files: ["/p/a/CLAUDE.md": "one\ntwo\nthree", "/p/b/CLAUDE.md": "same", "/p/c/AGENTS.md": "new rule"])
        let md = RuleFiles.changesReport(current: after, previous: before, since: nil)
        XCTAssertTrue(md.contains("## /p/a/CLAUDE.md (changed)"))
        XCTAssertTrue(md.contains("+ three"))
        XCTAssertTrue(md.contains("## /p/c/AGENTS.md (new file)"))
        XCTAssertFalse(md.contains("/p/b/CLAUDE.md"))
        XCTAssertTrue(RuleFiles.changesReport(current: before, previous: before, since: nil).contains("No rule or memory file changed."))
    }

    func testFollowUpDecodesButIsNotShown() throws {
        var json = try JSONSerialization.jsonObject(with: Data(CoreTests.sampleCard.utf8)) as! [String: Any]
        json["followUp"] = ["previousTitle": "Make checks a standing rule", "status": "partly_done",
                            "summary": "Added to demo-web/CLAUDE.md; not yet in Shop.", "evidence": []]
        let card = try JSONDecoder().decode(ScoreCard.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(card.followUp?.status, .partlyDone)
        // Cards that have a follow-up still decode, but it is no longer shown in the report.
        XCTAssertFalse(MarkdownRenderer.render(card).contains("Last recommendation"))
        // Older cards without the field still decode.
        XCTAssertNil(try JSONDecoder().decode(ScoreCard.self, from: Data(CoreTests.sampleCard.utf8)).followUp)
    }

    func testLowCoverageWarning() throws {
        var card = try JSONDecoder().decode(ScoreCard.self, from: Data(CoreTests.sampleCard.utf8))
        card.scope.sessionsExamined = 17
        XCTAssertTrue(card.isLowCoverage(sessionsAvailable: 45))
        card.scope.sessionsExamined = 40
        XCTAssertFalse(card.isLowCoverage(sessionsAvailable: 45))
        card.scope.sessionsExamined = 260
        XCTAssertFalse(card.isLowCoverage(sessionsAvailable: 1000)) // the target caps at 300
    }

    func testShellWritesToRuleFilesCountAsWrites() {
        for cmd in ["cat > CLAUDE.md <<'MD'", "echo x | tee -a AGENTS.md", "sed -i '' 's/a/b/' CLAUDE.md", "cp tmp CLAUDE.md"] {
            XCTAssertNotNil(SignalExtractor.shellWrite.firstMatch(in: cmd, range: NSRange(cmd.startIndex..., in: cmd)), cmd)
        }
        let read = "cat CLAUDE.md"
        XCTAssertNil(SignalExtractor.shellWrite.firstMatch(in: read, range: NSRange(read.startIndex..., in: read)))
    }
}

final class RubricTwoTests: XCTestCase {
    func testDeductionComesOffTheTotalNotTheDimensions() throws {
        var json = try JSONSerialization.jsonObject(with: Data(CoreTests.sampleCard.utf8)) as! [String: Any]
        json["deductions"] = [["points": 1, "reason": "Ran with --dangerously-skip-permissions and no hooks.", "evidence": []]]
        let card = try JSONDecoder().decode(ScoreCard.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(card.dimensionSum, 50)
        XCTAssertEqual(card.knownTotal, 49)
        XCTAssertEqual(card.totalLabel, "49")
        XCTAssertTrue(MarkdownRenderer.render(card).contains("## 49 / 100"))
        XCTAssertTrue(MarkdownRenderer.render(card).contains("−1 point deduction"))
        // Cards from before rubric 2 have no deductions field.
        XCTAssertEqual(try JSONDecoder().decode(ScoreCard.self, from: Data(CoreTests.sampleCard.utf8)).knownTotal, 50)
    }

    func testRubricThreeDeductionComesOffSecurity() throws {
        var json = try JSONSerialization.jsonObject(with: Data(CoreTests.sampleCard.utf8)) as! [String: Any]
        json["deductions"] = [["points": 1, "reason": "Ran with --dangerously-skip-permissions and no hooks.", "evidence": []]]
        var card = try JSONDecoder().decode(ScoreCard.self, from: JSONSerialization.data(withJSONObject: json))
        let before = card.ordered.first { $0.dimension == .security }!.score!
        card.applyDeductionToSecurity()
        card.applyDeductionToSecurity() // applying twice must not subtract twice
        XCTAssertEqual(card.ordered.first { $0.dimension == .security }!.score, max(before - 1, 0))
        XCTAssertEqual(card.scoreBeforeDeduction, before)
        XCTAssertEqual(card.totalDeductionPoints, 0)
        XCTAssertEqual(card.knownTotal, card.dimensionSum)
        XCTAssertEqual(card.knownTotal, 49)
        XCTAssertNotNil(card.deductionNote(for: .security))
        XCTAssertNil(card.deductionNote(for: .planningSpecs))
        XCTAssertFalse(MarkdownRenderer.render(card).contains("point deduction:"))
        XCTAssertTrue(MarkdownRenderer.render(card).contains("permission-bypass deduction"))
    }

    func testSecurityDeductionNeverGoesBelowZero() throws {
        var json = try JSONSerialization.jsonObject(with: Data(CoreTests.sampleCard.utf8)) as! [String: Any]
        json["deductions"] = [["points": 1, "reason": "bypass", "evidence": []]]
        var card = try JSONDecoder().decode(ScoreCard.self, from: JSONSerialization.data(withJSONObject: json))
        let i = card.dimensions.firstIndex { $0.dimension == .security }!
        card.dimensions[i].score = 0
        card.applyDeductionToSecurity()
        XCTAssertEqual(card.dimensions[i].score, 0)
        XCTAssertEqual(card.knownTotal, card.dimensionSum)
    }

    func testDeductionIsCappedAtOnePoint() throws {
        var json = try JSONSerialization.jsonObject(with: Data(CoreTests.sampleCard.utf8)) as! [String: Any]
        json["deductions"] = [["points": 1, "reason": "Claude Code bypass", "evidence": []],
                              ["points": 1, "reason": "Codex full access", "evidence": []]]
        let card = try JSONDecoder().decode(ScoreCard.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(card.deductionPoints, 1)
        XCTAssertEqual(card.knownTotal, 49)
    }

    func testSchemaAllowsOneDeductionEntry() throws {
        let obj = try JSONSerialization.jsonObject(with: Data(JSONSchema.scoreCard.utf8)) as! [String: Any]
        let deductions = (obj["properties"] as! [String: Any])["deductions"] as! [String: Any]
        XCTAssertEqual(deductions["maxItems"] as? Int, 1)
    }

    func testPromptIncludesNotesAndScoresAfresh() {
        let options = AssessmentOptions(instructions: "  The demo-skill sessions were only a test.  ")
        XCTAssertEqual(options.instructions, "The demo-skill sessions were only a test.")
        XCTAssertNil(AssessmentOptions(instructions: "   ").instructions)
        let prompt = Assessor.prompt(sources: [], now: Date(), previousDate: Date(), instructions: options.instructions)
        XCTAssertTrue(prompt.contains("# Notes from the person"))
        XCTAssertTrue(prompt.contains("The demo-skill sessions were only a test."))
        XCTAssertTrue(prompt.contains("Score every dimension afresh"))
        XCTAssertFalse(prompt.contains("Start each dimension from its previous score"))
        XCTAssertFalse(Assessor.prompt(sources: [], now: Date()).contains("# Notes from the person"))
    }

    func testRubricThreeDimensions() {
        XCTAssertEqual(Dimension.allCases.count, 10)
        XCTAssertEqual(Dimension.taskMapping.rawValue, "task_mapping")
        XCTAssertEqual(Dimension.taskMapping.title, "Orchestration I: Task Mapping")
        XCTAssertEqual(Dimension.feedbackLoops.title, "Orchestration II: Feedback Loops")
        XCTAssertEqual(Dimension.testingEvals.title, "Testing & Evals")
        XCTAssertEqual(Dimension.efficiencyCost.rawValue, "efficiency_cost")
    }

    func testRubricIsVersionThree() {
        XCTAssertEqual(AssessmentOptions.rubricVersion, "3")
        XCTAssertTrue(Assessor.rubric.contains("### 5. Orchestration I: Task Mapping"))
        XCTAssertTrue(Assessor.rubric.contains("### 6. Orchestration II: Feedback Loops"))
        XCTAssertTrue(Assessor.rubric.contains("### 10. Efficiency & Cost"))
        XCTAssertTrue(Assessor.rubric.contains("Permission-bypass deduction"))
    }
}

final class BandOrderTests: XCTestCase {
    func testBottlenecksComeFirstInTheReport() throws {
        let md = MarkdownRenderer.render(try JSONDecoder().decode(ScoreCard.self, from: Data(CoreTests.sampleCard.utf8)))
        let bottleneck = md.range(of: "BOTTLENECK · 0–5")!.lowerBound
        let developing = md.range(of: "DEVELOPING · 6–7")!.lowerBound
        let strong = md.range(of: "STRONG · 8–10")!.lowerBound
        XCTAssertLessThan(bottleneck, developing)
        XCTAssertLessThan(developing, strong)
    }
}

final class ReasonPointsTests: XCTestCase {
    func testPointsDecodeAndComposeAReason() throws {
        var json = try JSONSerialization.jsonObject(with: Data(CoreTests.sampleCard.utf8)) as! [String: Any]
        var dims = json["dimensions"] as! [[String: Any]]
        dims[0].removeValue(forKey: "reason")
        dims[0]["points"] = [["heading": "Specs name the outcome", "body": "- Login returns to the product\n- Checks listed"],
                             ["heading": "Constraints are rare", "body": "Two of nine handoffs said what must not change."]]
        dims[0]["conclusion"] = "Execution-ready specs are not yet the habit, so 7 is not reached."
        json["dimensions"] = dims
        let card = try JSONDecoder().decode(ScoreCard.self, from: JSONSerialization.data(withJSONObject: json))
        let d = card.dimensions[0]
        XCTAssertEqual(d.points?.map(\.heading), ["Specs name the outcome", "Constraints are rare"])
        XCTAssertTrue(d.reason.contains("**Specs name the outcome**"))
        XCTAssertTrue(d.reason.contains("so 7 is not reached"))
        let md = MarkdownRenderer.render(card)
        XCTAssertTrue(md.contains("**Specs name the outcome**<br>"))
        XCTAssertTrue(md.contains("<br>• Login returns to the product"))
        // Round-trips through the saved JSON with points intact.
        let again = try JSONDecoder().decode(ScoreCard.self, from: JSONEncoder().encode(card))
        XCTAssertEqual(again.dimensions[0].points?.count, 2)
        // Older cards keep their paragraphs.
        XCTAssertNil(try JSONDecoder().decode(ScoreCard.self, from: Data(CoreTests.sampleCard.utf8)).dimensions[0].points)
    }

    func testSchemaAsksForPointsAndConclusion() throws {
        let obj = try JSONSerialization.jsonObject(with: Data(JSONSchema.scoreCard.utf8)) as! [String: Any]
        let dims = (obj["properties"] as! [String: Any])["dimensions"] as! [String: Any]
        let item = dims["items"] as! [String: Any]
        let required = Set(item["required"] as! [String])
        XCTAssertTrue(required.isSuperset(of: ["headline", "points", "conclusion"]))
        XCTAssertFalse(required.contains("reason"))
    }
}

final class ToneTests: XCTestCase {
    typealias Tone = ScoreCard.DimensionResult.Tone

    func testToneEmojis() {
        XCTAssertEqual(Tone.allCases.map(\.emoji), ["✅", "⚠️", "ℹ️"])
        XCTAssertEqual(Tone.leading("⚠️ Acme: 501 lines")?.tone, .bad)
        XCTAssertEqual(Tone.leading("⚠️ Acme: 501 lines")?.rest, "Acme: 501 lines")
        XCTAssertEqual(Tone.leading("⚠ without the selector")?.tone, .bad)
        XCTAssertEqual(Tone.leading("ℹ️ context")?.tone, .neutral)
        XCTAssertNil(Tone.leading("plain bullet"))
    }

    func testTonedPointsInTheReport() throws {
        var json = try JSONSerialization.jsonObject(with: Data(CoreTests.sampleCard.utf8)) as! [String: Any]
        var dims = json["dimensions"] as! [[String: Any]]
        dims[0].removeValue(forKey: "reason")
        dims[0]["points"] = [["heading": "Strong files exist", "body": "Shop's file covers it.", "tone": "good"],
                             ["heading": "Gaps", "body": "- ⚠️ Acme: 501 lines\n- ℹ️ Sandbox excluded", "tone": "bad"]]
        dims[0]["conclusion"] = "Uneven coverage."
        json["dimensions"] = dims
        let card = try JSONDecoder().decode(ScoreCard.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(card.dimensions[0].points?.map(\.tone), [.good, .bad])
        XCTAssertTrue(card.dimensions[0].reason.hasPrefix("✅ **Strong files exist**"))
        let md = MarkdownRenderer.render(card)
        XCTAssertTrue(md.contains("⚠️ **Gaps**<br>"))
        XCTAssertTrue(md.contains("<br>⚠️ Acme: 501 lines"))
        XCTAssertFalse(md.contains("• ⚠️"))
    }
}
