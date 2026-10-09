import Foundation

/// Renders a `ScoreCard` in the Markdown card format the assessment spec defines.
public enum MarkdownRenderer {
    public static func render(_ card: ScoreCard, previous: ScoreCard? = nil, previousDate: String? = nil) -> String {
        var md = "# AI NATIVE SCORE\n\n"
        md += card.totalLabel.map { "## \($0) / 100\n\n" } ?? "## No score could be established\n\n"
        if card.totalDeductionPoints > 0 {
            for d in card.deductions ?? [] { md += "_Includes a −\(d.points) point deduction: \(d.reason)_\n\n" }
        }
        md += card.diagnosis + "\n\n"
        if let previous { md += changesSection(card, previous: previous, previousDate: previousDate) }

        for band in Band.displayOrder {
            md += "### \(band.heading)\n\n"
            let rows = card.dimensions(in: band)
            if rows.isEmpty {
                md += "No items.\n\n"
                continue
            }
            md += "| Dimension | Score | Reason |\n| --- | --- | --- |\n"
            for d in rows {
                var reason = "**\(d.headline)** " + (d.points?.isEmpty == false ? pointsCell(d) : d.reason)
                if let note = card.deductionNote(for: d.dimension) {
                    reason += " _" + note + " " + (card.deductions ?? []).map(\.reason).joined(separator: " ") + "_"
                }
                if !d.evidence.isEmpty {
                    reason += " _Evidence: " + d.evidence.map { "\($0.tool) \($0.sessionId.prefix(8)) (\($0.date)): \($0.note)" }.joined(separator: "; ") + "_"
                }
                md += "| \(d.dimension.title) | \(d.score ?? 0)/10 | \(cell(reason)) |\n"
            }
            md += "\n"
        }
        if !card.unassessed.isEmpty {
            md += "**Not scored:** " + card.unassessed.map { "\($0.dimension.title) — \($0.status.label)" }.joined(separator: "; ") + "\n\n"
        }

        md += "### 10 DIMENSIONS\n\n| Dimension | Progress | Score |\n| --- | --- | ---: |\n"
        for d in card.ordered {
            if let s = d.score {
                md += "| \(d.dimension.title) | `\(progress(s))` | \(s)/10 |\n"
            } else {
                md += "| \(d.dimension.title) | — | \(d.status.label) |\n"
            }
        }


        let imp = card.improvement
        md += "\n### One improvement to make first\n\n**\(imp.title)**\n\n\(imp.situation)\n\n"
        for (i, a) in imp.actions.enumerated() { md += "\(i + 1). \(a)\n" }
        if let instruction = imp.suggestedInstruction, !instruction.isEmpty {
            md += "\nSuggested instruction for your AI:\n\n> \(instruction)\n"
        }
        md += "\n**Try it on:** \(imp.tryItOn)\n\n**Sign it helped:** \(imp.signOfSuccess)\n\n"

        md += "### AI-use improvement roadmap\n\n| Stage | Change in AI use | Observable result |\n| --- | --- | --- |\n"
        for r in card.roadmap { md += "| \(r.stage) | \(cell(r.change)) | \(cell(r.result)) |\n" }

        let sc = card.scope
        md += "\n### Scope note\n\n"
        md += "Assessed \(sc.assessedAt) (\(sc.timeZone)). "
        md += sc.recordDates.map { "\($0.tool): \($0.sessions) sessions, \($0.from) → \($0.to)" }.joined(separator: "; ") + ". "
        md += "\(sc.sessionsExamined) unique sessions examined, \(sc.tasksCheckedInDetail) tasks checked in detail, "
        md += String(format: "%.1f minutes elapsed.", sc.elapsedMinutes)
        if !sc.limits.isEmpty { md += " Limits: " + sc.limits.joined(separator: " ") }
        return md + "\n"
    }

    static func changesSection(_ card: ScoreCard, previous: ScoreCard, previousDate: String?) -> String {
        let since = previousDate.map { " (\($0))" } ?? ""
        var md = "### Changes since the previous assessment\(since)\n\n"
        if let delta = ScoreChanges.totalDelta(card, to: previous) {
            md += "Total: \(previous.knownTotal) → \(card.knownTotal) (\(delta >= 0 ? "+" : "")\(delta)).\n\n"
        }
        let changes = ScoreChanges.compare(card, to: previous)
        if changes.isEmpty { return md + "No dimension changed.\n\n" }
        md += "| Dimension | Change | Why |\n| --- | --- | --- |\n"
        for c in changes {
            let why = c.isUnexplained ? "No new evidence cited; likely scoring variation." : c.reason!
            md += "| \(c.dimension.title) | \(c.from.map(String.init) ?? "–") → \(c.to.map(String.init) ?? "–") | \(cell(why)) |\n"
        }
        return md + "\n"
    }

    public static func progress(_ score: Int) -> String {
        let s = min(max(score, 0), 10)
        return String(repeating: "●", count: s) + String(repeating: "○", count: 10 - s)
    }

    /// Headed points inside one table cell: each point on its own line, bullets kept as "•" lines.
    private static func pointsCell(_ d: ScoreCard.DimensionResult) -> String {
        func flatten(_ body: String) -> String {
            body.split(separator: "\n").map { line in
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("- ") || t.hasPrefix("* ") {
                    let item = String(t.dropFirst(2))
                    if ScoreCard.DimensionResult.Tone.leading(item) != nil { return "<br>" + item }
                    return "<br>• " + item
                }
                return " " + t
            }.joined().trimmingCharacters(in: .whitespaces)
        }
        var parts = (d.points ?? []).map { "<br><br>" + ($0.tone.map { $0.emoji + " " } ?? "") + "**\($0.heading)**<br>" + flatten($0.body) }
        if let conclusion = d.conclusion, !conclusion.isEmpty { parts.append("<br><br>_\(conclusion)_") }
        return parts.joined()
    }

    private static func cell(_ s: String) -> String {
        s.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n\n", with: "<br><br>").replacingOccurrences(of: "\n", with: " ")
    }
}
