import Foundation

/// The judge, independent of which tools produced the transcripts.
public enum AssessmentEngine: String, Codable, CaseIterable, Identifiable, Sendable {
    case claude, codex

    public var id: String { rawValue }
    public var name: String { self == .claude ? "Claude Code" : "Codex" }
    public var command: String { rawValue }
    public var provider: String { self == .claude ? "Anthropic" : "OpenAI" }
    /// The context window in tokens that reading budgets are shares of. Claude Code compacts near 1M on Sonnet and Opus;
    /// Haiku has the smaller window. Codex reports 475K for its GPT models.
    public func contextWindow(model: String?) -> Int {
        switch self {
        case .claude: model?.lowercased().contains("haiku") == true ? 200_000 : 1_000_000
        case .codex: 475_000
        }
    }
    public var setupURL: URL {
        URL(string: self == .claude ? "https://claude.com/code" : "https://developers.openai.com/codex/cli")!
    }
    /// The Terminal command that installs the command-line tool scoring runs.
    public var installCommand: String {
        self == .claude ? "curl -fsSL https://claude.ai/install.sh | bash" : "npm install -g @openai/codex"
    }
    /// The Terminal command that signs the command-line tool in.
    public var signInCommand: String { self == .claude ? "claude auth login" : "codex login" }
    /// The maker's desktop app. Having it isn't enough for Claude: its Claude Code isn't the `claude` command.
    public var desktopAppName: String { self == .claude ? "Claude" : "ChatGPT" }

    /// Whether the maker's desktop app is installed, so a missing command can be explained in those terms.
    public var hasDesktopApp: Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["/Applications", "\(home)/Applications"].contains {
            FileManager.default.fileExists(atPath: "\($0)/\(desktopAppName).app")
        }
    }
}

public struct CLIInstallation: Sendable {
    public let executable: URL
    public let version: String?

    public init(executable: URL, version: String? = nil) {
        self.executable = executable
        self.version = version
    }

    /// npm-installed CLIs also need the Node executable alongside their launcher.
    var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        let paths = [executable.deletingLastPathComponent().path,
                     env["PATH"] ?? "", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        env["PATH"] = paths.filter { !$0.isEmpty }.joined(separator: ":")
        return env
    }
}

public enum CLILocator {
    public static func discover(_ engine: AssessmentEngine) async throws -> CLIInstallation? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var candidates = ["\(home)/.local/bin/\(engine.command)",
                          "\(home)/.claude/local/\(engine.command)",
                          "/opt/homebrew/bin/\(engine.command)", "/usr/local/bin/\(engine.command)"]
        if engine == .codex {
            // Desktop and npm installations can coexist, with different model support.
            for applications in ["/Applications", "\(home)/Applications"] {
                candidates.append("\(applications)/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex")
            }
        }
        if engine == .codex || !candidates.contains(where: isExecutable) {
            let result = try? await CLIProcess().run(
                executable: URL(fileURLWithPath: "/bin/zsh"),
                arguments: ["-lc", "command -v \(engine.command)"], timeout: 5)
            if let result {
                candidates += String(decoding: result.stdout, as: UTF8.self).split(separator: "\n")
                    .map(String.init).filter(isExecutable)
            }
        }
        return try await discover(engine, candidatePaths: candidates)
    }

    static func discover(_ engine: AssessmentEngine, candidatePaths: [String]) async throws -> CLIInstallation? {
        var seen = Set<String>()
        var newest: CLIInstallation?
        var firstError: Error?
        for path in candidatePaths where isExecutable(path) && seen.insert(path).inserted {
            try Task.checkCancellation()
            do {
                let installed = try await inspect(engine, path: path)
                if engine == .claude { return installed }
                if newest.map({ isNewer(installed, than: $0) }) ?? true { newest = installed }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // A broken or outdated installation must not hide a working one.
                if firstError == nil { firstError = error }
            }
        }
        if let newest { return newest }
        if let firstError { throw firstError }
        return nil
    }

    private static func inspect(_ engine: AssessmentEngine, path: String) async throws -> CLIInstallation {
        let executable = URL(fileURLWithPath: path)
        let installation = CLIInstallation(executable: executable)
        let version = try await CLIProcess().run(executable: executable, arguments: ["--version"],
                                                environment: installation.environment, timeout: 5)
        guard version.status == 0 else {
            throw AssessmentError.failed(engine, "The installed command could not start. Check it in Terminal.")
        }
        if engine == .codex {
            let help = try await CLIProcess().run(executable: executable, arguments: ["exec", "--help"],
                                                 environment: installation.environment, timeout: 5)
            guard help.status == 0 else {
                throw AssessmentError.failed(engine, "The installed command could not start. Check it in Terminal.")
            }
            try validateCodexHelp(String(decoding: help.stdout, as: UTF8.self))
        }
        return CLIInstallation(executable: executable,
                               version: String(decoding: version.stdout, as: UTF8.self)
                                .trimmingCharacters(in: .whitespacesAndNewlines).clipped(120))
    }

    private static func isNewer(_ candidate: CLIInstallation, than current: CLIInstallation) -> Bool {
        func version(_ installation: CLIInstallation) -> (core: [Int], prerelease: Bool) {
            let token = (installation.version ?? "").split(separator: " ").first { $0.first?.isNumber == true } ?? ""
            let parts = token.split(separator: "-", maxSplits: 1)
            let core = (parts.first ?? "").split(separator: ".").compactMap { Int($0) }
            return (core, parts.count > 1)
        }
        let left = version(candidate), right = version(current)
        if left.core != right.core { return right.core.lexicographicallyPrecedes(left.core) }
        if left.prerelease != right.prerelease { return !left.prerelease }
        return (candidate.version ?? "").compare(current.version ?? "", options: .numeric) == .orderedDescending
    }

    static func validateCodexHelp(_ help: String) throws {
        let required = ["--json", "--output-schema", "--output-last-message", "fork",
                        "--ignore-user-config", "--ignore-rules", "--sandbox", "--skip-git-repo-check", "--strict-config"]
        guard required.allSatisfy(help.contains) else {
            throw AssessmentError.failed(.codex, "Update Codex CLI to use scoring, then check installation again.")
        }
    }

    private static func isExecutable(_ path: String) -> Bool {
        var directory: ObjCBool = false
        return path.hasPrefix("/") && FileManager.default.fileExists(atPath: path, isDirectory: &directory)
            && !directory.boolValue && FileManager.default.isExecutableFile(atPath: path)
    }
}

/// Whether a found command-line tool is signed in, asked the tool itself in a few seconds.
public enum CLISignIn {
    /// False only when the tool clearly reports no sign-in; nil when it can't tell (an older version, a timeout,
    /// or a setup it doesn't describe), so an unclear answer never blocks scoring.
    public static func isSignedIn(_ engine: AssessmentEngine, _ installation: CLIInstallation) async -> Bool? {
        let arguments = engine == .claude ? ["auth", "status", "--json"] : ["login", "status"]
        guard let output = try? await CLIProcess().run(executable: installation.executable, arguments: arguments,
                                                      environment: installation.environment, timeout: 8) else { return nil }
        let text = String(decoding: output.stdout + output.stderr, as: UTF8.self)
        return engine == .claude ? claudeSignedIn(output.stdout) : codexSignedIn(status: output.status, output: text)
    }

    /// `claude auth status --json` reports `loggedIn`, and `authMethod` "none" when nothing at all is set up.
    static func claudeSignedIn(_ json: Data) -> Bool? {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let loggedIn = object["loggedIn"] as? Bool else { return nil }
        if loggedIn { return true }
        return (object["authMethod"] as? String) == "none" ? false : nil
    }

    /// `codex login status` prints "Logged in using …" or "Not logged in".
    static func codexSignedIn(status: Int32, output: String) -> Bool? {
        if output.localizedCaseInsensitiveContains("not logged in") { return false }
        if status == 0, output.localizedCaseInsensitiveContains("logged in") { return true }
        return nil
    }
}
