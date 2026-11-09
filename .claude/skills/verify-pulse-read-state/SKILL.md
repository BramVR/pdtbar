---
name: verify-pulse-read-state
description: "Check mark-as-read, pulse read-state reset, or snapshot commit changes against the TLA+ model."
---

# Verify pulse read state

`formal/pulse-read-state/PulseReadState.tla` models how the main thread's mark-as-read and the refresh worker share `pulse-read-state.json` and `latest-portfolio-snapshot.json`. Run it whenever a change touches any code listed under Coverage.

## Properties

- `DisplayMatchesStoreWhenIdle`. Once no refresh or mark-read is in flight, a menu row shows read exactly when the read store holds its fingerprint. Harm: the user marks a row read and a finishing background refresh shows it unread again.
- `ReadMarkClearedOnRecrossing`. When a saved snapshot records a concentration holding that newly crossed the threshold while its old read mark is still stored, a running refresh still owes the reset. Harm: the app quits mid-refresh, the old mark survives, and the re-crossing alert stays hidden until the weight bucket changes.
- `NoLostReadStateUpdate`. The read-state file always equals every `markRead` and reset applied in write order. Harm: a mark-read or a reset silently disappears.

## Coverage

Sync commit: `032058b`. The model describes the code at that commit.

`Sources/PDTBarCore/PDTBarCore.swift`:
- `PulseReadStore` (`mutationQueue` 675, `load` 681, `markRead` 693, `removeReadFingerprints` 704) and `OwnerOnlyLocalStore.write` 781 (temp file + rename, so writes are atomic).
- `PulseReadFilter.apply` 823 and `PulseLifecycleResult.applyingReadState` 6419.
- `PressureEngine.concentrationItems` 5608 (`resetsReadState` 5631).
- `PDTCoalescedFirstPortfolioFetch.fetch` 6790.
- `PDTBackgroundDetailRefresh.refresh` 7089 (prior load 7113, base commit 7126, phase commits 7158/7168/7188/7225, `refreshedPulse` call 7237).
- `PressureRunner.cachedPulse` 8188, `run` 8256 (read load 8274, commit 8275), `refreshedPulse` 8297 (read load 8306, commit 8314), `lifecycleResult` 8353, `readStateAfterResettingReappearedItems` 8414, `staleReadFingerprints` 8437.
- `SnapshotStore.commitCurrentSnapshot` 8507.
- `PDTLaunchRuntime.completeReadinessProbe` 3868, `retryFirstFetch` 3917, `completeBackgroundDetailRefresh` 3969, `publishPulse` 4009.

`Sources/PDTBarApp/main.swift`:
- `launch` 78, `startCachedPulseLoad` 102, `startFirstPortfolioFetch` 162, `finishFirstPortfolioFetch` 202, `startBackgroundPortfolioRefresh` 263, `finishBackgroundPortfolioRefresh` 318, `pulseApplyingCurrentReadState` 438, `markPulseItemRead` 1022.

Every action in the spec has a comment naming the Swift function and line it models. If `git diff 032058b -- <file>` shows changes in any function above, recheck the model against the code before trusting a pass.

## Run

```bash
formal/pulse-read-state/check.sh
```

About 6 seconds. It runs each config through `Scripts/formal/tlc.sh` (pinned TLA+ 1.7.4) and compares the result with the expectation listed in the script. Exit code is the number of mismatches. Expected today:

- `PulseReadState_store.cfg`: pass. Current code, `NoLostReadStateUpdate`.
- `PulseReadState_fixed.cfg`: pass. Both findings fixed in the model (`ReapplyOnBgPublish`, `ResetBeforeSnapshotCommit` TRUE), every invariant.
- `PulseReadState_stale_publish.cfg`: `DisplayMatchesStoreWhenIdle` violated. Finding 1.
- `PulseReadState_lost_reset.cfg`: `ReadMarkClearedOnRecrossing` violated. Finding 2.
- `PulseReadState_broken_markread.cfg`: `NoLostReadStateUpdate` violated. The "able to fail" mutation: `markRead` outside `mutationQueue`.

One config alone: `Scripts/formal/tlc.sh formal/pulse-read-state/PulseReadState.tla formal/pulse-read-state/<config>.cfg`. The default `PulseReadState.cfg` checks every invariant against current code and stops at whichever finding TLC reaches first.

Read every TLC result with the `/statechart` skill. It turns a violation into its shortest path in plain words, and on a pass it charts how the state moves. Chart `PulseReadState_fixed.cfg` for the full flow.

## Current findings

Finding 1, stale background publish. Steps: a cached pulse shows an income row unread. `startBackgroundPortfolioRefresh` starts. The worker reaches `PressureRunner.refreshedPulse` and loads read state without the row. The user clicks the row, `markPulseItemRead` saves it and republishes it read. The worker finishes, `finishBackgroundPortfolioRefresh` calls `completeBackgroundDetailRefresh` with the worker's older `readState`, and the row is unread again while the store says read. Confirmed against the Swift code with a throwaway sequential test through `PDTLaunchRuntime`. Fix direction: re-read the store before publishing, as `finishFirstPortfolioFetch` does with `pulseApplyingCurrentReadState`. Related, not modelled: `publishPulse` sets `backgroundDetailRefreshInFlight = false`, so a mark-read during a refresh also stops the progress rows.

Finding 2, reset lost on quit. Steps: the store holds concentration mark `c1` from an earlier crossing, and the snapshot has the holding below threshold. `PDTBackgroundDetailRefresh.refresh` loads that prior, fetches `c1`, and commits the base snapshot at 7126. The app quits during the detail phases, before `refreshedPulse` resets. On relaunch the prior is already above threshold, so no later refresh sees a crossing and `c1` stays read. `PressureRunner.run` has the same commit-then-reset order with a shorter window. Fix direction: remove the re-crossed marks before the commit that records the crossing.

When a finding is fixed, flip its constant to TRUE in `PulseReadState.cfg`, `PulseReadState_store.cfg`, `PulseReadState_stale_publish.cfg`, `PulseReadState_lost_reset.cfg`, and `PulseReadState_broken_markread.cfg`, change that finding's expectation in `check.sh` to `pass`, and update this section.

## Real bug or modelling error

Replay the counterexample against the code. For each step, open the function its action comment names and ask whether the code can take that step from that state.

- Real bug: every step maps to code that can run in that order. Main-thread actions (`MarkRead*`, `*Publish`, `*Start`) never interleave with each other. Worker actions interleave with anything. `Relaunch` can happen at any point.
- Modelling error: a step needs something the code rules out, such as a menu row that is not shown, two refreshes at once (`portfolioRefreshInFlight` and `firstFetchInFlight` prevent that), or a split of something that runs inside one `mutationQueue.sync`. Fix the model and say why in the action comment.

Never weaken an invariant or remove an action to make a finding pass. A sequential test through `PressureRunner` and `PDTLaunchRuntime`, as used for finding 1, is a cheap way to confirm a trace on the real code.

## Updating the model

- Keep one action per indivisible step in the code: one `mutationQueue.sync` call, one file write, or one main-thread handler or `DispatchQueue.main.async` block.
- If a change splits or merges such a step, split or merge the action, update its file:line comment, and rerun `check.sh`.
- New fingerprint kinds or reset rules go in `ConcItem`, `Resets`, `Stale`, and `ToRemove`.
- After confirming the model describes the code at a new commit, move the sync commit above to that commit and refresh the line anchors. Do not move it on a pass alone.

## Out of scope

- Two app processes writing one state directory. `mutationQueue` is per process.
- Disk errors, decode failures, the unreadable-read-state path, and refresh failures other than a quit at any step.
- Ranking and truncation of `rankedAttentionItems`, data health, and descriptor rendering beyond which rows show read.
- The `markPulseItemRead` branch where `currentPulse` is nil, and the first fetch that runs with a cached pulse when the connector configuration throws.
- Bounds: one income-style row with two fingerprints, one concentration row with below plus two buckets, at most one refresh at a time. A pass covers these bounds only.
