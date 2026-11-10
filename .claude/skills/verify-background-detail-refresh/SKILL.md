---
name: verify-background-detail-refresh
description: "Check a background detail refresh or price-history worker change against its TLA+ model."
---

# Verify background detail refresh

`formal/background-detail-refresh/BackgroundDetailRefresh.tla` models one run of `PDTBackgroundDetailRefresh.refresh`. It covers the phase sequence, per-phase commits, retry rules, cancellation, the auth/setup outage skip, and the price-history worker pool racing its deadline. TLC checks every interleaving of the main thread, two workers, three holdings, the deadline, and a cancel.

## Promises checked

- `CommittedNeverLost`. A slice committed fresh is never overwritten by a later phase, a later failure, a cancel, or the final commit.
- `ReturnedHasSucceededPhases`. Every optional phase that finished cleanly is on disk when `refresh` returns. Price history is not committed when its phase ends. Only the performance commit or `PressureRunner.refreshedPulse` writes it.
- `OutcomeHonest`. The outcome is `degraded` exactly when allocation, X-ray, income, or any price-history holding failed or returned a diagnostic, or the performance phase timed out.
- `NoDeterministicRetry`. Only `transientFailure`, `timeout`, and `exit` are retried. The list is written out in the property, apart from `isRetryable`, so a classifier change shows up.
- `NoPhaseAfterOutage`. Once a `setupUnavailable` or `unavailable` diagnostic is recorded, no later phase starts a Claude CLI run.
- `ConcurrencyBound`. At most `priceHistoryConcurrencyLimit` price-history runs are in flight.
- `PullAtMostOnce`. `nextQuoteID` hands each holding out at most once.
- `ExactlyOnceAtReturn`. When `priceSeries` returns, each holding is either refreshed or failed, never both and never neither.
- `ResultFrozen`. Late workers never change the accumulator after `priceSeries` returned it.
- `NoRetryAfterDeadline`. No price-history retry starts a new Claude CLI run after the deadline.
- `Terminates`. The refresh always returns or throws, even when the deadline fires or a cancel lands mid-flight.

## Covered code and sync commit

Sync commit: `3f0860d`. The model was last confirmed against the code at this commit.

- `Sources/PDTBarCore/PDTBackgroundDetailRefresh.swift:8-41`. `PDTDetailRefreshFailureCategory`, `isRetryable`, `indicatesUnavailableSetup`.
- `Sources/PDTBarCore/PDTBackgroundDetailRefresh.swift:90-130`. `PDTBackgroundDetailRefreshOptions` (concurrency limit, retry count, timeouts).
- `Sources/PDTBarCore/PDTBackgroundDetailRefresh.swift:173-441`. `refresh` and `runOptionalPhase`: cancellation checkpoints, tool discovery, base phase, the one outage gate and failure channel, per-phase commits, pagination diagnostics, performance and its timeout diagnostic, outcome, final commit.
- `Sources/PDTBarCore/PDTBackgroundDetailRefresh.swift:468-509`. `availableReadTools`, `preserveOptionalDetails`.
- `Sources/PDTBarCore/PDTBackgroundDetailRefresh.swift:511-558`. `performanceSummary`, `callPerformanceDecoded`.
- `Sources/PDTBarCore/PDTBackgroundDetailRefresh.swift:577-663`. `xRayHoldings`, `incomeEvents` (only whether they return a diagnostic).
- `Sources/PDTBarCore/PDTBackgroundDetailRefresh.swift:853-981`. `priceSeries`: worker loop, deadline, cancellation, `group.wait`, abandonment.
- `Sources/PDTBarCore/PDTBackgroundDetailRefresh.swift:983-1102`. `callDecoded`, `callDecodedWithRetry`, `throwIfCancelled`.
- `Sources/PDTBarCore/PDTBackgroundDetailRefresh.swift:1135-1243`. `PDTPriceHistoryAccumulator`, `PDTPriceHistoryWorkTracker`.
- `Sources/PDTBarCore/PDTLiveDataSource.swift:605-678`. `PDTListPaginationResult.truncationDiagnostic`, `paginatePDTList` (only the `.timeout` truncation diagnostic).
- `Sources/PDTBarCore/PDTCancellation.swift`. The cancel flag and its parent link.
- `Sources/PDTBarCore/LaunchRuntime.swift:213`. `BackgroundDetailRefreshPhase` (phase order only).

Every action in the spec names the Swift lines it models. To see whether a change touches this model, run:

```bash
git diff 3f0860d -- Sources/PDTBarCore/PDTBackgroundDetailRefresh.swift Sources/PDTBarCore/PDTCancellation.swift Sources/PDTBarCore/PDTLiveDataSource.swift | grep -n '^@@'
```

If a hunk falls in a range above, recheck the model. Line numbers drift with unrelated edits, so match by function name when they do.

## Run

Needs a JDK 11+. The runner pins TLA+ 1.7.4 and runs one TLC worker unless `PDTBAR_TLC_WORKERS` is set.

```bash
Scripts/formal/tlc.sh formal/background-detail-refresh/BackgroundDetailRefresh.tla
```

Expected at the sync commit: `No error has been found`, 3,290,492 distinct states, about 3 minutes on one worker or about 1 minute with `PDTBAR_TLC_WORKERS=4`. Any failure means the change broke something or the model needs updating.

## Retired findings

- `NoPhaseAfterOutage` (#272). Only a phase that threw reached `recordOptionalPhaseFailure`, the one writer of `skipRemainingPhasesForUnavailableSetup`. Price history never throws. It returns its per-holding diagnostics, so an outage seen there let the performance phase start one more doomed CLI run. TLC's shortest trace had 21 states: base and the first three optional phases succeed, a price-history worker gets `setupUnavailable`, the main thread abandons the rest, `Collect` leaves the flag false, and `Advance` enters performance. Fixed by `3f0860d`. Every optional phase now runs through `runOptionalPhase`, which is the only writer of `diagnostics` and skips the phase when `diagnostics` already holds an outage category. The boolean is gone. In the model, `skip` became `diagOutage` ("`diagnostics` holds an outage"), and both `OptionalFails` and `Collect` set it. The knob and `BackgroundDetailRefreshFindingsFixed.cfg` are gone. Making `Collect` leave `diagOutage` unchanged reproduces the 21-state trace.

- `NoRetryAfterDeadline`. `priceSeries` called `callDecodedWithRetry` without `retryDeadline`, so a transient price-history failure past the deadline started another full CLI run. Fixed by `f11cf27` (#236), which passes `retryDeadline: deadline`. `a4ffe5a` (#239) made `retryDeadline` required for every call. The knob is gone and the property stays as a guard. Dropping `~pastDeadline` from the retry guard in `WCallReturns` and from `WBackoffEnds`, which mirrors deleting `now() < retryDeadline` at `:1047` and the guard at `:1013`, fails it.

## Reading a result

Read every TLC result with the `/statechart` skill. A violation comes back as its shortest path in plain words. A pass comes back as a chart of how the refresh moves between states.

## Real bug or modeling error

Replay the trace against the Swift code, one action at a time, using the line numbers in each action's comment.

- It is a real bug when each step is something the code can do, in that order, with no lock or check between steps that the model leaves out. Report it with the trace in the code's names. Do not weaken the property or change product code unless asked.
- It is a modeling error when a step does something the code cannot do. Examples: two actions the code runs under one lock, split apart in the model. A value the model lets change that the code keeps fixed. A category the code never produces at that call site. Fix the model and say what you fixed.

Atomicity the model relies on:

- `WComplete` is one step because `PDTPriceHistoryWorkTracker.complete` runs the accumulator append inside its own lock.
- `Decide` is one step because `markAbandoned` empties pending and marks running holdings under one lock. It reads `cancelled` and the outage category first. Those flags only turn on, so reading them a little earlier reaches no other branch.
- `WCheck` reads the deadline, the cancel flag, and the outage flag in one step. All three only ever turn on.
- `WPull` merges `nextQuoteID` with the top of `callDecodedWithRetry` (cancel check, deadline guard) and the first CLI run. Nothing between them reads shared state other than those flags.
- `WBackoffEnds` merges the post-backoff cancel check, the next iteration's deadline guard, and the next run's start.
- A main-thread step that passes a `throwIfCancelled` checkpoint needs `~cancelled`. A cancel that lands just after a checkpoint is the same as the step running first and `Cancel` after it.

## Modeling choices

- `RetryCount = 1`. The app uses the default `optionalRetryCount: 0`, so the connector owns retries and the refresh layer never retries. Tests set it to 1. With 1, every behavior of 0 is still reachable up to the failure category, because a fail action may end a call with any category (the call's deadline can refuse a retry). The retry guards are only exercised with 1.
- The sequential phases' own deadlines (`effectivePaginationTimeoutSeconds`) are not clocks in the model. A guard that refuses a retry on the deadline shows up as the phase failing.
- X-ray and income can succeed with a `.timeout` diagnostic (`OptionalSucceedsWithDiagnostic`): pagination truncated by the page cap or deadline, or the income quote scan out of time. The slice is committed and the refresh degrades, but no outage is recorded.
- Cancellation is one flag. `priceCancellation` adds no state, because it is cancelled only when the caller cancelled or the deadline passed.

## Updating the model

When a covered function changes on purpose:

1. Edit the matching action so it does what the new code does, and update its line comment.
2. New shared state or a new lock section becomes a new variable or a new action. Keep one action per lock section.
3. Run both configs. Compare against the expected results above.
4. Prove a changed property can still fail. Break the new code path in a scratch edit, mirror the break in the model, see TLC fail, then revert both.
5. Move the sync commit and the line ranges forward only after you confirm the model describes the code at the new commit.

Bounds live in the `.cfg` files: `HoldingCount = 3`, `Limit = 2`, `RetryCount = 1`, `FailureCategories = {"transientFailure", "decode", "setupUnavailable"}`, one representative per retry class. Raising `HoldingCount` to 4 or adding categories grows the state space fast, so run that once, not on every change.

## How the properties were shown to fail

At `1b6ffd4`, a scratch change to the real code dropped `!abandonedQuoteIDs.contains(quoteID)` from `PDTPriceHistoryWorkTracker.complete` (`:1209`). `swift build` still passed. With the matching model edit (`record == h \notin finished` in `WComplete`), the config failed with `ResultFrozen`. Each other property also fails when its line in the model is broken this way:

- `CommittedNeverLost`. `Finalize` commits the prior snapshot instead of `snap`.
- `ReturnedHasSucceededPhases`. `Finalize` skips the commit (`store' = store`).
- `OutcomeHonest`. `Collect` drops the price-history diagnostics, or `Performance` drops its timeout diagnostic.
- `NoPhaseAfterOutage`. `Collect` leaves `diagOutage` unchanged (the #272 bug, 21 states), `OptionalFails` leaves it unchanged, or `Advance` ignores it. Rechecked at `3f0860d` with the #272, `ReturnedHasSucceededPhases`, `OutcomeHonest` (`Collect`), `NoDeterministicRetry`, and `ConcurrencyBound` mutations above. Each failed with its own invariant.
- `NoDeterministicRetry`. `IsRetryable` includes `"decode"`.
- `ConcurrencyBound`. `Workers == 1 .. HoldingCount`, so the `min` with the limit is dropped.
- `PullAtMostOnce`. `WPull` does not pop `pending`.
- `ExactlyOnceAtReturn`. `markAbandoned` ignores pending holdings.
- `NoRetryAfterDeadline`. The retry guard in `WCallReturns` and `WBackoffEnds` ignore `pastDeadline`.
- `Terminates`. `RecordAbandoned` never runs. Run with `-deadlock` to see the temporal failure instead of the deadlock.

## Out of scope

- Pagination page by page. Each optional phase is one action that succeeds, succeeds with a truncation diagnostic, or fails. Snapshot contents are not modeled, so a truncated slice still counts as fresh.
- The income quote scan's own deadline. Only its timeout diagnostic is modeled. `BackgroundDetailRefreshTests.swift` covers the rest.
- The connector's own retry in `ClaudeLocalConnection.callReadTool` and `ClaudeToolCallRetryPolicy`, and how a cancel kills the running CLI process. Each model run is one connector call that can return any category.
- `markCompleted` and the progress callbacks, including progress sent after the phase ended.
- Store write errors. A throwing `PressureRunner.refreshedPulse` would lose the uncommitted price history.
- The app side: `PDTLaunchRuntime`, `portfolioRefreshInFlight`, `activeRefreshCancellation`, and runs that overlap a later refresh.
- Snapshot contents. Slices are only `prior`, `fresh`, or `none`.
