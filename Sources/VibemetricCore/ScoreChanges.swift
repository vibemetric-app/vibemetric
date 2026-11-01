import Foundation

/// What moved between two assessments, and whether the judge said why.
public struct ScoreChange: Sendable, Identifiable {
    public var dimension: Dimension
    public var from: Int?
    public var to: Int?
    /// The judge's stated reason, if it gave one.
    public var reason: String?
    /// Every check kept its status: the score was worked out again from the same reasons, without the previous number.
    public var checksUnchanged = false

    public var id: String { dimension.rawValue }
    public var delta: Int? { if let from, let to { return to - from }; return nil }

    /// A moved score with no stated new evidence is most likely scoring variation, not progress.
    public var isUnexplained: Bool { (reason ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

public enum ScoreChanges {
    /// Dimensions whose score (or scored/unscored status) differs, in rubric order.
    public static func compare(_ current: ScoreCard, to previous: ScoreCard) -> [ScoreChange] {
        let before = Dictionary(previous.ordered.map { ($0.dimension, $0) }, uniquingKeysWith: { a, _ in a })
        return current.ordered.compactMap { d in
            let old = before[d.dimension]?.score
            guard old != d.score else { return nil }
            var change = ScoreChange(dimension: d.dimension, from: old, to: d.score, reason: d.changeReason)
            change.checksUnchanged = sameChecks(d.checks, before[d.dimension]?.checks)
            return change
        }
    }

    /// Both cards list the same checks with the same statuses.
    static func sameChecks(_ a: [ScoreCheck]?, _ b: [ScoreCheck]?) -> Bool {
        guard let a, let b, !a.isEmpty else { return false }
        return Set(a.map { "\($0.id):\($0.status.rawValue)" }) == Set(b.map { "\($0.id):\($0.status.rawValue)" })
    }

    /// Change in the total, when both cards are fully scored.
    public static func totalDelta(_ current: ScoreCard, to previous: ScoreCard) -> Int? {
        guard current.unknownCount == 0, previous.unknownCount == 0 else { return nil }
        return current.knownTotal - previous.knownTotal
    }
}
