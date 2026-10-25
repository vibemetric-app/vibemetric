import SwiftUI
import VibemetricCore

/// The first screen of a result: the score, strengths card, and category list.
/// Each category row opens its full explanation, evidence and steps.
struct ResultSummary: View {
    @Environment(\.textScale) private var scale
    var record: CardRecord
    var baseline: CardRecord?
    var changes: [ScoreChange] = []
    /// Opens every box (shared and exported cards).
    var expandAll = false
    var deepDiveFooter: ((VibemetricCore.Dimension) -> AnyView)?
    @State private var showsAllFixes = false

    /// Boxes shown before "Show more".
    static let visibleFixes = 10

    private var card: ScoreCard { record.card }

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            score
            if !highlights.isEmpty { doingWell }
            if !fixes.isEmpty { toFix }
        }
    }

    // MARK: Score

    private var score: some View {
        VStack(alignment: .leading, spacing: 6) {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                Text(RelativeDate.format(record.createdAt, now: context.date))
                    .foregroundStyle(Theme.muted)
                    .scaledFont(13)
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(card.totalLabel ?? "—").scaledFont(56, weight: .semibold).foregroundStyle(Theme.ink)
                    Text("/ 100").scaledFont(20).foregroundStyle(Theme.muted)
                }
                if let baseline, let delta = ScoreChanges.totalDelta(card, to: baseline.card) {
                    ChangePill(delta: delta, since: baseline.createdAt)
                }
            }
        }
    }

    // MARK: What you're doing well

    /// The card's own one-liners, or on older cards the headlines of its best categories.
    private var highlights: [String] {
        if let lines = card.highlights?.filter({ !$0.trimmingCharacters(in: .whitespaces).isEmpty }), !lines.isEmpty { return lines }
        return Array(card.ordered.filter { ($0.score ?? 0) >= 7 }
            .sorted { ($0.score ?? 0) > ($1.score ?? 0) }
            .prefix(3)
            .map(\.headline))
    }

    /// The heading, then the bullets in a rounded card like the category list below: a round green dot per point,
    /// with roomy lines and gaps.
    private var doingWell: some View {
        VStack(alignment: .leading, spacing: 12) {
            SummaryHeading(text: "What you're doing well", symbol: "checkmark.circle", color: Theme.color(for: .strong))
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(highlights.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Circle().fill(Theme.color(for: .strong))
                            .frame(width: 6 * scale, height: 6 * scale)
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 4 * scale }
                            .accessibilityHidden(true)
                        Text(inline(line)).scaledFont(15).foregroundStyle(Theme.ink)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.rule, lineWidth: 1))
        }
    }

    // MARK: What to fix

    /// Every category, the weakest first and unscored ones last (rubric order breaks ties).
    private var fixes: [ScoreCard.DimensionResult] {
        let order = VibemetricCore.Dimension.allCases
        return card.dimensions
            .sorted { ($0.score ?? 11, order.firstIndex(of: $0.dimension) ?? 0) < ($1.score ?? 11, order.firstIndex(of: $1.dimension) ?? 0) }
    }

    private var toFix: some View {
        let shown = showsAllFixes ? fixes : Array(fixes.prefix(Self.visibleFixes))
        let hidden = fixes.dropFirst(Self.visibleFixes)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                SummaryHeading(text: "Focus on these next", symbol: "exclamationmark.triangle", color: Theme.color(for: .developing))
                if fixes.count > Self.visibleFixes {
                    Text("· \(shown.count) of \(fixes.count)").scaledFont(13).foregroundStyle(Theme.muted)
                }
            }
            // One card, a row per category, split by inset hairlines.
            VStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, d in
                    if i > 0 { Rectangle().fill(Theme.rule).frame(height: 1).padding(.leading, 18 + 40 * scale + 14) }
                    FixBox(result: d, change: changes.first { $0.dimension == d.dimension },
                           note: card.deductionNote(for: d.dimension),
                           deductions: card.deductionAppliedTo == d.dimension ? card.deductions ?? [] : [],
                           footer: deepDiveFooter?(d.dimension), expanded: expandAll)
                }
            }
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.rule, lineWidth: 1))
            if !hidden.isEmpty {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { showsAllFixes.toggle() }
                } label: {
                    Label(showsAllFixes ? "Show fewer" : "Show \(hidden.count) more · \(hidden.map(\.dimension.title).joined(separator: ", "))",
                          systemImage: showsAllFixes ? "chevron.up" : "chevron.down")
                        .scaledFont(13)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// One category as a row of the list: a score ring, its name with the issue under it, and a chevron. A click opens the
/// full explanation, with the fix, below.
private struct FixBox: View {
    var result: ScoreCard.DimensionResult
    var change: ScoreChange?
    var note: String?
    var deductions: [ScoreCard.Deduction]
    var footer: AnyView?
    var expandAll: Bool
    @State private var expanded: Bool

    init(result: ScoreCard.DimensionResult, change: ScoreChange?, note: String?, deductions: [ScoreCard.Deduction],
         footer: AnyView?, expanded: Bool) {
        self.result = result
        self.change = change
        self.note = note
        self.deductions = deductions
        self.footer = footer
        self.expandAll = expanded
        _expanded = State(initialValue: expanded)
    }

    /// The scorer's one-line issue. Older cards have none: their problem text's first sentence when it's between six
    /// words and about one line, which carries more context than the headline, else the headline.
    private var issue: String {
        if let line = result.issueLine, !line.trimmingCharacters(in: .whitespaces).isEmpty { return line }
        if let first = result.saw.flatMap(Self.firstSentence), first.count <= 120,
           first.split(separator: " ").count >= 6 { return first }
        return result.headline
    }

    static func firstSentence(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var sentence = trimmed
        trimmed.enumerateSubstrings(in: trimmed.startIndex..., options: .bySentences) { substring, _, _, stop in
            if let substring { sentence = substring.trimmingCharacters(in: .whitespaces) }
            stop = true
        }
        return sentence
    }

    private var bandColor: Color { result.band.map(Theme.color(for:)) ?? Theme.muted }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) { summary.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .onHover { hovering = $0 }
                .accessibilityHint(expanded ? "Hides the details" : "Shows the details")
            if expanded {
                CategoryDetails(result: result, note: note, deductions: deductions, footer: footer, expandAll: expandAll)
                    .padding(.leading, 18 + ringSize + 14)
                    .padding(.trailing, 18)
                    .padding(.bottom, 18)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(hovering || expanded ? Theme.ink.opacity(0.035) : .clear)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @Environment(\.textScale) private var scale
    @State private var hovering = false
    private var ringSize: CGFloat { 40 * scale }

    private func toggle() { withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() } }

    /// The score as a ring, then the category's name with the issue under it, and a chevron.
    private var summary: some View {
        HStack(alignment: .center, spacing: 14) {
            ScoreRing(score: result.score, color: bandColor, size: ringSize)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(result.dimension.title).scaledFont(15, weight: .semibold).foregroundStyle(Theme.ink)
                    if let change { DeltaBadge(change: change) }
                }
                Text(inline(issue)).scaledFont(13).foregroundStyle(Theme.muted)
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .scaledFont(11, weight: .semibold)
                .foregroundStyle(Theme.muted.opacity(hovering ? 1 : 0.5))
                .rotationEffect(.degrees(expanded ? 90 : 0))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }
}

/// The summary's section titles: an icon in the section's color, then the title.
private struct SummaryHeading: View {
    var text: String
    var symbol: String
    var color: Color

    var body: some View {
        Label {
            Text(text).scaledFont(16, weight: .bold).foregroundStyle(Theme.ink)
        } icon: {
            Image(systemName: symbol).scaledFont(15, weight: .semibold).foregroundStyle(color)
        }
    }
}

/// The change in the total since the previous score, e.g. "↑ 7 since Oct 20": green up, red down, grey unchanged.
private struct ChangePill: View {
    var delta: Int
    var since: Date

    private var color: Color {
        delta > 0 ? Theme.color(for: .strong) : delta < 0 ? Theme.color(for: .bottleneck) : Theme.muted
    }
    private var text: String {
        let date = since.formatted(.dateTime.month(.abbreviated).day())
        if delta == 0 { return "No change since \(date)" }
        return "\(delta > 0 ? "↑" : "↓") \(abs(delta)) since \(date)"
    }

    var body: some View {
        Text(text)
            .scaledFont(12, weight: .semibold)
            .monospacedDigit()
            .padding(.horizontal, 10).padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }
}


private extension View {
    /// The pointing-hand cursor while the pointer is over this view, as for a link.
    func pointingHandCursor() -> some View {
        onHover { inside in
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

/// A category's score as a ring filled to the score, with the number inside: the same round shape as the
/// sidebar's score badges.
private struct ScoreRing: View {
    var score: Int?
    var color: Color
    var size: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(Theme.rule, lineWidth: size * 0.08)
            if let score {
                Circle()
                    .trim(from: 0, to: CGFloat(score) / 10)
                    .stroke(color, style: StrokeStyle(lineWidth: size * 0.08, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Text(score.map(String.init) ?? "–")
                .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(score == nil ? Theme.muted : color)
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(score.map { "\($0) out of 10" } ?? "Not scored")
    }
}
