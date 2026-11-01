import Foundation

/// One observable practice behind a dimension's score, as the rubric lists it under each dimension's table, with
/// what the records showed.
public struct ScoreCheck: Codable, Sendable, Equatable, Identifiable {
    public enum Status: String, Codable, Sendable, CaseIterable {
        case met, partly
        case notMet = "not_met"
        /// No task read called for it, or the records cannot show it. Not enough evidence, not a weakness.
        case notSeen = "not_seen"

        public var label: String {
            switch self {
            case .met: "Yes"
            case .partly: "Partly"
            case .notMet: "Not yet"
            case .notSeen: "Not enough evidence"
            }
        }
    }

    public struct Definition: Sendable, Equatable {
        public var id: String
        public var title: String
    }

    public var id: String
    public var status: Status
    /// One plain sentence with a real case.
    public var note: String
    /// How many of the relevant tasks read showed it, when at least `minimumCount` were read.
    public var seen: Int?
    public var of: Int?
    /// The full IDs of the sessions the note rests on, so a later score can open them again and recheck the status.
    /// Empty when the status rests on an absence; nil on cards from before checks cited sessions.
    public var sessions: [String]?

    public init(id: String, status: Status, note: String, seen: Int? = nil, of: Int? = nil, sessions: [String]? = nil) {
        self.id = id
        self.status = status
        self.note = note
        self.seen = seen
        self.of = of
        self.sessions = sessions
    }

    /// The fewest relevant tasks a count may rest on; with fewer, the check gives no count.
    public static let minimumCount = 3

    /// "9 of 14", when the check has a count the rubric allows.
    public var count: String? {
        guard let seen, let of, of >= Self.minimumCount, (0...of).contains(seen) else { return nil }
        return "\(seen) of \(of)"
    }

    /// The checks the rubric lists for each dimension, in its order.
    public static func definitions(for dimension: Dimension) -> [Definition] {
        let pairs: [(String, String)]
        switch dimension {
        case .planningSpecs:
            pairs = [("user_outcome", "Says the end user's outcome"), ("done_check", "Says how done will be checked"),
                     ("settles_unknowns", "Settles unclear requirements first")]
        case .contextEngineering:
            pairs = [("essentials_covered", "Project notes cover the essentials"),
                     ("concise_structure", "Project notes are concise and organized"),
                     ("kept_current", "Project notes are kept current")]
        case .memory:
            pairs = [("saves_what_matters", "Saves what later work needs"), ("reviews_memory", "Reviews and cleans up memory"),
                     ("memory_rules", "Has rules for what goes where")]
        case .toolIntegration:
            pairs = [("tools_do_work", "Connected tools do the real work"),
                     ("procedures_saved", "Recurring work is saved as tools or skills"),
                     ("kept_and_shared", "Proven tools are maintained and shared")]
        case .taskMapping:
            pairs = [("checkable_pieces", "Splits big work into checkable pieces"), ("wired_flow", "Orders and routes the pieces"),
                     ("saved_structure", "Reuses a saved way of splitting work")]
        case .feedbackLoops:
            pairs = [("results_decide", "Results decide the next step"),
                     ("defined_loop", "Loops have goals, checks, and stopping rules"),
                     ("loop_by_default", "The loop runs by default and improves")]
        case .testingEvals:
            pairs = [("real_checks", "Changes are checked in the real flow"),
                     ("core_tests", "Core behavior has tests that run and pass"),
                     ("automatic_checks", "Checks run automatically"), ("ai_evals", "AI features are evaluated")]
        case .humanSteering:
            pairs = [("specific_feedback", "Says exactly what is wrong and checks the fix"),
                     ("asks_for_evidence", "Asks for evidence before accepting"),
                     ("changes_course", "Stops wrong assumptions and extra scope")]
        case .security:
            pairs = [("limited_access", "Agents get only the access a task needs"),
                     ("security_checks", "AI-built code gets security checks"),
                     ("rules_by_default", "Security rules apply by default")]
        case .efficiencyCost:
            pairs = [("fit_model", "Matches model and effort to the task"), ("adjusts_from_results", "Adjusts from results and usage"),
                     ("routing_by_default", "Model rules apply by default")]
        }
        return pairs.map { Definition(id: $0.0, title: $0.1) }
    }

    /// Every check ID across the dimensions.
    public static var allIDs: [String] { Dimension.allCases.flatMap { definitions(for: $0).map(\.id) } }

    /// The anchors a score is chosen from. A 2, 4, 6 or 8 has reached the anchor below and works toward the one above.
    public static let anchors = [1, 3, 5, 7, 9, 10]

    /// The anchor above a score, or nil at 10.
    public static func nextAnchor(after score: Int) -> Int? { anchors.first { $0 > score } }
}

extension ScoreCard {
    /// Keeps each dimension's own checks, once each, in the rubric's order, and drops a count the rubric doesn't allow.
    public mutating func normalizeChecks() {
        for index in dimensions.indices {
            guard let returned = dimensions[index].checks else { continue }
            dimensions[index].checks = ScoreCheck.definitions(for: dimensions[index].dimension).compactMap { definition in
                guard var check = returned.first(where: { $0.id == definition.id }) else { return nil }
                if check.count == nil { check.seen = nil; check.of = nil }
                return check
            }
        }
    }
}
