import Foundation
import Darwin

/// Owns one CLI invocation at a time. All mutable lifecycle state is protected by the lock.
/// Pipe reads and waitUntilExit run off the cooperative executor, including during cancellation.
final class CLIProcess: @unchecked Sendable {
    struct Output: Sendable {
        var status: Int32
        var stdout: Data
        var stderr: Data
    }

    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    func cancel() {
        let active = lock.withLock { cancelled = true; return process }
        if let active { Self.stop(active) }
    }

    func run(executable: URL, arguments: [String], directory: URL? = nil,
             environment: [String: String]? = nil, input: URL? = nil,
             timeout: TimeInterval, onOutput: @escaping @Sendable (Data) -> Void = { _ in }) async throws -> Output {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let output = try self.execute(executable: executable, arguments: arguments, directory: directory,
                                                      environment: environment, input: input, timeout: timeout, onOutput: onOutput)
                        continuation.resume(returning: output)
                    } catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: { self.cancel() }
    }

    private func execute(executable: URL, arguments: [String], directory: URL?, environment: [String: String]?,
                         input: URL?, timeout: TimeInterval, onOutput: @escaping @Sendable (Data) -> Void) throws -> Output {
        let proc = Process()
        proc.executableURL = executable
        proc.arguments = arguments
        proc.currentDirectoryURL = directory
        proc.environment = environment
        let inputHandle = try input.map { try FileHandle(forReadingFrom: $0) }
        defer { try? inputHandle?.close() }
        proc.standardInput = inputHandle ?? FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        // Register and launch atomically: cancellation before launch must not start a process.
        try lock.withLock {
            if cancelled { throw CancellationError() }
            precondition(process == nil, "Only one invocation per CLIProcess")
            try proc.run()
            process = proc
        }
        defer { lock.withLock { process = nil } }
        let stdout = BoundedData(), stderr = BoundedData(), expired = LockedFlag()
        let reads = DispatchGroup()
        for (handle, destination, callback) in [
            (out.fileHandleForReading, stdout, onOutput),
            (err.fileHandleForReading, stderr, { @Sendable (_: Data) in }),
        ] {
            reads.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                defer { reads.leave(); try? handle.close() }
                while true {
                    let chunk = handle.availableData
                    if chunk.isEmpty { break }
                    destination.append(chunk)
                    callback(chunk)
                }
            }
        }
        let deadline = DispatchWorkItem {
            guard proc.isRunning else { return }
            expired.set()
            Self.stop(proc)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + max(0, timeout), execute: deadline)
        proc.waitUntilExit()
        deadline.cancel()
        reads.wait()
        if lock.withLock({ cancelled }) { throw CancellationError() }
        if expired.value { throw AssessmentError.timedOut }
        return Output(status: proc.terminationStatus, stdout: stdout.data, stderr: stderr.data)
    }

    private static func stop(_ proc: Process) {
        guard proc.isRunning else { return }
        let pid = proc.processIdentifier
        // Foundation launches a process group on macOS. Never signal the app's own group.
        let ownsGroup = getpgid(pid) == pid
        if ownsGroup { kill(-pid, SIGTERM) } else { proc.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
            if ownsGroup { kill(-pid, SIGKILL) }
            else if proc.isRunning { kill(pid, SIGKILL) }
        }
    }
}

private final class BoundedData: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()
    var data: Data { lock.withLock { storage } }
    func append(_ data: Data) {
        lock.withLock {
            storage.append(data)
            if storage.count > 128 * 1024 { storage = storage.suffix(128 * 1024) }
        }
    }
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = false
    var value: Bool { lock.withLock { storage } }
    func set() { lock.withLock { storage = true } }
}
