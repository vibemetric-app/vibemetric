import Foundation

/// Release and dev builds use separate bundle IDs (set by `scripts/build-app.sh`), so each has its own
/// preferences, Keychain item, data folders and privacy answers.
public enum AppVariant {
    public static let prodBundleID = "app.vibemetric.prod"
    public static let devBundleID = "app.vibemetric.dev"
    /// Builds before the prod/dev split used this ID.
    public static let legacyBundleID = "dev.vibemetric.app"

    public static var isDev: Bool { Bundle.main.bundleIdentifier == devBundleID }

    /// Shows Pro (the Categories tab, deep dives and the Pro key in Settings). On in every build since 0.1.2;
    /// `PRO_ENABLED=0 scripts/build-app.sh` hides it. `swift run` has no Info.plist and shows Pro.
    public static let proEnabled = Bundle.main.object(forInfoDictionaryKey: "VMProEnabled") as? Bool ?? true

    private static let migratedKey = "legacyBundleIDMigrated"

    /// On the first launch of the release build, copies the preferences from the legacy bundle ID once,
    /// so updating from an older build keeps them. Modules copy their own Keychain items.
    static func migrateLegacySettings() {
        guard Bundle.main.bundleIdentifier == prodBundleID else { return }
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migratedKey) else { return }
        defaults.set(true, forKey: migratedKey)
        if let old = defaults.persistentDomain(forName: legacyBundleID) {
            // Login items are registered per bundle ID, so the new ID registers its own once.
            // An API override was a development setting; the dev build now uses the develop API by default.
            let skipped: Set<String> = ["launchAtLoginDefaultApplied", "apiBaseURL"]
            for (key, value) in old where !skipped.contains(key) && defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
        }
    }
}
