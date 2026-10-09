import Foundation
import VibemetricCore

let args = Array(CommandLine.arguments.dropFirst())
let command = args.first ?? "help"

func value(_ flag: String) -> String? {
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
    return args[i + 1]
}

switch command {
case "scan":
    let scan = Scanner.scan()
    print("Scanned \(scan.sessions.count) sessions in \(String(format: "%.2f", scan.duration))s")
    for tool in AgentTool.allCases {
        print("  \(tool.rawValue): \(scan.sessions(for: tool).count)")
    }
    print("  projects: \(scan.projects.joined(separator: ", "))")

case "pack":
    let dir = URL(fileURLWithPath: value("--out") ?? "vibemetric-evidence")
    let scan = Scanner.scan()
    try EvidencePack.write(scan, to: dir, contextFiles: RuleFiles.snapshot(scan: scan))
    print("Wrote evidence pack for \(scan.sessions.count) sessions to \(dir.path)")

case "assess":
    let engineName = value("--engine") ?? "claude"
    guard let engine = AssessmentEngine(rawValue: engineName) else {
        FileHandle.standardError.write(Data("Unknown engine: \(engineName). Use claude or codex.\n".utf8))
        exit(2)
    }
    let dir = URL(fileURLWithPath: value("--out") ?? NSTemporaryDirectory() + "vibemetric-\(Int(Date().timeIntervalSince1970))")
    let scan = Scanner.scan()
    // --previous card.json anchors scores to an earlier run; its file date marks "since".
    let previous: EvidencePack.Previous? = try value("--previous").map { path in
        let url = URL(fileURLWithPath: path)
        let card = try JSONDecoder().decode(ScoreCard.self, from: Data(contentsOf: url))
        let date = (try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? Date()
        return EvidencePack.Previous(card: card, date: date)
    }
    // The CLI keeps no snapshots, so rule changes fall back to files modified since the previous card.
    let rules = RuleFiles.snapshot(scan: scan)
    let ruleChanges = previous.map { RuleFiles.changesReport(current: rules, previous: nil, since: $0.date) }
    try EvidencePack.write(scan, to: dir, previous: previous, ruleChanges: ruleChanges, contextFiles: rules)
    FileHandle.standardError.write(Data("Evidence pack: \(dir.path) (\(scan.sessions.count) sessions). Running \(engine.name)…\n".utf8))
    let outcome = try await Assessor().run(packDir: dir, sources: scan.sources, options: AssessmentOptions(engine: engine, model: value("--model")),
                                           previousDate: previous?.date) { event in
        switch event {
        case .started: FileHandle.standardError.write(Data("  started\n".utf8))
        case let .reading(what): FileHandle.standardError.write(Data("  · \(what)\n".utf8))
        case let .thinking(text): FileHandle.standardError.write(Data("  » \(text)\n".utf8))
        }
    }
    try outcome.rawJSON.write(to: dir.appendingPathComponent("card.json"))
    let md = MarkdownRenderer.render(outcome.card, previous: previous?.card)
    try md.write(to: dir.appendingPathComponent("card.md"), atomically: true, encoding: .utf8)
    print(md)
    let cost = outcome.costUSD.map { String(format: "$%.2f", $0) } ?? "cost not reported"
    FileHandle.standardError.write(Data(String(format: "Done with %@ in %.1f min (%@). Saved card.json and card.md in %@\n",
        engine.name, outcome.elapsed / 60, cost, dir.path).utf8))

default:
    print("""
    usage: vibemetric <command>

      scan                 Parse local transcripts and print counts
      pack [--out DIR]     Write the redacted evidence pack the assessor reads
      assess [--engine claude|codex] [--model M] [--out DIR] [--previous card.json]
                           Build the pack, run the selected local CLI, and print the card
    """)
}
