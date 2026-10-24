import Foundation
import Testing
@testable import VibemetricCore

struct NullableAssessmentOutputTests {
    @Test(arguments: AssessmentEngine.allCases)
    func schemaRequiredFieldsMatchEngineContract(_ engine: AssessmentEngine) throws {
        let schema = try #require(JSONSerialization.jsonObject(with: Data(JSONSchema.scoreCard(for: engine).utf8)) as? [String: Any])
        let root = try #require(schema["properties"] as? [String: Any])
        let dimensions = try #require(root["dimensions"] as? [String: Any])
        let items = try #require(dimensions["items"] as? [String: Any])
        let branches = try #require(items["anyOf"] as? [[String: Any]])

        #expect(branches.count == Dimension.allCases.count)
        for branch in branches {
            let properties = try #require(branch["properties"] as? [String: Any])
            let required = Set(try #require(branch["required"] as? [String]))
            let dimension = try #require(properties["dimension"] as? [String: Any])
            let id = try #require((dimension["enum"] as? [String])?.first)
            let changeReason = try #require(properties["changeReason"] as? [String: Any])

            let omitted = Set(properties.keys).subtracting(required)
            let expectedOmitted: Set<String>
            if engine == .claude {
                expectedOmitted = id == Dimension.planningSpecs.rawValue
                    ? ["assessment", "changeReason"]
                    : ["planning", "changeReason"]
            } else {
                expectedOmitted = []
            }
            #expect(omitted == expectedOmitted)
            #expect(changeReason["type"] as? [String] == ["string", "null"])
            if id == Dimension.planningSpecs.rawValue {
                #expect(required.contains("planning"))
                #expect((properties["assessment"] as? [String: Any])?["type"] as? String == "null")
            } else {
                #expect(required.contains("assessment"))
                #expect((properties["planning"] as? [String: Any])?["type"] as? String == "null")
            }
        }

        if engine == .codex {
            #expect(JSONSchema.scoreCard == JSONSchema.scoreCard(for: .codex))
        }
    }

    @Test func omittedNullOnlyFieldsDecodeAndKeepDetailedAssessments() throws {
        let original = try assessedCard()
        let data = try JSONEncoder().encode(original)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let dimensions = try #require(json["dimensions"] as? [[String: Any]])

        #expect(dimensions.allSatisfy { $0["changeReason"] == nil })
        #expect(dimensions[0]["assessment"] == nil)
        #expect(dimensions.dropFirst().allSatisfy { $0["planning"] == nil })

        let decoded = try JSONDecoder().decode(ScoreCard.self, from: data)
        try Assessor.validate(decoded, requirePlanning: true, requireAssessments: true, requireExplanations: true)
        #expect(decoded.dimensions[0].planning?.competencies.map(\.level) == [.high, .medium, .low, .unknown])
        #expect(decoded.dimensions[0].planning?.competencies[0].explanation?.overallJudgment == "The observed work supports this rating.")
        #expect(decoded.dimensions[1].assessment?.competencies.allSatisfy { $0.level == .medium } == true)
        #expect(decoded.dimensions[1].assessment?.competencies[0].explanation?.observedBehavior == "The fictional record shows the behavior directly.")
    }

    @Test func missingActiveDetailsAndInvalidOptionalTypesAreRejected() throws {
        var missingPlanning = try assessedCard()
        missingPlanning.dimensions[0].planning = nil
        #expect(throws: AssessmentError.self) {
            try Assessor.validate(missingPlanning, requirePlanning: true, requireAssessments: true, requireExplanations: true)
        }

        var missingAssessment = try assessedCard()
        missingAssessment.dimensions[1].assessment = nil
        #expect(throws: AssessmentError.self) {
            try Assessor.validate(missingAssessment, requirePlanning: true, requireAssessments: true, requireExplanations: true)
        }

        let encoded = try JSONEncoder().encode(assessedCard())
        var invalid = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var dimensions = try #require(invalid["dimensions"] as? [[String: Any]])
        dimensions[0]["changeReason"] = 3
        invalid["dimensions"] = dimensions
        let invalidChangeReason = try JSONSerialization.data(withJSONObject: invalid)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ScoreCard.self, from: invalidChangeReason)
        }

        dimensions[0].removeValue(forKey: "changeReason")
        dimensions[1]["planning"] = "unexpected"
        invalid["dimensions"] = dimensions
        let invalidInactiveDetails = try JSONSerialization.data(withJSONObject: invalid)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ScoreCard.self, from: invalidInactiveDetails)
        }
    }

    private func assessedCard() throws -> ScoreCard {
        var card = try JSONDecoder().decode(ScoreCard.self, from: Data(CoreTests.sampleCard.utf8))
        let explanation = PlanningAssessment.Explanation(
            sourceBasis: "A fictional practice guide defines the expected behavior.",
            criteria: "The rating follows the stated behavior anchors.",
            observedBehavior: "The fictional record shows the behavior directly.",
            overallJudgment: "The observed work supports this rating."
        )
        let levels: [PlanningAssessment.Level] = [.high, .medium, .low, .unknown]
        card.dimensions[0].planning = PlanningAssessment(
            competencies: zip(PlanningAssessment.CompetencyID.allCases, levels).map { id, level in
                PlanningAssessment.Competency(
                    id: id,
                    level: level,
                    summary: "A fictional task provides evidence for this competency.",
                    sources: [.init(
                        title: "Prove It Works",
                        url: "https://raw.githubusercontent.com/cursor/plugins/main/pstack/skills/principle-prove-it-works/SKILL.md",
                        note: "A public practice guide."
                    )],
                    criteria: .init(high: "Consistent.", medium: "Partial.", low: "Absent."),
                    explanation: explanation
                )
            }
        )

        let catalog = try RubricGuide.load()
        for index in card.dimensions.indices where card.dimensions[index].dimension != .planningSpecs {
            let guide = try #require(catalog.guide(for: card.dimensions[index].dimension))
            card.dimensions[index].assessment = BehavioralAssessment(
                competencies: guide.competencies.map { competency in
                    .init(
                        id: competency.id,
                        level: .medium,
                        title: competency.title,
                        summary: "A fictional task provides evidence for this competency.",
                        sources: [],
                        criteria: .init(high: "Consistent.", medium: "Partial.", low: "Absent."),
                        explanation: explanation
                    )
                }
            )
        }
        return card
    }
}
