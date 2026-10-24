import Foundation

/// The 10 rubric dimensions, in rubric order.
public enum Dimension: String, Codable, CaseIterable, Sendable, Identifiable {
    case planningSpecs = "planning_specs"
    case contextEngineering = "context_engineering"
    case memory = "memory_knowledge"
    case toolIntegration = "tool_integration"
    case taskMapping = "task_mapping"
    case feedbackLoops = "feedback_loops"
    case testingEvals = "testing_evals"
    case humanSteering = "human_steering"
    case security
    case efficiencyCost = "efficiency_cost"

    public var id: String { rawValue }

    /// IDs that older saved results stored, mapped to the current ID.
    public static let legacyIDs = ["task_framing": "planning_specs"]

    public init?(id: String) {
        self.init(rawValue: Self.legacyIDs[id] ?? id)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let value = Dimension(id: raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown dimension: \(raw)")
        }
        self = value
    }

    /// The SF Symbol shown before the dimension's name.
    public var symbol: String {
        switch self {
        case .planningSpecs: "checklist"
        case .contextEngineering: "doc.text"
        case .memory: "brain.head.profile"
        case .toolIntegration: "wrench.and.screwdriver"
        case .taskMapping: "square.split.2x2"
        case .feedbackLoops: "arrow.triangle.2.circlepath"
        case .testingEvals: "checkmark.seal"
        case .humanSteering: "steeringwheel"
        case .security: "lock.shield"
        case .efficiencyCost: "dollarsign.circle"
        }
    }

    /// The plain question each dimension answers, shown in its expanded details.
    public var question: String {
        switch self {
        case .planningSpecs: "Do you agree on the goal and the checks before work starts?"
        case .contextEngineering: "Does each project tell the AI what it must know?"
        case .memory: "Does the AI remember what it learned, correctly?"
        case .toolIntegration: "Does recurring work run through tools and skills?"
        case .taskMapping: "Is big work split into the right pieces?"
        case .feedbackLoops: "Do results decide the next step?"
        case .testingEvals: "Do you check the AI's work?"
        case .humanSteering: "Do you make informed decisions, redirect AI, and reconsider your own assumptions?"
        case .security: "Is the agent limited to what each task needs?"
        case .efficiencyCost: "Do the model and effort match each task?"
        }
    }

    public var title: String {
        switch self {
        case .planningSpecs: "Planning & Specs"
        case .contextEngineering: "Context Engineering"
        case .memory: "Memory & Knowledge"
        case .toolIntegration: "Tool Integration"
        case .taskMapping: "Orchestration I: Task Mapping"
        case .feedbackLoops: "Orchestration II: Feedback Loops"
        case .testingEvals: "Testing & Evals"
        case .humanSteering: "Human Steering"
        case .security: "Security"
        case .efficiencyCost: "Efficiency & Cost"
        }
    }
}

public enum Band: String, Sendable {
    case strong = "STRONG", developing = "DEVELOPING", bottleneck = "BOTTLENECK"

    /// The order bands appear on the card and in the report: what needs work first.
    public static let displayOrder: [Band] = [.bottleneck, .developing, .strong]

    public init(score: Int) {
        self = score >= 8 ? .strong : score >= 6 ? .developing : .bottleneck
    }

    public var heading: String {
        switch self {
        case .strong: "💪 STRONG · 8–10 points"
        case .developing: "◼ DEVELOPING · 6–7 points"
        case .bottleneck: "🚧 BOTTLENECK · 0–5 points"
        }
    }
}

/// The assessor's structured output. `JSONSchema.scoreCard` must stay in sync with this type.
public struct ScoreCard: Codable, Sendable {
    public struct DimensionResult: Codable, Sendable, Identifiable {
        public var dimension: Dimension
        /// nil when `status` is not `scored`.
        public var score: Int?
        public var status: Status
        /// The short summary: one sentence on the observed practice.
        public var headline: String
        /// The full explanation as Markdown. On newer cards it is composed from `points` and `conclusion`
        /// (so the Markdown report and other readers keep working); older cards have paragraphs here.
        public var reason: String
        /// The explanation as headed points, each with a short body (bullets allowed). nil on older cards.
        public var points: [Point]?
        /// The ending summary: why this score, and the gap to the next anchor. nil on older cards.
        public var conclusion: String?
        public var evidence: [Evidence]
        /// Why the score differs from the previous assessment; nil when unchanged or there was none.
        public var changeReason: String?
        /// Readable cards (rubric 4 output): short plain-text fields the app lays out. nil on older cards,
        /// which show `points` or `reason` instead.
        /// What the records show, with a number where one exists. On cards with `strengths`, only the gap that
        /// keeps the score below 10 (empty at 10); older cards may mix in what went well.
        public var saw: String?
        /// What the person already does well in this dimension, one short sentence each. nil on cards from
        /// before strengths were split out of `saw`.
        public var strengths: [String]?
        /// Why it matters: the effect on the person's work.
        public var impact: String?
        /// One action that would move the score up; nil or empty at 10.
        public var tryThis: String?
        /// The solution explained as 2–4 plain bullets: what to change, where, how to do it in the next task,
        /// and how to tell it worked. nil on older cards, which show `tryThis` alone.
        public var solutionSteps: [String]?
        /// Direct Planning competency ratings and the criteria used for the assessment.
        public var planning: PlanningAssessment?
        /// Direct competency ratings for the other dimensions, including the canonical guide snapshot.
        public var assessment: BehavioralAssessment?
        /// The problem and its fix in one short line each, for the result's first screen. nil on older cards, which
        /// show the headline and `tryThis` there instead.
        public var issueLine: String?
        public var fixLine: String?

        /// True when the card carries the short readable fields.
        public var isReadable: Bool { saw?.isEmpty == false || strengths != nil }

        public struct Point: Codable, Sendable {
            public var heading: String
            /// Markdown: a few sentences, or bullets when they organize the information better.
            /// Body bullets start with the tone emoji (✅, ⚠️ or ℹ️).
            public var body: String
            /// Whether the point is a strength, a gap, or neutral context. nil on cards from before tones.
            public var tone: Tone?
        }

        /// The app picks the emoji from the tone, so the set stays consistent and can change without a rescore.
        public enum Tone: String, Codable, Sendable, CaseIterable {
            case good, bad, neutral

            public var emoji: String {
                switch self {
                case .good: "✅"
                case .bad: "⚠️"
                case .neutral: "ℹ️"
                }
            }

            /// The tone a line of text starts with, and the text after the emoji.
            public static func leading(_ text: String) -> (tone: Tone, rest: String)? {
                let trimmed = text.trimmingCharacters(in: .whitespaces)
                for tone in allCases {
                    // Match ⚠ and ℹ with or without the emoji presentation selector.
                    for marker in [tone.emoji, tone.emoji.replacingOccurrences(of: "\u{FE0F}", with: "")] where trimmed.hasPrefix(marker) {
                        return (tone, String(trimmed.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces))
                    }
                }
                return nil
            }
        }

        public var id: String { dimension.rawValue }
        public var band: Band? { score.map(Band.init(score:)) }

        enum CodingKeys: String, CodingKey {
            case dimension, score, status, headline, reason, points, conclusion, evidence, changeReason, saw, strengths, impact, tryThis, solutionSteps,
                 planning, assessment, issueLine, fixLine
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            dimension = try c.decode(Dimension.self, forKey: .dimension)
            score = try c.decodeIfPresent(Int.self, forKey: .score)
            status = try c.decode(Status.self, forKey: .status)
            headline = try c.decode(String.self, forKey: .headline)
            points = try c.decodeIfPresent([Point].self, forKey: .points)
            conclusion = try c.decodeIfPresent(String.self, forKey: .conclusion)
            evidence = try c.decodeIfPresent([Evidence].self, forKey: .evidence) ?? []
            changeReason = try c.decodeIfPresent(String.self, forKey: .changeReason)
            saw = try c.decodeIfPresent(String.self, forKey: .saw)
            strengths = try c.decodeIfPresent([String].self, forKey: .strengths)
            impact = try c.decodeIfPresent(String.self, forKey: .impact)
            tryThis = try c.decodeIfPresent(String.self, forKey: .tryThis)
            solutionSteps = try c.decodeIfPresent([String].self, forKey: .solutionSteps)
            planning = try c.decodeIfPresent(PlanningAssessment.self, forKey: .planning)
            assessment = try c.decodeIfPresent(BehavioralAssessment.self, forKey: .assessment)
            issueLine = try c.decodeIfPresent(String.self, forKey: .issueLine)
            fixLine = try c.decodeIfPresent(String.self, forKey: .fixLine)
            reason = try c.decodeIfPresent(String.self, forKey: .reason)
                ?? (points?.isEmpty == false || (saw == nil && strengths == nil)
                    ? Self.compose(points: points ?? [], conclusion: conclusion)
                    : Self.compose(strengths: strengths ?? [], saw: saw, impact: impact, tryThis: tryThis, steps: solutionSteps ?? []))
        }

        /// The readable fields as one Markdown text, for the report and other single-block readers.
        static func compose(strengths: [String] = [], saw: String?, impact: String?, tryThis: String?, steps: [String] = []) -> String {
            var parts = strengths.isEmpty ? [] : ["**What's working:**\n" + strengths.map { "- \($0)" }.joined(separator: "\n")]
            parts += [("What we saw", saw), ("Why it matters", impact), ("Try this", tryThis)]
                .compactMap { label, text in text.flatMap { $0.isEmpty ? nil : "**\(label):** \($0)" } }
            var text = parts.joined(separator: "\n\n")
            if !steps.isEmpty { text += "\n\n" + steps.map { "- \($0)" }.joined(separator: "\n") }
            return text
        }

        /// Points and conclusion as one Markdown text, for places that show a single block.
        static func compose(points: [Point], conclusion: String?) -> String {
            var parts = points.map { ($0.tone.map { $0.emoji + " " } ?? "") + "**\($0.heading)** \($0.body)" }
            if let conclusion, !conclusion.isEmpty { parts.append("**\(conclusion)**") }
            return parts.joined(separator: "\n\n")
        }

        public enum Status: String, Codable, Sendable {
            case scored
            case notAssessable = "not_assessable"
            case notReviewed = "not_reviewed"

            public var label: String {
                switch self {
                case .scored: "Scored"
                case .notAssessable: "Not assessable"
                case .notReviewed: "Not reviewed"
                }
            }
        }
    }

    public struct Evidence: Codable, Sendable {
        public var tool: String
        public var sessionId: String
        public var date: String
        public var note: String
        /// The project the session belongs to, shown instead of the session id. nil on older cards.
        public var project: String?

        /// "checkout-flow · Oct 8": what the app shows for a reference.
        public var label: String {
            let day = Self.shortDate(date) ?? date
            return "\(project?.isEmpty == false ? project! : tool) · \(day)"
        }

        static func shortDate(_ iso: String) -> String? {
            let parser = DateFormatter()
            parser.locale = Locale(identifier: "en_US_POSIX")
            parser.dateFormat = "yyyy-MM-dd"
            guard let day = parser.date(from: String(iso.prefix(10))) else { return nil }
            return day.formatted(.dateTime.month(.abbreviated).day())
        }
    }

    public struct Improvement: Codable, Sendable {
        public var title: String
        public var situation: String
        public var actions: [String]
        public var suggestedInstruction: String?
        public var signOfSuccess: String
        public var tryItOn: String
        /// Readable cards: the dimension this improvement raises, why it matters, and its references.
        public var dimension: Dimension?
        public var impact: String?
        public var evidence: [Evidence]?
        /// The menu bar's headline number for this problem, with what it counts: 23, "agent edits never tested".
        /// nil when the records give no honest count.
        public var count: Int?
        public var countLabel: String?
    }

    /// Other categories in the bottleneck band, besides the one the improvement raises, weakest first
    /// (rubric order breaks ties). The menu bar shows the first with its fix and counts the rest.
    public var nextFixes: [DimensionResult] {
        ordered.filter { $0.band == .bottleneck && $0.dimension != improvement.dimension }
            .enumerated().sorted { ($0.element.score ?? 0, $0.offset) < ($1.element.score ?? 0, $1.offset) }
            .map(\.element)
    }

    /// All the categories in `nextFixes`: the count behind the menu bar's "+N more to fix".
    public var moreToFix: Int { nextFixes.count }

    /// True when every scored dimension carries the short readable fields (rubric 4 output).
    public var isReadable: Bool {
        let scored = ordered.filter { $0.status == .scored }
        return !scored.isEmpty && scored.allSatisfy(\.isReadable)
    }

    /// Whether the person acted on the previous card's "one improvement to make first",
    /// judged from their records (rule-file changes and later sessions), never self-reported.
    public struct FollowUp: Codable, Sendable {
        public enum Status: String, Codable, Sendable {
            case notStarted = "not_started"
            case partlyDone = "partly_done"
            case done
            case applied

            public var label: String {
                switch self {
                case .notStarted: "Not started yet"
                case .partlyDone: "Partly done"
                case .done: "Done"
                case .applied: "Done and applied"
                }
            }
        }
        public var previousTitle: String
        public var status: Status
        public var summary: String
        public var evidence: [Evidence]
    }

    /// The rubric's permission-bypass deduction. Rubric 3 takes it off Security; older cards took it off the total.
    public struct Deduction: Codable, Sendable {
        public var points: Int
        public var reason: String
        public var evidence: [Evidence]
    }

    public struct RoadmapStage: Codable, Sendable {
        public var stage: Int
        public var change: String
        public var result: String
    }

    public struct Scope: Codable, Sendable {
        public struct UnknownInvestigation: Codable, Sendable {
            public enum Status: String, Codable, Sendable { case notFound = "not_found", unavailable, incomplete }
            public var dimension: Dimension
            public var competencyID: String
            public var status: Status
            public var searches: [String]
            public var remainingLeads: [String]

            public init(dimension: Dimension, competencyID: String, status: Status, searches: [String], remainingLeads: [String]) {
                self.dimension = dimension
                self.competencyID = competencyID
                self.status = status
                self.searches = searches
                self.remainingLeads = remainingLeads
            }
        }
        public struct ToolRange: Codable, Sendable {
            public var tool: String
            public var from: String
            public var to: String
            public var sessions: Int
        }
        public var assessedAt: String
        public var timeZone: String
        public var recordDates: [ToolRange]
        public var sessionsExamined: Int
        public var tasksCheckedInDetail: Int
        public var elapsedMinutes: Double
        public var limits: [String]
        public var unknownInvestigations: [UnknownInvestigation]?
    }

    public var language: String
    public var diagnosis: String
    /// The summary at the top of the card: 2–3 plain-language bullets. nil on cards scored before it existed;
    /// those show `diagnosis` instead.
    public var summary: [String]?
    /// What the person does well, as up to four one-liners for the result's first screen. nil on cards scored before it
    /// existed; the app then uses the best categories' headlines.
    public var highlights: [String]?
    public var dimensions: [DimensionResult]
    public var improvement: Improvement
    /// nil when there was no previous card to follow up on.
    public var followUp: FollowUp?
    /// The permission-bypass deduction the judge found. nil on cards scored before rubric 2.
    public var deductions: [Deduction]?
    /// Set by the app once the deduction has been taken off this dimension's score (rubric 3: Security).
    /// nil means any deduction comes off the total, as on rubric 2 cards.
    public var deductionAppliedTo: Dimension?
    /// The dimension's score as the judge gave it, before the deduction.
    public var scoreBeforeDeduction: Int?
    public var roadmap: [RoadmapStage]
    public var scope: Scope

    // MARK: Derived totals — computed locally so the card can't disagree with itself.

    public var ordered: [DimensionResult] {
        Dimension.allCases.compactMap { d in dimensions.first { $0.dimension == d } }
    }

    /// The sum of the scored dimensions, before deductions.
    public var dimensionSum: Int { ordered.compactMap(\.score).reduce(0, +) }

    public enum ScoringError: Error {
        case invalidAssessments
    }

    /// Keep project-relative detail while hiding personal home-directory prefixes in all report text.
    /// Reference URLs remain exact. This also covers older saved cards and exported Markdown.
    public func hidingUserPaths() throws -> Self {
        let pattern = try NSRegularExpression(pattern: #"/(?:Users|home)/[^/\s]+/"#)
        func hide(_ value: Any) -> Any {
            if let text = value as? String {
                if text.hasPrefix("https://") || text.hasPrefix("http://") { return text }
                return pattern.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
            }
            if let array = value as? [Any] { return array.map(hide) }
            if let object = value as? [String: Any] { return object.mapValues(hide) }
            return value
        }
        let encoded = try JSONEncoder().encode(self)
        let object = try JSONSerialization.jsonObject(with: encoded)
        return try JSONDecoder().decode(Self.self, from: JSONSerialization.data(withJSONObject: hide(object)))
    }

    /// Only called for new assessments. Loading an older result preserves its original scoring policy.
    /// Puts each given dimension in place of the card's own (all copies of it), or adds it when the card had none.
    public mutating func replaceDimensions(_ replacements: [DimensionResult]) {
        for replacement in replacements {
            let position = dimensions.firstIndex { $0.dimension == replacement.dimension }
            dimensions.removeAll { $0.dimension == replacement.dimension }
            dimensions.insert(replacement, at: min(position ?? dimensions.count, dimensions.count))
        }
    }

    public mutating func calculateCompetencyScores() throws {
        guard dimensions.count == Dimension.allCases.count,
              Set(dimensions.map(\.dimension)) == Set(Dimension.allCases),
              dimensions.allSatisfy({ $0.status == .scored }) else {
            throw ScoringError.invalidAssessments
        }
        let catalog = try RubricGuide.load()
        let scores = try dimensions.map { result -> Int in
            let levels: [PlanningAssessment.Level]
            if result.dimension == .planningSpecs {
                guard let planning = result.planning, result.assessment == nil else {
                    throw ScoringError.invalidAssessments
                }
                try planning.validate()
                levels = planning.competencies.map(\.level)
            } else {
                guard let assessment = result.assessment, result.planning == nil,
                      let guide = catalog.guide(for: result.dimension) else {
                    throw ScoringError.invalidAssessments
                }
                try assessment.validate(expectedIDs: guide.competencies.map(\.id))
                levels = assessment.competencies.map(\.level)
            }
            guard levels.allSatisfy(PlanningAssessment.Level.assessmentCases.contains) else {
                throw ScoringError.invalidAssessments
            }
            return Int((Double(10 * levels.reduce(0) { $0 + $1.thirds }) / Double(3 * levels.count)).rounded())
        }
        for index in dimensions.indices { dimensions[index].score = scores[index] }
        deductions = nil
        deductionAppliedTo = nil
        scoreBeforeDeduction = nil
    }

    public mutating func normalizePlanningAssessment() throws {
        guard let index = dimensions.firstIndex(where: { $0.dimension == .planningSpecs }),
              var planning = dimensions[index].planning else { return }
        try planning.validate()
        planning.competencies = planning.ordered
        dimensions[index].planning = planning
        dimensions[index].reason = planning.markdown(language: language)
    }

    /// Validate the whole response before updating any dimension. Older saved cards remain unchanged.
    public mutating func normalizeBehavioralAssessments() throws {
        let indices = dimensions.indices.filter {
            dimensions[$0].dimension != .planningSpecs && dimensions[$0].assessment != nil
        }
        guard !indices.isEmpty else { return }
        let catalog = try RubricGuide.load()
        for index in indices {
            guard let guide = catalog.guide(for: dimensions[index].dimension) else {
                throw RubricGuide.LoadError.invalidDimensions
            }
            try dimensions[index].assessment!.validate(expectedIDs: guide.competencies.map(\.id))
        }
        for index in indices {
            let dimension = dimensions[index].dimension
            let guide = catalog.guide(for: dimension)!
            let ids = guide.competencies.map(\.id)
            var assessment = dimensions[index].assessment!
            assessment.competencies = assessment.ordered(expectedIDs: ids).map { competency in
                let definition = guide.competencies.first { $0.id == competency.id }!
                var snapshot = competency
                snapshot.title = definition.title
                snapshot.whyItHelps = definition.whyItHelps
                snapshot.sources = definition.sources
                snapshot.criteria = definition.criteria
                return snapshot
            }
            dimensions[index].assessment = assessment
            dimensions[index].reason = assessment.markdown(language: language, expectedIDs: ids)
        }
    }

    /// The rubric allows at most a 1-point deduction in total, so cap it even if the judge reports more.
    public static let maxDeductionPoints = 1

    /// Points the judge asked to deduct, capped at the rubric's maximum.
    public var deductionPoints: Int {
        min((deductions ?? []).reduce(0) { $0 + max($1.points, 0) }, Self.maxDeductionPoints)
    }

    /// Points still taken off the total: none once the deduction was applied to a dimension.
    public var totalDeductionPoints: Int { deductionAppliedTo == nil ? deductionPoints : 0 }

    /// The total shown everywhere: dimension sum minus any deduction still owed by the total, never below 0.
    public var knownTotal: Int { max(dimensionSum - totalDeductionPoints, 0) }

    /// Rubric 3 rule: the permission-bypass deduction comes off Security, never below 0. Safe to call twice.
    /// If Security wasn't scored, nothing is subtracted and the total is not charged either.
    public mutating func applyDeductionToSecurity() {
        guard deductionAppliedTo == nil, deductionPoints > 0 else { return }
        deductionAppliedTo = .security
        if let i = dimensions.firstIndex(where: { $0.dimension == .security }), let score = dimensions[i].score {
            scoreBeforeDeduction = score
            dimensions[i].score = max(score - deductionPoints, 0)
        }
    }

    /// One line explaining the deduction on the dimension it was taken from.
    public func deductionNote(for dimension: Dimension) -> String? {
        guard deductionAppliedTo == dimension, let before = scoreBeforeDeduction,
              let after = dimensions.first(where: { $0.dimension == dimension })?.score else { return nil }
        return "Includes the −\(before - after) permission-bypass deduction (\(before)/10 before the deduction)."
    }

    public var unknownCount: Int { Dimension.allCases.count - ordered.filter { $0.score != nil }.count }

    /// "73", "61–81" when some dimensions are unknown, or nil when nothing could be scored.
    public var totalLabel: String? {
        if unknownCount == Dimension.allCases.count { return nil }
        return unknownCount == 0 ? "\(knownTotal)" : "\(knownTotal)–\(knownTotal + unknownCount * 10)"
    }

    public func dimensions(in band: Band) -> [DimensionResult] {
        ordered.filter { $0.band == band }
    }

    public var unassessed: [DimensionResult] { ordered.filter { $0.score == nil } }

    /// True when the judge read far fewer sessions than its reading target, so scores may miss evidence.
    public func isLowCoverage(sessionsAvailable: Int) -> Bool {
        let expected = min(sessionsAvailable, AssessmentOptions.readingTarget)
        return expected > 0 && Double(scope.sessionsExamined) < Double(expected) * 0.8
    }
}
