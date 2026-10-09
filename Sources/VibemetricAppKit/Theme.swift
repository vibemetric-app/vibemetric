import SwiftUI
import VibemetricCore

/// Warm paper-and-ink palette that adapts to dark mode.
public enum Theme {
    public static let paper = Color(light: .init(red: 0.976, green: 0.965, blue: 0.941, alpha: 1), dark: .init(red: 0.086, green: 0.082, blue: 0.075, alpha: 1))
    static let card = Color(light: .white, dark: .init(red: 0.13, green: 0.125, blue: 0.115, alpha: 1))
    public static let ink = Color(light: .init(red: 0.11, green: 0.10, blue: 0.09, alpha: 1), dark: .init(red: 0.94, green: 0.92, blue: 0.88, alpha: 1))
    public static let muted = Color(light: .init(red: 0.45, green: 0.43, blue: 0.40, alpha: 1), dark: .init(red: 0.62, green: 0.60, blue: 0.56, alpha: 1))
    public static let rule = Color(light: .init(red: 0.88, green: 0.86, blue: 0.82, alpha: 1), dark: .init(red: 0.24, green: 0.23, blue: 0.21, alpha: 1))
    public static let accent = Color(light: .init(red: 0.85, green: 0.35, blue: 0.16, alpha: 1), dark: .init(red: 0.98, green: 0.52, blue: 0.30, alpha: 1))

    public static func color(for band: Band) -> Color {
        switch band {
        case .strong: Color(light: .init(red: 0.13, green: 0.55, blue: 0.33, alpha: 1), dark: .init(red: 0.35, green: 0.80, blue: 0.52, alpha: 1))
        case .developing: Color(light: .init(red: 0.78, green: 0.55, blue: 0.08, alpha: 1), dark: .init(red: 0.95, green: 0.74, blue: 0.30, alpha: 1))
        case .bottleneck: Color(light: .init(red: 0.78, green: 0.25, blue: 0.20, alpha: 1), dark: .init(red: 0.96, green: 0.45, blue: 0.40, alpha: 1))
        }
    }

    static let mono = Font.system(.body, design: .monospaced)

    /// Color for a total score out of 100, like a grade: 90+ green, 80s light green,
    /// 70s yellow, 60s orange, below 60 red.
    static func color(forTotal total: Int) -> Color {
        switch total {
        case 90...: Color(nsColor: .init(red: 0.13, green: 0.58, blue: 0.33, alpha: 1))
        case 80..<90: Color(nsColor: .init(red: 0.42, green: 0.66, blue: 0.20, alpha: 1))
        case 70..<80: Color(nsColor: .init(red: 0.86, green: 0.66, blue: 0.10, alpha: 1))
        case 60..<70: Color(nsColor: .init(red: 0.91, green: 0.47, blue: 0.16, alpha: 1))
        default: Color(nsColor: .init(red: 0.80, green: 0.26, blue: 0.21, alpha: 1))
        }
    }
}

extension Color {
    init(light: NSColor, dark: NSColor) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

/// A rounded, hairline-bordered surface used for every panel.
public struct Panel<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder var content: Content

    public init(padding: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.rule))
    }
}

struct SectionLabel: View {
    var text: String
    var body: some View {
        Text(text.uppercased())
            .scaledFont(11, weight: .semibold, design: .monospaced)
            .tracking(1.2)
            .foregroundStyle(Theme.muted)
    }
}

/// Ten pips, one per point.
public struct ScorePips: View {
    var score: Int?
    var baseSize: CGFloat = 9
    @Environment(\.textScale) private var scale

    public init(score: Int?, size: CGFloat = 9) {
        self.score = score
        self.baseSize = size
    }

    private var size: CGFloat { baseSize * scale }

    public var body: some View {
        HStack(spacing: size * 0.45) {
            ForEach(0..<10, id: \.self) { i in
                Circle()
                    .fill(fill(i))
                    .frame(width: size, height: size)
                    .overlay(Circle().strokeBorder(Theme.rule, lineWidth: score.map { i < $0 } ?? false ? 0 : 1))
            }
        }
        .accessibilityElement()
        .accessibilityLabel(score.map { "\($0) out of 10" } ?? "Not scored")
    }

    private func fill(_ i: Int) -> Color {
        guard let score, i < score else { return .clear }
        return Theme.color(for: Band(score: score))
    }
}

/// "Today 2:30pm", "Yesterday 1:15pm", "3 days ago", "Sep 21". Refreshes each minute so
/// labels stay right when the app is left open past midnight.
struct RelativeDateText: View {
    var date: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            Text(RelativeDate.format(date, now: context.date))
        }
    }
}

/// A total score in a filled circle colored by its grade (see `Theme.color(forTotal:)`).
struct ScoreBadge: View {
    var card: ScoreCard
    var size: CGFloat = 34
    @Environment(\.textScale) private var scale

    var body: some View {
        let d = size * scale
        ZStack {
            Circle().fill(card.totalLabel == nil ? Theme.muted : Theme.color(forTotal: card.knownTotal))
            Text(card.unknownCount == 0 ? "\(card.knownTotal)" : (card.totalLabel == nil ? "—" : "~\(card.knownTotal)"))
                .font(.system(size: d * 0.42, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .padding(.horizontal, 3)
        }
        .frame(width: d, height: d)
        .accessibilityElement()
        .accessibilityLabel("Score \(card.totalLabel ?? "not available")")
    }
}
