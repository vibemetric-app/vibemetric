import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VibemetricCore

struct CardView: View {
    var record: CardRecord
    @Environment(AppModel.self) private var model
    @State private var copied = false
    @State private var visibleSection: String?

    private var card: ScoreCard { record.card }
    private var baseline: CardRecord? { model.baseline(for: record) }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                CardContent(record: record, baseline: baseline,
                            deepDiveFooter: Extensions.categoryFooter.map { footer in { footer($0, record) } })
                ForEach(Extensions.cardSections.indices, id: \.self) { Extensions.cardSections[$0](record) }
            }
            .frame(maxWidth: .infinity)
        }
        .scrollPosition(id: $visibleSection, anchor: .top)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(markdownReport, forType: .string)
                    copied = true
                    Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                } label: {
                    Label(copied ? "Copied" : "Copy Markdown", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .help("Copy the full report as Markdown")
                Button { saveImage() } label: { Label("Save Image", systemImage: "photo") }
                    .help("Save a shareable score card image")
                Button { saveMarkdown() } label: { Label("Save Report", systemImage: "square.and.arrow.down") }
                    .help("Save the full report as a Markdown file")
            }
        }
    }

    // MARK: Export

    private var markdownReport: String {
        MarkdownRenderer.render(card, previous: baseline?.card,
                                previousDate: baseline?.createdAt.formatted(date: .abbreviated, time: .shortened))
    }

    private func saveMarkdown() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = "AI Native Score \(record.createdAt.formatted(.iso8601.year().month().day())).md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? markdownReport.write(to: url, atomically: true, encoding: .utf8)
    }

    @MainActor
    private func saveImage() {
        guard let png = ShareCard.png(card: card, date: record.createdAt) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "AI Native Score.png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? png.write(to: url)
    }
}

/// The scrollable body of a result, separate from `CardView` so it can be rendered to an image.
struct CardContent: View {
    @Environment(\.textScale) private var scale
    var record: CardRecord
    var baseline: CardRecord? = nil
    var expandAll = false
    /// The Pro deep-dive controls under each category; nil when rendering an image.
    var deepDiveFooter: ((VibemetricCore.Dimension) -> AnyView)? = nil
    private var card: ScoreCard { record.card }

    private var changes: [ScoreChange] {
        baseline.map { ScoreChanges.compare(card, to: $0.card) } ?? []
    }

    private func change(for d: VibemetricCore.Dimension) -> ScoreChange? { changes.first { $0.dimension == d } }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header.id("header")
            // A deduction taken off Security is explained inside the Security category; only older
            // cards, where it came off the total, still show it as a panel here.
            if card.deductionAppliedTo == nil, let deductions = card.deductions, !deductions.isEmpty { deductionPanel(deductions) }
            if let baseline { changesPanel(baseline) }
            dimensionsPanel.id("dimensions")
            ForEach(Band.displayOrder, id: \.self) { band in
                bandSection(band).id("band-\(band.rawValue)")
            }
            if !card.unassessed.isEmpty { unassessedSection }
            improvementPanel.id("improvement")
            roadmapPanel.id("roadmap")
            scopePanel.id("scope")
        }
        .scrollTargetLayout()
        // Every text on the card can be selected and copied (one text block at a time, a SwiftUI limit).
        .textSelection(.enabled)
        .padding(32)
        .frame(maxWidth: 820 * max(1, scale), alignment: .leading)
    }

    // MARK: Sections

    private func deductionPanel(_ deductions: [ScoreCard.Deduction]) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: card.deductionAppliedTo == nil ? "Deduction" : "Security deduction")
                ForEach(Array(deductions.enumerated()), id: \.offset) { _, d in
                    Text(card.deductionAppliedTo == nil ? "−\(d.points) point: \(d.reason)" : "−\(d.points) point from Security: \(d.reason)")
                        .scaledFont(13).foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(Array(d.evidence.enumerated()), id: \.offset) { _, e in
                        Text("\(e.tool) · \(String(e.sessionId.prefix(8))) · \(e.date) — \(e.note)")
                            .scaledFont(11, design: .monospaced)
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func changesPanel(_ baseline: CardRecord) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        SectionLabel(text: "Since \(RelativeDate.format(baseline.createdAt, now: context.date))")
                    }
                    Spacer()
                    if let delta = ScoreChanges.totalDelta(card, to: baseline.card) {
                        Text("\(baseline.card.knownTotal) → \(card.knownTotal)")
                            .scaledFont(13, weight: .semibold, design: .monospaced)
                            .foregroundStyle(delta == 0 ? Theme.muted : delta > 0 ? Theme.color(for: .strong) : Theme.color(for: .bottleneck))
                    }
                }
                if changes.isEmpty {
                    Text("No dimension changed.").scaledFont(12).foregroundStyle(Theme.muted)
                }
                ForEach(changes) { c in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(c.dimension.title).scaledFont(13, weight: .semibold).foregroundStyle(Theme.ink)
                            DeltaBadge(change: c)
                        }
                        Text(c.isUnexplained ? "No new evidence cited, so this is most likely scoring variation rather than a real change." : c.reason!)
                            .scaledFont(12)
                            .foregroundStyle(c.isUnexplained ? Theme.muted : Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var header: some View {
        Panel(padding: 28) {
            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 4) {
                    SectionLabel(text: "AI Native Score")
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(card.totalLabel ?? "—")
                            .scaledFont(72, weight: .heavy, design: .monospaced)
                            .foregroundStyle(Theme.ink)
                        Text("/ 100")
                            .scaledFont(20, weight: .semibold, design: .monospaced)
                            .foregroundStyle(Theme.muted)
                    }
                    if card.unknownCount > 0 {
                        Text("Provisional range: \(card.unknownCount) dimension\(card.unknownCount == 1 ? "" : "s") not scored")
                            .scaledFont(10).foregroundStyle(Theme.muted)
                    }
                    if card.totalDeductionPoints > 0 {
                        Text("\(card.dimensionSum) − \(card.totalDeductionPoints) deduction")
                            .scaledFont(10, weight: .semibold)
                            .foregroundStyle(Theme.color(for: .bottleneck))
                            .help((card.deductions ?? []).map(\.reason).joined(separator: "\n"))
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text(markdown(card.diagnosis))
                        .scaledFont(16, design: .serif)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        Text("\(RelativeDate.format(record.createdAt, now: context.date)) · \(card.scope.sessionsExamined) of \(record.sessionsScanned) sessions examined · \(record.engineLabel) · \(record.actualModel ?? record.model ?? "default model")")
                            .scaledFont(10).foregroundStyle(Theme.muted)
                    }
                    if card.isLowCoverage(sessionsAvailable: record.sessionsScanned) {
                        Label("Few sessions were examined, so this score may miss evidence.", systemImage: "exclamationmark.triangle.fill")
                            .scaledFont(10)
                            .foregroundStyle(Theme.color(for: .developing))
                    }
                }
                .padding(.top, 22)
            }
        }
    }

    private var dimensionsPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(text: "10 Dimensions")
                ForEach(card.ordered) { d in
                    HStack(spacing: 14) {
                        Text(d.dimension.title)
                            .scaledFont(13, weight: .medium)
                            .foregroundStyle(Theme.ink)
                            .frame(width: 180 * scale, alignment: .leading)
                        ScorePips(score: d.score, size: 11)
                        Spacer()
                        if let c = change(for: d.dimension) { DeltaBadge(change: c) }
                        Text(d.score.map { "\($0)/10" } ?? d.status.label)
                            .scaledFont(13, weight: .semibold, design: .monospaced)
                            .foregroundStyle(d.band.map(Theme.color(for:)) ?? Theme.muted)
                    }
                }
            }
        }
    }

    private func bandSection(_ band: Band) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(band.heading)
                .scaledFont(13, weight: .bold, design: .monospaced)
                .foregroundStyle(Theme.color(for: band))
            let rows = card.dimensions(in: band)
            if rows.isEmpty {
                Text("No items.").scaledFont(12).foregroundStyle(Theme.muted)
            }
            ForEach(rows) { d in
                ReasonCard(result: d, change: change(for: d.dimension), note: card.deductionNote(for: d.dimension),
                           deductions: card.deductionAppliedTo == d.dimension ? card.deductions ?? [] : [],
                           footer: deepDiveFooter?(d.dimension), expanded: expandAll)
            }
        }
    }

    private var unassessedSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Not scored")
            ForEach(card.unassessed) { d in
                Text("\(d.dimension.title) — \(d.status.label). \(d.reason)")
                    .scaledFont(12).foregroundStyle(Theme.muted)
            }
        }
    }

    private var improvementPanel: some View {
        let imp = card.improvement
        return Panel(padding: 24) {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(text: "One improvement to make first")
                Text(imp.title).scaledFont(20, weight: .bold, design: .serif).foregroundStyle(Theme.ink)
                Text(markdown(imp.situation)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(imp.actions.enumerated()), id: \.offset) { i, action in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(i + 1)").scaledFont(12, weight: .bold, design: .monospaced).foregroundStyle(Theme.accent)
                            Text(markdown(action)).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if let instruction = imp.suggestedInstruction, !instruction.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Say this to your AI").scaledFont(10, weight: .semibold).foregroundStyle(Theme.muted)
                        Text(instruction)
                            .scaledFont(13, design: .monospaced)
                            .textSelection(.enabled)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.paper, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                labeled("Try it on", imp.tryItOn)
                labeled("Sign it helped", imp.signOfSuccess)
            }
        }
    }

    private var roadmapPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel(text: "AI-use improvement roadmap")
                ForEach(card.roadmap, id: \.stage) { stage in
                    HStack(alignment: .top, spacing: 14) {
                        Text("\(stage.stage)")
                            .scaledFont(18, weight: .bold, design: .monospaced)
                            .foregroundStyle(Theme.accent)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(markdown(stage.change)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                            Text(markdown(stage.result)).scaledFont(12).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private var scopePanel: some View {
        let sc = card.scope
        return VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Scope note")
            Text(sc.recordDates.map { "\($0.tool): \($0.sessions) sessions, \($0.from) → \($0.to)" }.joined(separator: " · "))
            Text("\(sc.sessionsExamined) sessions examined · \(sc.tasksCheckedInDetail) tasks checked in detail · \(String(format: "%.1f", sc.elapsedMinutes)) min · assessed \(sc.assessedAt) (\(sc.timeZone))")
            ForEach(sc.limits, id: \.self) { Text("– \($0)") }
            if let notes = record.instructions {
                Text("Scored with your notes: \(notes)")
            }
        }
        .scaledFont(10)
        .foregroundStyle(Theme.muted)
        .textSelection(.enabled)
    }

    private func labeled(_ label: String, _ text: String) -> some View {
        (Text(label + ": ").bold() + Text(markdown(text)))
            .scaledFont(12)
            .foregroundStyle(Theme.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

}

struct ReasonCard: View {
    var result: ScoreCard.DimensionResult
    var change: ScoreChange?
    /// e.g. the permission-bypass deduction taken off Security.
    var note: String?
    /// The permission-bypass deduction taken off this category, explained in the full reason.
    var deductions: [ScoreCard.Deduction] = []
    var footer: AnyView?
    @State private var expanded: Bool

    init(result: ScoreCard.DimensionResult, change: ScoreChange? = nil, note: String? = nil,
         deductions: [ScoreCard.Deduction] = [], footer: AnyView? = nil, expanded: Bool = false) {
        self.result = result
        self.change = change
        self.note = note
        self.deductions = deductions
        self.footer = footer
        _expanded = State(initialValue: expanded)
    }

    var body: some View {
        Panel(padding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(result.dimension.title).scaledFont(15, weight: .semibold).foregroundStyle(Theme.ink)
                    Spacer()
                    if let change { DeltaBadge(change: change) }
                    ScorePips(score: result.score, size: 8)
                    Text("\(result.score ?? 0)/10")
                        .scaledFont(13, weight: .bold, design: .monospaced)
                        .foregroundStyle(result.band.map(Theme.color(for:)) ?? Theme.muted)
                }
                Text(markdown(result.headline))
                    .scaledFont(14, weight: .semibold, design: .serif)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let note {
                    Text(note)
                        .scaledFont(11, weight: .semibold)
                        .foregroundStyle(Theme.color(for: .bottleneck))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let points = result.points, !points.isEmpty {
                    // Newer cards: headed points. Headings always show so the reason can be scanned;
                    // their bodies, the ending summary and the evidence open with "Read the full reason".
                    VStack(alignment: .leading, spacing: expanded ? 14 : 6) {
                        ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    if let tone = point.tone {
                                        Text(tone.emoji).scaledFont(12).accessibilityLabel(tone.rawValue)
                                    } else {
                                        Circle().fill(result.band.map(Theme.color(for:)) ?? Theme.muted).frame(width: 6, height: 6)
                                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                                    }
                                    Text(markdown(point.heading)).scaledFont(13, weight: .bold).foregroundStyle(Theme.ink)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                if expanded {
                                    // Regular-weight description directly under the bold heading, not indented.
                                    ReviewMarkdown(source: point.body)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                }
                if expanded {
                    if result.points?.isEmpty == false {
                        if let conclusion = result.conclusion, !conclusion.isEmpty {
                            Text(markdown(conclusion)).scaledFont(13, weight: .semibold).foregroundStyle(Theme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background((result.band.map(Theme.color(for:)) ?? Theme.muted).opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                                .textSelection(.enabled)
                        }
                    } else {
                        ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, p in
                            Text(markdown(p)).scaledFont(13).foregroundStyle(Theme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                    }
                    ForEach(Array(deductions.enumerated()), id: \.offset) { _, d in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Permission-bypass deduction · −\(d.points)")
                                .scaledFont(11, weight: .bold).foregroundStyle(Theme.color(for: .bottleneck))
                            Text(markdown(d.reason)).scaledFont(12).foregroundStyle(Theme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            ForEach(Array(d.evidence.enumerated()), id: \.offset) { _, e in
                                Text("\(e.tool) · \(String(e.sessionId.prefix(8))) · \(e.date) — \(e.note)")
                                    .scaledFont(11, design: .monospaced).foregroundStyle(Theme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.color(for: .bottleneck).opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                    }
                    if !result.evidence.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Evidence").scaledFont(10, weight: .semibold).foregroundStyle(Theme.muted)
                            ForEach(Array(result.evidence.enumerated()), id: \.offset) { _, e in
                                Text("\(e.tool) · \(String(e.sessionId.prefix(8))) · \(e.date) — \(e.note)")
                                    .scaledFont(11, design: .monospaced)
                                    .foregroundStyle(Theme.muted)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    // The Pro deep dive sits at the end of the full reason, so it only shows once expanded.
                    if let footer { footer }
                }
                Button(expanded ? "Show less" : "Read the full reason") {
                    withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() }
                }
                .buttonStyle(.link)
                .scaledFont(12)
            }
        }
    }

    private var paragraphs: [String] {
        result.reason.components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}

/// "▲2" / "▼1" next to a score. Grey with a "?" when the judge gave no reason for the move.
struct DeltaBadge: View {
    var change: ScoreChange

    var body: some View {
        let delta = change.delta ?? 0
        let text = change.delta == nil ? "new" : "\(delta > 0 ? "▲" : "▼")\(abs(delta))\(change.isUnexplained ? "?" : "")"
        Text(text)
            .scaledFont(11, weight: .bold, design: .monospaced)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(change.isUnexplained ? Theme.muted : delta > 0 ? Theme.color(for: .strong) : Theme.color(for: .bottleneck))
            .background(Theme.paper, in: Capsule())
            .help(change.isUnexplained ? "Changed without new evidence: most likely scoring variation" : (change.reason ?? ""))
    }
}

public func markdown(_ s: String) -> AttributedString {
    (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
}
