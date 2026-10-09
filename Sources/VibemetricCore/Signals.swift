import Foundation

/// Cheap, deterministic hints that steer the assessor toward sessions worth reading.
/// These never produce a score on their own; the rubric requires judged, connected evidence.
enum SignalExtractor {
    private static func regex(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p, options: [.caseInsensitive]) }

    static let verifyCommand = regex(#"\b(test|tests|pytest|jest|vitest|mocha|rspec|go test|cargo test|swift test|xcodebuild[^|;]*test|playwright|cypress|lint|eslint|tsc\b|typecheck|mypy|ruff|build|curl\s|--dry-run|smoke|verify|check)"#)
    static let memoryPath = regex(#"(CLAUDE\.md|AGENTS\.md|MEMORY\.md|GEMINI\.md|\.cursorrules|\.cursor/rules|/memory/|/rules/|/skills/[^\s]*SKILL\.md|FEATURES?\.md|feature[-_]map)"#)
    static let correction = regex(#"^(no\b|nope|don'?t|do not|stop\b|wrong|that'?s not|not what|instead\b|actually\b|why did you|why are you|i told you|again\??$|revert|undo)|\b(i told you|you forgot|you didn'?t|not what i asked|as i said|still (not|broken|wrong|failing))\b"#)
    static let spec = regex(#"(acceptance criteria|definition of done|done when|\bdone means\b|success criteria|must (pass|return|show|not)|\bSHALL\b|given .{1,80} when .{1,80} then|expected (output|result|behavior)|should (return|output|display)|pass/fail|verify that)"#)
    static let eval = regex(#"(\beval(s|uation)?\b|rubric|llm[- ]as[- ]a?[- ]?judge|\bjudge\b|a/b test|benchmark|pass rate|golden (set|file)|test cases? set|regression (gate|suite))"#)
    /// Shell commands that write files: redirects, tee, in-place edits, copies and moves.
    static let shellWrite = regex(#"(>|\btee\b|\bsed\s+-i|\bperl\s+-[a-z]*i|\bcp\s|\bmv\s|apply_patch|write_text|\.write\()"#)
    static let writeTools: Set<String> = ["Edit", "Write", "MultiEdit", "NotebookEdit", "apply_patch", "str_replace_editor"]
    static let browserTools = ["Browser", "browser", "playwright", "computer", "Simulator", "screenshot", "navigate"]

    static func annotate(_ s: inout Session) {
        var sig = SessionSignals()
        var sawEdit = false
        var lastFailedCommand: String?

        for e in s.events {
            switch e.kind {
            case let .user(text):
                if matches(correction, text.prefix(200).lowercased()) { sig.corrections += 1 }
                if matches(spec, text) { sig.specLanguage += 1 }
                if matches(eval, text) { sig.evalLanguage += 1 }
            case let .tool(name, input, failed, result):
                let isShell = ["Bash", "exec", "exec_command", "shell", "js", "local_shell"].contains(name)
                if writeTools.contains(name) || (isShell && input.contains("apply_patch")) {
                    sawEdit = true
                    sig.edits += 1
                }
                if matches(memoryPath, input) {
                    if writeTools.contains(name) || (isShell && matches(shellWrite, input)) { sig.memoryWrites += 1 } else { sig.memoryReads += 1 }
                }
                if isShell && matches(verifyCommand, input) {
                    sig.verifyCommands += 1
                    if sawEdit { sig.verifyAfterEdit += 1 }
                    let key = String(input.prefix(60))
                    if failed { lastFailedCommand = key } else if lastFailedCommand == key { sig.failThenRerun += 1; lastFailedCommand = nil }
                }
                if name == "Agent" || name == "Task" || name.contains("spawn_agent") { sig.subagents += 1 }
                if name == "Skill" { sig.skills += 1 }
                if browserTools.contains(where: { name.contains($0) }) { sig.browserDriving += 1 }
                if failed && (result.localizedCaseInsensitiveContains("permission") || result.contains("doesn't want to proceed") || result.localizedCaseInsensitiveContains("denied")) {
                    sig.permissionDenials += 1
                }
            case let .system(text):
                if text.hasPrefix("memory injected") { sig.memoryInjected += 1 }
                if text.contains("hook") { sig.hooks += 1 }
                if text.contains("compact") { sig.compactions += 1 }
                if text.contains("plan mode") { sig.planMode += 1 }
                if text.hasPrefix("subagent ") { sig.subagents += 1 }
                if text.contains("interrupted") { sig.corrections += 1 }
            case .assistant:
                continue
            }
        }
        s.signals = sig
    }

    private static func matches<S: StringProtocol>(_ r: NSRegularExpression, _ text: S) -> Bool {
        let str = String(text)
        return r.firstMatch(in: str, range: NSRange(str.startIndex..., in: str)) != nil
    }
}
