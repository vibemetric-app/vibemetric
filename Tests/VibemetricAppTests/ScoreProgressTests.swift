import Foundation
import Testing
@testable import VibemetricAppKit
import VibemetricCore

/// The running screen's percentage: three chapters for skim, investigate, and write, never backwards, 100% only when done.
struct ScoreProgressTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func movesThroughTheChaptersWithoutGoingBackwards() {
        var progress = ScoreProgress(started: start)
        var last = progress.percent(at: start)
        func check(_ seconds: TimeInterval) {
            let now = progress.percent(at: start.addingTimeInterval(seconds))
            #expect(now >= last, "at \(seconds)s")
            last = now
        }
        #expect(last == 0)
        check(10)
        #expect(last < 5, "Preparing stays before the first chapter")

        progress.startReading(digests: 50, at: start.addingTimeInterval(15))
        check(15)
        for i in 0..<25 { progress.noteRead("Read cc-\(i)abcdef.md", at: start.addingTimeInterval(20)) }
        check(20)
        #expect(last >= 19, "Half of the pack's 50 digests fills about half of the first chapter")
        check(2000)
        #expect(last < 37, "Skimming never reaches the next chapter on its own")

        progress.startInvestigating(at: start.addingTimeInterval(2000))
        check(2000)
        #expect(last >= 37)
        check(5000)
        #expect(last < 69)

        progress.startWriting(at: start.addingTimeInterval(5000))
        check(5000)
        #expect(last >= 69)
        check(9000)
        #expect(last <= 99, "Never 100% before the card arrives")

        progress.finish()
        #expect(progress.percent(at: start.addingTimeInterval(9001)) == 100)
    }

    @Test func countsEachDigestOnceFromEitherEngine() {
        var progress = ScoreProgress(started: start)
        progress.startReading(digests: 4, at: start)
        progress.noteRead("Read cc-1a2b3c4d5e6f.md")
        progress.noteRead("Read cc-1a2b3c4d5e6f.md")
        progress.noteRead("Grep overview.md")
        progress.noteRead("sed -n 1,200p sessions/codex-0199abcd.md sessions/cc-77aa.md")
        #expect(progress.digestsRead.count == 3)
        #expect(progress.label == "1 of 3 · Skimming sessions · 3 of 4")
        progress.noteRead("cat sessions/codex-0199ffff.md")
        #expect(progress.stage == .skimming, "Only the app's phase notice moves the run on")
    }

    @Test func stagesOnlyMoveForward() {
        var progress = ScoreProgress(started: start)
        progress.startReading(digests: 10, at: start)
        progress.startWriting(at: start.addingTimeInterval(60))
        progress.startInvestigating(at: start.addingTimeInterval(61))
        #expect(progress.stage == .writing)
    }

    @Test func timeKeepsTheBarMovingWhileTheEngineThinks() {
        var progress = ScoreProgress(started: start, phases: .standard)
        progress.startReading(digests: 150, at: start)
        #expect(progress.percent(at: start.addingTimeInterval(60)) >= 19, "Halfway through the skim minimum")
    }
}
