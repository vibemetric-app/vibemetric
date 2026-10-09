import Foundation

/// CLI stdout is a byte stream: UTF-8 and JSON lines can split at any byte boundary.
final class AssessmentStream: @unchecked Sendable {
    struct Snapshot {
        var claudeResult: [String: Any]?
        var sessionID: String?
        var model: String?
        var failure: String?
        var completed = false
    }

    private let lock = NSLock()
    private let engine: AssessmentEngine
    private let onProgress: @Sendable (Assessor.Progress) -> Void
    private var buffer = Data()
    private var state = Snapshot()
    private var reportedItems = Set<String>()
    var snapshot: Snapshot { lock.withLock { state } }

    init(engine: AssessmentEngine, onProgress: @escaping @Sendable (Assessor.Progress) -> Void) {
        self.engine = engine
        self.onProgress = onProgress
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
            for part in message["content"] as? [[String: Any]] ?? [] {
                if part["type"] as? String == "tool_use" {
                    let input = part["input"] as? [String: Any] ?? [:]
                    let target = (input["file_path"] ?? input["pattern"] ?? input["path"]) as? String ?? ""
                    onProgress(.reading("\(part["name"] as? String ?? "Read") \(URL(fileURLWithPath: target).lastPathComponent)"))
                } else if part["type"] as? String == "text", let text = part["text"] as? String, !text.isEmpty {
                    onProgress(.thinking(Redactor.scrub(text).clipped(160)))
                }
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
                guard reportedItems.insert(key).inserted else { return }
                onProgress(.reading(Redactor.scrub(item["command"] as? String ?? "Reading evidence").clipped(160)))
            case "agent_message":
                guard event["type"] as? String == "item.completed", let text = item["text"] as? String,
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") else { return }
                onProgress(.thinking(Redactor.scrub(text).clipped(160)))
            default: break
            }
        default: break
        }
    }
}
