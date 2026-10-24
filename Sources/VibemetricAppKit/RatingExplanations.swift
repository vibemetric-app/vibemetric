import SwiftUI
import VibemetricCore

/// A score card leaves out each competency's 「What you did」 and 「Why you got this rating」 so the score finishes
/// sooner. Opening a category writes them by continuing the result's saved scoring session, and saves them with
/// the result.
enum RatingExplanations {
    static func key(_ recordID: String, _ dimension: VibemetricCore.Dimension) -> String { "\(recordID)|\(dimension.rawValue)" }
}

extension AppModel {
    /// Whether opening this category can write its explanations: they are missing and the scoring session was saved.
    func canExplain(_ dimension: VibemetricCore.Dimension, of record: CardRecord) -> Bool {
        record.card.needsExplanations(dimension) && record.hasSavedSession && Store.hasPack(for: record)
    }

    func explainRating(_ dimension: VibemetricCore.Dimension, of recordID: String) async {
        let key = RatingExplanations.key(recordID, dimension)
        guard !explainingRatings.contains(key), let record = history.first(where: { $0.id == recordID }),
              canExplain(dimension, of: record), let sessionID = record.sessionID else { return }
        explainingRatings.insert(key)
        ratingExplanationErrors[key] = nil
        defer { explainingRatings.remove(key) }
        let engine = record.effectiveEngine
        do {
            let card = try await Assessor(installation: installations[engine])
                .explain(dimension, in: record.card, sessionID: sessionID, packDir: Store.newPackDir(id: record.id),
                         sources: record.sources ?? [], options: AssessmentOptions(engine: engine, model: record.model))
            // The result may have changed or been deleted while this ran; apply to the current copy.
            guard let index = history.firstIndex(where: { $0.id == recordID }) else { return }
            var updated = history[index]
            updated.card = card
            try Store.save(updated)
            history[index] = updated
            if selected?.id == recordID { selected = updated }
        } catch is CancellationError {
        } catch {
            ratingExplanationErrors[key] = error.localizedDescription
        }
    }
}

/// What a category's competency rows show in place of an explanation that hasn't been written yet.
struct ExplanationStatus {
    var writing: Bool
    var error: String?
    var retry: () -> Void
}

private struct ExplanationStatusKey: EnvironmentKey {
    static let defaultValue: ExplanationStatus? = nil
}

private struct ResultRecordIDKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    /// The saved result a card view shows, so an opened category can write its explanations into it.
    var resultRecordID: String? {
        get { self[ResultRecordIDKey.self] }
        set { self[ResultRecordIDKey.self] = newValue }
    }

    /// Set by an open category whose explanations are written on demand; nil for older results and exports.
    var explanationStatus: ExplanationStatus? {
        get { self[ExplanationStatusKey.self] }
        set { self[ExplanationStatusKey.self] = newValue }
    }
}

/// In place of 「What you did」 or 「Why you got this rating」 while it is being written, or after writing it failed.
struct PendingExplanation: View {
    var status: ExplanationStatus

    var body: some View {
        if let error = status.error {
            VStack(alignment: .leading, spacing: 6) {
                Text("Couldn't write this explanation: \(error)")
                    .scaledFont(14).foregroundStyle(Theme.color(for: .bottleneck))
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try again", action: status.retry).controlSize(.small)
            }
        } else {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(status.writing ? "Writing this explanation from your sessions… about a minute" : "Starting…")
                    .scaledFont(14).foregroundStyle(Theme.muted)
            }
        }
    }
}
