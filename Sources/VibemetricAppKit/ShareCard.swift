import SwiftUI
import VibemetricCore

/// Fixed-size card rendered to PNG for sharing. Shows scores and the diagnosis only, never session details.
struct ShareCard: View {
    var card: ScoreCard
    var date: Date

    @MainActor
    static func png(card: ScoreCard, date: Date) -> Data? {
        let renderer = ImageRenderer(content: ShareCard(card: card, date: date).environment(\.colorScheme, .light))
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .firstTextBaseline) {
                Text("AI NATIVE SCORE")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(Theme.muted)
                Spacer()
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Theme.muted)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(card.totalLabel ?? "—")
                    .font(.system(size: 96, weight: .heavy, design: .monospaced))
                Text("/ 100")
                    .font(.system(size: 26, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.muted)
            }
            .foregroundStyle(Theme.ink)

            VStack(alignment: .leading, spacing: 11) {
                ForEach(card.ordered) { d in
                    HStack(spacing: 16) {
                        Text(d.dimension.title)
                            .font(.system(size: 15, weight: .medium))
                            .frame(width: 200, alignment: .leading)
                        ScorePips(score: d.score, size: 13)
                        Spacer()
                        Text(d.score.map { "\($0)" } ?? "–")
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                            .foregroundStyle(d.band.map(Theme.color(for:)) ?? Theme.muted)
                    }
                    .foregroundStyle(Theme.ink)
                }
            }

            Text(markdown(card.diagnosis))
                .font(.system(size: 16, design: .serif))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)

            Divider().overlay(Theme.rule)
            Text("vibemetric · scored from real Claude Code & Codex sessions")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.muted)
        }
        .padding(44)
        .frame(width: 680)
        .background(Theme.paper)
    }
}
