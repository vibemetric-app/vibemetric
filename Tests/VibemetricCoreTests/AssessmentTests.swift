import Foundation
import Testing
@testable import VibemetricCore

struct AssessmentTests {
    @Test func freshAssessmentsRequirePlanningDetailsWhileLegacyCardsRemainReadable() throws {
        let legacy = try JSONDecoder().decode(ScoreCard.self, from: Data(CoreTests.sampleCard.utf8))
        try Assessor.validate(legacy)
        #expect(throws: AssessmentError.self) { try Assessor.validate(legacy, requirePlanning: true) }
        #expect(throws: AssessmentError.self) { try Assessor.validate(legacy, requireAssessments: true) }
        #expect(throws: AssessmentError.self) { try Assessor.validate(legacy, requireExplanations: true) }
    }

    @Test func liveResultsRequireEveryExplanationParagraphButLegacyDecodeDoesNot() throws {
        let fixture = try CLIFixture()
        defer { fixture.remove() }
        let data = try Data(contentsOf: fixture.directory.appendingPathComponent("fixture-card.json"))
        var card = try JSONDecoder().decode(ScoreCard.self, from: data)
        try Assessor.validate(card, requirePlanning: true, requireAssessments: true, requireExplanations: true)
        card.dimensions[0].planning?.competencies[0].explanation = nil
        try Assessor.validate(card)
        #expect(throws: AssessmentError.self) { try Assessor.validate(card, requireExplanations: true) }
        card = try JSONDecoder().decode(ScoreCard.self, from: data)
        card.dimensions[1].assessment?.competencies[0].explanation?.overallJudgment = " \n "
        #expect(throws: AssessmentError.self) { try Assessor.validate(card, requireExplanations: true) }
    }

    @Test(arguments: AssessmentEngine.allCases)
    func scoresWithEitherCLI(_ engine: AssessmentEngine) async throws {
        let fixture = try CLIFixture()
        defer { fixture.remove() }
        let assessor = Assessor(installation: CLIInstallation(executable: fixture.command, version: "fixture"))
        let outcome = try await assessor.run(packDir: fixture.directory, sources: [], options: .fixture(engine)) { _ in }
        #expect(outcome.card.knownTotal == 68)
        #expect(outcome.card.dimensions[0].score == 5)
        #expect(outcome.card.dimensions.dropFirst().allSatisfy { $0.score == 7 })
        var input = try JSONDecoder().decode(ScoreCard.self, from: Data(contentsOf: fixture.directory.appendingPathComponent("fixture-card.json")))
        try input.calculateCompetencyScores()
        let saved = try JSONDecoder().decode(ScoreCard.self, from: outcome.rawJSON)
        #expect(saved.highlights == input.highlights)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        for (expected, actual) in zip(input.ordered, saved.ordered) {
            #expect(actual.score == expected.score)
            #expect(actual.issueLine == expected.issueLine)
            #expect(actual.fixLine == expected.fixLine)
            #expect(actual.saw == expected.saw)
            #expect(actual.tryThis == expected.tryThis)
            #expect(try encoder.encode(actual.planning) == encoder.encode(expected.planning))
            for (before, after) in zip(expected.assessment?.competencies ?? [], actual.assessment?.competencies ?? []) {
                #expect(after.id == before.id)
                #expect(after.level == before.level)
                #expect(after.summary == before.summary)
                #expect(after.solution == before.solution)
                #expect(try encoder.encode(after.explanation) == encoder.encode(before.explanation))
            }
        }
        // Skim, investigate, and write each continue the session saved by the request before.
        #expect(outcome.sessionID != CLIFixture.sessionID)
        #expect(outcome.sessionID != CLIFixture.forkID)
        #expect(outcome.engine == engine)
        #expect(outcome.cliVersion == "fixture")
        #expect(abs((outcome.costUSD ?? 0) - (engine == .claude ? 0.10 : 0)) < 0.000_001, "Skim, investigate, and three writing parts")
        #expect((outcome.costUSD == nil) == (engine == .codex))
        let args = try String(contentsOf: fixture.directory.appendingPathComponent("received-arguments.txt"), encoding: .utf8)
        if engine == .claude {
            #expect(args.contains("--tools\nRead\nGrep\nGlob\n--allowedTools\nRead\nGrep\nGlob\n--permission-mode\ndontAsk"))
            #expect(args.contains("--strict-mcp-config\n--mcp-config\n{\"mcpServers\":{}}\n"), "The person's MCP servers stay out of judging")
            #expect(!args.contains("WebSearch"))
            #expect(!args.contains("WebFetch"))
        } else {
            #expect(args.contains("web_search=\"disabled\""))
            #expect(!args.contains("web_search=\"live\""))
            #expect(args.contains("--sandbox\nread-only"))
        }
        for name in ["assessment-prompt.txt", "assessment-schema.json", "assessment-result.json"] {
            #expect(!FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent(name).path))
        }
    }

    @Test func codexArgumentsKeepTheJudgeReadOnlyAndPersistent() {
        let args = Assessor.arguments(options: AssessmentOptions(engine: .codex, model: "chosen-model"), sources: [],
                                      schemaFile: URL(fileURLWithPath: "/tmp/a space/schema.json"),
                                      resultFile: URL(fileURLWithPath: "/tmp/a space/result.json"))
        #expect(!args.contains("--ephemeral"))
        #expect(args.contains("--ignore-user-config"))
        #expect(args.contains("read-only"))
        #expect(args.contains("approval_policy=\"never\""))
        #expect(args.contains("features.hooks=false"))
        #expect(args.contains("features.apps=false"))
        #expect(args.contains("features.plugins=false"))
        #expect(args.contains("web_search=\"disabled\""))
        #expect(args.contains("chosen-model"))
        #expect(args.contains("/tmp/a space/schema.json"))
        #expect(!args.contains("--add-dir")) // Codex uses this flag for write grants.
        #expect(!args.contains("--dangerously-bypass-approvals-and-sandbox"))
        #expect(args.last == "-")
    }

    @Test(arguments: AgentTool.allCases)
    func persistedAssessmentAndItsForkAreExcludedFromScanning(_ tool: AgentTool) {
        let parent = Session(id: "parent", tool: tool, file: URL(fileURLWithPath: "/tmp/parent.jsonl"),
                             project: "assessment", events: [.init(kind: .user(Assessor.rubric))])
        var fork = parent
        fork.id = "fork"
        fork.events.append(.init(kind: .user("Deep dive into context engineering")))
        #expect(Scanner.isAssessmentRun(parent))
        #expect(Scanner.isAssessmentRun(fork))
    }

    @Test(arguments: [true, false])
    func savedForkIsExcludedEvenAfterItsEvidenceIsDeleted(isDev: Bool) {
        let directory = EvidencePack.savedPacksDirectory(isDev: isDev).appendingPathComponent("deleted-\(UUID())")
        var fork = Session(id: "fork", tool: .codex, file: URL(fileURLWithPath: "/tmp/fork.jsonl"),
                           project: "deep dive", cwd: directory.path,
                           events: [.init(kind: .user("Analyze this dimension"))])
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        #expect(Scanner.isAssessmentRun(fork))
        fork.cwd = directory.path.replacingOccurrences(of: "/packs/", with: "/packs-other/")
        #expect(!Scanner.isAssessmentRun(fork))
    }

    @Test(arguments: AssessmentEngine.allCases, [true, false])
    func webAccessIsOffUnlessAskedForAndLimitedForClaude(_ engine: AssessmentEngine, web: Bool) {
        let args = Assessor.arguments(options: AssessmentOptions(engine: engine), sources: [],
                                      schemaFile: URL(fileURLWithPath: "/tmp/s.json"), resultFile: URL(fileURLWithPath: "/tmp/r.json"),
                                      webAccess: web).joined(separator: "\n")
        switch (engine, web) {
        case (.claude, true):
            #expect(args.contains("--allowedTools\nRead\nGrep\nGlob\nWebSearch\nWebFetch(domain:docs.anthropic.com)\n"))
            #expect(!args.contains("\nWebFetch\n--permission-mode"), "No unrestricted WebFetch")
        case (.codex, true):
            #expect(args.contains("web_search=\"live\""))
        case (.claude, false):
            #expect(!args.contains("WebSearch") && !args.contains("WebFetch"))
        case (.codex, false):
            #expect(args.contains("web_search=\"disabled\""))
        }
    }

    @Test func splitUTF8EventsAndFinalLineWithoutNewline() {
        let progress = Events()
        let stream = AssessmentStream(engine: .codex) { progress.append($0) }
        let events = """
        {"type":"item.started","item":{"id":"read","type":"command_execution","command":"cat 자료.md"}}
        {"type":"item.completed","item":{"id":"read","type":"command_execution","command":"cat 자료.md"}}
        {"type":"future.event","unknown":true}
        {"type":"item.completed","item":{"id":"message","type":"agent_message","text":"검토 완료"}}
        {"type":"turn.completed","usage":{"input_tokens":12}}
        """
        for byte in events.utf8 { stream.consume(Data([byte])) }
        stream.finish()
        #expect(stream.snapshot.completed)
        #expect(progress.texts == ["cat 자료.md", "검토 완료"])
    }

    @Test(arguments: ["exit", "failed", "missing", "invalid"])
    func rejectsUnsuccessfulOrInvalidResults(_ mode: String) async throws {
        let fixture = try CLIFixture(mode: mode)
        defer { fixture.remove() }
        // A stale valid result must not hide a failed/missing response.
        try Data(CoreTests.sampleCard.utf8).write(to: fixture.directory.appendingPathComponent("assessment-result.json"))
        await #expect(throws: AssessmentError.self) {
            try await Assessor(installation: CLIInstallation(executable: fixture.command))
                .run(packDir: fixture.directory, sources: [], options: .fixture(.codex)) { _ in }
        }
    }

    @Test func readingRepliesWithoutTheCheckpointStillReachTheCard() async throws {
        let fixture = try CLIFixture(mode: "checkpoint-text")
        defer { fixture.remove() }
        let outcome = try await Assessor(installation: CLIInstallation(executable: fixture.command))
            .run(packDir: fixture.directory, sources: [], options: .fixture(.claude)) { _ in }
        #expect(outcome.card.dimensions.count == 10)
    }

    @Test func aMissingCardIsAskedForOnceMoreInTheSameSession() async throws {
        let fixture = try CLIFixture(mode: "missing-once")
        defer { fixture.remove() }
        let events = Events()
        let outcome = try await Assessor(installation: CLIInstallation(executable: fixture.command))
            .run(packDir: fixture.directory, sources: [], options: .fixture(.claude)) { events.append($0) }
        #expect(outcome.card.dimensions.count == 10)
        #expect(events.texts.contains(Assessor.rewriteNotice))
        let prompts = try String(contentsOf: fixture.directory.appendingPathComponent("prompt-log.txt"), encoding: .utf8)
        #expect(prompts.components(separatedBy: "Your last reply did not include the requested part").count - 1 == 3,
                "Each of the three parts is asked for once more")
    }

    @Test func aCardStillMissingAfterTheSecondRequestFails() async throws {
        let fixture = try CLIFixture(mode: "never-card")
        defer { fixture.remove() }
        await #expect(throws: AssessmentError.self) {
            try await Assessor(installation: CLIInstallation(executable: fixture.command))
                .run(packDir: fixture.directory, sources: [], options: .fixture(.claude)) { _ in }
        }
        let prompts = try String(contentsOf: fixture.directory.appendingPathComponent("prompt-log.txt"), encoding: .utf8)
        #expect(prompts.components(separatedBy: "Your last reply did not include the requested part").count - 1 == 3,
                "Each part is asked for once more, never twice")
    }

    @Test(arguments: AssessmentEngine.allCases)
    func theCardIsWrittenInThreePartsAndAssembled(_ engine: AssessmentEngine) async throws {
        let fixture = try CLIFixture()
        defer { fixture.remove() }
        let outcome = try await Assessor(installation: CLIInstallation(executable: fixture.command))
            .run(packDir: fixture.directory, sources: [], options: .fixture(engine)) { _ in }
        #expect(outcome.card.knownTotal == 68)
        #expect(Assessor.incompleteDimensions(outcome.card).isEmpty)
        let prompts = try String(contentsOf: fixture.directory.appendingPathComponent("prompt-log.txt"), encoding: .utf8)
        for part in ["part 1 of 3", "part 2 of 3", "part 3 of 3"] { #expect(prompts.contains(part)) }
        #expect(prompts.contains("planning_specs, context_engineering"), "The first part asks for the first five dimensions")
        #expect(prompts.contains("never write a straight double quote or a backslash"))
        #expect(!prompts.contains("Your last reply did not include the requested part"))
    }

    @Test func aCardClaudeCodeTurnsDownIsKeptInsteadOfWrittenAgain() async throws {
        let fixture = try CLIFixture(mode: "rejected-card")
        defer { fixture.remove() }
        let started = Date()
        let outcome = try await Assessor(installation: CLIInstallation(executable: fixture.command))
            .run(packDir: fixture.directory, sources: [], options: .fixture(.claude)) { _ in }
        #expect(outcome.card.knownTotal == 68)
        #expect(Date().timeIntervalSince(started) < 10, "The app stops the CLI instead of waiting for a rewrite")
        let prompts = try String(contentsOf: fixture.directory.appendingPathComponent("prompt-log.txt"), encoding: .utf8)
        #expect(!prompts.contains("Your last reply did not include the requested part"))
    }

    @Test(arguments: AssessmentEngine.allCases)
    func anIncompleteDimensionIsAskedForAloneAndMerged(_ engine: AssessmentEngine) async throws {
        let fixture = try CLIFixture(mode: "incomplete-dimension")
        defer { fixture.remove() }
        let full = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture.directory.appendingPathComponent("fixture-card.json"))) as! [String: Any]
        var dimensions = full["dimensions"] as! [[String: Any]]
        let index = dimensions.firstIndex { $0["dimension"] as? String == "security" }!
        let security = dimensions[index]
        var broken = security
        var assessment = broken["assessment"] as! [String: Any]
        var competencies = assessment["competencies"] as! [[String: Any]]
        var explanation = competencies[0]["explanation"] as! [String: Any]
        explanation["overallJudgment"] = " "
        competencies[0]["explanation"] = explanation
        assessment["competencies"] = competencies
        broken["assessment"] = assessment
        dimensions[index] = broken
        var incomplete = full
        incomplete["dimensions"] = dimensions
        try JSONSerialization.data(withJSONObject: incomplete).write(to: fixture.directory.appendingPathComponent("fixture-card-incomplete.json"))
        try JSONSerialization.data(withJSONObject: ["dimensions": [security]]).write(to: fixture.directory.appendingPathComponent("fixture-patch.json"))
        // Codex writes its answer to a file; the same three cards are served there.
        if engine == .codex {
            let script = try String(contentsOf: fixture.command, encoding: .utf8).replacingOccurrences(
                of: #"if [ "incomplete-dimension" != "missing" ]; then cat fixture-card.json > "$output"; fi"#,
                with: #"if grep -q "Phase 3 of 3" received-prompt.txt; then cat fixture-card-incomplete.json > "$output"; elif grep -q "Return only these dimensions" received-prompt.txt; then cat fixture-patch.json > "$output"; else cat fixture-card.json > "$output"; fi"#)
            try script.write(to: fixture.command, atomically: true, encoding: .utf8)
        }
        let outcome = try await Assessor(installation: CLIInstallation(executable: fixture.command))
            .run(packDir: fixture.directory, sources: [], options: .fixture(engine)) { _ in }
        #expect(outcome.card.knownTotal == 68)
        #expect(Assessor.incompleteDimensions(outcome.card).isEmpty)
        let prompts = try String(contentsOf: fixture.directory.appendingPathComponent("prompt-log.txt"), encoding: .utf8)
        #expect(prompts.components(separatedBy: "Return only these dimensions").count == 2)
        #expect(prompts.contains("except for these dimensions: security."))
        #expect(!prompts.contains("Your last reply did not include the requested part"))
    }

    @Test(arguments: AssessmentEngine.allCases)
    func readingStopsWhenTheContextIsHalfFullAndSkipsInvestigation(_ engine: AssessmentEngine) async throws {
        let fixture = try CLIFixture(mode: "context-full")
        defer { fixture.remove() }
        var options = AssessmentOptions.fixture(engine)
        options.reading.skimMinimum = 60
        options.reading.maxRequests = 3
        let events = Events()
        let started = Date()
        let outcome = try await Assessor(installation: CLIInstallation(executable: fixture.command))
            .run(packDir: fixture.directory, sources: [], options: options) { events.append($0) }
        #expect(outcome.card.knownTotal == 68)
        #expect(Date().timeIntervalSince(started) < 10, "The app stops the reading run instead of waiting for it")
        #expect(events.texts.contains(Assessor.contextNotice))
        #expect(!outcome.wrappedUp, "Reaching the context limit is not a time cut")
        let prompts = try String(contentsOf: fixture.directory.appendingPathComponent("prompt-log.txt"), encoding: .utf8)
        #expect(!prompts.contains("Keep skimming"), "A full context ends skimming even before its minimum time")
        #expect(!prompts.contains("Phase 2 of 3: investigate"))
        #expect(prompts.contains("Phase 3 of 3: write"))
    }

    @Test(arguments: AssessmentEngine.allCases)
    func readingRunsWithoutThinkingAndWritingKeepsIt(_ engine: AssessmentEngine) async throws {
        let fixture = try CLIFixture()
        defer { fixture.remove() }
        _ = try await Assessor(installation: CLIInstallation(executable: fixture.command))
            .run(packDir: fixture.directory, sources: [], options: .fixture(engine)) { _ in }
        if engine == .claude {
            let thinking = try String(contentsOf: fixture.directory.appendingPathComponent("thinking-log.txt"), encoding: .utf8)
            #expect(thinking.split(separator: "\n") == ["0", "0", "unset", "unset", "unset"],
                    "Skim and investigate without thinking; the three writing parts with it")
        } else {
            let effort = try String(contentsOf: fixture.directory.appendingPathComponent("effort-log.txt"), encoding: .utf8)
            #expect(effort.split(separator: "\n") == ["low", "low", "default", "default", "default"])
        }
    }

    @Test func claudeRepliesReportTheContextAndHandBackRejectedCards() {
        let rejected = Collected()
        let stream = AssessmentStream(engine: .claude, onProgress: { _ in }, onRejectedCard: { rejected.append($0) })
        let events = [
            #"{"type":"assistant","message":{"usage":{"input_tokens":2,"cache_read_input_tokens":400000,"cache_creation_input_tokens":1000,"output_tokens":50},"content":[{"type":"tool_use","id":"c1","name":"StructuredOutput","input":{"summary":["A fictional card."]}}]}}"#,
            #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"c1","is_error":true,"content":"Output does not match required schema"}]}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"c2","name":"StructuredOutput","input":{"summary":["Accepted."]}}]}}"#,
            #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"c2","content":"Structured output provided successfully"}]}}"#,
        ].joined(separator: "\n") + "\n"
        stream.consume(Data(events.utf8))
        #expect(stream.contextTokens == 401_052)
        #expect(rejected.values.count == 1, "Only the turned-down card is handed back")
        #expect(String(decoding: rejected.values[0], as: UTF8.self).contains("A fictional card."))
    }

    @Test func codexContextIsEstimatedFromWhatTheRunReads() {
        let stream = AssessmentStream(engine: .codex, contextBase: 1_000, onProgress: { _ in })
        let output = String(repeating: "기", count: 1_140)
        let event = #"{"type":"item.completed","item":{"id":"c1","type":"command_execution","command":"cat a","aggregated_output":"\#(output)"}}"#
        stream.consume(Data((event + "\n").utf8))
        #expect(stream.contextTokens == 1_000 + AssessmentStream.estimatedTokens("cat a") + AssessmentStream.estimatedTokens(output))
        #expect(AssessmentStream.estimatedTokens(output) >= 1_000, "About 1.14 characters per token")
    }

    @Test func rejectsDuplicateDimensionsAndOutOfRangeScores() throws {
        var card = try JSONDecoder().decode(ScoreCard.self, from: Data(CoreTests.sampleCard.utf8))
        card.dimensions[0] = card.dimensions[1]
        #expect(throws: AssessmentError.self) { try Assessor.validate(card) }
        card = try JSONDecoder().decode(ScoreCard.self, from: Data(CoreTests.sampleCard.utf8))
        card.dimensions[0].score = 11
        #expect(throws: AssessmentError.self) { try Assessor.validate(card) }
        card.dimensions[0].score = nil
        #expect(throws: AssessmentError.self) { try Assessor.validate(card) }
    }

    @Test func rejectsNotReviewedInNewAssessmentResults() async throws {
        let fixture = try CLIFixture()
        defer { fixture.remove() }
        var card = try JSONDecoder().decode(ScoreCard.self, from: Data(CoreTests.sampleCard.utf8))
        card.dimensions[0].status = .notReviewed
        card.dimensions[0].score = nil
        try JSONEncoder().encode(card).write(to: fixture.directory.appendingPathComponent("fixture-card.json"))
        await #expect(throws: AssessmentError.self) {
            try await Assessor(installation: CLIInstallation(executable: fixture.command))
                .run(packDir: fixture.directory, sources: [], options: .fixture(.codex)) { _ in }
        }
    }

    @Test func cancellationBeforeLaunchNeverStartsTheCLI() async throws {
        let fixture = try CLIFixture()
        defer { fixture.remove() }
        let assessor = Assessor(installation: CLIInstallation(executable: fixture.command))
        assessor.cancel()
        await #expect(throws: CancellationError.self) {
            try await assessor.run(packDir: fixture.directory, sources: [], options: .fixture(.codex)) { _ in }
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("received-prompt.txt").path))
    }

    @Test(arguments: [true, false])
    func stoppingAKnownChildProcessReturnsPromptly(_ cancel: Bool) async throws {
        let fixture = try CLIFixture(mode: "sleep")
        defer { fixture.remove() }
        let assessor = Assessor(installation: CLIInstallation(executable: fixture.command))
        var options = AssessmentOptions.fixture(.codex)
        options.timeout = cancel ? 10 : 0.15
        let started = Date()
        let task = Task { try await assessor.run(packDir: fixture.directory, sources: [], options: options) { _ in } }
        if cancel {
            try await Task.sleep(for: .milliseconds(150))
            task.cancel()
        }
        do {
            _ = try await task.value
            Issue.record("A stopped process must not produce a score")
        } catch is CancellationError { #expect(cancel) }
        catch AssessmentError.timedOut { #expect(!cancel) }
        #expect(Date().timeIntervalSince(started) < 4)
    }

    @Test(arguments: AssessmentEngine.allCases)
    func aRunPastItsReadingTimeIsFinishedFromItsSavedSession(_ engine: AssessmentEngine) async throws {
        let fixture = try CLIFixture(mode: "slow-first")
        defer { fixture.remove() }
        let assessor = Assessor(installation: CLIInstallation(executable: fixture.command))
        var options = AssessmentOptions(engine: engine)
        options.timeout = 10
        let events = Events()
        let started = Date()
        let raw = try await assessor.runStructured(prompt: "Score this", schema: JSONSchema.scoreCard, packDir: fixture.directory,
                                                   sources: [], options: options, wrapUp: (1.0, Assessor.wrapUpPrompt)) { events.append($0) }
        #expect(raw.wrappedUp)
        #expect(raw.sessionID == CLIFixture.forkID)
        #expect(Date().timeIntervalSince(started) < 5)
        #expect(events.texts.contains { $0.contains("Time limit reached") })
        let args = try String(contentsOf: fixture.directory.appendingPathComponent("received-arguments.txt"), encoding: .utf8)
        #expect(args.contains(engine == .claude ? "--resume\n\(CLIFixture.sessionID)\n--fork-session" : "fork\n\(CLIFixture.sessionID)"))
    }

    @Test func aRunWithoutASavedSessionStillTimesOut() async throws {
        let fixture = try CLIFixture(mode: "slow-unsaved")
        defer { fixture.remove() }
        let assessor = Assessor(installation: CLIInstallation(executable: fixture.command))
        var options = AssessmentOptions(engine: .claude)
        options.timeout = 10
        await #expect(throws: AssessmentError.self) {
            try await assessor.runStructured(prompt: "Score this", schema: JSONSchema.scoreCard, packDir: fixture.directory,
                                             sources: [], options: options, wrapUp: (0.5, Assessor.wrapUpPrompt)) { _ in }
        }
    }

    @Test func readingPhasesFitWithinTheOneHourLimit() {
        let phases = AssessmentOptions().reading
        #expect(AssessmentOptions.scoreTimeLimit == 60 * 60)
        #expect(phases.skimMinimum == 60 && phases.investigateMinimum == 3 * 60)
        #expect(phases.digestShare == 0.15 && phases.investigateShare == 0.20 && phases.writeStartShare == 0.50)
        #expect(AssessmentOptions(engine: .claude).digestTokenBudget == 150_000)
        #expect(AssessmentOptions(engine: .codex).digestTokenBudget == 71_250)
        #expect(phases.skimLimit + phases.investigateLimit < AssessmentOptions.scoreTimeLimit)
    }

    @Test(arguments: AssessmentEngine.allCases)
    func anEarlyCheckpointIsSentBackUntilTheSkimTargetIsMet(_ engine: AssessmentEngine) async throws {
        let fixture = try CLIFixture()
        defer { fixture.remove() }
        for name in ["cc-aaaa.md", "cc-bbbb.md"] {
            try "A fictional task record.".write(to: fixture.directory.appendingPathComponent("sessions/\(name)"), atomically: true, encoding: .utf8)
        }
        var options = AssessmentOptions.fixture(engine)
        options.reading.maxRequests = 3
        let outcome = try await Assessor(installation: CLIInstallation(executable: fixture.command))
            .run(packDir: fixture.directory, sources: [], options: options) { _ in }
        #expect(outcome.card.knownTotal == 68)
        let prompts = try String(contentsOf: fixture.directory.appendingPathComponent("prompt-log.txt"), encoding: .utf8)
        // The fixture never opens a digest, so skimming is sent back until its request limit, then the run moves on.
        #expect(prompts.components(separatedBy: "Keep skimming").count - 1 == 2)
        #expect(prompts.contains("Phase 2 of 3: investigate"))
        #expect(prompts.contains("Phase 3 of 3: write"))
    }

    @Test func incompatibleCodexGetsAnActionableError() {
        #expect(throws: AssessmentError.self) { try CLILocator.validateCodexHelp("--json --sandbox --output-schema") }
    }

    @Test func unsupportedModelDoesNotAssumeAnAccountProblem() {
        let detail = #"{"type":"invalid_request_error","message":"The 'gpt-6-sol' model is not supported when using Codex with a ChatGPT account."}"#
        #expect(Assessor.failureMessage(detail, engine: .codex)
                == "The selected model is not supported by this Codex setup. Update Codex and check model access, then try again.")
    }
}

struct CLIFixture {
    static let sessionID = "11111111-1111-4111-8111-111111111111"
    static let forkID = "22222222-2222-4222-8222-222222222222"
    let directory: URL
    let command: URL

    init(mode: String = "ok") throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("vibemetric test \(UUID())")
        command = directory.appendingPathComponent("fake-cli")
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        var card = try JSONDecoder().decode(ScoreCard.self, from: Data(CoreTests.sampleCard.utf8))
        card.highlights = ["You define the export result before the AI starts.", "Your AI uses a repeatable procedure for export work."]
        for index in card.dimensions.indices {
            card.dimensions[index].issueLine = "Your AI's export work still needs a recorded completion check."
            card.dimensions[index].fixLine = "Record the export check before your AI starts the next task."
        }
        let explanation = PlanningAssessment.Explanation(
            sourceBasis: "The supplied guide connects a result to its check.",
            criteria: "A connected check is high; an unresolved check is medium; no intended result is low.",
            observedBehavior: "Cedar's export request names its expected output.",
            overallJudgment: "One observed task supports the stated level; unread work is outside this judgment.")
        let levels: [PlanningAssessment.Level] = [.high, .medium, .low, .unknown]
        card.scope.unknownInvestigations = [.init(
            dimension: .planningSpecs, competencyID: "ambiguity_resolution", status: .notFound,
            searches: ["Inspected fictional task records and their available continuations."], remainingLeads: [])]
        card.dimensions[0].planning = PlanningAssessment(competencies: zip(PlanningAssessment.CompetencyID.allCases, levels).map { id, level in
            PlanningAssessment.Competency(id: id, level: level, summary: "Cedar defines its export work. The acceptance check is recorded.",
                sources: [.init(title: "Prove It Works", url: "https://raw.githubusercontent.com/cursor/plugins/main/pstack/skills/principle-prove-it-works/SKILL.md", note: "A fictional practice guide.")],
                criteria: .init(high: "Outcome and check agree.", medium: "Outcome is incomplete.", low: "Outcome is unspecified."),
                explanation: explanation)
        })
        let guide = try RubricGuide.load()
        for index in card.dimensions.indices where card.dimensions[index].dimension != .planningSpecs {
            let definition = guide.guide(for: card.dimensions[index].dimension)!
            card.dimensions[index].assessment = BehavioralAssessment(competencies: definition.competencies.map { competency in
                .init(id: competency.id, level: .medium, title: competency.title,
                      summary: "Cedar uses a relevant procedure. Its complete behavior remains unverified.",
                      sources: [], criteria: .init(high: "", medium: "", low: ""),
                      explanation: explanation)
            })
        }
        try JSONEncoder().encode(card).write(to: directory.appendingPathComponent("fixture-card.json"))
        let script = #"""
        #!/bin/sh
        printf '%s\n' "$@" > received-arguments.txt
        session_id="\#(Self.sessionID)"
        is_fork=0
        for arg in "$@"; do
          if [ "$arg" = "fork" ] || [ "$arg" = "--fork-session" ]; then is_fork=1; fi
        done
        # Every continuation gets a new session: the first is forkID, later ones count up.
        if [ "$is_fork" = 1 ]; then
          forks=$(cat fork-count 2>/dev/null || echo 0)
          echo $((forks + 1)) > fork-count
          if [ "$forks" = 0 ]; then session_id="\#(Self.forkID)"; else session_id=$(printf '33333333-3333-4333-8333-%012d' "$forks"); fi
        fi
        if [ "\#(mode)" = "same-session" ]; then session_id="\#(Self.sessionID)"; fi
        if [ "\#(mode)" = "no-session" ]; then session_id=""; fi
        cat > received-prompt.txt
        cat received-prompt.txt >> prompt-log.txt
        case "$*" in *model_reasoning_effort*) echo low ;; *) echo default ;; esac >> effort-log.txt
        if [ "\#(mode)" = "sleep" ]; then sleep 30; exit 1; fi
        # A first run that is still reading at its time limit, after saving its session (or not).
        if [ "$is_fork" = 0 ] && { [ "\#(mode)" = "slow-first" ] || [ "\#(mode)" = "slow-unsaved" ]; }; then
          if [ "\#(mode)" = "slow-first" ]; then
            if [ "$1" = "-p" ]; then printf '{"type":"system","subtype":"init","session_id":"%s"}\n' "$session_id"
            else printf '{"type":"thread.started","thread_id":"%s"}\n' "$session_id"; fi
          fi
          sleep 30; exit 1
        fi
        if [ "$1" = "-p" ]; then
          printf '{"type":"system","subtype":"init","session_id":"%s"}\n' "$session_id"
          printf '%s\n' "${MAX_THINKING_TOKENS:-unset}" >> thinking-log.txt
          # A first reading run whose context is already past half, still reading when the app stops it.
          if [ "\#(mode)" = "context-full" ] && [ "$is_fork" = 0 ]; then
            printf '{"type":"assistant","message":{"usage":{"input_tokens":2,"cache_read_input_tokens":600000,"output_tokens":10},"content":[]}}\n'
            sleep 30; exit 1
          fi
          # A card Claude Code turns down, after which the model would start writing it again.
          if [ "\#(mode)" = "rejected-card" ] && grep -q "Phase 3 of 3" received-prompt.txt; then
            printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"card1","name":"StructuredOutput","input":'
            tr -d '\n' < fixture-card.json
            printf '}]}}\n'
            printf '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"card1","is_error":true,"content":"Output does not match required schema"}]}}\n'
            sleep 30; exit 1
          fi
          card=fixture-card.json
          if [ "\#(mode)" = "incomplete-dimension" ]; then
            if grep -q "Phase 3 of 3" received-prompt.txt; then card=fixture-card-incomplete.json; fi
            if grep -q "Return only these dimensions" received-prompt.txt; then card=fixture-patch.json; fi
          fi
          # Replies that end in plain text instead of the structured output: every reading reply, or the first card.
          if { [ "\#(mode)" = "checkpoint-text" ] && ! grep -q "Phase 3 of 3" received-prompt.txt; } ||
             { [ "\#(mode)" = "missing-once" ] && grep -q "Phase 3 of 3" received-prompt.txt; } ||
             [ "\#(mode)" = "never-card" ]; then
            printf '{"type":"result","is_error":false,"total_cost_usd":0.02,"result":"Notes in plain text."}\n'
            exit 0
          fi
          printf '{"type":"result","is_error":false,"total_cost_usd":0.02,"structured_output":'
          tr -d '\n' < "$card"
          printf '}\n'
          exit 0
        fi
        if [ "\#(mode)" = "context-full" ] && [ "$is_fork" = 0 ]; then
          printf '{"type":"thread.started","thread_id":"%s"}\n' "$session_id"
          big=$(head -c 400000 /dev/zero | tr '\0' 'a')
          printf '{"type":"item.completed","item":{"id":"c1","type":"command_execution","command":"cat sessions/cc-a.md","aggregated_output":"%s"}}\n' "$big"
          sleep 30; exit 1
        fi
        printf '{"type":"thread.started","thread_id":"%s"}\n' "$session_id"
        while [ "$#" -gt 0 ]; do
          if [ "$1" = "--output-last-message" ]; then shift; output="$1"; fi
          shift
        done
        if [ "\#(mode)" != "missing" ]; then cat fixture-card.json > "$output"; fi
        if [ "\#(mode)" = "invalid" ]; then printf '{"dimensions":[]}' > "$output"; fi
        if [ "\#(mode)" = "exit" ]; then printf 'quota exceeded' >&2; exit 1; fi
        if [ "\#(mode)" = "failed" ]; then
          printf '{"type":"turn.failed","error":{"message":"unauthorized"}}\n'
        else
          printf '{"type":"turn.completed"}\n'
        fi
        """#
        try script.write(to: command, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: command.path)
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }
}

private final class Collected: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [Data] = []
    var values: [Data] { lock.withLock { items } }
    func append(_ data: Data) { lock.withLock { items.append(data) } }
}

private final class Events: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []
    var texts: [String] { lock.withLock { values } }
    func append(_ progress: Assessor.Progress) {
        lock.withLock {
            switch progress {
            case .started: break
            case let .reading(text), let .thinking(text): values.append(text)
            }
        }
    }
}

extension AssessmentOptions {
    /// Options for fixture runs: no reading minimums, so each phase is one request.
    static func fixture(_ engine: AssessmentEngine) -> AssessmentOptions {
        var options = AssessmentOptions(engine: engine)
        options.reading = .immediate
        return options
    }
}
