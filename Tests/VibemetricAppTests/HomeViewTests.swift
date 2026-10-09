import AppKit
import SwiftUI
import Testing
@testable import VibemetricCore
@testable import VibemetricAppKit

@Suite(.serialized)
@MainActor
struct HomeViewTests {
    @Test(arguments: [false, true])
    func searchPausesInBackgroundAndHonorsReducedMotion(isCompact: Bool) throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: isCompact ? 22 : 340,
                                                height: isCompact ? 18 : 174),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let search = HistorySearchLayerView(frame: window.contentLayoutRect, isCompact: isCompact)
        window.contentView = search
        search.layoutSubtreeIfNeeded()
        let track = try #require(search.layer?.sublayers?.first)
        search.configure(reduceMotion: false, isActive: true)
        #expect(track.speed == 1)
        search.configure(reduceMotion: false, isActive: false)
        #expect(track.speed == 0)
        search.configure(reduceMotion: true, isActive: true)
        #expect(track.sublayers?.allSatisfy { ($0.animationKeys() ?? []).isEmpty } == true)
        search.configure(reduceMotion: false, isActive: true)
        #expect(track.speed == 1)
        #expect(track.sublayers?.contains { !($0.animationKeys() ?? []).isEmpty } == true)
        search.removeFromSuperview()
        #expect(track.sublayers?.allSatisfy { ($0.animationKeys() ?? []).isEmpty } == true)
    }

    @Test func searchLoopHasNoHoldsOrVisibleSeamAndKeepsItsClockOnResize() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 174),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let search = HistorySearchLayerView(frame: window.contentLayoutRect)
        window.contentView = search
        search.layoutSubtreeIfNeeded()
        let layers = try #require(search.layer?.sublayers?.first?.sublayers)
        let file = try #require(layers.first)
        let fileAnimation = try #require(file.animation(forKey: "history-search") as? CAAnimationGroup)
        let movement = try #require(fileAnimation.animations?.first as? CAKeyframeAnimation)
        let transforms = try #require(movement.values as? [NSValue]).map(\.caTransform3DValue)
        // Any repeated X value would reintroduce the visible stop-and-go rhythm.
        for (before, after) in zip(transforms, transforms.dropFirst()) {
            #expect(after.m41 < before.m41)
        }
        let fade = try #require(fileAnimation.animations?.last as? CAKeyframeAnimation)
        let opacity = try #require(fade.values as? [NSNumber])
        #expect(opacity.first?.doubleValue == 0)
        #expect(opacity.last?.doubleValue == 0)

        let lens = try #require(layers.first { $0.name == "search-lens" })
        let lensAnimation = try #require(lens.animation(forKey: "history-search") as? CAKeyframeAnimation)
        let orbit = try #require(lensAnimation.values as? [NSValue]).map(\.caTransform3DValue)
        let first = try #require(orbit.first)
        let last = try #require(orbit.last)
        #expect(hypot(first.m41 - last.m41, first.m42 - last.m42) < 0.001)
        let outgoing = CGPoint(x: orbit[1].m41 - first.m41, y: orbit[1].m42 - first.m42)
        let incoming = CGPoint(x: last.m41 - orbit[orbit.count - 2].m41,
                               y: last.m42 - orbit[orbit.count - 2].m42)
        #expect(hypot(outgoing.x - incoming.x, outgoing.y - incoming.y) < 0.06)

        search.setFrameSize(NSSize(width: 300, height: 174))
        search.layoutSubtreeIfNeeded()
        #expect(lens.animation(forKey: "history-search")?.beginTime == lensAnimation.beginTime)
        #expect(file.animation(forKey: "history-search")?.beginTime == fileAnimation.beginTime)
    }

    /// Opt-in visual evidence uses fictional summary data and never runs a CLI or reads history.
    @Test func homeSnapshots() async throws {
        guard let output = ProcessInfo.processInfo.environment["VIBEMETRIC_UI_SNAPSHOTS"] else { return }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let cases: [(String, CGFloat, CGFloat, ColorScheme, CGFloat)] = [
            ("codex-light", 1100, 800, .light, 1),
            ("claude-light", 1100, 800, .light, 1),
            ("codex-dark", 1100, 800, .dark, 1),
            ("narrow", 600, 1250, .light, 1),
            ("large-text", 900, 1600, .light, 1.5),
            ("refreshing", 1100, 800, .light, 1),
            ("missing-engine", 1100, 900, .light, 1),
            ("empty-history", 1100, 800, .light, 1),
            ("initial-loading", 1100, 800, .light, 1),
            ("initial-loading-dark", 1100, 800, .dark, 1),
            ("initial-loading-narrow", 600, 1250, .light, 1),
        ]
        for (name, width, height, scheme, scale) in cases {
            let fixture = HomeFixture()
            defer { fixture.cleanUp() }
            if name == "claude-light" { fixture.model.engine = .claude }
            if name == "refreshing" {
                fixture.model.isScanning = true
                fixture.model.isCheckingEngines = true
            }
            if name == "missing-engine" {
                fixture.model.installations = [:]
                fixture.model.installationErrors[.codex] = "Update Codex CLI to use scoring, then check installation again."
            }
            if name == "empty-history" {
                fixture.model.summary = ScanSummary(ScanResult(sessions: [], sources: [], duration: 0))
            }
            if name.hasPrefix("initial-loading") {
                fixture.model.summary = nil
                fixture.model.isScanning = true
                fixture.model.installations = [:]
                fixture.model.isCheckingEngines = true
            }
            let window = fixture.window(width: width, height: height, scheme: scheme, scale: scale)
            defer { window.close() }
            await settle(window)
            let content = try #require(window.contentView)
            let bitmap = try #require(content.bitmapImageRepForCachingDisplay(in: content.bounds))
            content.cacheDisplay(in: content.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: directory.appendingPathComponent("\(name).png"))
            #expect(content.fittingSize.width <= width + 1)
        }
    }

    private func settle(_ window: NSWindow) async {
        for _ in 0..<4 {
            window.contentView?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            try? await Task.sleep(for: .milliseconds(40))
        }
    }

    private func findScrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        return view.subviews.lazy.compactMap { findScrollView(in: $0) }.first
    }

    private func findSearchAnimation(in view: NSView) -> HistorySearchLayerView? {
        if let search = view as? HistorySearchLayerView { return search }
        return view.subviews.lazy.compactMap { findSearchAnimation(in: $0) }.first
    }
}

@MainActor
private final class HomeFixture {
    private let preferenceName = "vibemetric-home-tests-\(UUID())"
    let preferences: UserDefaults
    let model: AppModel

    init() {
        preferences = UserDefaults(suiteName: preferenceName)!
        preferences.set(false, forKey: AutoSettings.enabledKey)
        model = AppModel(preferences: preferences, startAutomatically: false, history: [])
        model.engine = .codex
        model.codexModel = .astra
        model.scan = ScanResult(sessions: [], sources: [], duration: 0)
        var summary = ScanSummary(model.scan!)
        summary.total = 4_001
        summary.byTool = [(.claudeCode, 2_960), (.codex, 1_041)]
        summary.projects = 1_887
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2026, month: 7, day: 23))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 9, day: 30))!
        summary.range = start...end
        model.summary = summary
        model.installations = [
            .codex: CLIInstallation(executable: URL(fileURLWithPath: "/fixture/codex"), version: "codex-cli 0.145.0"),
            .claude: CLIInstallation(executable: URL(fileURLWithPath: "/fixture/claude"), version: "2.1.265 (Claude Code)"),
        ]
    }

    func cleanUp() { preferences.removePersistentDomain(forName: preferenceName) }

    func window(width: CGFloat, height: CGFloat, scheme: ColorScheme = .light, scale: CGFloat = 1) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        let view = HomeView()
            .environment(model)
            .environment(\.textScale, scale)
            .environment(\.colorScheme, scheme)
            .defaultAppStorage(preferences)
            .background(Theme.paper)
        window.contentView = NSHostingView(rootView: view)
        window.contentView?.setFrameSize(NSSize(width: width, height: height))
        return window
    }
}

private actor HomeScanGate {
    private var continuation: CheckedContinuation<ScanResult, Never>?
    private var finished = false

    func wait() async -> ScanResult {
        if finished { return ScanResult(sessions: [], sources: [], duration: 1) }
        return await withCheckedContinuation { continuation = $0 }
    }

    func finish() {
        finished = true
        continuation?.resume(returning: ScanResult(sessions: [], sources: [], duration: 1))
        continuation = nil
    }
}
