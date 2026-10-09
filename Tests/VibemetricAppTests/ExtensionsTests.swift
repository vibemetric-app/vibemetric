import Foundation
import SwiftUI
import Testing
@testable import VibemetricCore
@testable import VibemetricAppKit

/// The plug-in points: empty in a build without Pro, filled by the Pro registration, and respected by the app.
@Suite(.serialized)
@MainActor
struct ExtensionsTests {
    private func makeModel() throws -> (AppModel, UserDefaults, String) {
        let name = "extensions-tests-\(UUID())"
        let preferences = try #require(UserDefaults(suiteName: name))
        preferences.set(false, forKey: AutoSettings.enabledKey)
        return (AppModel(preferences: preferences, startAutomatically: false, history: []), preferences, name)
    }

    @Test func freeAppHasNoExtensions() {
        Extensions.reset()
        #expect(Extensions.sidebarTabs.isEmpty)
        #expect(Extensions.categoryFooter == nil)
        #expect(Extensions.settingsSections.isEmpty)
        #expect(Extensions.privacyNotes.isEmpty)
        #expect(Extensions.currentBusyReason == nil)
    }

    @Test func busyModuleBlocksANewAssessmentAndKeepsItsCard() throws {
        let (model, preferences, name) = try makeModel()
        defer { preferences.removePersistentDomain(forName: name); Extensions.reset() }
        let card = CardRecord(id: "in-use", createdAt: Date(), sessionsScanned: 0, elapsed: 0, card: try Self.minimalCard())
        model.history = [card]
        var deleted: [String] = []
        Extensions.busyReason.append { "Busy for a test" }
        Extensions.isCardInUse.append { $0.id == "in-use" }
        Extensions.onCardDeleted.append { deleted.append($0.id) }
        #expect(Extensions.currentBusyReason == "Busy for a test")
        #expect(!model.canStartAssessment)
        model.delete(card)
        #expect(model.history.map(\.id) == ["in-use"], "A card in use can't be deleted")
        #expect(deleted.isEmpty)
        Extensions.isCardInUse = []
        model.delete(card)
        #expect(model.history.isEmpty)
        #expect(deleted == ["in-use"])
    }

    private static func minimalCard() throws -> ScoreCard {
        let json = """
        {"language":"en","diagnosis":"Fictional card for tests.","dimensions":[],
        "improvement":{"title":"t","situation":"s","actions":[],"signOfSuccess":"x","tryItOn":"y"},"roadmap":[],
        "scope":{"assessedAt":"2026-10-08","timeZone":"UTC","recordDates":[],"sessionsExamined":0,
        "tasksCheckedInDetail":0,"elapsedMinutes":0,"limits":[]}}
        """
        return try JSONDecoder().decode(ScoreCard.self, from: Data(json.utf8))
    }
}
