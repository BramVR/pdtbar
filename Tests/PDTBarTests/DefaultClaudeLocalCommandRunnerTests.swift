import Foundation
import Testing
import PDTBarAppSupport

@Suite("Default Claude local command runner")
struct DefaultClaudeLocalCommandRunnerTests {
    @Test("Timed-out runs return promptly when an escaped grandchild keeps the pipes open")
    func timedOutRunsReturnPromptlyWhenEscapedGrandchildKeepsPipesOpen() throws {
        let runner = DefaultClaudeLocalCommandRunner()
        let started = Date()

        // The direct child dies on SIGTERM, so the SIGKILL sweep never runs.
        // The backgrounded grandchild ignores SIGTERM, survives the kill
        // sweep, and keeps the inherited stdout/stderr write ends open long
        // past the timeout, so an unbounded reader join would hang run().
        let result = try runner.run(
            executable: "/bin/sh",
            arguments: ["-c", #"echo before-hang; /bin/sh -c 'trap "" TERM; exec sleep 15' & sleep 15"#],
            timeout: 0.5,
            environment: ["PATH": "/usr/bin:/bin"]
        )

        let elapsed = Date().timeIntervalSince(started)
        #expect(result.exitCode == -1)
        #expect(result.stdout.contains("before-hang"))
        // Timeout (0.5s) + terminate wait + bounded reader grace, with CI slack.
        #expect(elapsed < 5.0)
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
}
