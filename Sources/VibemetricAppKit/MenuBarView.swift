import AppKit
import SwiftUI
import VibemetricCore

/// Draws the menu bar item: gauge icon plus the latest score (or "Scoring…").
enum MenuBarLabel {
    static func statusImage(symbol: String, text: String) -> NSImage {
        let height: CGFloat = 18
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        let icon = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config) ?? NSImage()
        let label = NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.black,
        ])
        let gap: CGFloat = text.isEmpty ? 0 : 4
        let size = NSSize(width: ceil(icon.size.width + gap + label.size().width), height: height)
        let image = NSImage(size: size, flipped: false) { _ in
            icon.draw(in: NSRect(x: 0, y: (height - icon.size.height) / 2, width: icon.size.width, height: icon.size.height))
            label.draw(at: NSPoint(x: icon.size.width + gap, y: (height - label.size().height) / 2))
            return true
        }
        // Template images take the menu bar's own color in light, dark, and tinted menu bars.
        image.isTemplate = true
        return image
    }
}

/// The panel that drops down from the menu bar item.
/// Left-click shows this; right-click shows the StatusItemController menu (copy, settings, quit).
struct MenuBarPanel: View {
    @Environment(AppModel.self) private var model
    // Read so the "Next automatic score" line refreshes as soon as Settings change.
    @AppStorage(AutoSettings.enabledKey) private var autoEnabled = true
    @AppStorage(AutoSettings.minuteKey) private var autoMinute = AutoSchedule.defaultMinuteOfDay
    @Environment(\.textScale) private var scale
    /// Closes the popover before an action opens another window.
    var close: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let latest = model.history.first {
                summary(latest)
            } else {
                Text("No score yet")
                    .scaledFont(18, weight: .bold, design: .serif)
                Text("Run your first assessment to see how you work with AI.")
                    .scaledFont(12).foregroundStyle(.secondary)
            }

            if model.isRunning {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        let s = Int(ctx.date.timeIntervalSince(model.runStarted ?? ctx.date))
                        Text(String(format: "Scoring… %d:%02d", s / 60, s % 60))
                            .scaledFont(12, design: .monospaced)
                    }
                }
            }

            if let next = AutoSchedule(enabled: autoEnabled, minuteOfDay: autoMinute).next(after: Date()) {
                Text("Next automatic score: \(RelativeDate.format(next))")
                    .scaledFont(11)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Button("Open Vibemetric") { show(selectLatest: true) }
                Spacer()
                Button(model.isRunning ? "Running…" : "Score me again") {
                    model.startAssessment()
                    show(selectLatest: false)
                }
                .disabled(!model.canStartAssessment)
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            }
        }
        .padding(16)
        .frame(width: 340 * scale)
    }

    private func summary(_ record: CardRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(record.card.totalLabel ?? "—")
                    .scaledFont(44, weight: .heavy, design: .monospaced)
                Text("/ 100").scaledFont(15, weight: .semibold, design: .monospaced).foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("AI NATIVE SCORE").scaledFont(10, weight: .bold, design: .monospaced).foregroundStyle(.secondary)
                    RelativeDateText(date: record.createdAt).scaledFont(10).foregroundStyle(.secondary)
                }
            }
            VStack(spacing: 5) {
                ForEach(record.card.ordered) { d in
                    HStack(spacing: 8) {
                        Text(d.dimension.title).scaledFont(11).frame(maxWidth: .infinity, alignment: .leading)
                        ScorePips(score: d.score, size: 6)
                        Text(d.score.map(String.init) ?? "–")
                            .scaledFont(11, weight: .bold, design: .monospaced)
                            .foregroundStyle(d.band.map(Theme.color(for:)) ?? .secondary)
                            .frame(width: 16, alignment: .trailing)
                    }
                }
            }
            (Text("Next: ").bold() + Text(record.card.improvement.title))
                .scaledFont(12)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func show(selectLatest: Bool) {
        close()
        model.showMainWindow(selectLatest: selectLatest)
    }
}
