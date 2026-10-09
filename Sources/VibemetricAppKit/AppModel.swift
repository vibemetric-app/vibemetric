import AppKit
import Foundation
import Observation
import VibemetricCore

/// A finished assessment saved to disk.
/// A saved score card with how it was made. Public because extensions receive it.
public struct CardRecord: Codable, Identifiable, Hashable {
    public var id: String
    var createdAt: Date
    public var model: String?
    var sessionsScanned: Int
    var elapsed: TimeInterval
    public var card: ScoreCard
    /// The result this run was anchored to, if any. Its scores are the baseline for "what changed".
    var previousId: String?
    /// True when the daily schedule started this run rather than the user.
    var automatic: Bool?
    /// Missing on legacy records, which were all scored by Claude Code.
    var engine: AssessmentEngine?
    var cliVersion: String?
    public var actualModel: String?
    var rubricVersion: String?
    /// The scoring notes from Settings that this run was given, if any.
    public var instructions: String?
    public var sessionID: String?
    public var sources: [TranscriptSource]?

    public var effectiveEngine: AssessmentEngine { engine ?? .claude }
    public var engineLabel: String { effectiveEngine.name }
    public var hasSavedSession: Bool { sessionID.flatMap(UUID.init(uuidString:)) != nil }

    func isComparable(to options: AssessmentOptions) -> Bool {
        effectiveEngine == options.engine && model == options.model
            && (rubricVersion ?? "1") == AssessmentOptions.rubricVersion
    }

    func isComparable(to record: CardRecord) -> Bool {
        effectiveEngine == record.effectiveEngine && model == record.model
            && (rubricVersion ?? "1") == (record.rubricVersion ?? "1")
            && (actualModel == nil || record.actualModel == nil || actualModel == record.actualModel)
    }

    /// When the records were read for this run (the run began then; `createdAt` is when it finished).
    public var scannedAt: Date { createdAt.addingTimeInterval(-elapsed) }

    public static func == (a: CardRecord, b: CardRecord) -> Bool { a.id == b.id }
    public func hash(into h: inout Hasher) { h.combine(id) }
}

/// Results and their evidence packs stay in Application Support until the result is deleted.
public enum Store {
    // The dev build must not modify production history or evidence packs.
    private static let directoryName = AppVariant.isDev ? "Vibemetric Dev" : "Vibemetric"
    public static let support: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("\(directoryName)/results", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let packs = EvidencePack.savedPacksDirectory(isDev: AppVariant.isDev)

    public static func newPackDir(id: String) -> URL {
        packs.appendingPathComponent(id, isDirectory: true)
    }

    public static func hasPack(for record: CardRecord) -> Bool {
        FileManager.default.fileExists(atPath: newPackDir(id: record.id).appendingPathComponent("overview.md").path)
    }

    static func load() -> [CardRecord] {
        let files = (try? FileManager.default.contentsOfDirectory(at: support, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return files.filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(CardRecord.self, from: Data(contentsOf: $0)) }
            .map { record in
                // Rubric 3 cards saved before the deduction moved to Security get the same treatment on load.
                var record = record
                if record.rubricVersion == "3" { record.card.applyDeductionToSecurity() }
                return record
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    static func save(_ record: CardRecord) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(record).write(to: support.appendingPathComponent("\(record.id).json"), options: .atomic)
    }

    /// Rule-file snapshots sit next to each result as `<id>.rules` (not .json, so load() skips them).
    static func saveRules(_ snapshot: RuleSnapshot, for id: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(snapshot).write(to: support.appendingPathComponent("\(id).rules"))
    }

    static func loadRules(for id: String) -> RuleSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? Data(contentsOf: support.appendingPathComponent("\(id).rules"))).flatMap { try? decoder.decode(RuleSnapshot.self, from: $0) }
    }

    static func delete(_ record: CardRecord) {
        try? FileManager.default.removeItem(at: newPackDir(id: record.id))
        try? FileManager.default.removeItem(at: support.appendingPathComponent("\(record.id).rules"))
        try? FileManager.default.removeItem(at: support.appendingPathComponent("\(record.id).json"))
    }
}

struct ScanSummary {
    var total: Int
    var byTool: [(AgentTool, Int)]
    var projects: Int
    var range: ClosedRange<Date>?
    var duration: TimeInterval

    init(_ scan: ScanResult) {
        total = scan.sessions.count
        byTool = AgentTool.allCases.map { ($0, scan.sessions(for: $0).count) }.filter { $0.1 > 0 }
        projects = scan.projects.count
        range = scan.dateRange
        duration = scan.duration
    }
}

enum ModelChoice: String, CaseIterable, Identifiable {
    case standard = "Default", opus = "Opus", sonnet = "Sonnet", haiku = "Haiku"
    var id: String { rawValue }
    var name: String { self == .standard ? "Default (Sonnet)" : rawValue }
    var alias: String {
        switch self {
        case .standard, .sonnet: "sonnet"
        case .opus: "opus"
        case .haiku: "haiku"
        }
    }
}

enum CodexModelChoice: String, CaseIterable, Identifiable {
    case standard = "default", astra = "gpt-6-astra", sol = "gpt-6-sol", luna = "gpt-6-luna"

    var id: String { rawValue }
    var modelID: String { self == .standard ? "gpt-6.1-sol" : rawValue }
    var name: String {
        switch self {
        case .standard: "Default (GPT 6.1 Sol)"
        case .astra: "Astra"
        case .sol: "Sol"
        case .luna: "Luna"
        }
    }
    var help: String {
        switch self {
        case .standard: "Uses GPT 6.1 Sol for this assessment."
        case .astra: "Strongest reasoning for complex analysis."
        case .sol: "A general-purpose model for detailed analysis."
        case .luna: "A faster model for focused analysis."
        }
    }
}

@MainActor
@Observable
public final class AppModel {
    enum Phase {
        case scanning
        case ready
        case running
        case failed(String)
    }

    struct Activity: Identifiable {
        let id = UUID()
        var text: String
        var isThought: Bool
    }

    var phase: Phase = .scanning
    public var scan: ScanResult?
    var summary: ScanSummary?
    static let engineKey = "assessment.engine"
    private static let claudeModelKey = "assessment.claudeModel"
    private static let codexModelKey = "assessment.codexModel"
    private let preferences: UserDefaults

    var engine: AssessmentEngine {
        didSet {
            preferences.set(engine.rawValue, forKey: Self.engineKey)
            if case .failed = phase { phase = .ready }
        }
    }
    var model: ModelChoice {
        didSet { preferences.set(model.rawValue, forKey: Self.claudeModelKey) }
    }
    var codexModel: CodexModelChoice {
        didSet { preferences.set(codexModel.rawValue, forKey: Self.codexModelKey) }
    }
    public var installations: [AssessmentEngine: CLIInstallation] = [:]
    var installationErrors: [AssessmentEngine: String] = [:]
    var isCheckingEngines = false
    public var isScanning = false
    var runningEngine: AssessmentEngine?
    var showsRunProgress = false

    var assessmentOptions: AssessmentOptions {
        AssessmentOptions(engine: engine, model: engine == .claude ? model.alias : codexModel.modelID,
                          instructions: UserDefaults.standard.string(forKey: Self.instructionsKey))
    }
    var canStartAssessment: Bool {
        !isRunning && !isScanning && Extensions.currentBusyReason == nil && installations[engine] != nil && (summary?.total ?? 0) > 0
    }
    var history: [CardRecord] = []
    public var selected: CardRecord? {
        didSet {
            guard let selected else { return }
            showsSettings = false
            Extensions.onCardSelected.forEach { $0(selected) }
        }
    }
    /// Settings live in the main window's detail pane rather than a separate window.
    public var showsSettings = false

    /// "General", or the id of a sidebar tab from `Extensions.sidebarTabs`.
    var sidebarTab = AppModel.generalTab
    static let generalTab = "General"

    /// Brings a sidebar tab to the front, together with the main window.
    public func showSidebarTab(_ id: String) {
        sidebarTab = id
        showsSettings = false
        showMainWindow(selectLatest: false)
    }

    var activity: [Activity] = []
    var runStarted: Date?
    var readsSoFar = 0
    var isPreparingAssessment = false

    /// What the last automatic check did, e.g. "Skipped: no new sessions since the last score".
    var lastAutoStatus: String? = UserDefaults.standard.string(forKey: AutoSettings.lastStatusKey)

    private var assessor: Assessor?
    private var runTask: Task<Void, Never>?
    private var autoTimer: Timer?

    init(preferences: UserDefaults = .standard, startAutomatically: Bool = true, history: [CardRecord]? = nil) {
        self.preferences = preferences
        self.history = history ?? Store.load()
        engine = preferences.string(forKey: Self.engineKey).flatMap(AssessmentEngine.init(rawValue:)) ?? .claude
        model = preferences.string(forKey: Self.claudeModelKey).flatMap(ModelChoice.init(rawValue:)) ?? .standard
        codexModel = preferences.string(forKey: Self.codexModelKey).flatMap(CodexModelChoice.init(rawValue:)) ?? .standard
        selected = self.history.first
        if !self.history.isEmpty && preferences.string(forKey: Self.engineKey) == nil {
            preferences.set(AssessmentEngine.claude.rawValue, forKey: Self.engineKey)
        }
        guard startAutomatically else { phase = .ready; return }
        Task {
            await rescan()
            checkAutoRun()
        }
        // Check once a minute and right after the Mac wakes, so a slot missed while asleep runs on wake.
        autoTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.checkAutoRun() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor [weak self] in self?.checkAutoRun() }
        }
    }

    // MARK: Windows and shared actions

    /// The app's single model, for AppKit callbacks (the app delegate) that can't reach SwiftUI state.
    static weak var shared: AppModel?

    /// Set by the main window scene; opens (or reopens) the "main" window.
    var openMainWindow: (() -> Void)?

    func showMainWindow(selectLatest: Bool) {
        if selectLatest { selected = history.first }
        NSApp.activate(ignoringOtherApps: true)
        if let openMainWindow {
            openMainWindow()
        } else {
            NSApp.windows.first { $0.identifier?.rawValue.contains("main") == true || $0.title == "Vibemetric" }?
                .makeKeyAndOrderFront(nil)
        }
    }

    func copyLatestReport() {
        guard let latest = history.first else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(MarkdownRenderer.render(latest.card, previous: baseline(for: latest)?.card), forType: .string)
    }

    /// Notes the person writes in Settings for the judge, e.g. which test sessions to leave out.
    static let instructionsKey = "assessment.instructions"

    /// Shows Settings in the main window.
    public func showSettings() {
        selected = nil
        showsRunProgress = false
        showsSettings = true
        showMainWindow(selectLatest: false)
    }

    /// For AppKit code and views without the model in their environment.
    static func openSettings() { shared?.showSettings() }

    // MARK: Daily automatic score

    var autoSchedule: AutoSchedule { AutoSettings.schedule }

    var nextAutoRun: Date? { autoSchedule.next(after: Date()) }

    /// Runs today's automatic score if its time has passed and nothing has covered it yet.
    func checkAutoRun(now: Date = Date()) {
        // Work an extension reports as busy can share the evidence-pack folder; wait and catch up on the next check.
        guard !isRunning, !isScanning, Extensions.currentBusyReason == nil,
              preferences.string(forKey: Self.engineKey) != nil else { return }
        let defaults = UserDefaults.standard
        let lastAttempt = defaults.object(forKey: AutoSettings.lastAttemptKey) as? Date
        guard autoSchedule.isDue(now: now, lastResultAt: history.first?.createdAt, lastAttemptAt: lastAttempt) else { return }
        // Record the attempt first so a failure or skip can't retry every minute.
        defaults.set(now, forKey: AutoSettings.lastAttemptKey)

        Task {
            await rescan()
            // rescan() returns at once when another scan is in flight; wait for that one to finish.
            while isScanning { try? await Task.sleep(for: .milliseconds(200)) }
            guard installations[engine] != nil else { return setAutoStatus("Skipped: \(engine.name) is not ready") }
            guard let scan, !scan.sessions.isEmpty else { return setAutoStatus("Skipped: no sessions found") }
            if AutoSettings.skipWhenIdle, let last = history.first(where: { $0.isComparable(to: assessmentOptions) }) {
                let hasNew = scan.sessions.contains { ($0.end ?? .distantPast) > last.scannedAt }
                guard hasNew else { return setAutoStatus("Skipped: no new sessions since the last score") }
            }
            guard startAssessment(automatic: true) else { return setAutoStatus("Skipped: scoring could not start") }
            setAutoStatus("Scoring started automatically")
        }
    }

    private func setAutoStatus(_ text: String) {
        let stamped = "\(RelativeDate.format(Date())): \(text)"
        lastAutoStatus = stamped
        UserDefaults.standard.set(stamped, forKey: AutoSettings.lastStatusKey)
    }

    func refreshEngines() async {
        guard !isCheckingEngines else { return }
        isCheckingEngines = true
        defer { isCheckingEngines = false }
        let results = await withTaskGroup(of: (AssessmentEngine, CLIInstallation?, String?).self) { group in
            for engine in AssessmentEngine.allCases {
                group.addTask {
                    do { return (engine, try await CLILocator.discover(engine), nil) }
                    catch { return (engine, nil, error.localizedDescription) }
                }
            }
            var results: [(AssessmentEngine, CLIInstallation?, String?)] = []
            for await result in group { results.append(result) }
            return results
        }
        for (engine, installed, error) in results {
            installations[engine] = installed
            installationErrors[engine] = error
        }
    }

    func rescan() async {
        await rescan { Scanner.scan() }
    }

    /// Existing scan data remains visible until its replacement is ready.
    func rescan(using scanRecords: @escaping @Sendable () async -> ScanResult) async {
        guard !isRunning, !isScanning else { return }
        isScanning = true
        if scan == nil { phase = .scanning }
        defer { isScanning = false }
        async let discovery: Void = refreshEngines()
        let result = await Task.detached(priority: .userInitiated) { await scanRecords() }.value
        await discovery
        scan = result
        summary = ScanSummary(result)
        phase = .ready
    }

    public var isRunning: Bool { if case .running = phase { return true }; return false }

    @discardableResult
    func startAssessment(automatic: Bool = false) -> Bool {
        guard canStartAssessment, let scan, let installation = installations[engine] else { return false }
        preferences.set(engine.rawValue, forKey: Self.engineKey)
        // An automatic run shouldn't pull the window away from a result the user is reading.
        let wasViewingLatest = selected == nil || selected?.id == history.first?.id
        let id = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-") + "-\(UUID().uuidString)"
        let packDir = Store.newPackDir(id: id)
        let assessor = Assessor(installation: installation)
        self.assessor = assessor
        isPreparingAssessment = true
        activity = [Activity(text: "Preparing session evidence and usage data…", isThought: true)]
        readsSoFar = 0
        runStarted = Date()
        if !automatic { selected = nil; showsSettings = false; showsRunProgress = true }
        phase = .running
        runningEngine = engine
        Notifier.shared.requestPermissionIfNeeded()
        let options = assessmentOptions
        let modelName = options.model
        // Anchor to the latest result so scores only move when new evidence justifies it.
        let baseline = history.first { $0.isComparable(to: options) }
        let previous = baseline.map { EvidencePack.Previous(card: $0.card, date: $0.scannedAt) }

        runTask = Task {
            do {
                let baselineId = baseline?.id
                let rules = try await Task.detached { () throws -> RuleSnapshot in
                    let snapshot = RuleFiles.snapshot(scan: scan)
                    let report = previous.map { prev in
                        RuleFiles.changesReport(current: snapshot, previous: baselineId.flatMap(Store.loadRules(for:)), since: prev.date)
                    }
                    try EvidencePack.write(scan, to: packDir, previous: previous, ruleChanges: report, contextFiles: snapshot)
                    try EvidencePack.writeSupplementary(scan, to: packDir, inputs: ["usage", "model_settings"])
                    return snapshot
                }.value
                guard FileManager.default.fileExists(atPath: packDir.appendingPathComponent("overview.md").path) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                isPreparingAssessment = false
                let outcome = try await assessor.run(packDir: packDir, sources: scan.sources, options: options,
                                                     previousDate: previous?.date) { event in
                    Task { @MainActor [weak self] in self?.record(event) }
                }
                let record = CardRecord(id: id, createdAt: Date(), model: modelName, sessionsScanned: scan.sessions.count,
                                        elapsed: outcome.elapsed, card: outcome.card, previousId: baseline?.id,
                                        automatic: automatic ? true : nil, engine: options.engine,
                                        cliVersion: outcome.cliVersion, actualModel: outcome.actualModel,
                                        rubricVersion: AssessmentOptions.rubricVersion, instructions: options.instructions,
                                        sessionID: outcome.sessionID, sources: scan.sources)
                try Store.save(record)
                Store.saveRules(rules, for: record.id)
                history.insert(record, at: 0)
                if !automatic || wasViewingLatest { selected = record }
                if automatic { setAutoStatus("Scored \(record.card.totalLabel ?? "—")") }
                Notifier.shared.scored(record, baseline: baseline)
                phase = .ready
            } catch is CancellationError {
                phase = .ready
                selected = history.first
            } catch {
                phase = Task.isCancelled ? .ready : .failed(error.localizedDescription)
                if automatic && !Task.isCancelled { setAutoStatus("Failed: \(error.localizedDescription)") }
                if !Task.isCancelled { Notifier.shared.failed(error.localizedDescription, automatic: automatic) }
            }
            if !history.contains(where: { $0.id == id }) { try? FileManager.default.removeItem(at: packDir) }
            self.isPreparingAssessment = false
            self.assessor = nil
            self.runningEngine = nil
            self.runTask = nil
        }
        return true
    }

    /// The result a record should be compared against: its recorded baseline, else the next older one.
    func baseline(for record: CardRecord) -> CardRecord? {
        if let id = record.previousId, let found = history.first(where: { $0.id == id }) {
            return found.isComparable(to: record) ? found : nil
        }
        // A new-engine result with no baseline stays a new baseline, including after deleting history.
        guard record.engine == nil, let i = history.firstIndex(of: record) else { return nil }
        return history.dropFirst(i + 1).first { $0.isComparable(to: record) }
    }

    func cancel() {
        assessor?.cancel()
        runTask?.cancel()
    }

    func delete(_ record: CardRecord) {
        guard !Extensions.isCardInUse.contains(where: { $0(record) }) else { return }
        Store.delete(record)
        history.removeAll { $0.id == record.id }
        if selected?.id == record.id { selected = history.first }
        Extensions.onCardDeleted.forEach { $0(record) }
    }

    private func record(_ event: Assessor.Progress) {
        switch event {
        case .started:
            activity.append(Activity(text: "\((runningEngine ?? engine).name) is reading your evidence pack…", isThought: true))
        case let .reading(what):
            readsSoFar += 1
            activity.append(Activity(text: what, isThought: false))
        case let .thinking(text):
            activity.append(Activity(text: text, isThought: true))
        }
        if activity.count > 200 { activity.removeFirst(activity.count - 200) }
    }
}
