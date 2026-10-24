import AppKit
import UserNotifications
import SwiftUI
import VibemetricCore

/// Development aid: `VIBEMETRIC_SNAPSHOT=<out dir> VIBEMETRIC_CARD=<card.json>` renders the result
/// views to PNG and exits, so layout can be checked without clicking through the app.
enum Snapshot {
    /// `VIBEMETRIC_TEST_NOTIFICATION=1` posts the "score finished" notification for the latest
    /// saved result, then exits, so notifications can be checked without a scoring run.
    @MainActor
    static func notificationTestIfRequested() {
        guard ProcessInfo.processInfo.environment["VIBEMETRIC_TEST_NOTIFICATION"] != nil else { return }
        let history = Store.load()
        guard let latest = history.first else { print("No saved results"); exit(1) }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            print("Notifications allowed: \(granted) \(error.map { String(describing: $0) } ?? "")")
            // Exit from a background timer: the main run loop isn't fully up this early in launch.
            Task { @MainActor in Notifier.shared.scored(latest, baseline: history.dropFirst().first) }
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) { exit(0) }
        }
        RunLoop.main.run()
    }

    @MainActor
    static func runIfRequested() {
        let env = ProcessInfo.processInfo.environment
        guard let out = env["VIBEMETRIC_SNAPSHOT"], let cardPath = env["VIBEMETRIC_CARD"] else { return }
        do {
            let card = try JSONDecoder().decode(ScoreCard.self, from: Data(contentsOf: URL(fileURLWithPath: cardPath)))
            let record = CardRecord(id: "snapshot", createdAt: Date(), model: nil, sessionsScanned: 0, elapsed: 0, card: card)
            // Optional VIBEMETRIC_BASELINE=<card.json> renders the "what changed" section too.
            let baseline = try env["VIBEMETRIC_BASELINE"].map {
                CardRecord(id: "baseline", createdAt: Date().addingTimeInterval(-3600), model: nil, sessionsScanned: 0, elapsed: 0,
                           card: try JSONDecoder().decode(ScoreCard.self, from: Data(contentsOf: URL(fileURLWithPath: $0))))
            }
            let dir = URL(fileURLWithPath: out)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for scheme in [ColorScheme.light, .dark] {
                let view = CardContent(record: record, baseline: baseline, expandAll: true)
                    .frame(width: 860)
                    .background(Theme.paper)
                    .environment(\.colorScheme, scheme)
                try render(view, scheme: scheme).write(to: dir.appendingPathComponent("card-\(scheme == .light ? "light" : "dark").png"))
            }
            // The same card with every category collapsed, as people first see it.
            // VIBEMETRIC_SNAPSHOT_TEXT_SCALE=1.75 renders the collapsed card at that text size (View > text size).
            let textScale = env["VIBEMETRIC_SNAPSHOT_TEXT_SCALE"].flatMap(Double.init).map { CGFloat($0) } ?? 1
            for scheme in [ColorScheme.light, .dark] {
                let collapsed = CardContent(record: record, baseline: baseline, expandAll: false)
                    .environment(\.textScale, textScale)
                    .frame(width: 860 * max(1, textScale)).background(Theme.paper).environment(\.colorScheme, scheme)
                try render(collapsed, scheme: scheme)
                    .write(to: dir.appendingPathComponent("card-collapsed-\(scheme == .light ? "light" : "dark").png"))
            }
            if let share = ShareCard.png(card: card, date: Date()) { try share.write(to: dir.appendingPathComponent("share.png")) }
            // The menu bar panel for the same card, in a throwaway preferences domain.
            let suite = "vibemetric-snapshot-\(UUID())"
            if let defaults = UserDefaults(suiteName: suite) {
                defaults.set(false, forKey: AutoSettings.enabledKey)
                let model = AppModel(preferences: defaults, startAutomatically: false, history: [record] + (baseline.map { [$0] } ?? []))
                for scheme in [ColorScheme.light, .dark] {
                    let panel = MenuBarPanel().environment(model).background(scheme == .dark ? Color(white: 0.17) : Color(white: 0.93))
                        .environment(\.colorScheme, scheme)
                    try render(panel, scheme: scheme).write(to: dir.appendingPathComponent("menubar-\(scheme == .light ? "light" : "dark").png"))
                }
                // The running screen partway through reading: 23 of 70 digests, 3 minutes in.
                let now = Date()
                model.runStarted = now.addingTimeInterval(-185)
                model.progress = ScoreProgress(started: now.addingTimeInterval(-185))
                model.progress.startReading(digests: EvidencePack.maxDigests, at: now.addingTimeInterval(-170))
                for i in 0..<23 { model.progress.noteRead("Read cc-\(i)a1b2c3d4.md") }
                model.activity = ["Claude Code is reading your evidence pack…", "Read overview.md", "Read leads.md", "Read cc-0a1b2c3d4.md"]
                    .enumerated().map { AppModel.Activity(text: $0.element, isThought: $0.offset == 0) }
                for scheme in [ColorScheme.light, .dark] {
                    let running = RunningView().environment(model).frame(width: 860, height: 520).background(Theme.paper)
                        .environment(\.colorScheme, scheme)
                    try render(running, scheme: scheme).write(to: dir.appendingPathComponent("running-\(scheme == .light ? "light" : "dark").png"))
                }
                // The start screen when Claude Code can't score: not installed (Codex ready), then signed out.
                let codex = CLIInstallation(executable: URL(fileURLWithPath: "/usr/local/bin/codex"), version: "codex-cli 0.163.0")
                let claude = CLIInstallation(executable: URL(fileURLWithPath: "/usr/local/bin/claude"), version: "2.1.308 (Claude Code)")
                model.selected = nil
                model.engine = .claude
                for (label, checks) in [("missing", [(AssessmentEngine.claude, CLIInstallation?.none, Bool?.none, String?.none),
                                                     (.codex, codex, true, nil)]),
                                        ("signedout", [(.claude, claude, false, nil), (.codex, nil, nil, nil)])] {
                    model.applyEngineChecks(checks)
                    for scheme in [ColorScheme.light, .dark] {
                        // The picker alone: ImageRenderer leaves a ScrollView, and so all of HomeView, blank.
                        let home = AssessmentEnginePicker(compact: true, showsDetails: false).environment(model)
                            .padding(24).frame(width: 760).background(Theme.paper)
                            .environment(\.colorScheme, scheme)
                        try render(home, scheme: scheme).write(to: dir.appendingPathComponent("home-\(label)-\(scheme == .light ? "light" : "dark").png"))
                    }
                }
                defaults.removePersistentDomain(forName: suite)
            }
            print("Snapshots written to \(dir.path)")
            exit(0)
        } catch {
            print("Snapshot failed: \(error)")
            exit(1)
        }
    }

    @MainActor
    private static func render(_ view: some View, scheme: ColorScheme) throws -> Data {
        let renderer = ImageRenderer(content: view)
        // VIBEMETRIC_SNAPSHOT_SCALE=2 renders at Retina resolution, for README and website images.
        renderer.scale = ProcessInfo.processInfo.environment["VIBEMETRIC_SNAPSHOT_SCALE"].flatMap(Double.init) ?? 1
        // NSColor dynamic providers resolve against the current appearance, so set it explicitly.
        NSApplication.shared.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        var data: Data?
        NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            if let img = renderer.nsImage, let tiff = img.tiffRepresentation {
                data = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
            }
        }
        guard let data else { throw CocoaError(.fileWriteUnknown) }
        return data
    }
}
