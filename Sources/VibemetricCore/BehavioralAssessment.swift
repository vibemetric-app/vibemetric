import Foundation

/// Direct competency ratings for one non-Planning dimension, with the criteria snapshot used to judge them.
public struct BehavioralAssessment: Codable, Sendable {
    public typealias Level = PlanningAssessment.Level
    public typealias Source = PlanningAssessment.Source
    public typealias Criteria = PlanningAssessment.Criteria
    public typealias Explanation = PlanningAssessment.Explanation

    public struct Competency: Codable, Sendable, Identifiable {
        public var id: String
        public var level: Level
        public var title: String
        public var summary: String
        public var whyItHelps: String
        public var sources: [Source]
        public var criteria: Criteria
        public var solution: String?
        public var explanation: Explanation?

        public init(id: String, level: Level, title: String, summary: String, sources: [Source], criteria: Criteria,
                    solution: String? = nil, whyItHelps: String = "",
                    explanation: Explanation? = nil) {
            self.id = id
            self.level = level
            self.title = title
            self.summary = summary
            self.whyItHelps = whyItHelps
            self.sources = sources
            self.criteria = criteria
            self.solution = solution
            self.explanation = explanation
        }

        enum CodingKeys: String, CodingKey {
            case id, level, title, summary, whyItHelps, sources, criteria, solution, explanation
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            level = try container.decode(Level.self, forKey: .level)
            title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
            summary = try container.decode(String.self, forKey: .summary)
            whyItHelps = try container.decodeIfPresent(String.self, forKey: .whyItHelps) ?? ""
            sources = try container.decodeIfPresent([Source].self, forKey: .sources) ?? []
            criteria = try container.decodeIfPresent(Criteria.self, forKey: .criteria)
                ?? .init(high: "", medium: "", low: "")
            solution = try container.decodeIfPresent(String.self, forKey: .solution)
            explanation = try container.decodeIfPresent(Explanation.self, forKey: .explanation)
        }

    }

    public enum ValidationError: Error, LocalizedError {
        case invalidCompetencies

        public var errorDescription: String? {
            switch self {
            case .invalidCompetencies:
                "The assessment must contain each competency defined for its dimension exactly once."
            }
        }
    }

    public var competencies: [Competency]

    public init(competencies: [Competency]) {
        self.competencies = competencies
    }

    public func validate(expectedIDs: [String]) throws {
        guard !expectedIDs.isEmpty, Set(expectedIDs).count == expectedIDs.count,
              competencies.count == expectedIDs.count,
              Set(competencies.map(\.id)) == Set(expectedIDs) else {
            throw ValidationError.invalidCompetencies
        }
    }

    public func ordered(expectedIDs: [String]) -> [Competency] {
        expectedIDs.compactMap { id in competencies.first { $0.id == id } }
    }

    public func markdown(language: String, expectedIDs: [String]) -> String {
        let korean = language.lowercased().hasPrefix("ko")
        return ordered(expectedIDs: expectedIDs).map { competency in
            let level = competency.level.label(language: language)
            var parts = ["### \(competency.title) · \(level)", competency.summary]
            let explanation = competency.explanation ?? Explanation(
                sourceBasis: competency.sources.map(\.note).joined(separator: " "),
                criteria: "\(Level.high.label(language: language)): \(competency.criteria.high) \(Level.medium.label(language: language)): \(competency.criteria.medium) \(Level.low.label(language: language)): \(competency.criteria.low)",
                observedBehavior: korean
                    ? "이 이전 결과에는 작성된 관찰 내용이 없습니다."
                    : "This older result does not include a written observation.",
                overallJudgment: korean
                    ? "저장된 평가는 \(level)입니다. 이 이전 결과에는 판정 설명이 없습니다."
                    : "The stored rating is \(level). This older result does not include a written judgment.")
            parts.append(explanation.markdown(language: language, sources: competency.sources))
            if competency.level.isProblem,
               let solution = competency.solution, !solution.isEmpty {
                parts.append((korean ? "**해결 방법**\n" : "**Solution**\n") + solution)
            }
            return parts.joined(separator: "\n\n")
        }.joined(separator: "\n\n")
    }
}
