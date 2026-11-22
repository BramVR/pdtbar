---
name: verify-pulse-read-state
description: "Check mark-as-read, pulse read-state reset, or snapshot commit changes against the TLA+ model."
---

# Verify pulse read state

`formal/pulse-read-state/PulseReadState.tla` models how the main thread's mark-as-read and the refresh worker share `pulse-read-state.json` and `latest-portfolio-snapshot.json`. Run it whenever a change touches any code listed under Coverage.

## Properties

- `DisplayMatchesStoreWhenIdle`. Once no refresh or mark-read is in flight, a menu row shows read exactly when the read store holds its fingerprint. Harm: the user marks a row read and a finishing background refresh shows it unread again.
- `ReadMarkClearedOnRecrossing`. When a saved snapshot records a concentration holding that newly crossed the threshold while its old read mark is still stored, a running refresh still owes the reset. Harm: the user quits mid-refresh, the old mark survives, and the re-crossing alert stays hidden until the weight bucket changes.
- `NoLostReadStateUpdate`. The read-state file always equals every `markRead` and reset applied in write order. Harm: a mark-read or a reset silently disappears.

## Coverage

Sync commit: `cd4d474` (#307). The 2026-11-16 upkeep read every covered hunk from `33b5faa`: #290 moves `setLastSyncFailure(nil)` ahead of the first checkpoint, #300 adds a first-fetch failure write, #303/#306 reshape the sync outcomes, and #307 adds `priceAsOf`. None writes either guarded file or changes a step the model tracks. Action comments name symbols, never line numbers. The Current findings traces below are history on `1b6ffd4`; names there that the code no longer has are plain text, not code spans.

`Sources/PDTBarCore/Persistence.swift`:
- `PulseReadStore` (`mutationQueue`, `load`, `markRead`, `removeReadFingerprints`) and `OwnerOnlyLocalStore.write` (temp file + rename, so writes are atomic).
- `PulseReadFilter.apply` and `PulseLifecycleResult.applyingReadState`.
- `PressureRunner.cachedPulse`, `run`, `refreshedPulse`, `lifecycleResult`, `readStateAfterPruningStaleItems`, `staleReadFingerprints`. `run` and `refreshedPulse` load the read state after their commit, and the reset after the commit only prunes stale marks.
- `SnapshotStore.commitCurrentSnapshot`. It removes the read marks of items that re-cross against the snapshot on disk, then writes the snapshot (#270). Nothing is computed without a readable prior.

`Sources/PDTBarCore/PressureEngine.swift`: `concentrationItems` (`resetsReadState`) and `reappearedReadFingerprints`.

`PDTCoalescedFirstPortfolioFetch.fetch` in `PDTCoalescedFirstPortfolioFetch.swift`, which runs `PressureRunner.run`.

`Sources/PDTBarCore/PDTAPIBackgroundDetailRefresh.swift`: `refresh` loads the prior with `loadPriorSnapshotResult`, fetches the base holdings, fills the optional facets in memory, and writes once through `PressureRunner.refreshedPulse` after its last `throwIfCancelled`. `formal/background-detail-refresh` checks that single commit.

`Sources/PDTBarCore/LaunchRuntime.swift`: `PDTLaunchRuntime.completeCachedPulseLoad`, `retryFirstFetch`, `beginBackgroundDetailRefresh`, `completeFirstFetch`, `completeBackgroundDetailRefresh`, `pulseReadStateDidChange`, and the connection status that starts the first fetch or the background refresh. `DisplayedPulse.show` is the only way to set the pulse the runtime shows, and it re-reads the store every time (#269).

`Sources/PDTBarApp/main.swift`: `launch`, `startCachedPulseLoad`, `startFirstPortfolioFetch`, `finishFirstPortfolioFetch`, `startBackgroundPortfolioRefresh`, `finishBackgroundPortfolioRefresh`, `markPulseItemRead`, `applicationWillTerminate`.

If `git diff cd4d474 -- <file>` shows changes inside any symbol above, recheck the model against the code before trusting a pass.

## Run

```bash
formal/pulse-read-state/check.sh
```

About 20 seconds. It runs each config through `Scripts/formal/tlc.sh` (pinned TLA+ 1.7.4) and compares the result with the expectation listed in the script. Exit code is the number of mismatches. Expected today:

- `PulseReadState_store.cfg`: pass. Current code, `NoLostReadStateUpdate`. Each passing config explores 229,392 distinct states.
- `PulseReadState_fixed.cfg`: pass. Both findings fixed (`ReapplyOnBgPublish`, `ResetBeforeSnapshotCommit` TRUE), every invariant. Same as `PulseReadState.cfg` now that both fixes are current code.
- `PulseReadState_stale_publish.cfg`: pass. Finding 1, fixed in #269.
- `PulseReadState_lost_reset.cfg`: pass. Finding 2, fixed in #270.
- `PulseReadState_broken_markread.cfg`: `NoLostReadStateUpdate` violated. The "able to fail" mutation: `markRead` outside `mutationQueue`.
- `PulseReadState_broken_bgpublish.cfg`: `DisplayMatchesStoreWhenIdle` violated. Mutation: the background refresh publishes its worker's read state, as before #269.
- `PulseReadState_broken_reset_order.cfg`: `ReadMarkClearedOnRecrossing` violated. Mutation: the snapshot commit lands before the re-crossing reset, as before #270.

One config alone: `Scripts/formal/tlc.sh formal/pulse-read-state/PulseReadState.tla formal/pulse-read-state/<config>.cfg`. The default `PulseReadState.cfg` checks every invariant against current code.

Read every TLC result with the `/statechart` skill. It turns a violation into its shortest path in plain words, and on a pass it charts how the state moves. Chart `PulseReadState_fixed.cfg` for the full flow.

## Current findings

Both reproduce on `1b6ffd4`. Finding 1 is fixed in #269, finding 2 in #270. Each was also replayed on the real Swift code with a throwaway sequential test through PDTBackgroundDetailRefresh and `PDTLaunchRuntime`.

Finding 1, stale background publish (fixed in #269). Shortest TLC trace on `1b6ffd4` (9 states). Today `PulseReadState_broken_bgpublish.cfg` replays it in 10 states: steps 4 and 5 become `BgEarlyReset` (#270), `BgCommit` (the single commit, #250), and `BgLoadReadState`.

1. Start (`Init`). The snapshot holds a concentration row in weight bucket `c1`. The read store holds the same holding's older bucket mark `c2`. The cached pulse (`PressureRunner.cachedPulse`) shows `c1` unread.
2. `BgStart`. `startBackgroundPortfolioRefresh` starts the worker.
3. `BgLoadPrior`. `refresh` loads the prior snapshot, already at `c1`, and fetches `c1`.
4. BgBaseCommit. Base commit.
5. `BgLoadReadState`. `refreshedPulse` loads read state `{c2}` and commits. `c1` stays visible because `c2` is a changed bucket mark (`PressureEngine.concentrationItems`).
6. `MarkRead`. The user clicks the row. `markPulseItemRead` saves `c1`. Store `{c1, c2}`.
7. `MarkReadReload`. `markPulseItemRead` republishes with the reloaded store. The row shows read.
8. `BgReset`. readStateAfterResettingReappearedItems finds nothing to remove and returns the loaded `{c2}`.
9. `BgPublish`. `finishBackgroundPortfolioRefresh` calls `completeBackgroundDetailRefresh` with readState `{c2}`. The row is unread again while the store says read.

The mark-read can also land after step 8, while the worker's `finishBackgroundPortfolioRefresh` block waits in the main queue. Fix (#269): `PDTLaunchRuntime` re-reads the store for every pulse it publishes, so no worker's read state reaches the menu. The related flag bug, where a mark-read during a refresh stopped the progress rows, is fixed in #268 and checked by `verify-launch-runtime`.

Finding 2, reset lost on quit (fixed in #270). Shortest TLC trace on `1b6ffd4` (5 states):

1. Start (`Init`). The read store holds concentration mark `c1` from an earlier crossing. The snapshot has the holding below threshold. PDT now has it at `c1`.
2. `BgStart`. `startBackgroundPortfolioRefresh`.
3. `BgLoadPrior`. `refresh` loads the below-threshold prior and fetches `c1`.
4. BgBaseCommit. The base commit records the crossing. The reset is owed.
5. `Relaunch`. The user quits. `applicationWillTerminate` cancels the refresh, which throws at its next `throwIfCancelled` before `refreshedPulse`. On relaunch `cachedPulse` hides `c1` as read.

After step 5 the prior is already above threshold, so no later refresh sees a crossing and `c1` stays read. A crash or force quit in the same window does the same. `PressureRunner.run` has the same commit-then-reset order (Persistence.swift) with a shorter window. A quit there kills the first-fetch worker at an arbitrary point, since quit neither cancels nor waits for it. Fix (#270): `SnapshotStore.commitCurrentSnapshot` removes the marks of items that re-cross against the snapshot on disk before it writes, so every commit site gets the order and no worker owes a reset after a commit. A stop between the two writes leaves the old snapshot below threshold, and the next run removes the mark again, which changes nothing. Later commits of the same holdings compare against the base already on disk, so they do not remove a mark the user set mid refresh. Regression test: BackgroundDetailRefreshTests "A returning concentration alert stays unread after a quit mid refresh", on the Claude refresh. #250 deletes it with that refresh and replaces it with an API refresh test of a cancel before the commit.

Since #250 the background refresh writes the snapshot once, in `refreshedPulse` after its last `throwIfCancelled`, so the cancel window in step 5 is gone. `PulseReadState_broken_reset_order.cfg` still fails in 5 states: `BgStart`, `BgLoadPrior`, `BgCommit` (the one write records the crossing before the reset), `Relaunch`. That stop now takes a crash, a force quit, or the 4 s quit timeout, because a normal quit's cancel no longer stops a refresh past its last checkpoint.

When a new finding is fixed, flip its constant to TRUE in every config except the mutation that replays it, change that finding's expectation in `check.sh` to `pass`, add a `broken_*` config that keeps the old behaviour, and update this section. Then `formal/pulse-read-state/check.sh` must exit 0.

## Real bug or modelling error

Replay the counterexample against the code. For each step, open the function its action comment names and ask whether the code can take that step from that state.

- Real bug: every step maps to code that can run in that order. Main-thread actions (`MarkRead*`, `*Publish`, `*Start`) never interleave with each other. Worker actions interleave with anything. `Relaunch` can happen at any point.
- Modelling error: a step needs something the code rules out, such as a menu row that is not shown, two refreshes at once (`backgroundDetailRefreshInFlight` and `firstFetchInFlight` in `PDTLaunchRuntime` prevent that), or a split of something that runs inside one `mutationQueue.sync`. Fix the model and say why in the action comment.

Never weaken an invariant or remove an action to make a finding pass. A sequential test through `PressureRunner` and `PDTLaunchRuntime`, as used for finding 1, is a cheap way to confirm a trace on the real code.

## Updating the model

- Keep one action per indivisible step in the code: one `mutationQueue.sync` call, one file write, or one main-thread handler or `DispatchQueue.main.async` block.
- If a change splits or merges such a step, split or merge the action, update the symbols its comment names, and rerun `check.sh`.
- New fingerprint kinds or reset rules go in `ConcItem`, `Resets`, `Stale`, and `ToRemove`.
- After confirming the model describes the code at a new commit, move the sync commit above to that commit. Do not move it on a pass alone.

## Out of scope

- Two app processes writing one state directory. `mutationQueue` is per process.
- Disk errors, decode failures, the unreadable-read-state path, and refresh failures other than a quit at any step.
- Refresh cancellation as its own action. Only `applicationWillTerminate` cancels a refresh, and a cancelled refresh writes no file (`AbortWritesNothing` in `formal/background-detail-refresh`), so `Relaunch` from any worker state covers it.
- Ranking and truncation of `rankedAttentionItems`, data health, and descriptor rendering beyond which rows show read.
- The `markPulseItemRead` branch where no pulse is shown.
- Bounds: one income-style row with two fingerprints, one concentration row with below plus two buckets, at most one refresh at a time. A pass covers these bounds only.
