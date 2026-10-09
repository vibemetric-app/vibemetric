import Foundation
import ServiceManagement
import VibemetricCore

/// Preferences for the daily automatic score. Views bind to the same keys with @AppStorage.
enum AutoSettings {
    static let enabledKey = "autoScoreEnabled"
    static let minuteKey = "autoScoreMinute"
    static let skipIdleKey = "autoScoreSkipWhenIdle"
    static let lastAttemptKey = "autoScoreLastAttempt"
    static let lastStatusKey = "autoScoreLastStatus"

    static var schedule: AutoSchedule {
        let d = UserDefaults.standard
        return AutoSchedule(
            enabled: d.object(forKey: enabledKey) as? Bool ?? true,
            minuteOfDay: d.object(forKey: minuteKey) as? Int ?? AutoSchedule.defaultMinuteOfDay
        )
    }

    static var skipWhenIdle: Bool { UserDefaults.standard.object(forKey: skipIdleKey) as? Bool ?? true }
}

/// "Open at login", via the system's login items (System Settings → General → Login Items).
enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }

    private static let defaultAppliedKey = "launchAtLoginDefaultApplied"

    /// On by default: turned on once, on the first launch. If the user turns it off later,
    /// it stays off. Only applies to the installed app, not `swift run` builds.
    static func enableOnFirstLaunch() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: defaultAppliedKey), Bundle.main.bundlePath.hasSuffix(".app") else { return }
        defaults.set(true, forKey: defaultAppliedKey)
        try? set(true)
    }
}
