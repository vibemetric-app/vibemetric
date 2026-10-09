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
            case dimension, score, status, headline, reason, points, conclusion, evidence, changeReason
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
            reason = try c.decodeIfPresent(String.self, forKey: .reason)
                ?? Self.compose(points: points ?? [], conclusion: conclusion)
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
    }

    public struct Improvement: Codable, Sendable {
        public var title: String
        public var situation: String
        public var actions: [String]
        public var suggestedInstruction: String?
        public var signOfSuccess: String
        public var tryItOn: String
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
    }

    public var language: String
    public var diagnosis: String
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

    /// True when the judge read far fewer sessions than were available, so scores may miss evidence.
    public func isLowCoverage(sessionsAvailable: Int) -> Bool {
        let expected = min(sessionsAvailable, 300)
        return expected > 0 && Double(scope.sessionsExamined) < Double(expected) * 0.8
    }
}
