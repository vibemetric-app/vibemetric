import Foundation
import Testing
@testable import VibemetricCore

/// Opt in with VIBEMETRIC_LIVE_CODEX=1. Uses the signed-in account, only synthetic evidence.
struct LiveCodexTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VIBEMETRIC_LIVE_CODEX"] == "1"))
    func syntheticEvidenceProducesAScoreCard() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("vibemetric-live-\(UUID())")
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = [
            "overview.md": "# Synthetic test evidence\nOne fictional Codex session, demo-001, project calculator. Date: 2026-09-30. This is test data, not a real person's activity.",
            "sessions.tsv": "tool\tsession\tdigest\nCodex\tdemo-001\tsessions/demo-001.md\n",
            "leads.md": "Read sessions/demo-001.md for planning and verification. Other dimensions may lack evidence.",
            "settings.md": "No settings evidence is available.",
            "sessions/demo-001.md": "# Codex demo-001 · 2026-09-30\nUser: Fix addition of negative numbers. Done when add(-2, 3) equals 1 and tests pass.\nAgent: Read calculator.swift, changed addition. Ran tests: exit 0, 4 passed.\nUser: Thanks.\n",
        ]
        for (name, text) in files { try text.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8) }
        var options = AssessmentOptions(engine: .codex, model: "gpt-6-sol")
        options.timeout = 180
        let outcome = try await Assessor().run(packDir: directory, sources: [], options: options) { event in
            switch event {
            case .started: print("Live Codex: started with synthetic evidence")
            case let .reading(text): print("Live Codex: \(text)")
            case .thinking: break
            }
        }
        #expect(outcome.engine == .codex)
        #expect(outcome.card.dimensions.count == 10)
        #expect(outcome.card.scope.sessionsExamined == 1)
    }
}
