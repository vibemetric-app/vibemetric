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
            if let share = ShareCard.png(card: card, date: Date()) { try share.write(to: dir.appendingPathComponent("share.png")) }
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
        renderer.scale = 1
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
