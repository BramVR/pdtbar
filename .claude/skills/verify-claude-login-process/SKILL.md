---
name: verify-claude-login-process
description: "Check Claude login process, cancellation, timeout, or process-tree cleanup changes against the TLA+ model."
---

# Verify the Claude login process

`formal/claude-login-process/ClaudeLoginProcess.tla` models "Log in with Claude" from the menu click to the cleanup of the `claude auth login` process tree. TLC checks it in every order the click handler, runner thread, detached task, main queue, and CLI process can interleave.

## What it promises

- `StaleResultNeverApplied`. A login result reaches the menu only from the most recent click. Harm if broken: a slow earlier attempt overwrites the state of the attempt the user just started.
- `RootDeadOnReturn`. When the runner returns, `claude auth login` itself is no longer running. Harm if broken: a stray login CLI keeps the PTY and its browser flow alive after PDTBar moved on.
- `EveryAttemptReturns` (liveness). Every started attempt returns exactly once, so the runner never hangs. Harm if broken: the menu sits on "Opening Claude" forever.
- `LatestAttemptResolves` (liveness). The latest click always ends with its success or failure applied in the menu, unless a newer click superseded it.
- `NoOrphanOnReturn`. When the runner returns, nothing `claude auth login` spawned is still running. **Fails at the sync commit.** See Known finding.

## When to run it

Run it when a diff touches any covered code below, or changes how `claude auth login` is launched, cancelled, timed out, or killed. A change outside these functions does not need it.

## Covered code

Sync commit: `1b6ffd4`. The model was last confirmed against the code at this commit.

`Sources/PDTBarApp/main.swift`:

- `loginWithClaude` (344-368). Modelled by `Click` and `ApplyOnMain`. The gate guard sits at 350.
- `ClaudeCLILoginHandoff.startLogin` (1171-1196) and `clearActiveCancellation` (1198-1204). Modelled by `Click` and `Deliver`.

`Sources/PDTBarCore/LaunchRuntime.swift`:

- `ClaudeLoginAttemptGate.begin` and `finish` (118-145). Modelled by `gateActive`, `Click`, and `ApplyOnMain`.

`Sources/PDTBarCore/PDTCancellation.swift`:

- `PDTCancellation` (3-28), the login's cancellation token. Modelled by `cancelled`. The login creates it without a parent.

`Sources/PDTBarAppSupport/ClaudeLocalConnection.swift`:

- `ClaudeLocalLoginOutcome` (764-768).
- `ClaudeLocalLoginRunner.runBlocking` (804-839) and `runPTY` (841-897). Modelled by `Start`, `LaunchFails`, and `PostLoop`.
- `TTYCommandRunner.run` (1170-1536): the cancellation checks at 1177, 1349, 1455, and 1492, the launch at 1293, the read loop at 1454-1490, and the result at 1525-1536. Modelled by `Start` through `PostLoop`.
- `cleanup()` inside `TTYCommandRunner.run` (1247-1288) with `defer` at 1290, and the post-launch `setpgid` at 1301-1304. Modelled by `CleanScan`, `CleanTerm`, `CleanWait`, and `CleanReap`.
- `ClaudeLocalProcessTreeTerminator` (1626-1669). Modelled by `SweepReachesKid` and the cleanup actions.

Every action in the `.tla` carries a comment naming the Swift line it models (`M:` main.swift, `C:` ClaudeLocalConnection.swift, `L:` LaunchRuntime.swift).

To see whether covered code changed since the sync commit:

```bash
git diff 1b6ffd4 -- Sources/PDTBarApp/main.swift Sources/PDTBarCore/LaunchRuntime.swift Sources/PDTBarCore/PDTCancellation.swift Sources/PDTBarAppSupport/ClaudeLocalConnection.swift
```

Only hunks inside the functions above matter.

## How to run

Needs a JDK 11+. The runner pins TLA+ 1.7.4.

```bash
Scripts/formal/tlc.sh formal/claude-login-process/ClaudeLoginProcess.tla
Scripts/formal/tlc.sh formal/claude-login-process/ClaudeLoginProcess.tla formal/claude-login-process/OrphanFinding.cfg
```

Expected at the sync commit:

- `ClaudeLoginProcess.cfg` (two clicks) prints `Model checking completed. No error has been found.` with 186,349 distinct states, in about 20 seconds.
- `OrphanFinding.cfg` (one click) prints `Invariant NoOrphanOnReturn is violated.` in under a second. This is the known finding. Any other result means the model or the code changed.

Read every result with the `/statechart` skill. For a violation it shows the shortest path in plain words. For a pass it charts how the login moves between states.

## Known finding

`NoOrphanOnReturn` fails on current code. A process that `claude auth login` spawns can outlive the runner.

Shortest trace from `OrphanFinding.cfg`, in the code's names:

1. The user clicks "Log in with Claude". `TTYCommandRunner.run` launches `claude auth login`.
2. The read loop reaches its 120 s deadline. `PostLoop` records `timedOut`.
3. `cleanup()` snapshots `descendantPIDs(of:)`, which is still empty.
4. `claude auth login` spawns a helper.
5. `terminateProcessTree(SIGTERM)` rescans and signals the helper and root. Root exits. The helper ignores SIGTERM.
6. Root is no longer running, so cleanup SIGKILLs only the old, empty snapshot. `waitUntilExit` returns and the helper is still alive.

A plainer path needs no race and no ignored signal. `claude auth login` spawns a helper, prints "Successfully logged in", and exits during the 0.35 s settle. By the time `cleanup()` scans, the helper has been reparented to launchd, so `descendantPIDs(of:)` finds nothing, and no signal reaches it. A throwaway test at `032058b` reproduced this against the real `ClaudeLocalLoginRunner`. A fake login script ran `sleep 30 &`, and the `sleep` was still alive after `run()` returned `.success`.

Why the process group does not save it: Foundation's `Process` already starts the child in its own process group (pgid equals pid), so the later `setpgid(pid, pid)` at C:1302 always fails with `EACCES` and `processGroup` stays nil. That was measured on macOS 26 at `032058b`, before #239. #239 did not touch this code. Setting `ProcessGroupRecorded = TRUE` in a cfg shows that recording the group alone is not enough either. The root-dead branch of `cleanup()` (C:1279-1282) still SIGKILLs only the snapshot, so a helper spawned after the SIGTERM sweep escapes. A fix needs both: use the group Foundation already created, and SIGKILL that group on both branches.

When a fix lands, mirror it in the model, confirm `OrphanFinding.cfg` passes, then move `NoOrphanOnReturn` into `ClaudeLoginProcess.cfg` and delete `OrphanFinding.cfg`.

## Real bug or modelling error

When TLC reports a violation:

1. Read the trace with `/statechart` and write it down as steps in the code's names.
2. For each step, open the Swift line the action's comment names and confirm that the code can take that step in that order. Two steps the model splits must really be separable in the code. One step the model treats as atomic must not have a cancellation check, signal, or process event in the middle.
3. If every step is possible in the code, it is a real bug. Report it with the trace. Do not weaken the property or the model to make it pass.
4. If a step is impossible in the code, the model is wrong. Fix the action so it matches the code, cite the line, and rerun.

Known modelling shortcuts that do not produce false traces: one `kid` stands for any number of spawned processes, a loop iteration's cancellation check, read, and exit check are separate actions, and the CLI's output is collapsed to `marker` (a success substring is in the buffer).

## Updating the model

When a change is intended:

1. Edit the matching action in `ClaudeLoginProcess.tla` and update its `C:`/`M:`/`P:` line comment.
2. Run both commands above.
3. Prove the changed property can still fail. Apply its mutation below to a scratch copy and confirm that TLC catches it.
4. Update the line anchors in this skill. Move the sync commit forward only after you confirm the model describes the code at the new commit.

Mutations that each property must catch. Each ran at `032058b`, and the `StaleResultNeverApplied` one ran again at `1b6ffd4`:

- `StaleResultNeverApplied`. In `ApplyOnMain`, replace `IF gateActive = a` with `IF TRUE` (the main.swift:350 gate guard removed). Result: the invariant is violated.
- `EveryAttemptReturns`. In `CleanWait`, make the root-alive branch `UNCHANGED <<kid, root, exitStatus>>` (the SIGKILL escalation at C:1272-1278 removed). Result: temporal properties are violated, because the run stutters in `cleanReap` (`waitUntilExit` hangs).
- `RootDeadOnReturn`. In `PostLoop`, go to `"returned"` instead of `"cleanScan"` unless cancelled (`defer { cleanup() }` replaced by cleanup on errors only). Result: the invariant is violated.
- `LatestAttemptResolves`. In `PostLoop`, change `"timedOut"` to `"cancelled"` (runBlocking mapping a timeout to `.cancelled`). Result: temporal properties are violated, because the latest click is never resolved.

## Out of scope

- `DefaultClaudeLocalCommandRunner.run` (`Sources/PDTBarAppSupport/DefaultClaudeLocalCommandRunner.swift`) and `ClaudeLocalPipeDrain` (the `claude auth status`, `claude -p`, and `claude mcp list` path). They use the same `setProcessGroup` call (line 70) and `ClaudeLocalProcessTreeTerminator`, so the process-group part of the finding applies there by reading the code, but the model does not check that path.
- Refresh cancellation from #239 and app quit. `applicationWillTerminate` cancels only the background refresh, not a running login.
- What `launchRuntime.beginLoginHandoff` and `completeLoginHandoff` do with the result, and what happens to other menu states while a login runs.
- The PTY byte stream: the rolling needle buffer, send-on-substring answers, cursor queries, URL detection, and partial reads of the success marker at the deadline.
- Processes that leave root's process group (`setsid`, daemonizing helpers), PID reuse, and a root process that cannot be killed by SIGKILL.
- Bounds: two clicks in `ClaudeLoginProcess.cfg`, one click in `OrphanFinding.cfg`, and one spawned helper per attempt.
