import Foundation
import Testing
@testable import VibemetricCore

struct CLILocatorTests {
    @Test(arguments: [("0.145.0", "0.158.0-alpha.2.1"), ("0.99.0", "0.100.0"), ("0.158.0-alpha.2.1", "0.158.0")])
    func newerCodexIsChosenEvenWhenOlderNpmInstallAppearsFirst(versions: (String, String)) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("vibemetric-locator-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let old = try command(in: directory, name: "npm-codex", version: versions.0)
        let new = try command(in: directory, name: "bundled-codex", version: versions.1)
        let found = try await CLILocator.discover(.codex, candidatePaths: [old.path, new.path])
        #expect(found?.executable == new)
        #expect(found?.version == "codex-cli \(versions.1)")
    }

    @Test func brokenInstallationDoesNotHideAWorkingCodex() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("vibemetric-locator-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let broken = try command(in: directory, name: "broken-codex", version: "0.999.0")
        try "#!/bin/sh\nexit 1\n".write(to: broken, atomically: false, encoding: .utf8)
        let working = try command(in: directory, name: "working-codex", version: "0.158.0")
        let found = try await CLILocator.discover(.codex, candidatePaths: [broken.path, working.path])
        #expect(found?.executable == working)
    }

    private func command(in directory: URL, name: String, version: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        let script = """
        #!/bin/sh
        if [ "$1" = "--version" ]; then
          printf 'codex-cli \(version)\\n'
        else
          printf '%s\\n' '--json --output-schema --output-last-message fork --ignore-user-config --ignore-rules --sandbox --skip-git-repo-check --strict-config'
        fi
        """
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }
}
