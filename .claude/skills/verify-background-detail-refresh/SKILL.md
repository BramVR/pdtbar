---
name: verify-background-detail-refresh
description: "Check a PDT API background detail refresh change against its TLA+ model."
---

# Verify background detail refresh

`formal/background-detail-refresh/BackgroundDetailRefresh.tla` models one run of `PDTAPIBackgroundDetailRefresh.refresh`. It covers the phase order, paged facets, the `syncEnded` skip, the cancellation checkpoints, the single snapshot commit, the outcome, and the stored sync failure. TLC checks every request outcome in every phase, every page count a paged facet can stop at, two price batches, and a cancel landing between any two steps.

## Promises checked

- `OneCommitAtEnd`. The snapshot is written at most once, and only by `PressureRunner.refreshedPulse` after the last phase. A counter of snapshot writes carries the check.
- `AbortWritesNothing`. A failed base fetch, or a cancel that lands before the last `throwIfCancelled`, leaves the snapshot and the pulse read state untouched.
- `NoRequestAfterSyncEnded`. Once a failure that ends the sync is recorded, no later phase or price batch sends a request. The kinds that end it are written out in the model apart from `PDTSyncFailure.Kind.endsSync`, so a classifier change shows up.
- `FailedSliceKeepsPrior`. A facet or price batch that failed or was skipped keeps the prior snapshot's data. Nothing is lost.
- `FreshFacetReadEveryPage`. X-ray or income is replaced only by a call that read every page. A slow or failed first page, or a later page that fails, keeps the prior facet (#275). A ghost, `pagesBehind`, records the pages behind each fresh facet.
- `OutcomeHonest`. The outcome is `degraded` exactly when some facet or price batch was not refreshed.
- `StoredFailureIsThisRuns`. Once `refresh` has run its first statement, `SnapshotStore.lastSyncFailure()` never holds an earlier run's failure, a cancel before the first checkpoint included (#289). A returned refresh leaves `failures.last`, or none.
- `Terminates`. The refresh always returns or throws.

## Covered code and sync commit

Sync commit: `bcbbcf9`. The model was last confirmed against the code at this commit.

- `PDTAPIBackgroundDetailRefresh.refresh` in `Sources/PDTBarCore/PDTAPIBackgroundDetailRefresh.swift`: the checkpoints, `setLastSyncFailure(nil)`, the base fetch and its catch, `record`, `optionalPhase`, the three facet closures, the price batch loop, the performance progress and final checkpoint, the outcome, the `refreshedPulse` call, `setLastSyncFailure(failures.last)`. Also `fetch` and `throwIfCancelled` in the same type.
- `PDTAPIBackgroundDetailRefresh.preserveOptionalDetails` and `priceSeriesWithPriorFallback`. #250 moved these statics from the deleted Claude `PDTBackgroundDetailRefresh` without a behavior change.
- `PDTSyncFailure.Kind.endsSync` in `Sources/PDTBarCore/PDTSyncFailure.swift`.
- `PDTAPIClient.send`, `sendOnce`, `collectPages`, and `collectOffsets` in `Sources/PDTBarCore/PDTAPIClient.swift`. Only the cancel check before each request is modeled, the fact that every failure reaches `fetch` as a `PDTAPIRequestFailure`, and the fact that a paged call returns rows only after its last page.
- `PressureRunner.refreshedPulse` and `SnapshotStore.commitCurrentSnapshot`, `setLastSyncFailure` in `Sources/PDTBarCore/Persistence.swift`.
- `PDTCancellation` in `Sources/PDTBarCore/PDTCancellation.swift`.

Every action's comment names the statement or symbol it models. To see whether a change touches this model, run:

```bash
git diff bcbbcf9 -- Sources/PDTBarCore/PDTAPIBackgroundDetailRefresh.swift Sources/PDTBarCore/PDTSyncFailure.swift Sources/PDTBarCore/PDTAPIClient.swift Sources/PDTBarCore/Persistence.swift Sources/PDTBarCore/PDTCancellation.swift
```

Recheck the model when a hunk falls inside one of the symbols above.

## Run

Needs a JDK 11+. The runner pins TLA+ 1.7.4.

```bash
Scripts/formal/tlc.sh formal/background-detail-refresh/BackgroundDetailRefresh.tla
formal/background-detail-refresh/mutations.sh
```

Expected at the sync commit:

- The model run prints `No error has been found` with 1,470 states generated, 989 distinct, depth 15, in about a second. Any failure means the change broke something or the model needs updating.
- `mutations.sh` prints one row per mutation with the invariant it expects to be violated, and exits 0 in about 8 seconds. A row that reports `No error has been found` means the model lost its teeth.

## Mutations

Each row breaks one statement of the model the way a code change could. Each was confirmed at `bcbbcf9`.

- `perPhaseCommit`: an optional phase that refreshed its facet commits it, the Claude refresh's shape. Caught by `OneCommitAtEnd`.
- `optionalIgnoresSyncEnded`: `optionalPhase` loses `guard !syncEnded`. Caught by `NoRequestAfterSyncEnded`.
- `priceIgnoresSyncEnded`: the batch loop loses its `if syncEnded`. Caught by `NoRequestAfterSyncEnded` (an ending failure in batch 1, then batch 2 sends).
- `rateLimitKeepsSyncing`: `endsSync` drops `.rateLimited`. Caught by `NoRequestAfterSyncEnded`.
- `failedPhaseDropsPrior`: a failed optional phase clears its facet. Caught by `FailedSliceKeepsPrior`.
- `outcomeIgnoresFailures`: the outcome stops reading `failures`. Caught by `OutcomeHonest`.
- `noFailureClearAtStart`: `refresh` stops calling `setLastSyncFailure(nil)` first. Caught by `StoredFailureIsThisRuns`.
- `cancelBeforeFailureClear`: the #289 fix reverted, so `throwIfCancelled` runs before `setLastSyncFailure(nil)`. Caught by `StoredFailureIsThisRuns`. TLC's shortest trace: the cancel lands, `Start` throws, and the earlier run's failure is still stored.
- `zeroPageCommits`: #275's shape. A paged call that read no page returns an empty list as success. Caught by `FreshFacetReadEveryPage`. TLC's shortest trace: X-ray reads 0 of 2 pages and is marked fresh.
- `partialPagesCommit`: a paged call that failed after some pages returns the rows it collected. Caught by `FreshFacetReadEveryPage`.
- `noFinalCancelCheck`: the `throwIfCancelled` before `refreshedPulse` is dropped. Caught by `AbortWritesNothing`. TLC's shortest trace: income fails with an ending kind, price history is skipped with no checkpoint, the cancel lands, and the commit runs.

Dropping the `if !syncEnded` around the price block fails nothing, and the model is right about that. The per-batch gate already stops every request, and skipping the block leaves the same prior series.

A mutation that makes an action unsatisfiable passes silently. An example is adding `writes' = writes + 1` to an action that also lists `writes` under `UNCHANGED`. Read a new row's TLC trace once to see that it reaches the break.

## Reading a result

Read every TLC result with the `/statechart` skill. A violation comes back as its shortest path in plain words. A pass comes back as a chart of how the refresh moves between states.

## Real bug or modeling error

Replay the trace against `refresh`, one action at a time, using each action's comment.

- It is a real bug when each step is something the code can do, in that order. Report it with the trace in the code's names. Do not weaken the property or change product code unless asked.
- It is a modeling error when a step does something the code cannot do. Examples: a request outcome the client never returns at that call site, or a checkpoint the model places where the code has none. Fix the model and say what you fixed.

Atomicity the model relies on:

- The refresh is sequential. The only other actor is the cancel.
- One optional-phase step covers its requests, the `record` of a failure, and the `throwIfCancelled` after the phase. Nothing between them writes a file or reads the flag except the client's own check.
- A request step in a cancelled run throws. The client checks the flag before it sends, and `fetch`'s catch rethrows it as `PDTAPIError.cancelled`, which no phase catches.
- A cancel that lands just after a step's checkpoint is the same as the step running first and `Cancel` after it. The ghost `cancelEarly` records whether the cancel landed before the final checkpoint.

## Modeling choices

- Each request is one `PDTAPIClient` call whose retries, pages, backoff, token refresh retry, and semaphore wait are folded into its final outcome: success or one `PDTSyncFailure.Kind`.
- Each optional phase is one step. Its call ends after `read` pages, from 0 up to the facet's page count, and only a full read succeeds. `PageCount = 2` is the smallest count with both a zero-page and a partial read. Income's two requests are one call. A change that sends income's dividends request after the calendar request ended the sync would not show.
- `Kinds = {"reconnect", "rateLimited", "server"}`: lost access, the 429 that outlasted the client's retries, and a failure that does not end the sync. The other ending kinds behave like `reconnect`.
- `ChunkCount = 2`: the smallest count where an ending failure in one batch can be followed by another batch.
- The base failure's kind does not matter. It always throws.

Bounds live in `BackgroundDetailRefresh.cfg`. The state space is small, so raising `ChunkCount` or adding kinds is cheap.

## Updating the model

When a covered symbol changes on purpose:

1. Edit the matching action so it does what the new code does, and update its comment.
2. A new checkpoint, gate, or write becomes its own step or variable.
3. Run the model and `mutations.sh`. Compare against the expected results above.
4. Prove a changed property can still fail. Break the new code path in a scratch edit, mirror the break in the model, see TLC fail, then revert both. Add the model break as a `mutations.sh` row.
5. Move the sync commit forward only after you confirm the model describes the code at the new commit.

## Out of scope

- Store write errors. A throwing `refreshedPulse` makes `refresh` throw with the stored failure still cleared.
- The read-state order inside `commitCurrentSnapshot`. `formal/pulse-read-state` checks it.
- The app side: `startBackgroundPortfolioRefresh`, `applicationWillTerminate`'s wait, and `PDTLaunchRuntime`. `formal/launch-runtime` checks the wiring.
- `PDTAPIClient` internals: retry delays, the `Retry-After` cap, the token refresh retry, and the request semaphore. `PDTAPIClientTests` cover them.
- A `URLError.cancelled` without the flag set. It becomes a recorded `.cancelled` failure that does not end the sync.
- Progress callbacks, snapshot contents beyond `prior` / `fresh` / `none`, and performance, which is always unavailable and never carried.

## History

#275 asked whether a pagination deadline could commit an empty X-ray or income list. The deadline lived in the Claude path's `paginatePDTList` and went with #250. The REST client has no pagination deadline, so on `ad90cdc` a slow or failed first page fails the phase and keeps the prior. `FreshFacetReadEveryPage` and the `zeroPageCommits` and `partialPagesCommit` rows keep it that way. #289's review found the early cancel that skipped `setLastSyncFailure(nil)`. `bcbbcf9` fixed it, and `cancelBeforeFailureClear` guards it.

Until #250 this model described the Claude CLI refresh, `PDTBackgroundDetailRefresh`, with its price-history worker pool, phase deadlines, per-phase commits, and category retries. Its retired findings (#272, the outage gate, and #236, retries after the price deadline) are in the git history of this file before #250.
