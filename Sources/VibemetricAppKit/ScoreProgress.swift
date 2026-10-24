import Foundation
import VibemetricCore

/// How far a score has got, as a percentage the running screen can show.
///
/// Preparing (scanning and writing the evidence pack) fills the first 5%. The rest is three equal chapters that match
/// the app's reading phases: skimming digests, investigating original transcripts, and writing the card. Skimming moves
/// with the digests opened out of the skim target or the time out of its minimum, whichever is further; investigating
/// moves with its minimum time; writing eases toward 99% until the card arrives. A chapter stays just short of its end
/// until the next phase starts, so the bar never moves backwards and reaches 100% only when the score is done.
struct ScoreProgress {
    enum Stage: Equatable { case preparing, skimming, investigating, writing, done }

    /// Where the chapters meet on the bar, for the dividers the running screen draws.
    static let chapterStarts: [Double] = [0.05, 0.37, 0.69]
    static let chapterTitles = ["Skim", "Investigate", "Write"]

    private(set) var stage: Stage = .preparing
    private(set) var digestsRead: Set<String> = []
    /// Digests that must be opened before skimming may end: every digest in the pack, once it is written.
    private(set) var target: Int
    private let phases: ReadingPhases
    private var started: Date
    private var stageStarted: Date?

    init(started: Date = Date(), phases: ReadingPhases = .standard) {
        self.started = started
        self.phases = phases
        target = EvidencePack.maxDigests
    }

    /// The evidence pack is ready and the engine starts skimming it.
    mutating func startReading(digests: Int, at now: Date = Date()) {
        target = max(1, digests)
        enter(.skimming, at: now)
    }

    /// One reading step from the engine, such as "Read cc-1a2b3c4d5e6f.md" or a `cat sessions/...` command.
    mutating func noteRead(_ what: String, at now: Date = Date()) {
        guard stage == .skimming || stage == .investigating else { return }
        for match in what.matches(of: Self.digestName) { digestsRead.insert(String(what[match.range])) }
    }

    mutating func startInvestigating(at now: Date = Date()) { enter(.investigating, at: now) }
    mutating func startWriting(at now: Date = Date()) { enter(.writing, at: now) }
    mutating func finish() { stage = .done }

    /// Stages only move forward.
    private mutating func enter(_ next: Stage, at now: Date) {
        let order: [Stage] = [.preparing, .skimming, .investigating, .writing, .done]
        guard order.firstIndex(of: next)! > order.firstIndex(of: stage)! else { return }
        stage = next
        stageStarted = now
    }

    /// The percentage to show at `now`, from 0 to 100.
    func percent(at now: Date = Date()) -> Int { Int(fraction(at: now) * 100) }

    func fraction(at now: Date) -> Double {
        let starts = Self.chapterStarts + [1]
        let inStage = now.timeIntervalSince(stageStarted ?? now)
        func chapter(_ index: Int, _ done: Double) -> Double {
            starts[index] + (starts[index + 1] - starts[index]) * min(max(done, 0), 1)
        }
        switch stage {
        case .preparing:
            // Preparing usually takes seconds; ease toward the first chapter so it moves without overshooting.
            return starts[0] * ease(now.timeIntervalSince(started), over: 20) * 0.9
        case .skimming:
            let byDigests = Double(digestsRead.count) / Double(target)
            let byTime = inStage / max(phases.skimMinimum, 1)
            return chapter(0, 0.95 * min(max(byDigests, byTime), 1))
        case .investigating:
            return chapter(1, 0.95 * min(inStage / max(phases.investigateMinimum, 1), 1))
        case .writing:
            return chapter(2, 0.97 * ease(inStage, over: 150))
        case .done:
            return 1
        }
    }

    /// 0 at the start, about 63% after `seconds`, approaching 1.
    private func ease(_ elapsed: TimeInterval, over seconds: TimeInterval) -> Double {
        1 - exp(-max(elapsed, 0) / seconds)
    }

    /// Digest file names from `EvidencePack`: `cc-<id>.md` or `codex-<id>.md`.
    private static let digestName = try! Regex(#"(?:cc|codex)-[A-Za-z0-9_-]+\.md"#)

    /// What the running screen says about the current stage.
    var label: String {
        switch stage {
        case .preparing: "Preparing your evidence"
        case .skimming: "1 of 3 · Skimming sessions · \(min(digestsRead.count, target)) of \(target)"
        case .investigating: "2 of 3 · Investigating sessions · \(digestsRead.count) read"
        case .writing: "3 of 3 · Writing your score"
        case .done: "Done"
        }
    }
}
