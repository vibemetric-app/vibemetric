import Foundation
import Testing
@testable import VibemetricCore
@testable import VibemetricAppKit

@MainActor
struct EngineSelectionTests {
    @Test(arguments: [
        (CodexModelChoice.standard, "gpt-6.1-sol"),
        (.astra, "gpt-6-astra"),
        (.sol, "gpt-6-sol"),
        (.luna, "gpt-6-luna")
    ])
    func selectionAndEachEnginesModelSurviveRelaunch(choice: CodexModelChoice, expectedModel: String) throws {
        let name = "vibemetric-tests-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let first = AppModel(preferences: defaults, startAutomatically: false, history: [])
        first.model = .sonnet
        first.engine = .codex
        first.codexModel = choice
        #expect(defaults.string(forKey: "assessment.codexModel") == choice.rawValue)
        let reopened = AppModel(preferences: defaults, startAutomatically: false, history: [])
        #expect(reopened.engine == .codex)
        #expect(reopened.codexModel == choice)
        #expect(reopened.assessmentOptions.model == expectedModel)
        reopened.engine = .claude
        #expect(reopened.assessmentOptions.model == "sonnet")
        reopened.engine = .codex
        #expect(reopened.assessmentOptions.model == expectedModel)
        let args = Assessor.arguments(options: reopened.assessmentOptions, sources: [],
                                      schemaFile: URL(fileURLWithPath: "/fixture/schema.json"),
                                      resultFile: URL(fileURLWithPath: "/fixture/result.json"))
        let index = try #require(args.firstIndex(of: "--model"))
        #expect(Array(args[index...].prefix(2)) == ["--model", expectedModel])
    }

    @Test(arguments: [
        (ModelChoice.standard, "Default", "sonnet"),
        (.opus, "Opus", "opus"),
        (.sonnet, "Sonnet", "sonnet"),
        (.haiku, "Haiku", "haiku")
    ])
    func claudeSelectionSurvivesRelaunchAndEngineSwitch(choice: ModelChoice, savedModel: String, expectedModel: String) throws {
        let name = "vibemetric-tests-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(savedModel, forKey: "assessment.claudeModel")
        let first = AppModel(preferences: defaults, startAutomatically: false, history: [])
        #expect(first.model == choice)
        first.model = choice
        #expect(defaults.string(forKey: "assessment.claudeModel") == savedModel)
        first.engine = .codex
        let reopened = AppModel(preferences: defaults, startAutomatically: false, history: [])
        #expect(reopened.model == choice)
        reopened.engine = .claude
        #expect(reopened.assessmentOptions.model == expectedModel)
        let args = Assessor.arguments(options: reopened.assessmentOptions, sources: [],
                                      schemaFile: URL(fileURLWithPath: "/fixture/schema.json"),
                                      resultFile: URL(fileURLWithPath: "/fixture/result.json"))
        let index = try #require(args.firstIndex(of: "--model"))
        #expect(Array(args[index...].prefix(2)) == ["--model", expectedModel])
    }

    @Test func newPreferencesUseExplicitDefaults() {
        let name = "vibemetric-tests-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let model = AppModel(preferences: defaults, startAutomatically: false, history: [])
        #expect(model.model == .standard)
        #expect(model.model.name == "Default (Sonnet)")
        #expect(model.assessmentOptions.model == "sonnet")
        model.engine = .codex
        #expect(model.codexModel == .standard)
        #expect(model.codexModel.name == "Default (GPT 6.1 Sol)")
        #expect(model.assessmentOptions.model == "gpt-6.1-sol")
    }

    @Test(arguments: ["", "old-custom-model", "gpt-5.5"])
    func unsupportedSavedModelUsesDefault(savedModel: String) {
        let name = "vibemetric-tests-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(savedModel, forKey: "assessment.codexModel")
        let model = AppModel(preferences: defaults, startAutomatically: false, history: [])
        model.engine = .codex
        #expect(model.codexModel == .standard)
        #expect(model.assessmentOptions.model == "gpt-6.1-sol")
    }

    @Test func codexOnlyInstallationCanScore() {
        let name = "vibemetric-tests-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let model = AppModel(preferences: defaults, startAutomatically: false, history: [])
        model.scan = ScanResult(sessions: [], sources: [], duration: 0)
        model.summary = ScanSummary(model.scan!)
        model.summary?.total = 1
        model.installations = [.codex: CLIInstallation(executable: URL(fileURLWithPath: "/test/codex"))]
        model.engine = .claude
        #expect(!model.canStartAssessment)
        model.engine = .codex
        #expect(model.canStartAssessment)
        model.isScanning = true
        #expect(!model.canStartAssessment)
    }

    @Test func legacyCardsStayClaudeAndNewEngineStartsItsOwnBaseline() throws {
        let raw = """
        {"id":"legacy","createdAt":"2026-09-29T12:00:00Z","sessionsScanned":1,"elapsed":1,"rubricVersion":"\(AssessmentOptions.rubricVersion)","card":\(Self.cardJSON)}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let legacy = try decoder.decode(CardRecord.self, from: Data(raw.utf8))
        #expect(legacy.effectiveEngine == .claude)
        #expect(!legacy.hasSavedSession)
        #expect(legacy.isComparable(to: AssessmentOptions(engine: .claude)))
        #expect(!legacy.isComparable(to: AssessmentOptions(engine: .codex)))
        var codex = legacy
        codex.id = "codex"
        codex.engine = .codex
        let name = "vibemetric-tests-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let model = AppModel(preferences: defaults, startAutomatically: false, history: [codex, legacy])
        #expect(model.baseline(for: codex) == nil)
        codex.previousId = legacy.id
        #expect(model.baseline(for: codex) == nil)
    }

    @Test func rescanRetainsVisibleSummarySelectionAndPhase() async throws {
        let name = "vibemetric-tests-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let model = AppModel(preferences: defaults, startAutomatically: false, history: [])
        let before = ScanResult(sessions: [], sources: [], duration: 12)
        model.scan = before
        model.summary = ScanSummary(before)
        model.summary?.total = 42
        // Keep installation discovery out of this data-refresh test.
        model.isCheckingEngines = true
        let gate = ScanGate()
        let task = Task { await model.rescan { await gate.wait() } }
        while !model.isScanning { await Task.yield() }
        #expect(model.summary?.total == 42)
        #expect(model.scan?.duration == 12)
        if case .ready = model.phase {} else { Issue.record("Existing content was replaced by initial loading") }
        await gate.finish()
        await task.value
        #expect(!model.isScanning)
        #expect(model.scan?.duration == 99)
    }

    private static var cardJSON: String {
        let dimensions = Dimension.allCases.map {
            #"{"dimension":"\#($0.rawValue)","score":5,"status":"scored","headline":"h","reason":"r","evidence":[]}"#
        }.joined(separator: ",")
        return """
        {"language":"en","diagnosis":"Demo","dimensions":[\(dimensions)],
        "improvement":{"title":"t","situation":"s","actions":["a","b"],"signOfSuccess":"x","tryItOn":"y"},
        "roadmap":[],"scope":{"assessedAt":"2026-09-30","timeZone":"UTC","recordDates":[],
        "sessionsExamined":1,"tasksCheckedInDetail":1,"elapsedMinutes":0,"limits":[]}}
        """
    }
}

private actor ScanGate {
    private var continuation: CheckedContinuation<ScanResult, Never>?
    private var finished = false
    func wait() async -> ScanResult {
        if finished { return ScanResult(sessions: [], sources: [], duration: 99) }
        return await withCheckedContinuation { continuation = $0 }
    }
    func finish() {
        finished = true
        continuation?.resume(returning: ScanResult(sessions: [], sources: [], duration: 99))
        continuation = nil
    }
}
