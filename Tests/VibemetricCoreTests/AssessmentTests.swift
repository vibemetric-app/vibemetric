import Foundation
import Testing
@testable import VibemetricCore

struct AssessmentTests {
    @Test(arguments: AssessmentEngine.allCases)
    func scoresWithEitherCLI(_ engine: AssessmentEngine) async throws {
        let fixture = try CLIFixture()
        defer { fixture.remove() }
        let assessor = Assessor(installation: CLIInstallation(executable: fixture.command, version: "fixture"))
        let outcome = try await assessor.run(packDir: fixture.directory, sources: [], options: AssessmentOptions(engine: engine)) { _ in }
        #expect(outcome.card.knownTotal == 50)
        #expect(outcome.sessionID == CLIFixture.sessionID)
        #expect(outcome.engine == engine)
        #expect(outcome.cliVersion == "fixture")
        #expect(outcome.costUSD == (engine == .claude ? 0.02 : nil))
        let prompt = try String(contentsOf: fixture.directory.appendingPathComponent("received-prompt.txt"), encoding: .utf8)
        #expect(prompt.contains("AI Native Score"))
        #expect(prompt.contains(engine == .claude ? "You only have Read" : "read-only shell commands"))
        let args = try String(contentsOf: fixture.directory.appendingPathComponent("received-arguments.txt"), encoding: .utf8)
        if engine == .claude {
            #expect(args.contains("--tools\nRead\nGrep\nGlob\n--allowedTools\nRead\nGrep\nGlob\n--permission-mode\ndontAsk"))
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
                .run(packDir: fixture.directory, sources: [], options: AssessmentOptions(engine: .codex)) { _ in }
        }
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

    @Test func cancellationBeforeLaunchNeverStartsTheCLI() async throws {
        let fixture = try CLIFixture()
        defer { fixture.remove() }
        let assessor = Assessor(installation: CLIInstallation(executable: fixture.command))
        assessor.cancel()
        await #expect(throws: CancellationError.self) {
            try await assessor.run(packDir: fixture.directory, sources: [], options: AssessmentOptions(engine: .codex)) { _ in }
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("received-prompt.txt").path))
    }

    @Test(arguments: [true, false])
    func stoppingAKnownChildProcessReturnsPromptly(_ cancel: Bool) async throws {
        let fixture = try CLIFixture(mode: "sleep")
        defer { fixture.remove() }
        let assessor = Assessor(installation: CLIInstallation(executable: fixture.command))
        var options = AssessmentOptions(engine: .codex)
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

    @Test func incompatibleCodexGetsAnActionableError() {
        #expect(throws: AssessmentError.self) { try CLILocator.validateCodexHelp("--json --sandbox --output-schema") }
    }

    @Test func unsupportedModelDoesNotAssumeAnAccountProblem() {
        let detail = #"{"type":"invalid_request_error","message":"The 'gpt-6-sol' model is not supported when using Codex with a ChatGPT account."}"#
        #expect(Assessor.failureMessage(detail, engine: .codex)
                == "The selected model is not supported by this Codex setup. Update Codex and check model access, then try again.")
    }
}

private struct CLIFixture {
    static let sessionID = "11111111-1111-4111-8111-111111111111"
    static let forkID = "22222222-2222-4222-8222-222222222222"
    let directory: URL
    let command: URL

    init(mode: String = "ok") throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("vibemetric test \(UUID())")
        command = directory.appendingPathComponent("fake-cli")
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        try Data(CoreTests.sampleCard.utf8).write(to: directory.appendingPathComponent("fixture-card.json"))
        let script = #"""
        #!/bin/sh
        printf '%s\n' "$@" > received-arguments.txt
        session_id="\#(Self.sessionID)"
        for arg in "$@"; do
          if [ "$arg" = "fork" ] || [ "$arg" = "--fork-session" ]; then session_id="\#(Self.forkID)"; fi
        done
        if [ "\#(mode)" = "same-session" ]; then session_id="\#(Self.sessionID)"; fi
        if [ "\#(mode)" = "no-session" ]; then session_id=""; fi
        cat > received-prompt.txt
        if [ "\#(mode)" = "sleep" ]; then sleep 30; exit 1; fi
        if [ "$1" = "-p" ]; then
          printf '{"type":"system","subtype":"init","session_id":"%s"}\n' "$session_id"
          printf '{"type":"result","is_error":false,"total_cost_usd":0.02,"structured_output":'
          tr -d '\n' < fixture-card.json
          printf '}\n'
          exit 0
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
