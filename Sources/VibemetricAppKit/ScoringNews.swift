import SwiftUI
import VibemetricCore

/// "What's changed in scoring": shown once, the first time someone with saved scores opens a version whose scoring
/// works differently. Change `id` when the scoring changes again so the next note shows.
enum ScoringNews {
    static let id = "2026-11-recheck-reasons"
    static let seenKey = "seenScoringNews"

    struct Point: Hashable {
        var symbol: String
        var title: String
        var body: String
    }

    static let points = [
        Point(symbol: "checklist", title: "Scores come from the reasons",
              body: "Each new score looks again at the checks behind your last one and works out the number from them, not from last time's number."),
        Point(symbol: "text.page.badge.magnifyingglass", title: "Every check names its sessions",
              body: "So the next score reopens those sessions and your new ones, instead of reading your whole history again."),
        Point(symbol: "arrow.up.arrow.down", title: "Your next score may move once",
              body: "Some earlier scores kept a number their reasons didn't support. If a category moves, it says why."),
    ]
}

/// The pop-up itself.
struct ScoringNewsSheet: View {
    @Environment(\.textScale) private var scale
    var done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text("What's changed in scoring").scaledFont(22, weight: .bold).foregroundStyle(Theme.ink)
                Text("Scores in this version are steadier and easier to explain.")
                    .scaledFont(14).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 16) {
                ForEach(ScoringNews.points, id: \.self) { point in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: point.symbol)
                            .scaledFont(16, weight: .semibold).foregroundStyle(Theme.accent)
                            .frame(width: 24 * scale)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(point.title).scaledFont(14, weight: .semibold).foregroundStyle(Theme.ink)
                            Text(point.body).scaledFont(13).foregroundStyle(Theme.ink).lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            HStack {
                Text("Rubric version \(AssessmentOptions.rubricVersion)").scaledFont(12).foregroundStyle(Theme.muted)
                Spacer()
                Button(action: done) {
                    Text("Got it")
                        .scaledFont(13, weight: .semibold).foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .frame(minHeight: 32 * scale)
                        .background(Theme.accent, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("scoring-news-done")
            }
        }
        .padding(28)
        .frame(width: 480 * scale)
        .background(Theme.paper)
    }
}
