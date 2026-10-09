import AppKit
import SwiftUI
import VibemetricCore

/// The review's deliberately small Markdown vocabulary, rendered with native views.
/// Old plain-text reviews remain readable; no web view or network content is loaded.
enum ReviewBlock: Equatable {
    case paragraph(String)
    case heading(String)
    case bullet(String)
    case code(String)
    case table(headers: [String], rows: [[String]])

    static func parse(_ source: String) -> [ReviewBlock] {
        let lines = source.components(separatedBy: .newlines)
        var blocks: [ReviewBlock] = [], index = 0
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            if line.isEmpty { index += 1; continue }
            if line.hasPrefix("```") {
                let marker = String(line.prefix(while: { $0 == "`" }))
                index += 1
                var content: [String] = []
                while index < lines.count && lines[index].trimmingCharacters(in: .whitespaces) != marker {
                    content.append(lines[index]); index += 1
                }
                blocks.append(.code(content.joined(separator: "\n")))
                if index < lines.count { index += 1 }
            } else if line.hasPrefix("- ") {
                blocks.append(.bullet(String(line.dropFirst(2))))
                index += 1
            } else if line.hasPrefix("#") && line.contains(" ") {
                blocks.append(.heading(String(line.drop(while: { $0 == "#" || $0 == " " }))))
                index += 1
            } else if line.hasPrefix("|"), index + 1 < lines.count,
                      cells(lines[index + 1]).allSatisfy({ $0.range(of: #"^:?-{3,}:?$"#, options: .regularExpression) != nil }),
                      !cells(lines[index + 1]).isEmpty {
                let headers = cells(line)
                index += 2
                var rows: [[String]] = []
                while index < lines.count && lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    let row = cells(lines[index])
                    rows.append(Array((row + Array(repeating: "", count: headers.count)).prefix(headers.count)))
                    index += 1
                }
                blocks.append(.table(headers: headers, rows: rows))
            } else {
                var paragraph = [lines[index]]
                index += 1
                while index < lines.count && !lines[index].trimmingCharacters(in: .whitespaces).isEmpty
                    && !lines[index].hasPrefix("```") && !lines[index].hasPrefix("#") && !lines[index].hasPrefix("|") && !lines[index].hasPrefix("- ") {
                    paragraph.append(lines[index]); index += 1
                }
                blocks.append(.paragraph(paragraph.joined(separator: "\n")))
            }
        }
        return blocks
    }

    private static func cells(_ line: String) -> [String] {
        var result: [String] = [], cell = "", escaped = false
        for character in line.trimmingCharacters(in: .whitespaces).dropFirst().dropLast() {
            if character == "|" && !escaped {
                result.append(cell.trimmingCharacters(in: .whitespaces)); cell = ""
            } else {
                cell.append(character)
            }
            escaped = character == "\\" && !escaped
        }
        result.append(cell.trimmingCharacters(in: .whitespaces))
        return result
    }
}

public struct ReviewMarkdown: View {
    var source: String
    var bodySize: CGFloat = 13
    @Environment(\.textScale) private var scale

    public init(source: String, bodySize: CGFloat = 13) {
        self.source = source
        self.bodySize = bodySize
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(ReviewBlock.parse(source).enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let text):
                    inline(text).scaledFont(bodySize).lineSpacing(bodySize > 13 ? 5 : 4)
                case .bullet(let text):
                    // A bullet that starts with ✅ ⚠️ ℹ️ shows that emoji in place of the dot.
                    let toned = ScoreCard.DimensionResult.Tone.leading(text)
                    HStack(alignment: .top, spacing: 8) {
                        if let toned {
                            Text(toned.tone.emoji).scaledFont(11).accessibilityLabel(toned.tone.rawValue)
                        } else {
                            Text("•").scaledFont(13).foregroundStyle(Theme.muted)
                        }
                        inline(toned.map { Self.boldLabel($0.rest) } ?? text).scaledFont(bodySize - 1).lineSpacing(bodySize > 13 ? 4 : 3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case .heading(let text):
                    inline(text).scaledFont(bodySize > 13 ? bodySize : 12, weight: .semibold).padding(.top, 2)
                case .code(let text):
                    ReviewCodeBlock(text: text)
                case .table(let headers, let rows):
                    ViewThatFits(in: .horizontal) {
                        table(headers: headers, rows: rows)
                            .frame(minWidth: 560 * scale, idealWidth: 560 * scale, maxWidth: .infinity)
                        compactTable(headers: headers, rows: rows)
                    }
                }
            }
        }
        .foregroundStyle(Theme.ink).tint(Theme.accent)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    /// "Demo web: CLAUDE.md has…" → "**Demo web:** CLAUDE.md has…": a short label before the
    /// first colon reads as the bullet's bold heading. Text already starting with bold is left alone.
    static func boldLabel(_ text: String) -> String {
        guard !text.hasPrefix("**"), let colon = text.firstIndex(of: ":") else { return text }
        let label = text[..<colon]
        guard !label.isEmpty, label.count <= 40, !label.contains("`"), !label.contains("http") else { return text }
        return "**\(label):**" + text[text.index(after: colon)...]
    }

    private func inline(_ source: String) -> Text {
        var value = markdown(source)
        for run in value.runs where run.inlinePresentationIntent?.contains(.code) == true {
            value[run.range].font = .system(size: 12 * scale, design: .monospaced)
        }
        return Text(value)
    }

    /// Columns size to their content (SwiftUI Grid). The first column stays narrow only when it holds
    /// ranks or numbers (as in the Pro review); text there gets up to 200pt and wraps beyond that.
    private func table(headers: [String], rows: [[String]]) -> some View {
        let numericFirst = !rows.isEmpty && rows.allSatisfy { Self.isRank($0.first ?? "") }
        let columns = headers.count
        // Columns of short values (counts, percentages, ratings) take only the width they need,
        // so the remaining width goes to the columns of longer text.
        let short = (0..<columns).map { c in ([headers] + rows).allSatisfy { ($0.count > c ? $0[c] : "").count <= 16 } }
        func padded(_ row: [String]) -> [String] { Array((row + Array(repeating: "", count: max(columns - row.count, 0))).prefix(columns)) }
        return Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                ForEach(Array(headers.enumerated()), id: \.offset) { index, cell in
                    tableCell(cell, column: index, header: true, numericFirst: numericFirst, short: short[index])
                        .background(Theme.paper.opacity(0.65))
                }
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                Divider().overlay(Theme.rule).gridCellUnsizedAxes(.horizontal)
                GridRow {
                    ForEach(Array(padded(row).enumerated()), id: \.offset) { index, cell in
                        tableCell(cell, column: index, header: false, numericFirst: numericFirst, short: short[index])
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.rule))
    }

    @ViewBuilder
    private func tableCell(_ cell: String, column: Int, header: Bool, numericFirst: Bool, short: Bool) -> some View {
        let text = inline(cell).scaledFont(header ? 10 : 12, weight: header ? .semibold : (column == 0 ? .semibold : .regular))
            .foregroundStyle(header ? Theme.muted : Theme.ink)
            .fixedSize(horizontal: false, vertical: true)
        Group {
            if column == 0 {
                text.frame(minWidth: numericFirst ? 28 * scale : nil, maxWidth: numericFirst ? 28 * scale : 200 * scale, alignment: .leading)
            } else if short {
                text.fixedSize(horizontal: true, vertical: false)
            } else {
                text.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 10)
        .padding(.leading, column == 0 ? 5 : 0)
    }

    /// "1", "#2", "3." — a rank or short number, the only thing a narrow first column suits.
    static func isRank(_ cell: String) -> Bool {
        cell.trimmingCharacters(in: .whitespaces).range(of: #"^#?\d{1,3}\.?$"#, options: .regularExpression) != nil
    }

    private func compactTable(headers: [String], rows: [[String]]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 { Divider().overlay(Theme.rule) }
                ForEach(Array(row.enumerated()), id: \.offset) { column, cell in
                    if column > 1 {
                        Text(headers[column]).scaledFont(10, weight: .semibold).foregroundStyle(Theme.muted)
                    }
                    inline(cell).scaledFont(column < 2 ? 12 : 11, weight: column < 2 ? .semibold : .regular)
                }
            }
        }.padding(12)
            .background(Theme.paper.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct ReviewCodeBlock: View {
    var text: String
    @State private var copied = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .scaledFont(10)
                }
                .buttonStyle(.borderless).foregroundStyle(Theme.muted)
                .help("Copy this command or prompt")
            }
            Text(text).scaledFont(11, design: .monospaced).lineSpacing(4)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.rule.opacity(0.8)))
        .onChange(of: text) { copied = false }
    }
}
