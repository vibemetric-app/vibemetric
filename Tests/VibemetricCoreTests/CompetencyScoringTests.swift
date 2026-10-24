import Foundation
import Testing
@testable import VibemetricCore

struct CompetencyScoringTests {
    typealias Level = PlanningAssessment.Level

    private func card() throws -> ScoreCard {
        let fixture = try CLIFixture()
        defer { fixture.remove() }
        return try JSONDecoder().decode(ScoreCard.self, from: Data(contentsOf: fixture.directory.appendingPathComponent("fixture-card.json")))
    }

    private func setLevels(_ levels: [Level], for dimension: VibemetricCore.Dimension, in card: inout ScoreCard) {
        let index = card.dimensions.firstIndex { $0.dimension == dimension }!
        if dimension == .planningSpecs {
            for i in card.dimensions[index].planning!.competencies.indices {
                card.dimensions[index].planning!.competencies[i].level = levels[i % levels.count]
            }
        } else {
            for i in card.dimensions[index].assessment!.competencies.indices {
                card.dimensions[index].assessment!.competencies[i].level = levels[i % levels.count]
            }
        }
    }

    @Test func equalWeightsIncludeUnknownAndRoundOnlyOncePerDimension() throws {
        var result = try card()
        setLevels([.medium, .medium, .unknown], for: .contextEngineering, in: &result)
        setLevels([.medium, .medium, .medium, .unknown], for: .toolIntegration, in: &result)
        setLevels([.medium], for: .memory, in: &result)
        setLevels([.medium, .unknown, .unknown], for: .security, in: &result)
        setLevels([.low, .low, .low, .unknown], for: .planningSpecs, in: &result)
        try result.calculateCompetencyScores()
        #expect(result.ordered[0].score == 3) // 2.5 rounds up after summing.
        #expect(result.ordered[1].score == 4)
        #expect(result.ordered[2].score == 7) // Not 2 + 2 + 2.
        #expect(result.ordered[3].score == 5)
        #expect(result.ordered[8].score == 2)
        #expect(result.knownTotal == result.ordered.compactMap(\.score).reduce(0, +))
        let first = try JSONEncoder().encode(result)
        try result.calculateCompetencyScores()
        let decoded = try JSONDecoder().decode(ScoreCard.self, from: first)
        #expect(result.ordered.map(\.score) == decoded.ordered.map(\.score))
    }

    @Test(arguments: [(Level.high, 10), (.medium, 7), (.low, 3), (.unknown, 0)])
    func everyDimensionUsesTheSameLevelScale(_ entry: (Level, Int)) throws {
        var result = try card()
        for dimension in Dimension.allCases { setLevels([entry.0], for: dimension, in: &result) }
        try result.calculateCompetencyScores()
        #expect(result.ordered.allSatisfy { $0.score == entry.1 && $0.status == .scored })
        #expect(result.knownTotal == 10 * entry.1)
    }

    @Test func rejectsMissingDuplicateInapplicableAndUnscoredDetailsWithoutPartialMutation() throws {
        for mode in 0..<6 {
            var result = try card()
            switch mode {
            case 0: result.dimensions[9].assessment!.competencies.removeLast()
            case 1: result.dimensions[9].assessment!.competencies[1].id = result.dimensions[9].assessment!.competencies[0].id
            case 2: result.dimensions[9].assessment!.competencies[0].level = .notApplicable
            case 3: result.dimensions[9].status = .notReviewed
            case 4: result.dimensions[9].assessment!.competencies[0].level = .absent
            default: result.dimensions[9].assessment = nil
            }
            let scores = result.dimensions.map(\.score)
            #expect(throws: (any Error).self) { try result.calculateCompetencyScores() }
            #expect(result.dimensions.map(\.score) == scores)
        }
    }

    @Test func legacyAbsentRemainsReadableWithoutChangingStoredScores() throws {
        #expect(Level.absent.label(language: "en") == "Absent")
        #expect(Level.absent.isProblem)
        #expect(!Level.unknown.isProblem)
        var result = try card()
        setLevels([.absent], for: .planningSpecs, in: &result)
        setLevels([.absent], for: .contextEngineering, in: &result)
        result.dimensions[0].planning!.competencies[0].solution = "Establish the intended outcome."
        result.dimensions[1].assessment!.competencies[0].solution = "Maintain a usable project fact."
        result.dimensions[1].score = 0
        let stored = try JSONDecoder().decode(ScoreCard.self, from: JSONEncoder().encode(result))
        #expect(stored.dimensions[1].score == 0)
        #expect(stored.dimensions[1].assessment!.competencies[0].level == .absent)
        let planning = result.dimensions[0].planning!.markdown(language: "en")
        let behavioral = result.dimensions[1].assessment!.markdown(language: "en", expectedIDs: result.dimensions[1].assessment!.competencies.map(\.id))
        #expect(planning.contains("Absent"))
        #expect(planning.contains("Establish the intended outcome."))
        #expect(behavioral.contains("Absent"))
        #expect(behavioral.contains("Maintain a usable project fact."))
    }

    @Test(arguments: AssessmentEngine.allCases)
    func acceptsLevelOnlyResponsesAndSavesCalculatedScores(_ engine: AssessmentEngine) async throws {
        let fixture = try CLIFixture()
        defer { fixture.remove() }
        let file = fixture.directory.appendingPathComponent("fixture-card.json")
        var input = try JSONDecoder().decode(ScoreCard.self, from: Data(contentsOf: file))
        for index in input.dimensions.indices { input.dimensions[index].score = nil }
        setLevels([.low], for: .contextEngineering, in: &input)
        try JSONEncoder().encode(input).write(to: file)
        let outcome = try await Assessor(installation: CLIInstallation(executable: fixture.command))
            .run(packDir: fixture.directory, sources: [], options: .fixture(engine)) { _ in }
        let saved = try JSONDecoder().decode(ScoreCard.self, from: outcome.rawJSON)
        #expect(saved.ordered[1].score == 3)
        #expect(saved.ordered[1].assessment!.competencies.allSatisfy { $0.level == .low })
        #expect(saved.ordered.map(\.score) == outcome.card.ordered.map(\.score))
        #expect(saved.knownTotal == 64)
    }

    @Test func humanSteeringUsesAllThreeDefinedCompetenciesWithEqualWeights() throws {
        var result = try card()
        setLevels([.high, .medium, .low], for: .humanSteering, in: &result)
        try result.calculateCompetencyScores()
        let steering = try #require(result.dimensions.first { $0.dimension == .humanSteering })
        #expect(steering.assessment!.competencies.map(\.id) == [
            "informed_proposal_decisions", "evidence_based_redirection", "evidence_based_reconsideration"
        ])
        #expect(steering.score == 7)
        let scores = result.dimensions.map(\.score)
        let index = result.dimensions.firstIndex { $0.dimension == .humanSteering }!
        result.dimensions[index].assessment!.competencies.removeLast()
        #expect(throws: BehavioralAssessment.ValidationError.self) { try result.calculateCompetencyScores() }
        #expect(result.dimensions.map(\.score) == scores)
    }

    @Test(arguments: [
        ([Level.medium, .medium, .medium], 7),
        ([Level.high, .medium, .low], 7),
        ([Level.high, .medium, .unknown], 6),
        ([Level.medium, .medium, .unknown], 4)
    ])
    func mergedContextUsesThreeEqualWeightsAndRejectsMissingDetails(_ entry: ([Level], Int)) throws {
        var result = try card()
        setLevels(entry.0, for: .contextEngineering, in: &result)
        try result.calculateCompetencyScores()
        let index = try #require(result.dimensions.firstIndex { $0.dimension == .contextEngineering })
        let assessment = try #require(result.dimensions[index].assessment)
        #expect(assessment.competencies.map(\.id) == [
            "essential_project_context", "guidance_delivery", "guidance_upkeep"
        ])
        #expect(result.dimensions[index].score == entry.1)
        let scores = result.dimensions.map(\.score)
        result.dimensions[index].assessment!.competencies.removeFirst()
        #expect(throws: BehavioralAssessment.ValidationError.self) { try result.calculateCompetencyScores() }
        #expect(result.dimensions.map(\.score) == scores)
    }

    @Test(arguments: AssessmentEngine.allCases)
    func unfinishedInvestigationReturnsScoreCard(_ engine: AssessmentEngine) async throws {
        let fixture = try CLIFixture()
        defer { fixture.remove() }
        let file = fixture.directory.appendingPathComponent("fixture-card.json")
        var input = try JSONDecoder().decode(ScoreCard.self, from: Data(contentsOf: file))
        input.scope.unknownInvestigations![0].status = .incomplete
        input.scope.unknownInvestigations![0].remainingLeads = ["A fictional related session was not opened."]
        try JSONEncoder().encode(input).write(to: file)
        let outcome = try await Assessor(installation: CLIInstallation(executable: fixture.command))
            .run(packDir: fixture.directory, sources: [], options: .fixture(engine)) { _ in }
        #expect(outcome.card.knownTotal == 68)
        #expect(outcome.card.scope.unknownInvestigations?[0].status == .incomplete)
        #expect(outcome.card.scope.unknownInvestigations?[0].remainingLeads == input.scope.unknownInvestigations?[0].remainingLeads)
    }

    @Test func reportTextHidesPersonalHomePrefixesWithoutChangingScoresOrSourceURLs() throws {
        var original = try card()
        original.summary = ["In /Users/example/cedar, the AI checked src/export.swift."]
        original.dimensions[1].assessment!.competencies[0].summary = "The AI read /home/example/cedar/AGENTS.md."
        original.dimensions[1].assessment!.competencies[0].sources = [.init(
            title: "Source", url: "https://example.org/Users/example/reference", note: "Source note.")]
        original.scope.limits = ["Read /Users/example/cedar and /Users/another/alder."]
        let clean = try original.hidingUserPaths()
        #expect(clean.summary == ["In cedar, the AI checked src/export.swift."])
        #expect(clean.dimensions[1].assessment!.competencies[0].summary == "The AI read cedar/AGENTS.md.")
        #expect(clean.dimensions[1].assessment!.competencies[0].sources[0].url == "https://example.org/Users/example/reference")
        #expect(clean.scope.limits == ["Read cedar and alder."])
        #expect(clean.ordered.map(\.score) == original.ordered.map(\.score))
        #expect(original.summary == ["In /Users/example/cedar, the AI checked src/export.swift."])
    }
}
