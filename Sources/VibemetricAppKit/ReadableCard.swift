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

    private var card: ScoreCard { record.card }
    private var changes: [ScoreChange] { baseline.map { ScoreChanges.compare(card, to: $0.card) } ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            ResultSummary(record: record, baseline: baseline, changes: changes, expandAll: expandAll,
                          deepDiveFooter: deepDiveFooter).id("header")
            about.id("scope")
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

/// A category's full explanation: what works, the problem with its evidence, the solution and its steps, any
/// deduction, and the footer (the Pro deep dive in official builds).
struct CategoryDetails: View {
    var result: ScoreCard.DimensionResult
    var note: String?
    var deductions: [ScoreCard.Deduction] = []
    var footer: AnyView?
    var expandAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if result.dimension == .planningSpecs, let planning = result.planning {
                PlanningAssessmentView(assessment: planning, expandAll: expandAll)
            } else if let assessment = result.assessment {
                BehavioralAssessmentView(assessment: assessment, expandAll: expandAll)
            } else if result.isReadable {
                if let strengths = result.strengths {
                    // Newer cards: what works on its own, above a problem that holds only the gap.
                    if !strengths.isEmpty { WhatsWorking(points: strengths) }
                    ProblemSolution(problem: [result.saw ?? "", result.impact ?? ""], evidence: result.evidence,
                                    solution: result.tryThis ?? "", steps: result.solutionSteps ?? [],
                                    nextStep: result.band == .strong)
                } else {
                    // Older cards: a strong category's text is what went well.
                    ProblemSolution(problem: [result.saw ?? "", result.impact ?? ""], evidence: result.evidence,
                                    solution: result.tryThis ?? "", steps: result.solutionSteps ?? [],
                                    goodNews: result.band == .strong, nextStep: result.band == .strong)
                }
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

/// Problem and Solution: the one structure every fix and category uses.
/// Problem is what happened and what it cost, as one paragraph, with the sessions it comes from.
/// Solution is the fix in one line; when there is more, tabs hold the prompt to paste and the steps.
/// `goodNews` labels the first part "What's working" (older cards, whose strong categories describe what went well);
/// `nextStep` labels the second part "Next step", for a strong category.
private struct ProblemSolution: View {
    /// Sentences joined into one paragraph; empty ones are left out.
    var problem: [String]
    var evidence: [ScoreCard.Evidence] = []
    var solution: String
    var prompt: String? = nil
    var steps: [String] = []
    var tryItOn: String? = nil
    var signOfSuccess: String? = nil
    var goodNews = false
    var nextStep = false

    private enum Tab: String, CaseIterable { case prompt = "Prompt", steps = "Steps" }
    @State private var tab: Tab = .prompt

    private var problemText: String {
        problem.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
    }
    /// The problem as bullets, one sentence each.
    private var problemPoints: [String] { sentences(problemText) }
    private var hasPrompt: Bool { !(prompt ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
    private var hasSteps: Bool { !steps.isEmpty || !(tryItOn ?? "").isEmpty || !(signOfSuccess ?? "").isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !problemText.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    PartLabel(text: goodNews ? "What's working" : "Problem",
                              symbol: goodNews ? "checkmark.circle.fill" : "exclamationmark.triangle.fill", color: problemColor)
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(Array(problemPoints.enumerated()), id: \.offset) { _, point in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("•").foregroundStyle(problemColor)
                                Text(inline(point)).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .scaledFont(14)
                    .foregroundStyle(Theme.ink)
                    EvidenceChips(evidence: evidence)
                }
                .modifier(PartPanel(color: problemColor))
            }
            if !solution.isEmpty || hasPrompt || hasSteps {
                VStack(alignment: .leading, spacing: 8) {
                    PartLabel(text: nextStep ? "Next step" : "Solution",
                              symbol: nextStep ? "arrow.up.right.circle.fill" : "lightbulb.fill", color: solutionColor)
                    if !solution.isEmpty || hasSteps { stepsView }
                    if hasPrompt && hasSteps {
                        // Drawn tabs rather than a segmented Picker, so they also render in snapshots.
                        HStack(spacing: 4) {
                            ForEach(Tab.allCases, id: \.self) { t in
                                Button { tab = t } label: {
                                    Text(t.rawValue)
                                        .scaledFont(13, weight: .semibold)
                                        .padding(.horizontal, 12).padding(.vertical, 4)
                                        .foregroundStyle(tab == t ? Theme.paper : Theme.muted)
                                        .background(tab == t ? Theme.ink : Color.clear, in: Capsule())
                                        .contentShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(3)
                        .background(Theme.rule.opacity(0.5), in: Capsule())
                        .padding(.top, 2)
                    }
                    if hasPrompt && (tab == .prompt || !hasSteps) {
                        CopyBox(caption: "Paste this into your context file or prompt", text: prompt!)
                    }
                }
                .modifier(PartPanel(color: solutionColor))
            }
        }
    }

    private var problemColor: Color { goodNews ? Theme.color(for: .strong) : Theme.color(for: .bottleneck) }
    private var solutionColor: Color { nextStep ? Theme.accent : Theme.color(for: .strong) }

    /// The solution as bullets, laid out like the problem's: its title first in bold, then how to do it,
    /// where to try it, and how to tell it worked.
    private var stepsView: some View {
        VStack(alignment: .leading, spacing: 5) {
            if !solution.isEmpty { bullet(Text(inline(solution)).fontWeight(.semibold)) }
            ForEach(Array(steps.enumerated()), id: \.offset) { _, step in bullet(Text(inline(step))) }
            if let tryItOn, !tryItOn.isEmpty { bullet(Text("Try it on: ").fontWeight(.semibold) + Text(inline(tryItOn))) }
            if let signOfSuccess, !signOfSuccess.isEmpty {
                bullet(Text("You'll know it worked when: ").fontWeight(.semibold) + Text(inline(signOfSuccess)))
            }
        }
        .scaledFont(14)
        .foregroundStyle(Theme.ink)
    }

    private func bullet(_ text: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•").foregroundStyle(solutionColor)
            text.fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// What the person already does well in a category, shown above its Problem in the category details.
private struct WhatsWorking: View {
    var points: [String]
    private var color: Color { Theme.color(for: .strong) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PartLabel(text: "What's working", symbol: "checkmark.circle.fill", color: color)
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(color)
                        Text(inline(point)).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .scaledFont(14)
            .foregroundStyle(Theme.ink)
        }
        .modifier(PartPanel(color: color))
    }
}

/// "Problem" / "Solution": a small bold label in the part's color, with its symbol.
private struct PartLabel: View {
    var text: String
    var symbol: String
    var color: Color
    var body: some View {
        Label(text, systemImage: symbol)
            .scaledFont(13, weight: .bold)
            .foregroundStyle(color)
    }
}

/// The panel behind Problem or Solution: a light tint of the part's color, so the two read as separate
/// blocks at a glance.
private struct PartPanel: ViewModifier {
    var color: Color
    func body(content: Content) -> some View {
        content
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Text to paste, in a box with a Copy button.
private struct CopyBox: View {
    var caption: String
    var text: String
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(caption).scaledFont(12).foregroundStyle(Theme.muted)
                Text(inline(text)).scaledFont(14).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button(copied ? "Copied" : "Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                copied = true
                Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
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
