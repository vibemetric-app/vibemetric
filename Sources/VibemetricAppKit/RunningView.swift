import SwiftUI

struct RunningView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 14) {
                Text(model.isPreparingAssessment ? "Preparing your session" : "Scoring your AI practice")
                    .scaledFont(24, weight: .bold, design: .serif)
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button("Cancel", role: .cancel) { model.cancel() }
            }

            // Moves with time as well as reads, so it is redrawn every second.
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let percent = model.progress.percent(at: ctx.date)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(model.progress.label)
                            .scaledFont(13, weight: .semibold)
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Text("\(percent)%")
                            .scaledFont(15, weight: .bold)
                            .monospacedDigit()
                            .foregroundStyle(Theme.accent)
                    }
                    ProgressBar(fraction: Double(percent) / 100, chapterStarts: ScoreProgress.chapterStarts)
                    ChapterLabels(starts: ScoreProgress.chapterStarts, titles: ScoreProgress.chapterTitles)
                    Text("\(elapsed(ctx.date)) elapsed · usually done within 15 minutes")
                        .scaledFont(12, design: .monospaced)
                        .foregroundStyle(Theme.muted)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(model.progress.label), \(percent) percent")
            }

            Panel(padding: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(model.activity) { item in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(item.isThought ? "»" : "·").foregroundStyle(Theme.accent)
                                    Text(item.text)
                                        .foregroundStyle(item.isThought ? Theme.ink : Theme.muted)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .scaledFont(12, design: .monospaced)
                                .id(item.id)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onChange(of: model.activity.count) {
                        if let last = model.activity.last { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            .frame(maxHeight: .infinity)

            Text(model.isPreparingAssessment
                 ? "Preparing local session records and usage data. \((model.runningEngine ?? model.engine).name) will start when this is ready."
                 : "\((model.runningEngine ?? model.engine).name) is analyzing your session evidence with read-only access. You can keep working while it scores.")
                .scaledFont(10)
                .foregroundStyle(Theme.muted)
        }
        .padding(32)
        .frame(maxWidth: 820)
    }

    private func elapsed(_ now: Date) -> String {
        let s = Int(now.timeIntervalSince(model.runStarted ?? now))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// A thin rounded bar in the accent color. Drawn rather than a ProgressView, so it also renders in snapshots.
private struct ProgressBar: View {
    var fraction: Double
    /// Where each chapter begins, as fractions of the bar; a divider marks every start after the first.
    var chapterStarts: [Double] = []

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.rule.opacity(0.6))
                Capsule().fill(Theme.accent)
                    .frame(width: max(8, geo.size.width * min(max(fraction, 0), 1)))
                    .animation(.easeOut(duration: 0.4), value: fraction)
                ForEach(Array(chapterStarts.dropFirst()), id: \.self) { start in
                    Rectangle().fill(Theme.paper).frame(width: 2).offset(x: geo.size.width * start - 1)
                }
            }
        }
        .frame(height: 8)
    }
}

/// The chapter names under the bar, each starting where its chapter starts.
private struct ChapterLabels: View {
    var starts: [Double]
    var titles: [String]

    var body: some View {
        GeometryReader { geo in
            ForEach(Array(zip(starts, titles).enumerated()), id: \.offset) { index, chapter in
                Text("\(index + 1). \(chapter.1)")
                    .scaledFont(11, weight: .medium)
                    .foregroundStyle(Theme.muted)
                    .offset(x: geo.size.width * chapter.0)
            }
        }
        .frame(height: 14)
    }
}
