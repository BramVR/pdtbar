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

Sync commit: `1b6ffd4`. The model was last confirmed against the code at this commit.

- `Sources/PDTBarCore/PDTBackgroundDetailRefresh.swift:8-41`. `PDTDetailRefreshFailureCategory`, `isRetryable`, `indicatesUnavailableSetup`.
- `Sources/PDTBarCore/PDTBackgroundDetailRefresh.swift:90-130`. `PDTBackgroundDetailRefreshOptions` (concurrency limit, retry count, timeouts).
- `Sources/PDTBarCore/PDTBackgroundDetailRefresh.swift:166-428`. `refresh`: cancellation checkpoints, tool discovery, base phase, `recordOptionalPhaseFailure`, skip gates, per-phase commits, pagination diagnostics, performance and its timeout diagnostic, outcome, final commit.
- `Sources/PDTBarCore/PDTBackgroundDetailRefresh.swift:455-496`. `availableReadTools`, `preserveOptionalDetails`.
- `Sources/PDTBarCore/PDTBackgroundDetailRefresh.swift:498-545`. `performanceSummary`, `callPerformanceDecoded`.
- `Sources/PDTBarCore/PDTBackgroundDetailRefresh.swift:564-650`. `xRayHoldings`, `incomeEvents` (only whether they return a diagnostic).
- `Sources/PDTBarCore/PDTBackgroundDetailRefresh.swift:840-968`. `priceSeries`: worker loop, deadline, cancellation, `group.wait`, abandonment.
- `Sources/PDTBarCore/PDTBackgroundDetailRefresh.swift:970-1089`. `callDecoded`, `callDecodedWithRetry`, `throwIfCancelled`.
- `Sources/PDTBarCore/PDTBackgroundDetailRefresh.swift:1122-1230`. `PDTPriceHistoryAccumulator`, `PDTPriceHistoryWorkTracker`.
- `Sources/PDTBarCore/PDTLiveDataSource.swift:605-678`. `PDTListPaginationResult.truncationDiagnostic`, `paginatePDTList` (only the `.timeout` truncation diagnostic).
- `Sources/PDTBarCore/PDTCancellation.swift`. The cancel flag and its parent link.
- `Sources/PDTBarCore/LaunchRuntime.swift:213`. `BackgroundDetailRefreshPhase` (phase order only).

Every action in the spec names the Swift lines it models. To see whether a change touches this model, run:

```bash
git diff 1b6ffd4 -- Sources/PDTBarCore/PDTBackgroundDetailRefresh.swift Sources/PDTBarCore/PDTCancellation.swift Sources/PDTBarCore/PDTLiveDataSource.swift | grep -n '^@@'
```

If a hunk falls in a range above, recheck the model. Line numbers drift with unrelated edits, so match by function name when they do.

## Run

Needs a JDK 11+. The runner pins TLA+ 1.7.4 and runs one TLC worker unless `PDTBAR_TLC_WORKERS` is set.

```bash
Scripts/formal/tlc.sh formal/background-detail-refresh/BackgroundDetailRefresh.tla
Scripts/formal/tlc.sh formal/background-detail-refresh/BackgroundDetailRefresh.tla formal/background-detail-refresh/BackgroundDetailRefreshFindingsFixed.cfg
```

Expected at the sync commit:

- `BackgroundDetailRefresh.cfg` models the shipped code. It fails in about 10 seconds with `Invariant NoPhaseAfterOutage is violated`, a 21-state trace. That is the open finding below.
- `BackgroundDetailRefreshFindingsFixed.cfg` sets the finding knob to its fixed value. It passes with 3,290,492 distinct states in about 3 minutes on one worker. Use it to check every other property while the finding stays open. With `PDTBAR_TLC_WORKERS=4` it takes about 1 minute.

A new failure in either run, or a different invariant in the first run, means the change broke something or the model needs updating.

## Open finding at the sync commit

`NoPhaseAfterOutage`. Price-history diagnostics with an outage category never set `skipRemainingPhasesForUnavailableSetup`, so the performance phase still runs during an outage. TLC's shortest trace on the shipped config, in the code's names:

1. Tool discovery lists the performance tools. `Discover`, `PDTBackgroundDetailRefresh.swift:171-195`, gate `:365`.
2. The base holdings call returns and is committed. `BaseSucceeds`, `:201-225`.
3. Allocation, X-ray, and income each return and commit. `Advance` and `OptionalSucceeds`, `:245-323`.
4. `priceSeries` starts two workers. `Advance`, `:334-344`, `:840-866`.
5. Worker 1 passes the while-condition. `WCheck`, `:870-872`.
6. Worker 1 takes holding 1 and starts `pdt-list-symbol-prices`. `WPull`, `:873`, `:1006-1026`.
7. The price-history deadline passes. `Tick`.
8. `group.wait` times out. `WaitTimedOut`, `:928`.
9. Worker 1's run returns `setupUnavailable`. The retry guard throws. `WCallReturns`, `:1044-1049`.
10. Worker 1 records the diagnostic. The accumulator sets `firstUnavailableSetupCategory`. `WComplete`, `:914-916`, `:1161-1168`.
11. The main thread reads the outage category and abandons holdings 2 and 3. `Decide`, `:928-939`.
12. Holdings 2 and 3 get `setupUnavailable` diagnostics. `RecordAbandoned` twice, `:943-964`.
13. `priceSeries` returns. `refresh` appends the diagnostics and leaves the skip flag false. `Collect`, `:346-362`.
14. The performance gate passes and the performance phase starts, calling `pdt-get-portfolio-performance` during the outage. `Advance`, `:364-372`, `:498-506`.

The deadline is incidental. With no timeout, worker 2 sees the outage and exits, and the same thing happens one step later. The cost is one wasted CLI run of up to the performance call's timeout, and the docs promise an observed outage skips the remaining phases. Knob `PriceHistoryOutageSetsSkip`.

When the fix lands, set the knob to `TRUE` in `BackgroundDetailRefresh.cfg` and confirm this passes:

```bash
Scripts/formal/tlc.sh formal/background-detail-refresh/BackgroundDetailRefresh.tla
```

Then delete `BackgroundDetailRefreshFindingsFixed.cfg`, and the knob too if you like.

## Retired findings

- `NoRetryAfterDeadline`. `priceSeries` called `callDecodedWithRetry` without `retryDeadline`, so a transient price-history failure past the deadline started another full CLI run. Fixed by `f11cf27` (#236), which passes `retryDeadline: deadline`. `a4ffe5a` (#239) made `retryDeadline` required for every call. The knob is gone and the property stays as a guard. Dropping `~pastDeadline` from the retry guard in `WCallReturns` and from `WBackoffEnds`, which mirrors deleting `now() < retryDeadline` at `:1047` and the guard at `:1013`, fails it with the findings-fixed config.

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

At the sync commit, a scratch change to the real code dropped `!abandonedQuoteIDs.contains(quoteID)` from `PDTPriceHistoryWorkTracker.complete` (`:1209`). `swift build` still passed. With the matching model edit (`record == h \notin finished` in `WComplete`), the findings-fixed config failed with `ResultFrozen`. Each other property also fails when its line in the model is broken this way:

- `CommittedNeverLost`. `Finalize` commits the prior snapshot instead of `snap`.
- `ReturnedHasSucceededPhases`. `Finalize` skips the commit (`store' = store`).
- `OutcomeHonest`. `Collect` drops the price-history diagnostics, or `Performance` drops its timeout diagnostic.
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
