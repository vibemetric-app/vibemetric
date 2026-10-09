import Foundation

/// The AI coding tool a transcript came from.
public enum AgentTool: String, Codable, CaseIterable, Sendable {
    case claudeCode = "Claude Code"
    case codex = "Codex"
}

/// One event in a normalized session timeline.
public struct TimelineEvent: Sendable {
    public enum Kind: Sendable {
        /// Something the human typed.
        case user(String)
        /// Prose the assistant wrote to the user.
        case assistant(String)
        /// A tool call and, once seen, whether it failed and a short excerpt of the result.
        case tool(name: String, input: String, failed: Bool, result: String)
        /// Runtime events: compaction, hooks, plan mode, memory injection, permission changes.
        case system(String)
    }

    public var time: Date?
    public var kind: Kind
}

/// A single AI session normalized across tools.
public struct Session: Sendable {
    public var id: String
    public var tool: AgentTool
    public var file: URL
    public var project: String
    public var cwd: String?
    public var title: String?
    public var start: Date?
    public var end: Date?
    public var models: Set<String> = []
    public var permissionModes: Set<String> = []
    public var events: [TimelineEvent] = []
    /// Child sessions (Claude Code subagents) folded into this one.
    public var childCount = 0
    public var signals = SessionSignals()

    public var userTurns: Int {
        events.reduce(0) { n, e in if case .user = e.kind { return n + 1 }; return n }
    }

    public var toolCalls: Int {
        events.reduce(0) { n, e in if case .tool = e.kind { return n + 1 }; return n }
    }

    public var failedToolCalls: Int {
        events.reduce(0) { n, e in if case let .tool(_, _, failed, _) = e.kind, failed { return n + 1 }; return n }
    }
}

/// Counters the evidence pack uses to point the assessor at promising sessions.
public struct SessionSignals: Sendable {
    public var edits = 0
    public var verifyCommands = 0
    public var verifyAfterEdit = 0
    public var failThenRerun = 0
    public var memoryReads = 0
    public var memoryWrites = 0
    public var memoryInjected = 0
    public var subagents = 0
    public var skills = 0
    public var hooks = 0
    public var compactions = 0
    public var planMode = 0
    public var permissionDenials = 0
    public var corrections = 0
    public var specLanguage = 0
    public var evalLanguage = 0
    public var browserDriving = 0

    public var tags: [String] {
        var t: [String] = []
        if specLanguage > 0 { t.append("spec") }
        if memoryWrites > 0 { t.append("mem-write") }
        if memoryReads > 0 { t.append("mem-read") }
        if verifyAfterEdit > 0 { t.append("verify") }
        if failThenRerun > 0 { t.append("fix-loop") }
        if subagents > 0 { t.append("subagents") }
        if skills > 0 { t.append("skills") }
        if hooks > 0 { t.append("hooks") }
        if compactions > 0 { t.append("compact") }
        if planMode > 0 { t.append("plan") }
        if permissionDenials > 0 { t.append("denied") }
        if corrections > 0 { t.append("correction") }
        if evalLanguage > 0 { t.append("eval") }
        if browserDriving > 0 { t.append("drives-ui") }
        return t
    }
}
