import AppKit
import UserNotifications
import VibemetricCore

/// macOS notifications when a score finishes or fails. Clicking one opens the result.
@MainActor
public final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    public static let shared = Notifier()
    static let enabledKey = "notifyWhenScored"

    static var isEnabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

    private let center = UNUserNotificationCenter.current()

    /// Call once at launch so clicks on notifications route back to the app.
    func install() {
        center.delegate = self
    }

    /// Asks for permission the first time a score starts, when the reason is obvious.
    public func requestPermissionIfNeeded() {
        guard Self.isEnabled else { return }
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    func scored(_ record: CardRecord, baseline: CardRecord?) {
        let content = UNMutableNotificationContent()
        let total = record.card.totalLabel ?? "—"
        var title = "AI Native Score: \(total)"
        if let base = baseline, let delta = ScoreChanges.totalDelta(record.card, to: base.card), delta != 0 {
            title += " (\(delta > 0 ? "+" : "")\(delta))"
        }
        content.title = title
        content.body = Self.body(record, baseline: baseline)
        content.sound = .default
        content.userInfo = ["recordId": record.id]
        post(content, id: record.id)
    }

    public func failed(_ message: String, automatic: Bool) {
        let content = UNMutableNotificationContent()
        content.title = automatic ? "Daily score didn't finish" : "Scoring didn't finish"
        content.body = message
        content.sound = .default
        post(content, id: "failed-\(Date().timeIntervalSince1970)")
    }

    /// "Planning & Specs 4 → 5, Safety & Cost 4 → 5" when dimensions moved with a reason; otherwise the next step.
    static func body(_ record: CardRecord, baseline: CardRecord?) -> String {
        if let base = baseline {
            let moved = ScoreChanges.compare(record.card, to: base.card).filter { !$0.isUnexplained }
            if !moved.isEmpty {
                return moved.prefix(3).map { "\($0.dimension.title) \($0.from.map(String.init) ?? "–") → \($0.to.map(String.init) ?? "–")" }
                    .joined(separator: ", ")
            }
            return "No change since your last score. Next: \(record.card.improvement.title)"
        }
        return "Next: \(record.card.improvement.title)"
    }

    /// A notification with a sound. A click on it goes to the `Extensions.notificationHandlers` entry
    /// for the first `userInfo` key that has one.
    public func post(title: String, body: String, userInfo: [String: String] = [:], id: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = userInfo
        post(content, id: id)
    }

    private func post(_ content: UNMutableNotificationContent, id: String) {
        guard Self.isEnabled else { return }
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    // Show banners even while Vibemetric is the active app.
    public nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    // Clicking the notification opens the result it's about.
    public nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let id = info["recordId"] as? String
        var strings: [String: String] = [:]
        for case let (key as String, value as String) in info { strings[key] = value }
        Task { @MainActor in
            guard let model = AppModel.shared else { return }
            if let (handler, value) = Extensions.notificationHandlers.lazy.compactMap({ key, handler in
                strings[key].map { (handler, $0) } }).first {
                handler(value)
                return
            }
            model.showMainWindow(selectLatest: true)
            if let id, let record = model.history.first(where: { $0.id == id }) { model.selected = record }
        }
        completionHandler()
    }
}
