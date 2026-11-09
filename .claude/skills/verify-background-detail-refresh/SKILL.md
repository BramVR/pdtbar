---
name: verify-background-detail-refresh
description: "Check a background detail refresh or price-history worker change against its TLA+ model."
---

# Verify background detail refresh

`formal/background-detail-refresh/BackgroundDetailRefresh.tla` models one run of `PDTBackgroundDetailRefresh.refresh`. It covers the phase sequence, per-phase commits, retry rules, the auth/setup outage skip, and the price-history worker pool racing its deadline. TLC checks every interleaving of the main thread, two workers, three holdings, and the deadline.

## Promises checked

- `CommittedNeverLost`. A slice committed fresh is never overwritten by a later phase, a later failure, or the final commit.
- `ReturnedHasSucceededPhases`. Every optional phase that finished cleanly is on disk when `refresh` returns. Price history is not committed when its phase ends. Only the performance commit or `PressureRunner.refreshedPulse` writes it.
- `OutcomeHonest`. The outcome is `degraded` exactly when allocation, X-ray, income, or any price-history holding failed.
- `NoDeterministicRetry`. Only `transientFailure`, `timeout`, and `exit` are retried. The list is written out in the property, apart from `isRetryable`, so a classifier change shows up.
- `NoPhaseAfterOutage`. Once a `setupUnavailable` or `unavailable` diagnostic is recorded, no later phase starts a Claude CLI run.
- `ConcurrencyBound`. At most `priceHistoryConcurrencyLimit` price-history runs are in flight.
- `PullAtMostOnce`. `nextQuoteID` hands each holding out at most once.
- `ExactlyOnceAtReturn`. When `priceSeries` returns, each holding is either refreshed or failed, never both and never neither.
- `ResultFrozen`. Late workers never change the accumulator after `priceSeries` returned it.
- `NoRetryAfterDeadline`. No price-history retry starts a new Claude CLI run after the deadline.
- `Terminates`. The refresh always returns or throws, even when the deadline fires mid-flight.

## Covered code and sync commit

Sync commit: `032058b`. The model was last confirmed against the code at this commit.

- `Sources/PDTBarCore/PDTBarCore.swift:6971-7004`. `PDTDetailRefreshFailureCategory`, `isRetryable`, `indicatesUnavailableSetup`.
- `Sources/PDTBarCore/PDTBarCore.swift:7029-7057`. `PDTBackgroundDetailRefreshOptions` (concurrency limit, retry count).
- `Sources/PDTBarCore/PDTBarCore.swift:7089-7259`. `refresh`: tool discovery, base phase, `recordOptionalPhaseFailure`, skip gates, per-phase commits, performance, outcome, final commit.
- `Sources/PDTBarCore/PDTBarCore.swift:7295-7309`. `preserveOptionalDetails`.
- `Sources/PDTBarCore/PDTBarCore.swift:7566-7677`. `priceSeries`: worker loop, deadline, `group.wait`, abandonment.
- `Sources/PDTBarCore/PDTBarCore.swift:7683-7730`. `callDecodedWithRetry`.
- `Sources/PDTBarCore/PDTBarCore.swift:7779-7887`. `PDTPriceHistoryAccumulator`, `PDTPriceHistoryWorkTracker`.
- `Sources/PDTBarCore/PDTBarCore.swift:3019`. `BackgroundDetailRefreshPhase` (phase order only).

Every action in the spec names the Swift lines it models. To see whether a change touches this model, run:

```bash
git diff 032058b -- Sources/PDTBarCore/PDTBarCore.swift | grep -n '^@@'
```

If a hunk falls in a range above, recheck the model. Line numbers drift with unrelated edits, so match by function name when they do.

## Run

Needs a JDK 11+. The runner pins TLA+ 1.7.4.

```bash
Scripts/formal/tlc.sh formal/background-detail-refresh/BackgroundDetailRefresh.tla
Scripts/formal/tlc.sh formal/background-detail-refresh/BackgroundDetailRefresh.tla formal/background-detail-refresh/BackgroundDetailRefreshFindingsFixed.cfg
```

Expected at the sync commit:

- `BackgroundDetailRefresh.cfg` models the shipped code. It fails in about 1 second with `Invariant NoRetryAfterDeadline is violated`. That is open finding 1 below. Once finding 1 is fixed, it fails with `NoPhaseAfterOutage`, open finding 2.
- `BackgroundDetailRefreshFindingsFixed.cfg` sets both finding knobs to their fixed value. It passes with 596,402 distinct states in about 15 seconds. Use it to check every other property while the findings stay open.

A new failure in either run, or a different invariant in the first run, means the change broke something or the model needs updating.

## Open findings at the sync commit

1. `NoRetryAfterDeadline`. `priceSeries` calls `callDecodedWithRetry` at `PDTBarCore.swift:7602` without `retryDeadline`. TLC's trace: the refresh reaches price history, worker 1 passes the `Date() < deadline` check, the deadline passes, worker 1 takes holding 1, its `pdt-list-symbol-prices` run fails with `transientFailure`, and after the backoff it starts a second full Claude CLI run past the deadline. The same happens to any run still in flight when the deadline passes. The main thread has already abandoned that holding, so the result is thrown away. That run can take up to the connector's 120-second tool timeout, twice with the connector's own retry. It overlaps the next refresh, and its `Retrying pdt-list-symbol-prices` progress can show in that refresh's menu. Knob `PriceHistoryRetryDeadline`. The income quote scan already passes its deadline (`:7503`).
2. `NoPhaseAfterOutage`. Price-history diagnostics with an outage category never set `skipRemainingPhasesForUnavailableSetup`. TLC's trace: a price-history run returns `setupUnavailable`, the pool abandons the rest with that category, `refresh` appends the diagnostics at `:7217`, and the performance phase still starts and calls `pdt-get-portfolio-performance` during the outage. That is one wasted CLI run of up to 15 seconds, and the docs promise an observed outage skips the remaining phases. Knob `PriceHistoryOutageSetsSkip`.

When a fix lands, set its knob to `TRUE` in `BackgroundDetailRefresh.cfg` and confirm the shipped config moves to the next finding or passes. When both are fixed, both configs hold the same values. Delete `BackgroundDetailRefreshFindingsFixed.cfg` then, and delete the knobs too if you like.

## Reading a result

Read every TLC result with the `/statechart` skill. A violation comes back as its shortest path in plain words. A pass comes back as a chart of how the refresh moves between states.

## Real bug or modeling error

Replay the trace against the Swift code, one action at a time, using the line numbers in each action's comment.

- It is a real bug when each step is something the code can do, in that order, with no lock or check between steps that the model leaves out. Report it with the trace in the code's names. Do not weaken the property or change product code unless asked.
- It is a modeling error when a step does something the code cannot do. Examples: two actions the code runs under one lock, split apart in the model. A value the model lets change that the code keeps fixed. A category the code never produces at that call site. Fix the model and say what you fixed.

Atomicity the model relies on:

- `WComplete` is one step because `PDTPriceHistoryWorkTracker.complete` runs the accumulator append inside its own lock.
- `Decide` is one step because `markAbandoned` empties pending and marks running holdings under one lock.
- `WCheck` reads the deadline and the outage flag in one step. Both flags only ever turn on, so a two-step read reaches no other outcome.
- `WPull` merges `nextQuoteID` with the first CLI run. Nothing between them reads shared state.
- `WBackoffEnds` merges the post-backoff deadline check with the next run's start. The microsecond gap between them is not reported.

## Updating the model

When a covered function changes on purpose:

1. Edit the matching action so it does what the new code does, and update its line comment.
2. New shared state or a new lock section becomes a new variable or a new action. Keep one action per lock section.
3. Run both configs. Compare against the expected results above.
4. Prove a changed property can still fail. Break the new code path in a scratch edit, mirror the break in the model, see TLC fail, then revert both.
5. Move the sync commit and the line ranges forward only after you confirm the model describes the code at the new commit.

Bounds live in the `.cfg` files: `HoldingCount = 3`, `Limit = 2`, `RetryCount = 1`, `FailureCategories = {"transientFailure", "decode", "setupUnavailable"}`, one representative per retry class. Raising `HoldingCount` to 4 or adding categories grows the state space fast, so run that once, not on every change.

## How the properties were shown to fail

At the sync commit, a scratch change to the real code dropped `!abandonedQuoteIDs.contains(quoteID)` from `PDTPriceHistoryWorkTracker.complete`. With the matching model edit, the findings-fixed config failed with `ResultFrozen`. Each other property also fails when its line in the model is broken this way:

- `CommittedNeverLost`. `Finalize` commits the prior snapshot instead of `snap`.
- `ReturnedHasSucceededPhases`. `Finalize` skips the commit (`store' = store`).
- `OutcomeHonest`. `Collect` drops the price-history diagnostics.
- `NoDeterministicRetry`. `IsRetryable` includes `"decode"`.
- `ConcurrencyBound`. `Workers == 1 .. HoldingCount`, so the `min` with the limit is dropped.
- `PullAtMostOnce`. `WPull` does not pop `pending`.
- `ExactlyOnceAtReturn`. `markAbandoned` ignores pending holdings.
- `Terminates`. `RecordAbandoned` never runs. Run with `-deadlock` to see the temporal failure instead of the deadlock.

## Out of scope

- Pagination of X-ray, calendar events, and dividends. Each optional phase is one call.
- The income quote scan's own deadline and diagnostics. `BackgroundDetailRefreshTests.swift` covers them.
- The connector's own retry in `ClaudeLocalConnection.callReadTool` and `ClaudeToolCallRetryPolicy`. Each model run is one connector call.
- `markCompleted` and the progress callbacks, including progress sent after the phase ended.
- Store write errors. A throwing `PressureRunner.refreshedPulse` would lose the uncommitted price history.
- The app side: `PDTLaunchRuntime`, `portfolioRefreshInFlight`, and runs that overlap a later refresh.
- Snapshot contents. Slices are only `prior`, `fresh`, or `none`.
