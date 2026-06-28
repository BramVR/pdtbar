import Foundation
import Testing
import PDTBarAppSupport

@Suite("Claude local login runner")
struct ClaudeLocalLoginRunnerTests {
    @Test("Product login runner ignores inherited scripted binary environment")
    func productLoginRunnerIgnoresInheritedScriptedBinaryEnvironment() async throws {
        let directory = try temporaryDirectory(prefix: "pdtbar-login-env-hook")
        let marker = directory.appending(path: "env-hook-marker")
        let hook = try writeLoginScript(
            directory: directory,
            name: "env-hook.sh",
            body: """
            #!/bin/sh
            printf invoked > "\(marker.path)"
            printf 'Successfully logged in\\n'
            exit 0
            """
        )

        let runner = ClaudeLocalLoginRunner(
            environment: [
                "PDTBAR_CLAUDE_BIN": hook.path,
                "PATH": "/usr/bin:/bin",
            ],
            binary: "pdtbar-missing-claude-for-test"
        )

        let outcome = await runner.run(timeout: 0.2, onPhaseChange: { _ in })

        #expect(outcome == .failed(.missingBinary, "Claude CLI not found"))
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }

    @Test("Product binary selection preserves configured Claude binary")
    func productBinarySelectionPreservesConfiguredClaudeBinary() throws {
        let binary = ClaudeLocalLoginRunner.productBinary(
            environment: ["PDTBAR_CLAUDE_BIN": "/usr/local/bin/claude-wrapper"]
        )

        #expect(binary == "/usr/local/bin/claude-wrapper")
    }

    @Test("Default runner preserves configured Claude binary")
    func defaultRunnerPreservesConfiguredClaudeBinary() throws {
        let configured = ClaudeLocalLoginRunner(
            environment: ["PDTBAR_CLAUDE_BIN": "/usr/local/bin/claude-wrapper"]
        )

        #expect(configured.binary == "/usr/local/bin/claude-wrapper")
    }

    @Test("Scripted handoff environment removes inherited Claude binary")
    func scriptedHandoffEnvironmentRemovesInheritedClaudeBinary() throws {
        let sanitized = ClaudeLocalEnvironment.removingScriptedHandoffHook([
            "PDTBAR_CLAUDE_BIN": "/tmp/pdtbar-tests/handoff-success.sh",
            "PDTBAR_CLAUDE_HANDOFF_MARKER": "/tmp/pdtbar-tests/marker",
        ])
        let preserved = ClaudeLocalEnvironment.removingScriptedHandoffHook([
            "PDTBAR_CLAUDE_BIN": "/usr/local/bin/claude-wrapper",
        ])

        #expect(sanitized["PDTBAR_CLAUDE_BIN"] == nil)
        #expect(preserved["PDTBAR_CLAUDE_BIN"] == "/usr/local/bin/claude-wrapper")
    }

    @Test("Explicit scripted login binary can fake success")
    func explicitScriptedLoginBinaryCanFakeSuccess() async throws {
        let directory = try temporaryDirectory(prefix: "pdtbar-login-success")
        let script = try writeLoginScript(
            directory: directory,
            name: "success.sh",
            body: """
            #!/bin/sh
            printf 'Successfully logged in\\n'
            exit 0
            """
        )

        let runner = ClaudeLocalLoginRunner(environment: ["PATH": "/usr/bin:/bin"], binary: script.path)

        let outcome = await runner.run(timeout: 1.0, onPhaseChange: { _ in })

        #expect(outcome == .success)
    }

    @Test("Explicit scripted login binary can fake failure")
    func explicitScriptedLoginBinaryCanFakeFailure() async throws {
        let directory = try temporaryDirectory(prefix: "pdtbar-login-failure")
        let script = try writeLoginScript(
            directory: directory,
            name: "failure.sh",
            body: """
            #!/bin/sh
            printf 'Claude login failed\\n'
            exit 42
            """
        )

        let runner = ClaudeLocalLoginRunner(environment: ["PATH": "/usr/bin:/bin"], binary: script.path)

        let outcome = await runner.run(timeout: 1.0, onPhaseChange: { _ in })

        #expect(outcome == .failed(.failed, "claude auth login exited with status 42"))
    }
}

private func temporaryDirectory(prefix: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "\(prefix)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func writeLoginScript(directory: URL, name: String, body: String) throws -> URL {
    let script = directory.appending(path: name)
    try Data(body.utf8).write(to: script, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
    return script
}
