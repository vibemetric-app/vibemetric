import SwiftUI
import VibemetricCore

/// Places where an optional module adds screens and behavior to the app. Builds from source leave them all
/// empty, and the app then works on its own. Names describe where something attaches, never what it does.
/// Treat these as a stable interface: discuss before changing them.
@MainActor
public enum Extensions {
    /// Extra sidebar views next to "General". The tab picker appears only when this isn't empty.
    public static var sidebarTabs: [SidebarTabExtension] = []
    /// Shown under each category on the score card.
    public static var categoryFooter: (@MainActor (VibemetricCore.Dimension, CardRecord) -> AnyView)?
    /// Extra sections at the end of the score card.
    public static var cardSections: [@MainActor (CardRecord) -> AnyView] = []
    /// Extra sections in Settings, after the schedule.
    public static var settingsSections: [@MainActor () -> AnyView] = []
    /// Extra sentences for the home screen's "Vibemetric's server" privacy note.
    public static var privacyNotes: [String] = []
    /// Called when a score card becomes the selected one.
    public static var onCardSelected: [@MainActor (CardRecord) -> Void] = []
    /// Called after a score card is deleted.
    public static var onCardDeleted: [@MainActor (CardRecord) -> Void] = []
    /// Returns true while a module still needs this card, so it can't be deleted yet.
    public static var isCardInUse: [@MainActor (CardRecord) -> Bool] = []
    /// Work in progress that blocks a new scan; returns a short reason, or nil when idle.
    public static var busyReason: [@MainActor () -> String?] = []
    /// Handlers for notification clicks, keyed by the userInfo key they own. The value is that key's string.
    public static var notificationHandlers: [String: @MainActor (String) -> Void] = [:]

    /// Empties every plug-in point. For tests that register a module and must not leak it into other tests.
    static func reset() {
        sidebarTabs = []; categoryFooter = nil; cardSections = []; settingsSections = []; privacyNotes = []
        onCardSelected = []; onCardDeleted = []; isCardInUse = []; busyReason = []; notificationHandlers = [:]
    }

    /// The first reason any module is busy, or nil.
    static var currentBusyReason: String? { busyReason.lazy.compactMap { $0() }.first }
}

/// A sidebar view that a module adds next to "General", with the detail it shows.
public struct SidebarTabExtension: Identifiable {
    /// The tab's label, for example "Reports".
    public let id: String
    public let sidebar: @MainActor () -> AnyView
    public let detail: @MainActor () -> AnyView

    public init(id: String, sidebar: @escaping @MainActor () -> AnyView, detail: @escaping @MainActor () -> AnyView) {
        self.id = id
        self.sidebar = sidebar
        self.detail = detail
    }
}
