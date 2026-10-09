import Sparkle

/// Automatic updates through Sparkle. Starts only in a bundle that has a feed URL and a public key
/// (`scripts/build-app.sh` adds both to release builds), so `swift run` and dev builds never check for updates.
@MainActor
final class AppUpdater {
    static let shared = AppUpdater()

    private let controller: SPUStandardUpdaterController?

    private init() {
        let info = Bundle.main.infoDictionary ?? [:]
        let configured = info["SUFeedURL"] != nil && info["SUPublicEDKey"] != nil
        controller = configured ? SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil) : nil
    }

    var isEnabled: Bool { controller != nil }

    func checkForUpdates() { controller?.checkForUpdates(nil) }
}
