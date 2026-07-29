import Darwin
import Foundation
import PDTBarAppSupport
import PDTBarCore
import Testing

@Suite("Default Claude local command runner")
struct DefaultClaudeLocalCommandRunnerTests {
    @Test("Already-cancelled runs do not launch a child")
    func alreadyCancelledRunsDoNotLaunchChild() throws {
        let runner = DefaultClaudeLocalCommandRunner()
        let cancellation = PDTCancellation()
        cancellation.cancel()
        let markerFile = FileManager.default.temporaryDirectory
            .appending(path: "pdtbar-pre-cancelled-\(UUID().uuidString).marker")
        defer {
            try? FileManager.default.removeItem(at: markerFile)
        }

        let result = try runner.run(
            executable: "/bin/sh",
            arguments: ["-c", #"touch "$MARKER_FILE""#],
            timeout: 10,
            environment: ["PATH": "/usr/bin:/bin", "MARKER_FILE": markerFile.path],
            cancellation: cancellation
        )

        #expect(result.exitCode == -1)
        #expect(!FileManager.default.fileExists(atPath: markerFile.path))
    }

    @Test("Cancelled runs terminate the child before the configured timeout")
    func cancelledRunsTerminateChildBeforeTimeout() throws {
        let runner = DefaultClaudeLocalCommandRunner()
        let cancellation = PDTCancellation()
        let pidFile = FileManager.default.temporaryDirectory
            .appending(path: "pdtbar-cancelled-child-\(UUID().uuidString).pid")
        defer {
            try? FileManager.default.removeItem(at: pidFile)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
            cancellation.cancel()
        }

        let started = Date()
        let result = try runner.run(
            executable: "/bin/sh",
            arguments: [
                "-c",
                #"echo $$ > "$PID_FILE"; exec sleep 15"#,
            ],
            timeout: 10,
            environment: ["PATH": "/usr/bin:/bin", "PID_FILE": pidFile.path],
            cancellation: cancellation
        )
        let elapsed = Date().timeIntervalSince(started)

        #expect(result.exitCode == -1)
        #expect(elapsed < 4.0)
        let childPID = try #require(pid_t(
            String(contentsOf: pidFile).trimmingCharacters(in: .whitespacesAndNewlines)
        ))
        #expect(eventuallyProcessExits(childPID))
    }

    @Test("Timed-out runs return promptly when an escaped grandchild keeps the pipes open")
    func timedOutRunsReturnPromptlyWhenEscapedGrandchildKeepsPipesOpen() throws {
        let runner = DefaultClaudeLocalCommandRunner()
        let started = Date()
        let pidFile = FileManager.default.temporaryDirectory
            .appending(path: "pdtbar-grandchild-\(UUID().uuidString).pid")

        // The direct child dies on SIGTERM, while the backgrounded grandchild
        // ignores SIGTERM and keeps the inherited stdout/stderr write ends
        // open long past the timeout. `run()` must still return promptly and
        // must not leave that grandchild alive for later fetch retries.
        let result = try runner.run(
            executable: "/bin/sh",
            arguments: [
                "-c",
                #"echo before-hang; /bin/sh -c 'trap "" TERM; exec sleep 15' & echo $! > "$PID_FILE"; sleep 15"#,
            ],
            timeout: 0.5,
            environment: ["PATH": "/usr/bin:/bin", "PID_FILE": pidFile.path]
        )

        let elapsed = Date().timeIntervalSince(started)
        #expect(result.exitCode == -1)
        #expect(result.stdout.contains("before-hang"))
        // Timeout (0.5s) + terminate wait + bounded reader grace, with CI slack.
        #expect(elapsed < 5.0)
        let escapedPID = try #require(pid_t(String(contentsOf: pidFile).trimmingCharacters(in: .whitespacesAndNewlines)))
        #expect(eventuallyProcessExits(escapedPID))
    }

    @Test("Cancellation after root exit terminates a pipe-holding descendant")
    func cancellationAfterRootExitTerminatesDescendant() throws {
        let runner = DefaultClaudeLocalCommandRunner()
        let cancellation = PDTCancellation()
        let pidFile = FileManager.default.temporaryDirectory
            .appending(path: "pdtbar-exited-root-grandchild-\(UUID().uuidString).pid")
        defer {
            try? FileManager.default.removeItem(at: pidFile)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            cancellation.cancel()
        }

        let started = Date()
        let result = try runner.run(
            executable: "/bin/sh",
            arguments: [
                "-c",
                #"/bin/sh -c 'trap "" TERM; exec sleep 15' & echo $! > "$PID_FILE"; sleep 0.3"#,
            ],
            timeout: 10,
            environment: ["PATH": "/usr/bin:/bin", "PID_FILE": pidFile.path],
            cancellation: cancellation
        )
        let elapsed = Date().timeIntervalSince(started)

        #expect(result.exitCode == -1)
        #expect(elapsed < 4.0)
        let descendantPID = try #require(pid_t(
            String(contentsOf: pidFile).trimmingCharacters(in: .whitespacesAndNewlines)
        ))
        #expect(eventuallyProcessExits(descendantPID))
    }

    @Test("Normal runs still drain output larger than the pipe buffer in full")
    func normalRunsStillDrainOutputLargerThanPipeBufferInFull() throws {
        let runner = DefaultClaudeLocalCommandRunner()
        let expectedLine = "0123456789abcdef"
        let expectedLineCount = 8192

        let result = try runner.run(
            executable: "/bin/sh",
            arguments: ["-c", "yes \(expectedLine) | head -n \(expectedLineCount); echo drained-err 1>&2"],
            timeout: 10,
            environment: ["PATH": "/usr/bin:/bin"]
        )

        #expect(result.exitCode == 0)
        #expect(result.stdout.count == (expectedLine.count + 1) * expectedLineCount)
        #expect(result.stderr.contains("drained-err"))
    }

    private func eventuallyProcessExits(_ pid: pid_t) -> Bool {
        let deadline = Date().addingTimeInterval(2.0)
        repeat {
            if kill(pid, 0) != 0, errno == ESRCH {
                return true
            }
            Thread.sleep(forTimeInterval: 0.05)
        } while Date() < deadline
        return false
    }
}
