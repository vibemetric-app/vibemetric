import Foundation

public struct PlanningAssessment: Codable, Sendable {
    public enum CompetencyID: String, Codable, CaseIterable, Sendable {
        case outcomesCompletion = "outcomes_completion"
        case constraints
        case taskContext = "task_context"
        case ambiguityResolution = "ambiguity_resolution"

        public var title: String {
            switch self {
            case .outcomesCompletion: "Goals and completion checks"
            case .constraints: "Limits and requirements"
            case .taskContext: "Task background"
            case .ambiguityResolution: "Requirement clarity"
            }
        }

        public func title(language: String) -> String {
            guard language.lowercased().hasPrefix("ko") else { return title }
            switch self {
            case .outcomesCompletion: return "목표와 완료 기준"
            case .constraints: return "작업 범위와 제약"
            case .taskContext: return "작업 배경"
            case .ambiguityResolution: return "요구사항 명확성"
            }
        }
    }

    public enum Level: String, Codable, CaseIterable, Sendable {
        case high, medium, low, unknown
        // Older saved cards remain readable, but new assessments cannot return these levels.
        case absent
        case notApplicable = "not_applicable"

        public static let assessmentCases: [Self] = [.high, .medium, .low, .unknown]

        public var isProblem: Bool { self == .medium || self == .low || self == .absent }

        /// Integer thirds avoid rounding individual competency contributions.
        var thirds: Int {
            switch self {
            case .high: 3
            case .medium: 2
            case .low: 1
            case .absent, .unknown, .notApplicable: 0
            }
        }

        public func label(language: String) -> String {
            let korean = language.lowercased().hasPrefix("ko")
            switch self {
            case .high: return korean ? "상" : "High"
            case .medium: return korean ? "중" : "Medium"
            case .low: return korean ? "하" : "Low"
            case .absent: return "Absent"
            case .unknown: return korean ? "미확인" : "Unknown"
            case .notApplicable: return korean ? "해당 없음" : "Not applicable"
            }
        }
    }

    public struct Source: Codable, Sendable {
        public var title: String
        public var url: String
        public var note: String

        public init(title: String, url: String, note: String) {
            self.title = title
            self.url = url
            self.note = note
        }
    }

    public struct Criteria: Codable, Sendable {
        public var high: String
        public var medium: String
        public var low: String
        public var absent: String?

        public init(high: String, medium: String, low: String) {
            self.init(high: high, medium: medium, low: low, absent: nil)
        }

        public init(high: String, medium: String, low: String, absent: String?) {
            self.high = high
            self.medium = medium
            self.low = low
            self.absent = absent
        }
    }

    public struct Explanation: Codable, Sendable {
        public var sourceBasis: String
        public var criteria: String
        public var observedBehavior: String
        public var overallJudgment: String

        public init(sourceBasis: String, criteria: String, observedBehavior: String, overallJudgment: String) {
            self.sourceBasis = sourceBasis
            self.criteria = criteria
            self.observedBehavior = observedBehavior
            self.overallJudgment = overallJudgment
        }

        func markdown(language: String, sources: [Source]) -> String {
            let korean = language.lowercased().hasPrefix("ko")
            var parts = [(korean ? "**출처 근거**\n" : "**Source basis**\n") + sourceBasis]
            parts += sources.map { "- [\($0.title)](\($0.url))" }
            parts.append((korean ? "**판정 기준**\n" : "**Criteria**\n") + criteria)
            parts.append((korean ? "**관찰한 행동**\n" : "**Observed behavior**\n") + observedBehavior)
            parts.append((korean ? "**종합 판단**\n" : "**Overall judgment**\n") + overallJudgment)
            return parts.joined(separator: "\n\n")
        }
    }

    public struct Competency: Codable, Sendable, Identifiable {
        public var id: CompetencyID
        public var level: Level
        public var summary: String
        public var sources: [Source]
        public var criteria: Criteria
        public var solution: String?
        public var explanation: Explanation?

        public init(id: CompetencyID, level: Level, summary: String, sources: [Source], criteria: Criteria,
                    solution: String? = nil, explanation: Explanation? = nil) {
            self.id = id
            self.level = level
            self.summary = summary
            self.sources = sources
            self.criteria = criteria
            self.solution = solution
            self.explanation = explanation
        }

    }

    public enum ValidationError: Error, LocalizedError {
        case invalidCompetencies
        case unsupportedSourceURL(CompetencyID, String)

        public var errorDescription: String? {
            switch self {
            case .invalidCompetencies:
                return "Planning must contain each of its four competencies exactly once."
            case let .unsupportedSourceURL(id, url):
                return "Planning competency \(id.rawValue) uses an unsupported source URL: \(url)."
            }
        }
    }

    public var competencies: [Competency]

    public init(competencies: [Competency]) {
        self.competencies = competencies
    }

    private static let sourceURLs: Set<String> = [
        "https://raw.githubusercontent.com/cursor/plugins/main/pstack/skills/principle-prove-it-works/SKILL.md",
        "https://raw.githubusercontent.com/cursor/plugins/main/pstack/skills/sharpen/SKILL.md",
        "https://raw.githubusercontent.com/mattpocock/skills/main/skills/productivity/grilling/SKILL.md",
        "https://code.claude.com/docs/en/best-practices",
        "https://raw.githubusercontent.com/github/spec-kit/main/templates/spec-template.md"
    ]

    public func validate() throws {
        guard competencies.count == CompetencyID.allCases.count,
              Set(competencies.map(\.id)) == Set(CompetencyID.allCases) else {
            throw ValidationError.invalidCompetencies
        }
        for competency in competencies {
            for source in competency.sources where !Self.sourceURLs.contains(source.url) {
                throw ValidationError.unsupportedSourceURL(competency.id, source.url)
            }
        }
    }

    public var ordered: [Competency] {
        CompetencyID.allCases.compactMap { id in competencies.first { $0.id == id } }
    }

    public func markdown(language: String) -> String {
        let korean = language.lowercased().hasPrefix("ko")
        return ordered.map { competency in
            let title = competency.id.title(language: language)
            let level = competency.level.label(language: language)
            var parts = ["### \(title) · \(level)", competency.summary]
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
