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

Sync commit: `1b6ffd4`. The model describes the code at that commit.

`Sources/PDTBarCore/Persistence.swift`:
- `PulseReadStore` 18 (`mutationQueue` 20, `load` 26, `markRead` 38, `removeReadFingerprints` 49) and `OwnerOnlyLocalStore.write` 126 (temp file + rename, so writes are atomic).
- `PulseReadFilter.apply` 168 and `PulseLifecycleResult.applyingReadState` 271.
- `PressureRunner.cachedPulse` 343, `run` 411 (read load 429, commit 430), `refreshedPulse` 452 (read load 461, commit 469), `lifecycleResult` 508, `readStateAfterResettingReappearedItems` 569, `staleReadFingerprints` 592.
- `SnapshotStore.commitCurrentSnapshot` 662.

`Sources/PDTBarCore/PressureEngine.swift`: `concentrationItems` 210 (`resetsReadState` 233).

`Sources/PDTBarCore/PDTLiveDataSource.swift`: `PDTCoalescedFirstPortfolioFetch.fetch` 416.

`Sources/PDTBarCore/PDTBackgroundDetailRefresh.swift`: `refresh` 166 (prior load 198, base fetch 202, base commit 225, phase commits 264/288/322/379, `throwIfCancelled` checks 171-400, `refreshedPulse` call 406) and `throwIfCancelled` 1072.

`Sources/PDTBarCore/LaunchRuntime.swift`: `PDTLaunchRuntime.completeCachedPulseLoad` 1032, `completeReadinessProbe` 1068, `retryFirstFetch` 1117, `completeBackgroundDetailRefresh` 1169, `publishPulse` 1209. After the sync commit, #269 moved the read-state join into the runtime: `DisplayedPulse.show` is the only way to set the pulse the runtime shows, and it re-reads the store every time. Mark-read calls `pulseReadStateDidChange`.

`Sources/PDTBarApp/main.swift`: `launch` 82, `startCachedPulseLoad` 106, `startFirstPortfolioFetch` 159, `finishFirstPortfolioFetch` 196, `startBackgroundPortfolioRefresh` 257, `finishBackgroundPortfolioRefresh` 320, `pulseApplyingCurrentReadState` 442 (removed in #269), mark-read row setup 573, `markPulseItemRead` 1031, `applicationWillTerminate` 1117.

Every action in the spec has a comment naming the Swift function and line it models. If `git diff 1b6ffd4 -- <file>` shows changes in any function above, recheck the model against the code before trusting a pass.

## Run

```bash
formal/pulse-read-state/check.sh
```

About 15 seconds. It runs each config through `Scripts/formal/tlc.sh` (pinned TLA+ 1.7.4) and compares the result with the expectation listed in the script. Exit code is the number of mismatches. Expected today:

- `PulseReadState_store.cfg`: pass. Current code, `NoLostReadStateUpdate`.
- `PulseReadState_fixed.cfg`: pass. Both findings fixed in the model (`ReapplyOnBgPublish`, `ResetBeforeSnapshotCommit` TRUE), every invariant.
- `PulseReadState_stale_publish.cfg`: pass. Finding 1, fixed in #269.
- `PulseReadState_lost_reset.cfg`: `ReadMarkClearedOnRecrossing` violated. Finding 2.
- `PulseReadState_broken_markread.cfg`: `NoLostReadStateUpdate` violated. The "able to fail" mutation: `markRead` outside `mutationQueue`.
- `PulseReadState_broken_bgpublish.cfg`: `DisplayMatchesStoreWhenIdle` violated. Mutation: the background refresh publishes its worker's read state, as before #269.

One config alone: `Scripts/formal/tlc.sh formal/pulse-read-state/PulseReadState.tla formal/pulse-read-state/<config>.cfg`. The default `PulseReadState.cfg` checks every invariant against current code and stops at whichever finding TLC reaches first.

Read every TLC result with the `/statechart` skill. It turns a violation into its shortest path in plain words, and on a pass it charts how the state moves. Chart `PulseReadState_fixed.cfg` for the full flow.

## Current findings

Both reproduce on `1b6ffd4`. Finding 1 is fixed in #269; finding 2 is open. Each was also replayed on the real Swift code with a throwaway sequential test through `PDTBackgroundDetailRefresh` and `PDTLaunchRuntime`.

Finding 1, stale background publish (fixed in #269). Shortest TLC trace on `1b6ffd4` (now `PulseReadState_broken_bgpublish.cfg`, 9 states):

1. Start (`Init`). The snapshot holds a concentration row in weight bucket `c1`. The read store holds the same holding's older bucket mark `c2`. The cached pulse (`PressureRunner.cachedPulse`, Persistence.swift:343) shows `c1` unread.
2. `BgStart`. `startBackgroundPortfolioRefresh` starts the worker (main.swift:257).
3. `BgLoadPrior`. `refresh` loads the prior snapshot, already at `c1` (PDTBackgroundDetailRefresh.swift:198), and fetches `c1` (202).
4. `BgBaseCommit`. Base commit (PDTBackgroundDetailRefresh.swift:225).
5. `BgLoadReadState`. `refreshedPulse` loads read state `{c2}` (Persistence.swift:461) and commits (469). `c1` stays visible because `c2` is a changed bucket mark (`concentrationItems`, PressureEngine.swift:210).
6. `MarkRead`. The user clicks the row. `markPulseItemRead` saves `c1` (main.swift:1038, Persistence.swift:38). Store `{c1, c2}`.
7. `MarkReadReload`. `markPulseItemRead` republishes with the reloaded store (main.swift:1040-1041). The row shows read.
8. `BgReset`. `readStateAfterResettingReappearedItems` finds nothing to remove and returns the loaded `{c2}` (Persistence.swift:586-588).
9. `BgPublish`. `finishBackgroundPortfolioRefresh` (main.swift:320) calls `completeBackgroundDetailRefresh` (LaunchRuntime.swift:1169) with readState `{c2}`. The row is unread again while the store says read.

The mark-read can also land after step 8, while the worker's `finishBackgroundPortfolioRefresh` block waits in the main queue. Fix (#269): `PDTLaunchRuntime` re-reads the store for every pulse it publishes, so no worker's read state reaches the menu. The related flag bug, where a mark-read during a refresh stopped the progress rows, is fixed in #268 and checked by `verify-launch-runtime`.

Finding 2, reset lost on quit. Shortest TLC trace (`PulseReadState_lost_reset.cfg`, 5 states):

1. Start (`Init`). The read store holds concentration mark `c1` from an earlier crossing. The snapshot has the holding below threshold. PDT now has it at `c1`.
2. `BgStart`. `startBackgroundPortfolioRefresh` (main.swift:257).
3. `BgLoadPrior`. `refresh` loads the below-threshold prior (PDTBackgroundDetailRefresh.swift:198) and fetches `c1` (202).
4. `BgBaseCommit`. The base commit (225) records the crossing. The reset is owed.
5. `Relaunch`. The user quits. `applicationWillTerminate` (main.swift:1117) cancels the refresh, which throws at its next `throwIfCancelled` (256-400) before `refreshedPulse` (406). On relaunch `cachedPulse` hides `c1` as read.

After step 5 the prior is already above threshold, so no later refresh sees a crossing and `c1` stays read. A crash or force quit in the same window does the same. `PressureRunner.run` has the same commit-then-reset order (Persistence.swift:430, then 508) with a shorter window. A quit there kills the first-fetch worker at an arbitrary point, since quit neither cancels nor waits for it. Fix direction: remove the re-crossed marks before the commit that records the crossing.

When a finding is fixed, flip its constant to TRUE in `PulseReadState.cfg`, `PulseReadState_store.cfg`, `PulseReadState_stale_publish.cfg`, `PulseReadState_lost_reset.cfg`, and `PulseReadState_broken_markread.cfg`, change that finding's expectation in `check.sh` to `pass`, and update this section. Then `formal/pulse-read-state/check.sh` must exit 0.

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
- Refresh cancellation as its own action. Only `applicationWillTerminate` cancels a refresh, and a cancelled refresh writes no file after its last `throwIfCancelled`, so `Relaunch` from any worker state covers it.
- Ranking and truncation of `rankedAttentionItems`, data health, and descriptor rendering beyond which rows show read.
- The `markPulseItemRead` branch where `currentPulse` is nil, and the first fetch that runs with a cached pulse when the connector configuration throws or a scripted configuration disables background refresh.
- Bounds: one income-style row with two fingerprints, one concentration row with below plus two buckets, at most one refresh at a time. A pass covers these bounds only.
