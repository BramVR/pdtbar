import Darwin
import Foundation
import PDTBarAppSupport
import PDTBarCore
import Testing

@Suite("Claude local login runner", .serialized)
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

    enum AttemptEnd: String, CaseIterable, Sendable {
        case success
        case failure
        case timeout
        case cancel
    }

    @Test(
        "No helper from the login process tree outlives the attempt",
        arguments: AttemptEnd.allCases
    )
    func noHelperOutlivesTheAttempt(end: AttemptEnd) async throws {
        let directory = try temporaryDirectory(prefix: "pdtbar-login-helper-\(end.rawValue)")
        let pidFile = directory.appending(path: "helper.pid")
        let rootEnding = switch end {
        case .success: "printf 'Successfully logged in\\n'; exit 0"
        case .failure: "printf 'Claude login failed\\n'; exit 42"
        case .timeout, .cancel: "printf 'Waiting for browser\\n'; exec sleep 30"
        }
        // The subshell exits at once, so the helper is reparented to launchd
        // before any descendant scan can see it, and it ignores SIGTERM.
        let script = try writeLoginScript(
            directory: directory,
            name: "login.sh",
            body: """
            #!/bin/sh
            ( /bin/sh -c 'trap "" TERM; exec sleep 30' & echo $! > "\(pidFile.path)" )
            \(rootEnding)
            """
        )
        let cancellation = PDTCancellation()
        if end == .cancel {
            DispatchQueue.global().async {
                let deadline = Date().addingTimeInterval(5)
                while !FileManager.default.fileExists(atPath: pidFile.path), Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.05)
                }
                cancellation.cancel()
            }
        }
        let runner = ClaudeLocalLoginRunner(environment: ["PATH": "/usr/bin:/bin"], binary: script.path)

        let outcome = await runner.run(
            timeout: end == .timeout ? 1.0 : 10,
            cancellation: cancellation,
            onPhaseChange: { _ in }
        )

        let expected: ClaudeLocalLoginOutcome = switch end {
        case .success: .success
        case .failure: .failed(.failed, "claude auth login exited with status 42")
        case .timeout: .failed(.timedOut, "Claude login timed out")
        case .cancel: .cancelled
        }
        #expect(outcome == expected)
        let helperPID = try #require(pid_t(
            String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        ))
        defer { kill(helperPID, SIGKILL) }
        #expect(processHasExited(helperPID), "helper \(helperPID) outlived the \(end.rawValue) attempt")
    }
}

private func processHasExited(_ pid: pid_t) -> Bool {
    let deadline = Date().addingTimeInterval(1.0)
    repeat {
        if kill(pid, 0) != 0, errno == ESRCH {
            return true
        }
        Thread.sleep(forTimeInterval: 0.05)
    } while Date() < deadline
    return false
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
