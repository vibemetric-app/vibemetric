import AppKit
import SwiftUI
import VibemetricCore

/// The menu bar item. Left-click shows the score panel; right-click shows a menu with the
/// less frequent actions (copy report, settings, quit). SwiftUI's MenuBarExtra can't tell the
/// two clicks apart, hence NSStatusItem.
@MainActor
final class StatusItemController: NSObject {
    private let model: AppModel
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()

    init(model: AppModel) {
        self.model = model
        super.init()

        popover.behavior = .transient
        let host = NSHostingController(rootView: StatusPanelRoot(model: model) { [weak self] in
            self?.popover.performClose(nil)
        })
        // Size the popover from the panel's own fixed width, never from a long line of text.
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host

        if let button = item.button {
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        refreshLabel()
    }

    /// Redraws the label whenever the latest score or the running state changes.
    private func refreshLabel() {
        withObservationTracking {
            let running = model.isRunning
            let score = model.history.first?.card.totalLabel
            let button = item.button
            if running {
                button?.image = MenuBarLabel.statusImage(symbol: "gauge.with.dots.needle.33percent", text: "Scoring…")
                button?.setAccessibilityLabel("Vibemetric: scoring")
            } else if let score {
                button?.image = MenuBarLabel.statusImage(symbol: "gauge.with.dots.needle.67percent", text: score)
                button?.setAccessibilityLabel("AI Native Score \(score)")
            } else {
                button?.image = MenuBarLabel.statusImage(symbol: "gauge.with.dots.needle.0percent", text: "")
                button?.setAccessibilityLabel("Vibemetric")
            }
        } onChange: {
            Task { @MainActor [weak self] in self?.refreshLabel() }
        }
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            togglePanel(sender)
        }
    }

    private func togglePanel(_ button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showMenu() {
        popover.performClose(nil)
        let menu = NSMenu()
        menu.addItem(entry("Open Vibemetric", #selector(openApp)))
        let score = entry(model.isRunning ? "Scoring…" : "Score Now", #selector(scoreNow))
        score.isEnabled = model.canStartAssessment
        menu.addItem(score)
        let copy = entry("Copy Report", #selector(copyReport))
        copy.isEnabled = model.history.first != nil
        menu.addItem(copy)
        menu.addItem(.separator())
        menu.addItem(entry("Settings…", #selector(openSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(entry("Quit Vibemetric", #selector(quit), key: "q"))
        // Show the menu under the item, then detach it so left-clicks keep opening the panel.
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    private func entry(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menuItem.target = self
        return menuItem
    }

    @objc private func openApp() { model.showMainWindow(selectLatest: true) }

    @objc private func scoreNow() {
        model.startAssessment()
        model.showMainWindow(selectLatest: false)
    }

    @objc private func copyReport() { model.copyLatestReport() }

    @objc private func openSettings() { AppModel.openSettings() }

    @objc private func quit() { NSApp.terminate(nil) }
}

/// Supplies the model and text zoom to the panel inside the popover.
private struct StatusPanelRoot: View {
    let model: AppModel
    let close: () -> Void
    @AppStorage(TextScale.storageKey) private var textScale = 1.0
    static let maxScale = 1.25

    var body: some View {
        MenuBarPanel(close: close)
            .environment(model)
            // The panel drops from the menu bar, so it can't grow with the main window's zoom.
            .environment(\.textScale, min(textScale, Self.maxScale))
    }
}
