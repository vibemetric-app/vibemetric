import SwiftUI
import VibemetricCore

/// The first screen of a result: the score, what's going well, and what to fix, one short box per category.
/// The full explanations, evidence and steps sit below it in `ReadableCardContent`, behind "See all 10 categories".
struct ResultSummary: View {
    @Environment(\.textScale) private var scale
    var record: CardRecord
    var baseline: CardRecord?
    var changes: [ScoreChange] = []
    /// Opens every box (shared and exported cards).
    var expandAll = false
    var deepDiveFooter: ((VibemetricCore.Dimension) -> AnyView)?
    /// Opens a category's full details on their own page; nil where the full details show in place (shared images).
    var openDetails: ((VibemetricCore.Dimension) -> Void)?
    /// The categories open in the list, kept by the window; nil where each row keeps its own (shared images).
    var openCategories: Binding<Set<VibemetricCore.Dimension>>?
    @State private var showsAllFixes = false
    @AppStorage(ResultViewMode.storageKey) private var mode: ResultViewMode = .text

    /// Boxes shown before "Show more".
    static let visibleFixes = 10

    private var card: ScoreCard { record.card }

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            score
            // Newer results open with a summary of good and bad; older ones keep what's going well.
            if let overview = card.groupedOverview, !overview.isEmpty { summary(overview) } else if !highlights.isEmpty { doingWell }
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
                Text("Rubric v\(record.rubricVersion ?? "1")")
                    .scaledFont(12, weight: .medium)
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.rule, lineWidth: 1))
                    .help("The version of the scoring rubric this score used. Scores compare only within one version.")
                    .accessibilityIdentifier("result-rubric-version")
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

    // MARK: Summary

    /// The scorer's opening points in the same rounded card: what works first, with a green check, then what holds the
    /// person back, with an amber mark.
    private func summary(_ points: [ScoreCard.SummaryPoint]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SummaryHeading(text: "Summary", symbol: "text.alignleft", color: Theme.ink)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: point.tone == .good ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .scaledFont(13, weight: .semibold)
                            .foregroundStyle(point.tone == .good ? Theme.color(for: .strong) : Theme.color(for: .developing))
                            .accessibilityLabel(point.tone == .good ? "Working well" : "To improve")
                        Text(inline(point.text)).scaledFont(15).foregroundStyle(Theme.ink)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
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
        // Shared and exported cards always show the list.
        let showsRadar = mode == .radar && !expandAll
        return VStack(alignment: .leading, spacing: 12) {
            if expandAll {
                // Shared and exported cards have only the list, under a plain heading.
                SummaryHeading(text: "Details", symbol: "list.bullet.rectangle", color: Theme.ink)
            } else {
                ResultViewPicker(mode: $mode)
            }
            if showsRadar {
                RadarChart(card: card, baseline: baseline?.card, baselineDate: baseline?.createdAt) { dimension in
                    AnyView(card.dimensions.first { $0.dimension == dimension }.map { d in
                        if let openDetails, d.isReadable {
                            AnyView(CategoryBrief(result: d, footer: deepDiveFooter?(d.dimension)) { openDetails(d.dimension) })
                        } else {
                            AnyView(CategoryDetails(result: d, note: card.deductionNote(for: d.dimension),
                                                    deductions: card.deductionAppliedTo == d.dimension ? card.deductions ?? [] : [],
                                                    footer: deepDiveFooter?(d.dimension)))
                        }
                    })
                }
            } else {
                fixList(shown: shown, hidden: hidden)
            }
        }
    }

    private func fixList(shown: [ScoreCard.DimensionResult], hidden: ArraySlice<ScoreCard.DimensionResult>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // One card, a row per category, split by inset hairlines.
            VStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, d in
                    // One view per row, named by its category, so the window can scroll back to the row.
                    VStack(spacing: 0) {
                        if i > 0 { Rectangle().fill(Theme.rule).frame(height: 1).padding(.leading, 18 + 40 * scale + 14) }
                        FixBox(result: d, change: changes.first { $0.dimension == d.dimension },
                               note: card.deductionNote(for: d.dimension),
                               deductions: card.deductionAppliedTo == d.dimension ? card.deductions ?? [] : [],
                               footer: deepDiveFooter?(d.dimension), expanded: expandAll,
                               isOpen: openCategories.map { open in
                                   Binding(get: { open.wrappedValue.contains(d.dimension) },
                                           set: { if $0 { open.wrappedValue.insert(d.dimension) } else { open.wrappedValue.remove(d.dimension) } })
                               },
                               openDetails: openDetails.map { open in { open(d.dimension) } })
                    }
                    .id(d.dimension.rawValue)
                }
            }
            .scrollTargetLayout()
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

/// One category as a row of the list: a score ring, its name with its good and gap lines (or, on older cards, the
/// issue) under it, and a chevron. A click opens the
/// full explanation, with the fix, below.
private struct FixBox: View {
    var result: ScoreCard.DimensionResult
    var change: ScoreChange?
    var note: String?
    var deductions: [ScoreCard.Deduction]
    var footer: AnyView?
    var openDetails: (() -> Void)?
    /// Whether the row is open, when the window keeps it; otherwise the row keeps it itself.
    var isOpen: Binding<Bool>?
    @State private var keptOpen: Bool
    private var expanded: Bool { isOpen?.wrappedValue ?? keptOpen }

    init(result: ScoreCard.DimensionResult, change: ScoreChange?, note: String?, deductions: [ScoreCard.Deduction],
         footer: AnyView?, expanded: Bool, isOpen: Binding<Bool>? = nil, openDetails: (() -> Void)? = nil) {
        self.result = result
        self.change = change
        self.note = note
        self.deductions = deductions
        self.footer = footer
        self.openDetails = openDetails
        self.isOpen = isOpen
        _keptOpen = State(initialValue: expanded)
    }

    private var issue: String { result.shortIssue }

    /// The good line, then the gap line, when the card has them.
    private var quickLines: [(good: Bool, text: String)] {
        [(true, result.goodLine), (false, result.gapLine)].compactMap { good, text in
            guard let text = text?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
            return (good, text)
        }
    }

    private var bandColor: Color { result.band.map(Theme.color(for:)) ?? Theme.muted }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) { summary.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .onHover { hovering = $0 }
                .accessibilityHint(expanded ? "Hides the details" : "Shows the details")
                .accessibilityIdentifier("category-row-\(result.dimension.rawValue)")
                .overlayPreferenceValue(HelpSlot.self) { slot in
                    GeometryReader { geo in
                        if let slot {
                            let rect = geo[slot]
                            CategoryHelpButton(dimension: result.dimension).position(x: rect.midX, y: rect.midY)
                        }
                    }
                }
            if expanded {
                Group {
                    if let openDetails, result.isReadable {
                        CategoryBrief(result: result, footer: footer, openDetails: openDetails)
                    } else {
                        CategoryDetails(result: result, note: note, deductions: deductions, footer: footer)
                    }
                }
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

    private func toggle() {
        withAnimation(.easeOut(duration: 0.15)) {
            if let isOpen { isOpen.wrappedValue.toggle() } else { keptOpen.toggle() }
        }
    }

    /// The score as a ring, then the category's name with the issue under it, and a chevron.
    private var summary: some View {
        HStack(alignment: .center, spacing: 14) {
            ScoreRing(score: result.score, color: bandColor, size: ringSize)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(result.dimension.title).scaledFont(15, weight: .semibold).foregroundStyle(Theme.ink)
                    // Holds the place of the help button, which sits over the row instead of inside its button so a
                    // click on it doesn't also open the row.
                    CategoryHelpButton(dimension: result.dimension).hidden().accessibilityHidden(true)
                        .anchorPreference(key: HelpSlot.self, value: .bounds) { $0 }
                    if let change { DeltaBadge(change: change) }
                }
                if expanded && openDetails != nil && result.isReadable {
                    // The opened row shows the short problem, solution, habits and strengths below instead.
                    EmptyView()
                } else if !quickLines.isEmpty {
                    ForEach(Array(quickLines.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: line.good ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                .scaledFont(11, weight: .semibold)
                                .foregroundStyle(line.good ? Theme.color(for: .strong) : Theme.color(for: .developing))
                                .accessibilityLabel(line.good ? "Working well" : "To improve")
                            Text(inline(line.text)).scaledFont(13).foregroundStyle(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    Text(inline(issue)).scaledFont(13).foregroundStyle(Theme.muted)
                        .lineSpacing(1)
                        .fixedSize(horizontal: false, vertical: true)
                }
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


extension View {
    /// The pointing-hand cursor while the pointer is over this view, as for a link.
    func pointingHandCursor() -> some View {
        onHover { inside in
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

/// A category's score as a ring filled to the score, with the number inside: the same round shape as the
/// sidebar's score badges.
/// Used for every score shown as a circle: a category's score out of 10, or a total out of 100.
public struct ScoreRing: View {
    var score: Int?
    var outOf: Int
    var color: Color
    var size: CGFloat
    /// The text inside, when it isn't just the score (for example "~72" for a total with unscored categories).
    var label: String?

    public init(score: Int?, outOf: Int = 10, color: Color, size: CGFloat, label: String? = nil) {
        self.score = score
        self.outOf = outOf
        self.color = color
        self.size = size
        self.label = label
    }

    public var body: some View {
        ZStack {
            Circle().stroke(Theme.rule, lineWidth: size * 0.08)
            if let score {
                Circle()
                    .trim(from: 0, to: CGFloat(min(max(score, 0), outOf)) / CGFloat(outOf))
                    .stroke(color, style: StrokeStyle(lineWidth: size * 0.08, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Text(label ?? score.map(String.init) ?? "–")
                .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(score == nil ? Theme.muted : color)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .padding(.horizontal, size * 0.12)
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(score.map { "\($0) out of \(outOf)" } ?? "Not scored")
    }
}

/// Where a category row's help button goes, beside the category's name.
private struct HelpSlot: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) { value = value ?? nextValue() }
}
