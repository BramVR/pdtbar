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
- `NoOrphanOnReturn`. When the runner returns, nothing `claude auth login` spawned is still running. Harm if broken: an invisible helper outlives the attempt, and repeated clicks pile them up (#271).

## When to run it

Run it when a diff touches any covered code below, or changes how `claude auth login` is launched, cancelled, timed out, or killed. A change outside these functions does not need it.

## Covered code

Sync commit: `35b1343`. The model was last confirmed against the code at this commit.

`Sources/PDTBarApp/main.swift`:

- `loginWithClaude` (326-348). Modelled by `Click` and `ApplyOnMain`. The gate guard sits at 331.
- `ClaudeCLILoginHandoff.startLogin` (1153-1178) and `clearActiveCancellation` (1180-1186). Modelled by `Click` and `Deliver`.

`Sources/PDTBarCore/LaunchRuntime.swift`:

- `ClaudeLoginAttemptGate.begin` and `finish` (118-145). Modelled by `gateActive`, `Click`, and `ApplyOnMain`.

`Sources/PDTBarCore/PDTCancellation.swift`:

- `PDTCancellation` (3-28), the login's cancellation token. Modelled by `cancelled`. The login creates it without a parent.

`Sources/PDTBarAppSupport/ClaudeLocalConnection.swift`:

- `ClaudeLocalLoginOutcome` (764-768).
- `ClaudeLocalLoginRunner.runBlocking` (804-839) and `runPTY` (841-897). Modelled by `Start`, `LaunchFails`, and `PostLoop`.
- `TTYCommandRunner.run` (1170-1483): the cancellation checks at 1177, 1297, 1403, and 1439, the spawn at 1241, the read loop at 1402-1437, `child.end()` at 1472, and the result at 1473-1482. Modelled by `Start` through `PostLoop`, then the cleanup actions.

`Sources/PDTBarAppSupport/ChildProcessGroup.swift`:

- `ChildProcessGroup.spawn` (48-95) starts root as the leader of a new process group and throws on any failed spawn attribute or file action. `isRunning` (97) polls without reaping. `end()` (106) and `deinit` (112) both run `terminate` (116-134): SIGTERM the group, wait up to 2 s for root, SIGKILL the group, reap root. Only a `RootObservation.unreaped` value (144-160) carries the `ReservedGroup` (163-174) that can signal the group. Modelled by `Launch`, `LoopProcessExited`, `CleanTerm`, `CleanWait`, and `CleanReap`.

Every action in the `.tla` carries a comment naming the Swift line it models (`M:` main.swift, `C:` ClaudeLocalConnection.swift, `G:` ChildProcessGroup.swift, `L:` LaunchRuntime.swift).

To see whether covered code changed since the sync commit:

```bash
git diff 35b1343 -- Sources/PDTBarApp/main.swift Sources/PDTBarCore/LaunchRuntime.swift Sources/PDTBarCore/PDTCancellation.swift Sources/PDTBarAppSupport/ClaudeLocalConnection.swift Sources/PDTBarAppSupport/ChildProcessGroup.swift
```

Only hunks inside the functions above matter.

## How to run

Needs a JDK 11+. The runner pins TLA+ 1.7.4.

```bash
Scripts/formal/tlc.sh formal/claude-login-process/ClaudeLoginProcess.tla
formal/claude-login-process/mutations.sh
```

Expected at the sync commit:

- `ClaudeLoginProcess.cfg` (two clicks) prints `Model checking completed. No error has been found.` with 65,042 distinct states, in under 10 seconds.
- `mutations.sh` prints one row per mutation, each with the property it expects reported as violated, and exits 0. A row that reports `No error has been found` means the model lost its teeth.

Read every result with the `/statechart` skill. For a violation it shows the shortest path in plain words. For a pass it charts how the login moves between states.

## Why the group kill is safe and complete

`posix_spawn` with `POSIX_SPAWN_SETPGROUP` makes root the leader of a new group whose id is root's pid. Everything root spawns inherits that group unless it calls `setsid` or `setpgid` itself. Root is never reaped before the final SIGKILL, so the group id cannot be reused, and `kill(-pid, …)` reaches helpers even after they are reparented to launchd. The SIGKILL runs on every path, whether or not root already exited, which is what #271's root-dead branch got wrong.

Before #271 the code used Foundation's `Process`. It already put the child in its own group, so the post-launch `setpgid(pid, pid)` always failed with `EACCES` and the group was never signalled. Foundation also reaps the child on its own thread, so a wrapper around `Process` could not prove that a later group signal still targets the login's group.

## Real bug or modelling error

When TLC reports a violation:

1. Read the trace with `/statechart` and write it down as steps in the code's names.
2. For each step, open the Swift line the action's comment names and confirm that the code can take that step in that order. Two steps the model splits must really be separable in the code. One step the model treats as atomic must not have a cancellation check, signal, or process event in the middle.
3. If every step is possible in the code, it is a real bug. Report it with the trace. Do not weaken the property or the model to make it pass.
4. If a step is impossible in the code, the model is wrong. Fix the action so it matches the code, cite the line, and rerun.

Known modelling shortcuts that do not produce false traces: one `kid` stands for any number of spawned processes, a loop iteration's cancellation check, read, and exit check are separate actions, and the CLI's output is collapsed to `marker` (a success substring is in the buffer).

## Updating the model

When a change is intended:

1. Edit the matching action in `ClaudeLoginProcess.tla` and update its `C:`/`G:`/`M:`/`L:` line comment.
2. Run both commands above.
3. Prove the changed property can still fail. Add or adjust its row in `mutations.sh` and confirm that the row reports a violation.
4. Update the line anchors in this skill. Move the sync commit forward only after you confirm the model describes the code at the new commit.

`mutations.sh` rows, each confirmed at `35b1343`:

- `rootDeadSkipsGroup` (`NoOrphanOnReturn`). `CleanWait` kills the helper only while root is alive. This is #271's root-dead branch. The trace matches the issue: deadline, helper spawned after cleanup starts, root dies on SIGTERM, helper survives.
- `noGroupKill` (`NoOrphanOnReturn`). `CleanWait` never kills the helper, as when the process group was never recorded.
- `noGateGuard` (`StaleResultNeverApplied`). The main.swift:331 gate guard removed.
- `noKillEscalation` (temporal). The SIGKILL removed: `waitpid` hangs on a root that ignores SIGTERM. `NoOrphanOnReturn` is dropped for this row, because it also catches it.
- `cleanupOnErrorsOnly` (`RootDeadOnReturn`). A normal return skips `end()`. `NoOrphanOnReturn` is dropped for this row.
- `timeoutAsCancelled` (temporal). `runBlocking` maps a timeout to `.cancelled`, so the latest click is never resolved.

## Out of scope

- `DefaultClaudeLocalCommandRunner.run` (the `claude auth status`, `claude -p`, and `claude mcp list` path). It uses the same `ChildProcessGroup`, so it gets the same cleanup, but the model does not check its loop or `ClaudeLocalPipeDrain`.
- Refresh cancellation from #239 and app quit. `applicationWillTerminate` cancels only the background refresh, not a running login.
- What `launchRuntime.beginLoginHandoff` and `completeLoginHandoff` do with the result, and what happens to other menu states while a login runs.
- The PTY byte stream: the rolling needle buffer, send-on-substring answers, cursor queries, URL detection, and partial reads of the success marker at the deadline.
- A foreign reaper. If something else in PDTBar reaped root, `RootObservation.lost` makes cleanup signal nothing, because the group id may already be reused. The app has no other reaper, so the model leaves this state out.
- Processes that leave root's process group (`setsid`, daemonizing helpers), a group member that forks at the instant the group SIGKILL is sent, and a root process that cannot be killed by SIGKILL.
- Bounds: two clicks and one spawned helper per attempt.
