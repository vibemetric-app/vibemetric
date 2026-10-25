import Foundation

/// CLI stdout is a byte stream: UTF-8 and JSON lines can split at any byte boundary.
final class AssessmentStream: @unchecked Sendable {
    struct Snapshot {
        var claudeResult: [String: Any]?
        var sessionID: String?
        var model: String?
        var failure: String?
        var completed = false
        /// Evidence-pack digests the run opened, by file name.
        var digestsOpened: Set<String> = []
        /// Tokens in the engine's context now. Claude Code reports it with every reply; for Codex it is estimated
        /// from the context the run started with plus what it has read and written since.
        var contextTokens = 0
    }

    /// Digest file names from `EvidencePack`: `cc-<id>.md` or `codex-<id>.md`.
    private static let digestName = try! NSRegularExpression(pattern: #"(?:cc|codex)-[A-Za-z0-9_-]+\.md"#)

    private func noteDigests(in text: String) {
        for match in Self.digestName.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            if let range = Range(match.range, in: text) { state.digestsOpened.insert(String(text[range])) }
        }
    }

    private let lock = NSLock()
    private let engine: AssessmentEngine
    private let onProgress: @Sendable (Assessor.Progress) -> Void
    private var buffer = Data()
    private var state = Snapshot()
    private var reportedItems = Set<String>()
    /// Structured outputs Claude Code has been sent but not yet answered, by tool call.
    private var pendingCards: [String: Data] = [:]
    private let onRejectedCard: @Sendable (Data) -> Void
    var snapshot: Snapshot { lock.withLock { state } }
    var contextTokens: Int { lock.withLock { state.contextTokens } }

    /// `contextBase` is the estimated context a Codex run starts with. `onRejectedCard` receives each structured output
    /// Claude Code turns down, so a card the app can still use is not thrown away.
    init(engine: AssessmentEngine, contextBase: Int = 0, onProgress: @escaping @Sendable (Assessor.Progress) -> Void,
         onRejectedCard: @escaping @Sendable (Data) -> Void = { _ in }) {
        self.engine = engine
        self.onProgress = onProgress
        self.onRejectedCard = onRejectedCard
        state.contextTokens = contextBase
    }

    func consume(_ chunk: Data) {
        lock.withLock {
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                handle(line)
            }
        }
    }

    func finish() {
        lock.withLock {
            if !buffer.isEmpty { handle(buffer); buffer.removeAll() }
        }
    }

    private func handle(_ line: Data) {
        guard let event = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return }
        if engine == .claude { handleClaude(event) } else { handleCodex(event) }
    }

    private func handleClaude(_ event: [String: Any]) {
        switch event["type"] as? String {
        case "system":
            if event["subtype"] as? String == "init" { state.sessionID = event["session_id"] as? String }
            state.model = event["model"] as? String ?? state.model
        case "assistant":
            let message = event["message"] as? [String: Any] ?? [:]
            state.model = message["model"] as? String ?? state.model
            if let usage = message["usage"] as? [String: Any] {
                let used = ["input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens", "output_tokens"]
                    .reduce(0) { $0 + (usage[$1] as? Int ?? 0) }
                if used > 0 { state.contextTokens = used }
            }
            for part in message["content"] as? [[String: Any]] ?? [] {
                if part["type"] as? String == "tool_use", part["name"] as? String == "StructuredOutput" {
                    if let id = part["id"] as? String, let input = part["input"], JSONSerialization.isValidJSONObject(input),
                       let data = try? JSONSerialization.data(withJSONObject: input) {
                        pendingCards[id] = data
                    }
                } else if part["type"] as? String == "tool_use" {
                    let input = part["input"] as? [String: Any] ?? [:]
                    let target = (input["file_path"] ?? input["pattern"] ?? input["path"]) as? String ?? ""
                    if part["name"] as? String == "Read" { noteDigests(in: target) }
                    onProgress(.reading("\(part["name"] as? String ?? "Read") \(URL(fileURLWithPath: target).lastPathComponent)"))
                } else if part["type"] as? String == "text", let text = part["text"] as? String, !text.isEmpty {
                    onProgress(.thinking(Redactor.scrub(text).clipped(160)))
                }
            }
        case "user":
            let message = event["message"] as? [String: Any] ?? [:]
            for part in message["content"] as? [[String: Any]] ?? [] where part["type"] as? String == "tool_result" {
                guard let id = part["tool_use_id"] as? String, let card = pendingCards.removeValue(forKey: id) else { continue }
                if part["is_error"] as? Bool == true { onRejectedCard(card) }
            }
        case "result":
            state.sessionID = event["session_id"] as? String ?? state.sessionID
            state.claudeResult = event
            if event["is_error"] as? Bool == true {
                state.failure = event["result"] as? String ?? event["subtype"] as? String ?? "The assessment failed."
            } else { state.completed = true }
        default: break
        }
    }

    /// Codex reports no per-reply context size, so what a run reads and writes is counted at the rate measured for
    /// mostly Korean records (about 1.14 characters per token). English text costs less, so the estimate errs high.
    static func estimatedTokens(_ text: String) -> Int { Int((Double(text.count) / 1.14).rounded(.up)) }

    private func handleCodex(_ event: [String: Any]) {
        switch event["type"] as? String {
        case "thread.started":
            state.sessionID = event["thread_id"] as? String
            state.model = event["model"] as? String ?? state.model
        case "turn.completed": state.completed = true
        case "turn.failed":
            state.failure = (event["error"] as? [String: Any])?["message"] as? String ?? "The assessment failed."
        case "error":
            // A reconnect can emit a non-terminal error; only turn.failed or exit status ends the run.
            if let message = event["message"] as? String { onProgress(.thinking(Redactor.scrub(message).clipped(160))) }
        case "item.started", "item.completed":
            guard let item = event["item"] as? [String: Any] else { return }
            let key = "\(item["id"] as? String ?? ""):\(item["type"] as? String ?? "")"
            switch item["type"] as? String {
            case "command_execution":
                if event["type"] as? String == "item.completed" {
                    state.contextTokens += Self.estimatedTokens(item["command"] as? String ?? "")
                        + Self.estimatedTokens(item["aggregated_output"] as? String ?? "")
                }
                guard reportedItems.insert(key).inserted else { return }
                noteDigests(in: item["command"] as? String ?? "")
                onProgress(.reading(Redactor.scrub(item["command"] as? String ?? "Reading evidence").clipped(160)))
            case "agent_message":
                if event["type"] as? String == "item.completed" {
                    state.contextTokens += Self.estimatedTokens(item["text"] as? String ?? "")
                }
                guard event["type"] as? String == "item.completed", let text = item["text"] as? String,
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") else { return }
                onProgress(.thinking(Redactor.scrub(text).clipped(160)))
            default: break
            }
        default: break
        }
    }
}
