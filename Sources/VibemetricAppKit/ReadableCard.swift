import AppKit
import NaturalLanguage
import SwiftUI
import VibemetricCore

/// The score card for readable cards (short plain-text fields). First a short summary (`ResultSummary`): the score,
/// what's going well, and one box per category that opens on a click to its full explanation. The technical
/// details sit folded at the end.
/// Older cards keep `CardContent`'s original layout.
struct ReadableCardContent: View {
    @Environment(\.textScale) private var scale
    var record: CardRecord
    var baseline: CardRecord?
    var expandAll: Bool
    var deepDiveFooter: ((VibemetricCore.Dimension) -> AnyView)?
    /// The category whose full details are open on their own page, in place of the summary. nil where the page can't
    /// open (shared images), so categories show their full details in place.
    var openCategory: Binding<VibemetricCore.Dimension?>?
    var openCategories: Binding<Set<VibemetricCore.Dimension>>?

    private var card: ScoreCard { record.card }
    private var changes: [ScoreChange] { baseline.map { ScoreChanges.compare(card, to: $0.card) } ?? [] }

    var body: some View {
        Group {
                if let dimension = openCategory?.wrappedValue, let result = card.dimensions.first(where: { $0.dimension == dimension }) {
                    CategoryPage(result: result, change: changes.first { $0.dimension == dimension },
                                 note: card.deductionNote(for: dimension),
                                 deductions: card.deductionAppliedTo == dimension ? card.deductions ?? [] : [],
                                 footer: deepDiveFooter?(dimension)) { openCategory?.wrappedValue = nil }
                        .id("header")
                } else {
                    VStack(alignment: .leading, spacing: 30) {
                        ResultSummary(record: record, baseline: baseline, changes: changes, expandAll: expandAll,
                                      deepDiveFooter: deepDiveFooter,
                                      openDetails: expandAll ? nil : openCategory.map { open in { open.wrappedValue = $0 } },
                                      openCategories: expandAll ? nil : openCategories)
                            .id("header")
                        about.id("scope")
                    }
                }
        }
        .scrollTargetLayout()
        .textSelection(.enabled)
        .padding(32)
        .frame(maxWidth: 820 * max(1, scale), alignment: .leading)
    }

    // MARK: About this score: the technical details, folded

    private var about: some View {
        let sc = card.scope
        return DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                Text(sc.recordDates.map { "\($0.tool): \($0.sessions) sessions, \($0.from) to \($0.to)" }.joined(separator: " · "))
                Text("\(sc.sessionsExamined) of \(record.sessionsScanned) sessions read · \(sc.tasksCheckedInDetail) tasks checked in detail")
                Text("Scored by \(record.engineLabel) (\(record.actualModel ?? record.model ?? "default model")) in \(String(format: "%.1f", sc.elapsedMinutes)) minutes")
                if card.isLowCoverage(sessionsAvailable: record.sessionsScanned) {
                    Text("Few sessions were examined, so this score may miss evidence.")
                }
                if card.unknownCount > 0 {
                    Text("\(card.unknownCount) categor\(card.unknownCount == 1 ? "y" : "ies") could not be scored, so the total is a range.")
                }
                ForEach(sc.limits, id: \.self) { Text("– \($0)") }
                if let notes = record.instructions { Text("Scored with your notes: \(notes)") }
                Text("Scores can move a point or two between runs. Every finding links to the sessions behind it.")
            }
            .scaledFont(13)
            .foregroundStyle(Theme.muted)
            .padding(.top, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("About this score").scaledFont(14, weight: .semibold).foregroundStyle(Theme.ink)
        }
    }
}

extension ScoreCard.DimensionResult {
    /// The scorer's one-line issue. Older cards have none: their problem text's first sentence when it's between six
    /// words and about one line, which carries more context than the headline, else the headline.
    var shortIssue: String {
        if let line = issueLine, !line.trimmingCharacters(in: .whitespaces).isEmpty { return line }
        if let first = saw.flatMap(Self.firstSentence), first.count <= 120,
           first.split(separator: " ").count >= 6 { return first }
        return headline
    }

    /// The scorer's one-line fix, else the fix's title.
    var shortFix: String? {
        if let line = fixLine, !line.trimmingCharacters(in: .whitespaces).isEmpty { return line }
        return tryThis.flatMap(Self.firstSentence)
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
}

/// An opened category, short, top to bottom: the problem and the solution in a line each, the habits checked with
/// how each went, and what's working, then a link to the full details on their own page. The footer (the Pro deep
/// dive) stays here so it's one click away.
struct CategoryBrief: View {
    @Environment(\.textScale) private var scale
    var result: ScoreCard.DimensionResult
    var footer: AnyView?
    var openDetails: () -> Void

    private func line(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        return text
    }
    private var strength: String? {
        line(result.goodLine) ?? result.strengths?.first.flatMap(ScoreCard.DimensionResult.firstSentence)
    }

    /// The parts that have something to say, in tab order.
    private var parts: [CategoryDetails.Tab] {
        var parts: [CategoryDetails.Tab] = []
        if result.band != .strong || result.issueLine != nil, line(result.shortIssue) != nil { parts.append(.problem) }
        if line(result.shortFix) != nil { parts.append(.solution) }
        if result.checks?.isEmpty == false { parts.append(.habits) }
        if strength != nil { parts.append(.working) }
        return parts
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(parts.enumerated()), id: \.element) { index, tab in
                    if index > 0 { Rectangle().fill(Theme.ink.opacity(0.2)).frame(height: 1).padding(.vertical, 12) }
                    switch tab {
                    case .problem: part(tab) { sentence(result.shortIssue) }
                    case .solution: part(tab) { sentence(result.shortFix ?? "") }
                    case .habits: part(tab) { YourHabits(result: result, compact: true) }
                    case .working: part(tab) { sentence(strength ?? "") }
                    }
                }
            }
            // With a footer, the link sits first in the footer's row of actions.
            Group {
                if let footer { footer.environment(\.categoryFooterLead, AnyView(seeDetails)) } else { seeDetails }
            }
            .padding(.top, 8)
        }
    }

    private var seeDetails: some View {
        Button(action: openDetails) {
            HStack(spacing: 4) {
                Text("See details")
                Image(systemName: "chevron.right")
            }
            .scaledFont(13, weight: .semibold).foregroundStyle(Theme.accent)
            .padding(.horizontal, 14)
            .frame(minHeight: 32 * scale)
            // An outlined button: the accent border with no fill, beside the deep dive's filled one.
            .overlay(Capsule().strokeBorder(Theme.accent, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .accessibilityIdentifier("category-see-full-details")
    }

    private func part(_ tab: CategoryDetails.Tab, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(tab.title, systemImage: tab.symbol)
                .scaledFont(12, weight: .semibold).foregroundStyle(tab.color)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func sentence(_ text: String) -> some View {
        Text(inline(text)).scaledFont(14).foregroundStyle(Theme.ink)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// One category's full details on their own page: a way back, the category's name and score, then its tabs.
struct CategoryPage: View {
    @Environment(\.textScale) private var scale
    var result: ScoreCard.DimensionResult
    var change: ScoreChange?
    var note: String?
    var deductions: [ScoreCard.Deduction]
    var footer: AnyView?
    var back: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Button(action: back) {
                Label("Back to results", systemImage: "chevron.left")
                    .scaledFont(13, weight: .semibold).foregroundStyle(Theme.accent)
                    .frame(minHeight: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .keyboardShortcut(.cancelAction)
            .accessibilityIdentifier("category-back-to-results")
            HStack(spacing: 14) {
                ScoreRing(score: result.score, color: result.band.map(Theme.color(for:)) ?? Theme.muted, size: 48 * scale)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(result.dimension.title).scaledFont(22, weight: .bold).foregroundStyle(Theme.ink)
                        CategoryHelpButton(dimension: result.dimension, size: 17)
                        if let change { DeltaBadge(change: change) }
                    }
                    Text(result.dimension.question).scaledFont(13).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            CategoryDetails(result: result, note: note, deductions: deductions, footer: footer)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A category's full explanation as tabs: Problem, Solution, Your habits and Strengths, each shown when it has
/// something to say. Any deduction and the footer (the Pro deep dive, 「Go deeper」, in official builds) sit below the
/// tabs, so they stay in view whichever tab is open.
struct CategoryDetails: View {
    var result: ScoreCard.DimensionResult
    var note: String?
    var deductions: [ScoreCard.Deduction] = []
    var footer: AnyView?

    enum Tab: String, CaseIterable, Identifiable, DetailTab {
        case problem = "Problem", solution = "Solution", habits = "Your habits", working = "Strengths"
        var id: String { rawValue }
        var title: String { rawValue }

        var symbol: String {
            switch self {
            case .problem: "exclamationmark.triangle.fill"
            case .solution: "lightbulb.fill"
            case .habits: "checklist"
            case .working: "checkmark.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .problem: Theme.color(for: .bottleneck)
            case .solution: Theme.color(for: .strong)
            case .habits: Theme.accent
            case .working: Theme.blue
            }
        }
    }
    @State private var chosen: Tab?

    /// Older cards keep a strong category's good news in its problem text, with no separate strengths.
    private var olderStrong: Bool { result.strengths == nil && result.band == .strong }
    private var problemText: String {
        [result.saw ?? "", result.impact ?? ""].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            .joined(separator: " ")
    }
    /// The scorer's own problem list when the card has one, so nothing it filed as a strength shows here; older cards
    /// split their problem text into sentences.
    private var problemPoints: [String] {
        if let problems = result.problems {
            return problems.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty } + sentences(result.impact ?? "")
        }
        return olderStrong ? [] : sentences(problemText)
    }
    private var workingPoints: [String] { result.strengths ?? (olderStrong ? sentences(problemText) : []) }
    private var solution: String { result.tryThis ?? "" }
    private var steps: [String] { result.solutionSteps ?? [] }

    var tabs: [Tab] {
        Tab.allCases.filter { tab in
            switch tab {
            case .problem: !problemPoints.isEmpty
            case .solution: !solution.isEmpty || !steps.isEmpty
            case .habits: result.checks?.isEmpty == false
            case .working: !workingPoints.isEmpty
            }
        }
    }

    @ViewBuilder private func content(_ tab: Tab) -> some View {
        switch tab {
        case .problem: ProblemTab(points: problemPoints, evidence: result.evidence)
        case .solution: SolutionTab(solution: solution, steps: steps)
        case .habits: YourHabits(result: result)
        case .working: WorkingTab(points: workingPoints)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if result.isReadable {
                TabbedBox(tabs: tabs, chosen: $chosen) { content($0) }
            } else {
                // A category from an older card inside a readable one: its reason as written.
                Text(markdown(result.reason)).scaledFont(13).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
            }
            if let note {
                Text(note).scaledFont(12, weight: .semibold).foregroundStyle(Theme.color(for: .bottleneck))
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(deductions.enumerated()), id: \.offset) { _, d in
                Text("Permission-bypass deduction (−\(d.points)): \(d.reason)")
                    .scaledFont(12).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.color(for: .bottleneck).opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            }
            if !result.isReadable { EvidenceChips(evidence: result.evidence) }
            if let footer { footer }
        }
    }
}

/// One tab of a `TabbedBox`: its name, icon and color.
public protocol DetailTab: Hashable, Identifiable {
    var title: String { get }
    var symbol: String { get }
    var color: Color { get }
}

/// Tabs and what the open one shows, as one box, so the tabs read as the box's headings. With `keepsHeight`, every
/// tab's content is laid out and only the open one shown, so the box keeps the height of its tallest tab and doesn't
/// jump when another is chosen; without it, the box fits the open tab (for long pages, where a short tab would
/// otherwise sit above a large gap).
public struct TabbedBox<Tab: DetailTab, Content: View>: View {
    var tabs: [Tab]
    @Binding var chosen: Tab?
    var keepsHeight: Bool
    var content: (Tab) -> Content

    public init(tabs: [Tab], chosen: Binding<Tab?>, keepsHeight: Bool = true, @ViewBuilder content: @escaping (Tab) -> Content) {
        self.tabs = tabs
        _chosen = chosen
        self.keepsHeight = keepsHeight
        self.content = content
    }

    /// The chosen tab while it's still offered, else the first.
    private var selected: Tab? { chosen.flatMap { tabs.contains($0) ? $0 : nil } ?? tabs.first }

    public var body: some View {
        if let selected {
            VStack(spacing: 0) {
                TabBar(tabs: tabs, selected: selected) { chosen = $0 }
                ZStack(alignment: .topLeading) {
                    ForEach(keepsHeight ? tabs : [selected]) { tab in
                        content(tab)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .opacity(tab == selected ? 1 : 0)
                            .allowsHitTesting(tab == selected)
                            .accessibilityHidden(tab != selected)
                    }
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(selected.color.opacity(0.06))
            }
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.rule, lineWidth: 1))
        }
    }
}

/// The details' tabs across the top of their box, each as wide as the others: an icon and a name in its part's color.
/// The open tab is bold on a light tint over a thick underline, so which one is open is plain at a glance.
private struct TabBar<Tab: DetailTab>: View {
    var tabs: [Tab]
    var selected: Tab
    var select: (Tab) -> Void
    @State private var hovered: Tab?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                let isOn = tab == selected
                Button { select(tab) } label: {
                    VStack(spacing: 0) {
                        Label(tab.title, systemImage: tab.symbol)
                            .scaledFont(14, weight: isOn ? .bold : .semibold)
                            .lineLimit(1)
                            .foregroundStyle(tab.color)
                            .padding(.vertical, 11)
                            .frame(maxWidth: .infinity)
                        Rectangle().fill(isOn ? tab.color : Color.clear).frame(height: 3)
                    }
                    .background(isOn ? tab.color.opacity(0.12) : (hovered == tab ? Theme.rule.opacity(0.4) : Color.clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovered = $0 ? tab : (hovered == tab ? nil : hovered) }
                .accessibilityAddTraits(isOn ? [.isSelected] : [])
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.rule).frame(height: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Details")
    }
}

/// What happened and what it cost, one sentence a bullet, with the sessions it comes from.
private struct ProblemTab: View {
    var points: [String]
    var evidence: [ScoreCard.Evidence]
    private var color: Color { Theme.color(for: .bottleneck) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Bullets(points: points.map { Text(inline($0)) }, color: color)
            EvidenceChips(evidence: evidence)
        }
    }
}

/// The fix: its title in bold, then how to do it.
private struct SolutionTab: View {
    var solution: String
    var steps: [String]
    private var color: Color { Theme.color(for: .strong) }

    var body: some View {
        Bullets(points: (solution.isEmpty ? [] : [Text(inline(solution)).fontWeight(.semibold)]) + steps.map { Text(inline($0)) },
                color: color)
    }
}

/// What the person already does well in this category.
private struct WorkingTab: View {
    var points: [String]
    private var color: Color { Theme.blue }

    var body: some View {
        Bullets(points: points.map { Text(inline($0)) }, color: color)
    }
}

private struct Bullets: View {
    var points: [Text]
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•").foregroundStyle(color)
                    point.lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .scaledFont(14)
        .foregroundStyle(Theme.ink)
    }
}

/// Your habits: the rubric's checks for this category with what the records showed. Not enough evidence is shown as
/// such, apart from what is missing.
private struct YourHabits: View {
    var result: ScoreCard.DimensionResult
    /// Each habit and how it went on one line, without the note.
    var compact = false

    private var checks: [(title: String, check: ScoreCheck)] {
        let titles = Dictionary(uniqueKeysWithValues: ScoreCheck.definitions(for: result.dimension).map { ($0.id, $0.title) })
        return (result.checks ?? []).compactMap { check in titles[check.id].map { ($0, check) } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 14) {
            ForEach(checks, id: \.check.id) { item in row(item.title, item.check) }
        }
        .padding(.top, compact ? 2 : 0)
    }

    private func row(_ title: String, _ check: ScoreCheck) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol(check.status)).scaledFont(13, weight: .semibold).foregroundStyle(color(check.status))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title).scaledFont(14, weight: compact ? .regular : .semibold).foregroundStyle(Theme.ink)
                    Text([check.status.label, check.count].compactMap { $0 }.joined(separator: " · "))
                        .scaledFont(12, weight: .medium).foregroundStyle(color(check.status))
                }
                if !compact, !check.note.isEmpty {
                    Text(inline(check.note)).scaledFont(13).foregroundStyle(Theme.muted)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func symbol(_ status: ScoreCheck.Status) -> String {
        switch status {
        case .met: "checkmark.circle.fill"
        case .partly: "circle.lefthalf.filled"
        case .notMet: "xmark.circle"
        case .notSeen: "questionmark.circle"
        }
    }

    private func color(_ status: ScoreCheck.Status) -> Color {
        switch status {
        case .met: Theme.color(for: .strong)
        case .partly: Theme.color(for: .developing)
        case .notMet: Theme.color(for: .bottleneck)
        case .notSeen: Theme.muted
        }
    }
}

/// References as "project · date" chips; a click shows what happened in that session.
private struct EvidenceChips: View {
    var evidence: [ScoreCard.Evidence]
    @State private var open: Int?

    var body: some View {
        if !evidence.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    ForEach(Array(evidence.enumerated()), id: \.offset) { i, e in
                        Button {
                            open = open == i ? nil : i
                        } label: {
                            Text(e.label)
                                .scaledFont(11, weight: .medium)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .foregroundStyle(open == i ? Theme.paper : Theme.ink)
                                .background(open == i ? Theme.ink : Theme.rule.opacity(0.6), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .help(e.note)
                    }
                }
                if let open, evidence.indices.contains(open) {
                    Text(inline(evidence[open].note))
                        .scaledFont(13).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.rule.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
}

/// Splits text into sentences for bullets. Text inside `backticks` is never split.
func sentences(_ text: String) -> [String] {
    // Mask sentence punctuation inside code so file names like `CLAUDE.md` stay whole.
    var chars = Array(text), code = false
    for i in chars.indices {
        if chars[i] == "`" { code.toggle() } else if code && (chars[i] == "." || chars[i] == "!" || chars[i] == "?") { chars[i] = "\u{2024}" }
    }
    let masked = String(chars)
    let tokenizer = NLTokenizer(unit: .sentence)
    tokenizer.string = masked
    var out: [String] = []
    tokenizer.enumerateTokens(in: masked.startIndex..<masked.endIndex) { range, _ in
        let s = masked[range].trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\u{2024}", with: ".")
        if !s.isEmpty { out.append(s) }
        return true
    }
    return out.isEmpty ? [text] : out
}

/// Readable fields are plain text with `code` in backticks; render only that, so stray asterisks stay literal.
func inline(_ s: String) -> AttributedString {
    var result = AttributedString()
    for (i, part) in s.components(separatedBy: "`").enumerated() {
        var piece = AttributedString(part)
        if i % 2 == 1 { piece.inlinePresentationIntent = .code }
        result += piece
    }
    return result
}

/// A question mark in a circle, placed after a category's name. Clicking it shows what the category covers and the
/// checks that raise its score.
public struct CategoryHelpButton: View {
    var dimension: VibemetricCore.Dimension
    var size: CGFloat
    @State private var showing = false

    public init(dimension: VibemetricCore.Dimension, size: CGFloat = 13) {
        self.dimension = dimension
        self.size = size
    }

    public var body: some View {
        Button { showing.toggle() } label: {
            Image(systemName: "questionmark.circle").scaledFont(size).foregroundStyle(Theme.muted)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .help("What \(dimension.title) means")
        .accessibilityLabel("What \(dimension.title) means")
        .accessibilityIdentifier("category-help-\(dimension.rawValue)")
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Label {
                    Text(dimension.title).scaledFont(15, weight: .bold).foregroundStyle(Theme.ink)
                } icon: {
                    Image(systemName: dimension.symbol).scaledFont(14, weight: .semibold).foregroundStyle(Theme.accent)
                }
                Text(dimension.question).scaledFont(13, weight: .semibold).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(dimension.meaning).scaledFont(13).foregroundStyle(Theme.muted).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                let checks = ScoreCheck.definitions(for: dimension)
                if !checks.isEmpty {
                    Divider()
                    Text("What raises the score").scaledFont(12, weight: .semibold).foregroundStyle(Theme.muted)
                    ForEach(checks, id: \.id) { check in
                        Label {
                            Text(check.title).scaledFont(13).foregroundStyle(Theme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "checkmark").scaledFont(11, weight: .semibold).foregroundStyle(Theme.color(for: .strong))
                        }
                    }
                }
            }
            .padding(16)
            .frame(width: 480, alignment: .leading)
            // A colored edge so the popover stands out from the dark window behind it.
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.accent.opacity(0.7), lineWidth: 1.5))
        }
    }
}
