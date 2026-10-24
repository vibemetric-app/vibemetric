import Foundation
import Testing
@testable import VibemetricCore

struct PlanningAssessmentTests {
    private typealias Level = PlanningAssessment.Level
    private typealias Competency = PlanningAssessment.Competency

    private func competency(_ id: PlanningAssessment.CompetencyID = .outcomesCompletion,
                            level: Level, explanation: PlanningAssessment.Explanation? = nil) -> Competency {
        Competency(
            id: id,
            level: level,
            summary: "Cedar defines the expected export result.",
            sources: [.init(
                title: "Practice guide",
                url: "https://code.claude.com/docs/en/best-practices",
                note: "Define checks.")],
            criteria: .init(
                high: "Result and check are connected.",
                medium: "Result is defined.",
                low: "Only a change is named."),
            solution: "Connect the expected result to an observable check.",
            explanation: explanation ?? .init(
                sourceBasis: "The guide recommends an observable result check.",
                criteria: "High connects the result and check; medium leaves a gap; low names only a change.",
                observedBehavior: "Cedar's request defines the export result and its acceptance check.",
                overallJudgment: "The evidence supports the stored rating."))
    }

    private func assessment(_ levels: [Level]) -> PlanningAssessment {
        PlanningAssessment(competencies: zip(PlanningAssessment.CompetencyID.allCases, levels).map {
            competency($0.0, level: $0.1)
        })
    }

    private func card() throws -> ScoreCard {
        try JSONDecoder().decode(ScoreCard.self, from: Data(CoreTests.sampleCard.utf8))
    }

    private func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(value)
    }

    @Test func legacyCardsWithoutPlanningRemainUnchanged() throws {
        var result = try card()
        #expect(result.dimensions[0].planning == nil)
        let before = try encoded(result)
        try result.normalizePlanningAssessment()
        #expect(try encoded(result) == before)
    }

    @Test func directLevelsRoundTripAndFreshEncodingContainsNoTasks() throws {
        let original = assessment([.high, .medium, .low, .unknown])
        let data = try encoded(original)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let entries = try #require(json["competencies"] as? [[String: Any]])
        #expect(entries.map { $0["level"] as? String } == ["high", "medium", "low", "unknown"])
        #expect(entries.allSatisfy { $0["tasks"] == nil })
        let decoded = try JSONDecoder().decode(PlanningAssessment.self, from: data)
        #expect(decoded.competencies.map(\.level) == [.high, .medium, .low, .unknown])
    }

    @Test func missingNullOrInvalidLevelFailsDecoding() {
        func data(levelField: String) -> Data {
            Data("""
            {"id":"outcomes_completion"\(levelField),"summary":"Summary","sources":[],"criteria":{"high":"H","medium":"M","low":"L"}}
            """.utf8)
        }
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Competency.self, from: data(levelField: "")) }
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Competency.self, from: data(levelField: ",\"level\":null")) }
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Competency.self, from: data(levelField: ",\"level\":\"excellent\"")) }
    }

    @Test func validationRequiresAllFourUniqueIDsAndCanonicalSources() throws {
        var planning = assessment([.high, .medium, .low, .notApplicable])
        try planning.validate()
        planning.competencies[3].id = .constraints
        #expect(throws: PlanningAssessment.ValidationError.self) { try planning.validate() }
        planning = assessment([.high, .medium, .low, .unknown])
        planning.competencies.removeLast()
        #expect(throws: PlanningAssessment.ValidationError.self) { try planning.validate() }
        planning = assessment([.high, .medium, .low, .unknown])
        planning.competencies[0].sources[0].url = "https://example.org/guide"
        #expect(throws: PlanningAssessment.ValidationError.self) { try planning.validate() }
    }

    @Test func normalizationOrdersCompetenciesAndPreservesAIScoreStatusAndNarrative() throws {
        var result = try card()
        var planning = assessment([.high, .medium, .low, .unknown])
        planning.competencies.reverse()
        result.dimensions[0].planning = planning
        result.dimensions[0].score = 9
        result.dimensions[0].status = .scored
        result.dimensions[0].headline = "The AI found strong planning with one narrow gap."
        result.dimensions[0].changeReason = "Acceptance checks improved."
        result.dimensions[0].impact = "The remaining gap can cause rework."
        result.dimensions[0].strengths = ["Goals are explicit."]
        result.dimensions[0].saw = "One constraint was implicit."
        result.dimensions[0].tryThis = "State the constraint."
        result.dimensions[0].solutionSteps = ["Add the constraint to the next request."]
        let limits = result.scope.limits

        try result.normalizePlanningAssessment()

        let value = result.dimensions[0]
        #expect(value.planning?.competencies.map(\.id) == PlanningAssessment.CompetencyID.allCases)
        #expect(value.score == 9)
        #expect(value.status == .scored)
        #expect(value.headline == "The AI found strong planning with one narrow gap.")
        #expect(value.changeReason == "Acceptance checks improved.")
        #expect(value.impact == "The remaining gap can cause rework.")
        #expect(value.strengths == ["Goals are explicit."])
        #expect(value.saw == "One constraint was implicit.")
        #expect(value.tryThis == "State the constraint.")
        #expect(value.solutionSteps == ["Add the constraint to the next request."])
        #expect(value.reason.contains("The evidence supports the stored rating."))
        #expect(result.scope.limits == limits)

        let first = try encoded(result)
        try result.normalizePlanningAssessment()
        #expect(try encoded(result) == first)
    }

    @Test func invalidPlanningCannotPartlyNormalizeCard() throws {
        var result = try card()
        var planning = assessment([.high, .medium, .low, .unknown])
        planning.competencies[0].id = .constraints
        result.dimensions[0].planning = planning
        result.dimensions[0].score = 8
        let before = try encoded(result)
        #expect(throws: PlanningAssessment.ValidationError.self) { try result.normalizePlanningAssessment() }
        #expect(try encoded(result) == before)
    }

    @Test func markdownUsesStoredLevelsAndOnlyShowsSolutionsForRatedGaps() {
        var planning = assessment([.high, .medium, .low, .unknown])
        for index in planning.competencies.indices {
            planning.competencies[index].solution = "solution-\(index)"
        }
        let korean = planning.markdown(language: "ko")
        #expect(korean.contains("### 목표와 완료 기준 · 상"))
        #expect(korean.contains("**해결 방법**"))
        #expect(!korean.contains("solution-0"))
        #expect(korean.contains("solution-1"))
        #expect(korean.contains("solution-2"))
        #expect(!korean.contains("solution-3"))
        #expect(planning.markdown(language: "en").contains("**Solution**"))
    }
}
