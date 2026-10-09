import Foundation
import Testing
@testable import VibemetricCore

/// Opt in to two short, synthetic turns per installed engine. No personal transcripts are read.
struct LiveSessionForkTests {
    private static var engines: [AssessmentEngine] {
        if let value = ProcessInfo.processInfo.environment["VIBEMETRIC_LIVE_FORK"],
           let engine = AssessmentEngine(rawValue: value) { return [engine] }
        return AssessmentEngine.allCases
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VIBEMETRIC_LIVE_FORK"] != nil),
          arguments: Self.engines)
    func forksPersistedConversationForANewRun(_ engine: AssessmentEngine) async throws {
        let installation = try #require(try await CLILocator.discover(engine))
        let root = EvidencePack.savedPacksDirectory(isDev: true).appendingPathComponent("live-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let schema = #"{"type":"object","properties":{"token":{"type":"string"}},"required":["token"],"additionalProperties":false}"#
        let token = UUID().uuidString
        var parentFile: URL?
        var parentData: Data?
        var parentID: String?
        for index in 0...1 {
            let directory = root.appendingPathComponent("turn-\(index)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let schemaFile = directory.appendingPathComponent("schema.json")
            let resultFile = directory.appendingPathComponent("result.json")
            let promptFile = directory.appendingPathComponent("prompt.txt")
            try schema.write(to: schemaFile, atomically: true, encoding: .utf8)
            let prompt = index == 0
                ? "AI Native Score synthetic session test. Remember the token \(token). Return it in the token field. Do not use tools."
                : "Return the token from the preceding conversation in the token field. Do not use tools."
            try prompt.write(to: promptFile, atomically: true, encoding: .utf8)
            let arguments = Assessor.arguments(options: AssessmentOptions(engine: engine), sources: [], schema: schema,
                                               schemaFile: schemaFile, resultFile: resultFile, forkSessionID: parentID)
            let stream = AssessmentStream(engine: engine) { _ in }
            // Claude Code resumes a session only from the folder it ran in (a deep dive that forks it does the same).
            let started = engine == .claude && index == 1 ? root.appendingPathComponent("turn-0") : directory
            let result = try await CLIProcess().run(executable: installation.executable, arguments: arguments,
                                                   directory: started, environment: installation.environment,
                                                   input: promptFile, timeout: 120) { stream.consume($0) }
            stream.finish()
            try #require(result.status == 0, "\(Redactor.scrub(String(decoding: result.stderr, as: UTF8.self)).prefix(300))")
            try #require(stream.snapshot.failure == nil)
            let sessionID = try #require(stream.snapshot.sessionID)
            #expect(UUID(uuidString: sessionID) != nil)
            #expect(sessionID != parentID)
            let response: [String: Any]
            if engine == .claude {
                response = try #require(stream.snapshot.claudeResult?["structured_output"] as? [String: Any])
            } else {
                response = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: resultFile)) as? [String: Any])
            }
            #expect(response["token"] as? String == token)
            if engine == .codex {
                let home = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
                    ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
                let files = FileManager.default.enumerator(at: home.appendingPathComponent("sessions"), includingPropertiesForKeys: nil)
                let file = try #require(files?.allObjects.compactMap { $0 as? URL }.first { $0.lastPathComponent.hasSuffix("\(sessionID).jsonl") })
                let parsed = try #require(CodexParser.parse(file: file))
                #expect(Scanner.isAssessmentRun(parsed))
                if index == 0 {
                    parentFile = file
                    parentData = try Data(contentsOf: file)
                } else {
                    #expect(try Data(contentsOf: #require(parentFile)) == parentData)
                }
            }
            if index == 0 { parentID = sessionID }
            print("Live \(engine.name): \(index == 0 ? "saved" : "forked") session verified")
        }
    }
}
