import Foundation
import Testing
@testable import VibemetricCore

struct BehavioralAssessmentTests {
    private typealias Level = BehavioralAssessment.Level
    private typealias Competency = BehavioralAssessment.Competency

    private func competency(_ id: String = "example", level: Level = .medium,
                            explanation: BehavioralAssessment.Explanation? = nil) -> Competency {
        Competency(
            id: id,
            level: level,
            title: "Saved title",
            summary: "Cedar checks the requested behavior.",
            sources: [.init(title: "Saved source", url: "https://example.org/saved", note: "Saved note")],
            criteria: .init(high: "Saved high", medium: "Saved medium", low: "Saved low"),
            solution: "Check the requested behavior in the next task.",
            whyItHelps: "Saved explanation",
            explanation: explanation ?? .init(
                sourceBasis: "The guide recommends checking the requested behavior.",
                criteria: "High is consistent; medium has a gap; low misses the behavior.",
                observedBehavior: "Cedar requested a concrete behavior check.",
                overallJudgment: "The evidence supports the stored rating."))
    }

    private func assessment(_ guide: RubricGuide.DimensionGuide, levels: [Level]) -> BehavioralAssessment {
        .init(competencies: guide.competencies.enumerated().map { index, definition in
            competency(definition.id, level: levels[index % levels.count])
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

    @Test func cardsWithoutBehavioralAssessmentsRemainUnchanged() throws {
        var result = try card()
        #expect(result.dimensions.allSatisfy { $0.assessment == nil })
        let before = try encoded(result)
        try result.normalizeBehavioralAssessments()
        #expect(try encoded(result) == before)
    }

    @Test func directLevelRoundTripsWithoutTasks() throws {
        let original = BehavioralAssessment(competencies: [competency(level: .notApplicable)])
        let data = try encoded(original)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let entry = try #require((json["competencies"] as? [[String: Any]])?.first)
        #expect(entry["level"] as? String == "not_applicable")
        #expect(entry["tasks"] == nil)
        let decoded = try JSONDecoder().decode(BehavioralAssessment.self, from: data)
        #expect(decoded.competencies.first?.level == .notApplicable)
    }

    @Test func liveResponseRequiresLevelAndMayOmitCanonicalSnapshotFields() throws {
        let valid = #"{"competencies":[{"id":"example","level":"unknown","summary":"A behavior was checked.","solution":null}]}"#
        let decoded = try JSONDecoder().decode(BehavioralAssessment.self, from: Data(valid.utf8))
        let value = try #require(decoded.competencies.first)
        #expect(value.level == .unknown)
        #expect(value.title.isEmpty)
        #expect(value.sources.isEmpty)
        #expect(value.criteria.high.isEmpty)
        #expect(value.whyItHelps.isEmpty)
        #expect(value.explanation == nil)

        for invalid in [
            #"{"id":"example","summary":"Summary"}"#,
            #"{"id":"example","level":null,"summary":"Summary"}"#,
            #"{"id":"example","level":"excellent","summary":"Summary"}"#,
        ] {
            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(Competency.self, from: Data(invalid.utf8))
            }
        }
    }

    @Test func validationRequiresEveryExpectedIDExactlyOnce() throws {
        var result = BehavioralAssessment(competencies: [
            competency("one", level: .high),
            competency("two", level: .notApplicable),
        ])
        try result.validate(expectedIDs: ["one", "two"])
        result.competencies[1].id = "one"
        #expect(throws: BehavioralAssessment.ValidationError.self) {
            try result.validate(expectedIDs: ["one", "two"])
        }
        result.competencies[1].id = "other-dimension-id"
        #expect(throws: BehavioralAssessment.ValidationError.self) {
            try result.validate(expectedIDs: ["one", "two"])
        }
        result.competencies.removeLast()
        #expect(throws: BehavioralAssessment.ValidationError.self) {
            try result.validate(expectedIDs: ["one", "two"])
        }
    }

    @Test func allCompetenciesNormalizeToCanonicalOrderAndMetadataWithoutChangingAIResults() throws {
        let catalog = try RubricGuide.load()
        #expect(catalog.dimensions.flatMap(\.competencies).count + PlanningAssessment.CompetencyID.allCases.count == 33)
        for guide in catalog.dimensions {
            var result = try card()
            let index = try #require(result.dimensions.firstIndex { $0.dimension == guide.dimension })
            var direct = assessment(guide, levels: [.high, .medium, .low, .unknown, .notApplicable])
            direct.competencies.reverse()
            result.dimensions[index].assessment = direct
            result.dimensions[index].score = 9
            result.dimensions[index].status = .scored
            result.dimensions[index].headline = "The AI assigned this dimension directly."
            result.dimensions[index].changeReason = "The observed practice changed."
            result.dimensions[index].impact = "This affects delivery confidence."
            result.dimensions[index].strengths = ["One practice is consistent."]
            result.dimensions[index].saw = "One practice still has a gap."
            result.dimensions[index].tryThis = "Close the observed gap."
            result.dimensions[index].solutionSteps = ["Apply the guide in the next task."]
            let limits = result.scope.limits

            try result.normalizeBehavioralAssessments()

            let value = result.dimensions[index]
            let normalized = try #require(value.assessment)
            #expect(normalized.competencies.map(\.id) == guide.competencies.map(\.id))
            for (snapshot, definition) in zip(normalized.competencies, guide.competencies) {
                #expect(snapshot.title == definition.title)
                #expect(snapshot.criteria.high == definition.high)
                #expect(snapshot.sources.map(\.url) == definition.sources.map(\.url))
                #expect(snapshot.whyItHelps == definition.whyItHelps)
            }
            #expect(value.score == 9)
            #expect(value.status == .scored)
            #expect(value.headline == "The AI assigned this dimension directly.")
            #expect(value.changeReason == "The observed practice changed.")
            #expect(value.impact == "This affects delivery confidence.")
            #expect(value.strengths == ["One practice is consistent."])
            #expect(value.saw == "One practice still has a gap.")
            #expect(value.tryThis == "Close the observed gap.")
            #expect(value.solutionSteps == ["Apply the guide in the next task."])
            #expect(value.reason.contains("The evidence supports the stored rating."))
            #expect(result.scope.limits == limits)

            let first = try encoded(result)
            try result.normalizeBehavioralAssessments()
            #expect(try encoded(result) == first)
        }
    }

    @Test func invalidLaterDimensionCannotPartlyNormalizeEarlierDimension() throws {
        let catalog = try RubricGuide.load()
        let first = try #require(catalog.guide(for: .contextEngineering))
        let later = try #require(catalog.guide(for: .efficiencyCost))
        var result = try card()
        result.dimensions[1].assessment = assessment(first, levels: [.high])
        result.dimensions[9].assessment = assessment(later, levels: [.low])
        result.dimensions[9].assessment?.competencies[0].id = "wrong-id"
        let before = try encoded(result)
        #expect(throws: BehavioralAssessment.ValidationError.self) {
            try result.normalizeBehavioralAssessments()
        }
        #expect(try encoded(result) == before)
    }

    @Test func structuredOutputRequiresDirectLevelsAndHasNoTasks() throws {
        let schema = try #require(JSONSerialization.jsonObject(with: Data(JSONSchema.scoreCard.utf8)) as? [String: Any])
        let root = try #require(schema["properties"] as? [String: Any])
        let dimensions = try #require(root["dimensions"] as? [String: Any])
        let items = try #require(dimensions["items"] as? [String: Any])
        let branches = try #require(items["anyOf"] as? [[String: Any]])
        #expect(branches.count == 10)
        for branch in branches {
            let fields = try #require(branch["properties"] as? [String: Any])
            let dimension = try #require(fields["dimension"] as? [String: Any])
            let id = try #require((dimension["enum"] as? [String])?.first)
            let key = id == Dimension.planningSpecs.rawValue ? "planning" : "assessment"
            let detail = try #require(fields[key] as? [String: Any])
            let detailFields = try #require(detail["properties"] as? [String: Any])
            let entries = try #require(detailFields["competencies"] as? [String: Any])
            let entry = try #require(entries["items"] as? [String: Any])
            let required = Set(try #require(entry["required"] as? [String]))
            #expect(required.contains("level"))
            #expect(!required.contains("tasks"))
            let entryFields = try #require(entry["properties"] as? [String: Any])
            #expect(entryFields["tasks"] == nil)
            let level = try #require(entryFields["level"] as? [String: Any])
            #expect(level["enum"] as? [String] == Level.assessmentCases.map(\.rawValue))
        }
    }
}
