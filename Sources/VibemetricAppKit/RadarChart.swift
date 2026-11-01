import SwiftUI
import VibemetricCore

/// How the result page shows its categories: as text (the summary and the list) or as a radar chart.
enum ResultViewMode: String, CaseIterable, Identifiable {
    case text, radar
    var id: String { rawValue }
    static let storageKey = "resultViewMode"

    var title: String {
        switch self {
        case .text: "List"
        case .radar: "Chart"
        }
    }

    var symbol: String {
        switch self {
        case .text: "text.alignleft"
        case .radar: "hexagon"
        }
    }
}

/// The two views as a pair of small tiles, each a picture of the view with its name below.
/// The open one has an accent border and tint, so the choice is easy to see and to change.
struct ResultViewPicker: View {
    @Binding var mode: ResultViewMode
    @State private var hovered: ResultViewMode?
    @Environment(\.textScale) private var scale

    var body: some View {
        HStack(spacing: 10) {
            ForEach(ResultViewMode.allCases) { m in
                let isOn = m == mode
                Button { withAnimation(.easeOut(duration: 0.15)) { mode = m } } label: {
                    VStack(spacing: 6) {
                        ViewModeIllustration(mode: m, isOn: isOn)
                            .frame(width: 52 * max(1, scale), height: 38 * max(1, scale))
                        Text(m.title).scaledFont(13, weight: .semibold).foregroundStyle(isOn ? Theme.accent : Theme.ink)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                    .background(isOn ? Theme.accent.opacity(0.07) : (hovered == m ? Theme.rule.opacity(0.35) : Theme.card),
                                in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isOn ? Theme.accent.opacity(0.55) : Theme.rule, lineWidth: 1))
                    .contentShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .onHover { hovered = $0 ? m : (hovered == m ? nil : hovered) }
                .accessibilityLabel(m.title)
                .accessibilityAddTraits(isOn ? [.isSelected] : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Show the result as")
    }
}

/// A small picture of a view: lines of text with colored marks, or a radar shape on its rings.
private struct ViewModeIllustration: View {
    var mode: ResultViewMode
    var isOn: Bool

    var body: some View {
        let ink = isOn ? Theme.accent : Theme.muted
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Theme.paper)
            RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.rule, lineWidth: 1)
            switch mode {
            case .text:
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(zip([Theme.color(for: .bottleneck), Theme.color(for: .developing), Theme.color(for: .strong)],
                                      [0.85, 0.65, 0.75])), id: \.1) { color, width in
                        HStack(spacing: 5) {
                            Circle().fill(color).frame(width: 5, height: 5)
                            Capsule().fill(ink.opacity(0.55)).frame(height: 3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .scaleEffect(x: width, anchor: .leading)
                        }
                    }
                }
                .padding(.horizontal, 8)
            case .radar:
                GeometryReader { geo in
                    let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                    let radius = min(geo.size.width, geo.size.height) / 2 - 3
                    let values: [CGFloat] = [0.9, 0.55, 0.8, 0.45, 0.7, 0.6]
                    ZStack {
                        ForEach([1.0, 0.6], id: \.self) { ring in
                            Self.polygon(center: center, radius: radius, values: Array(repeating: ring, count: 6))
                                .stroke(Theme.rule, lineWidth: 1)
                        }
                        Self.polygon(center: center, radius: radius, values: values).fill(ink.opacity(0.22))
                        Self.polygon(center: center, radius: radius, values: values).stroke(ink, lineWidth: 1.5)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    private static func polygon(center: CGPoint, radius: CGFloat, values: [CGFloat]) -> Path {
        Path { path in
            for (i, value) in values.enumerated() {
                let angle = -Double.pi / 2 + Double(i) * 2 * .pi / Double(values.count)
                let point = CGPoint(x: center.x + cos(angle) * radius * value, y: center.y + sin(angle) * radius * value)
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
        }
    }
}

/// The 10 categories on a radar chart, in rubric order clockwise from the top: rings at every 2 points, this score
/// as a filled shape with a dot per category in its band's color, and the previous score, when there is one, as a
/// dashed outline. Each category's name and score sit outside its spoke; a click on one opens a panel in the middle of
/// the chart with its good and gap lines and its full explanation.
struct RadarChart: View {
    @Environment(\.textScale) private var scale
    var card: ScoreCard
    var baseline: ScoreCard?
    var baselineDate: Date?
    /// A category's full explanation (its tabs, any deduction and the deep dive), shown in its panel under its lines.
    var details: ((VibemetricCore.Dimension) -> AnyView)?
    @State private var selected: VibemetricCore.Dimension?

    /// `opened` starts with that category's panel open (for snapshots).
    init(card: ScoreCard, baseline: ScoreCard? = nil, baselineDate: Date? = nil, opened: VibemetricCore.Dimension? = nil,
         details: ((VibemetricCore.Dimension) -> AnyView)? = nil) {
        self.card = card
        self.baseline = baseline
        self.baselineDate = baselineDate
        self.details = details
        _selected = State(initialValue: opened)
    }

    private var dimensions: [VibemetricCore.Dimension] { VibemetricCore.Dimension.allCases }
    private func result(_ d: VibemetricCore.Dimension) -> ScoreCard.DimensionResult? { card.dimensions.first { $0.dimension == d } }
    private func previous(_ d: VibemetricCore.Dimension) -> Int? { baseline?.dimensions.first { $0.dimension == d }?.score }
    private var hasBaseline: Bool { baseline.map { b in dimensions.contains { d in b.dimensions.contains { $0.dimension == d && $0.score != nil } } } ?? false }

    /// The category whose panel is open.
    private var focus: VibemetricCore.Dimension? { selected }

    private func close() { withAnimation(.easeOut(duration: 0.15)) { selected = nil } }

    /// The chart, and over it, while a category is picked, its panel on a dimmed backdrop. A click on the backdrop,
    /// the panel's close button or Escape closes it. A panel taller than the chart makes the box grow to fit it.
    var body: some View {
        ZStack {
            chart
                .padding(.vertical, 8)
                .allowsHitTesting(selected == nil)
            if let d = selected, let r = result(d) {
                Theme.card.opacity(0.75)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: close)
                    .transition(.opacity)
                RadarPanel(result: r, previous: previous(d), details: details?(d), close: close)
                    .frame(maxWidth: 720 * scale)
                    .padding(24)
                    .id(d)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.rule, lineWidth: 1))
        .onExitCommand { if selected != nil { close() } }
    }

    // MARK: Chart

    private var chartHeight: CGFloat { 470 * scale }

    private var chart: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                let radius = min(geo.size.width / 2 - 120 * scale, geo.size.height / 2 - 62 * scale)
                ZStack {
                    Canvas { ctx, _ in draw(in: &ctx, center: center, radius: radius) }
                    ForEach(Array(dimensions.enumerated()), id: \.element) { i, d in
                        label(d, index: i, center: center, radius: radius)
                    }
                }
            }
            .frame(height: chartHeight)
            if hasBaseline { legend.padding(.top, 6).padding(.bottom, 10) }
        }
    }

    private func angle(_ i: Int) -> Double { -Double.pi / 2 + 2 * Double.pi * Double(i) / Double(dimensions.count) }

    private func point(_ i: Int, value: Double, center: CGPoint, radius: CGFloat) -> CGPoint {
        let r = radius * CGFloat(value / 10)
        return CGPoint(x: center.x + r * CGFloat(cos(angle(i))), y: center.y + r * CGFloat(sin(angle(i))))
    }

    private func polygon(_ values: [Double], center: CGPoint, radius: CGFloat) -> Path {
        Path { p in
            for (i, v) in values.enumerated() {
                let pt = point(i, value: v, center: center, radius: radius)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath()
        }
    }

    private func draw(in ctx: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        let n = dimensions.count
        // Rings at 2, 4, 6, 8 and 10, the outer one a little stronger, with the spokes.
        for level in stride(from: 2, through: 10, by: 2) {
            let ring = polygon(Array(repeating: Double(level), count: n), center: center, radius: radius)
            ctx.stroke(ring, with: .color(Theme.rule), lineWidth: level == 10 ? 1.5 : 1)
        }
        for i in 0..<n {
            var spoke = Path()
            spoke.move(to: center)
            spoke.addLine(to: point(i, value: 10, center: center, radius: radius))
            let isFocus = dimensions[i] == focus
            ctx.stroke(spoke, with: .color(isFocus ? Theme.accent.opacity(0.6) : Theme.rule), lineWidth: isFocus ? 1.5 : 1)
        }
        // Ring values along the top spoke.
        for level in stride(from: 2, through: 10, by: 2) {
            let pt = point(0, value: Double(level), center: center, radius: radius)
            ctx.draw(Text("\(level)").font(.system(size: 9 * scale)).foregroundStyle(Theme.muted),
                     at: CGPoint(x: pt.x + 8 * scale, y: pt.y + 1), anchor: .leading)
        }
        if hasBaseline, let baseline {
            let prev = dimensions.map { d in Double(baseline.dimensions.first { $0.dimension == d }?.score ?? 0) }
            ctx.stroke(polygon(prev, center: center, radius: radius), with: .color(Theme.muted),
                       style: StrokeStyle(lineWidth: 1.5, lineJoin: .round, dash: [5, 4]))
        }
        let values = dimensions.map { Double(result($0)?.score ?? 0) }
        let shape = polygon(values, center: center, radius: radius)
        ctx.fill(shape, with: .color(Theme.accent.opacity(0.16)))
        ctx.stroke(shape, with: .color(Theme.accent), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
        for (i, d) in dimensions.enumerated() {
            let r = result(d)
            let pt = point(i, value: values[i], center: center, radius: radius)
            let size: CGFloat = (d == focus ? 11 : 8) * scale
            let dot = Path(ellipseIn: CGRect(x: pt.x - size / 2, y: pt.y - size / 2, width: size, height: size))
            if let band = r?.band, r?.score != nil {
                ctx.fill(dot, with: .color(Theme.color(for: band)))
                ctx.stroke(dot, with: .color(Theme.card), lineWidth: 1.5)
            } else {
                ctx.fill(dot, with: .color(Theme.card))
                ctx.stroke(dot, with: .color(Theme.muted), lineWidth: 1.5)
            }
        }
    }

    /// A category's name and score outside its spoke, aligned away from the chart, as a button that picks it.
    private func label(_ d: VibemetricCore.Dimension, index i: Int, center: CGPoint, radius: CGFloat) -> some View {
        let r = result(d)
        let pt = point(i, value: 10, center: center, radius: radius + 16 * scale)
        let c = cos(angle(i)), s = sin(angle(i))
        let side: HorizontalAlignment = c > 0.25 ? .leading : c < -0.25 ? .trailing : .center
        let width = 112 * scale
        let x = pt.x + (side == .leading ? width / 2 : side == .trailing ? -width / 2 : 0)
        let y = pt.y + (abs(c) <= 0.25 ? (s < 0 ? -12 : 24) * scale : 0)
        let color = r?.band.map(Theme.color(for:)) ?? Theme.muted
        let isFocus = d == focus
        return Button { withAnimation(.easeOut(duration: 0.15)) { selected = d } } label: {
            VStack(alignment: side, spacing: 1) {
                Text(d.title)
                    .scaledFont(12, weight: isFocus ? .bold : .medium)
                    .foregroundStyle(isFocus ? Theme.ink : Theme.ink.opacity(0.8))
                    .multilineTextAlignment(side == .leading ? .leading : side == .trailing ? .trailing : .center)
                    .lineLimit(2)
                Text(r?.score.map { "\($0)/10" } ?? "–")
                    .scaledFont(12, weight: .semibold)
                    .monospacedDigit()
                    .foregroundStyle(color)
            }
            .frame(width: width, alignment: Alignment(horizontal: side, vertical: .center))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .position(x: x, y: y)
        .accessibilityLabel("\(d.title), \(r?.score.map { "\($0) out of 10" } ?? "not scored")")
        .accessibilityAddTraits(isFocus ? [.isSelected] : [])
    }

    private var legend: some View {
        HStack(spacing: 18) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2).fill(Theme.accent.opacity(0.3))
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.accent, lineWidth: 1.5))
                    .frame(width: 14 * scale, height: 10 * scale)
                Text("This score").scaledFont(12).foregroundStyle(Theme.muted)
            }
            HStack(spacing: 6) {
                Path { p in p.move(to: CGPoint(x: 0, y: 5 * scale)); p.addLine(to: CGPoint(x: 18 * scale, y: 5 * scale)) }
                    .stroke(Theme.muted, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .frame(width: 18 * scale, height: 10 * scale)
                Text(baselineDate.map { "Previous, \($0.formatted(.dateTime.month(.abbreviated).day()))" } ?? "Previous")
                    .scaledFont(12).foregroundStyle(Theme.muted)
            }
        }
    }
}

/// A category's panel over the chart: its content on a raised card, with a close button in the corner.
struct RadarPanel: View {
    var result: ScoreCard.DimensionResult
    var previous: Int?
    var details: AnyView?
    var close: () -> Void = {}

    var body: some View {
        RadarFocus(result: result, previous: previous, details: details)
            .background(Theme.paper, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.rule, lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .scaledFont(12, weight: .semibold)
                        .foregroundStyle(Theme.muted)
                        .frame(width: 28, height: 28)
                        .background(Theme.rule.opacity(0.5), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close")
                .padding(14)
            }
            .shadow(color: .black.opacity(0.18), radius: 24, y: 8)
    }
}

/// A category's panel content: its icon, name and score (with the change since the previous score), then its good
/// and gap lines, or on older cards its headline, then its full explanation.
private struct RadarFocus: View {
    var result: ScoreCard.DimensionResult
    var previous: Int?
    var details: AnyView?

    private var color: Color { result.band.map(Theme.color(for:)) ?? Theme.muted }
    private var lines: [(good: Bool, text: String)] {
        let pairs = [(true, result.goodLine), (false, result.gapLine)].compactMap { good, text -> (Bool, String)? in
            guard let text = text?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
            return (good, text)
        }
        return pairs.isEmpty ? [(false, result.issueLine ?? result.headline)] : pairs
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: result.dimension.symbol).scaledFont(14, weight: .semibold).foregroundStyle(color)
                Text(result.dimension.title).scaledFont(18, weight: .bold).foregroundStyle(Theme.ink)
                CategoryHelpButton(dimension: result.dimension, size: 15)
                Text(result.score.map { "\($0)/10" } ?? "Not scored").scaledFont(14, weight: .semibold)
                    .monospacedDigit().foregroundStyle(color)
                if let score = result.score, let previous, previous != score {
                    let up = score > previous
                    Text("\(up ? "↑" : "↓") \(abs(score - previous))")
                        .scaledFont(12, weight: .semibold)
                        .foregroundStyle(up ? Theme.color(for: .strong) : Theme.color(for: .bottleneck))
                }
            }
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: line.good ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .scaledFont(12, weight: .semibold)
                        .foregroundStyle(line.good ? Theme.color(for: .strong) : Theme.color(for: .developing))
                        .accessibilityLabel(line.good ? "Working well" : "To improve")
                    Text(inline(line.text)).scaledFont(14).foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let details { details.padding(.top, 8) }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
