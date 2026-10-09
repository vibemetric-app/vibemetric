import SwiftUI

struct RunningView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 14) {
                ProgressView().controlSize(.regular)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.isPreparingAssessment ? "Preparing your session" : "Scoring your AI practice")
                        .scaledFont(24, weight: .bold, design: .serif)
                        .foregroundStyle(Theme.ink)
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text(model.isPreparingAssessment
                             ? "\(elapsed(ctx.date)) elapsed · preparing evidence"
                             : "\(elapsed(ctx.date)) elapsed · \(model.readsSoFar) reading steps")
                            .scaledFont(12, design: .monospaced)
                            .foregroundStyle(Theme.muted)
                    }
                }
                Spacer()
                Button("Cancel", role: .cancel) { model.cancel() }
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
