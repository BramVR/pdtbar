---
name: verify-launch-runtime
description: "Check changes to PDTBar launch, readiness probe, login handoff, first fetch, cached pulse, or background refresh wiring against the TLA+ launch model."
---

# Verify launch runtime

A TLA+ model of the no-argument PDTBar launch: `PDTLaunchRuntime` plus the `AppDelegate` code that runs its effects on background queues and feeds results back on the main queue. TLC explores every order in which probes, the cached-pulse load, first fetch, background refresh, login and menu clicks can complete.

## When to use

Run it when a change touches any covered function below, the order of main-queue work in `AppDelegate`, which buttons a launch menu shows, or the meaning of `readinessProbeInFlight`, `firstFetchInFlight`, `backgroundDetailRefreshInFlight`, `portfolioRefreshInFlight`, `pendingReadyProbeAfterCachedPulseLoad`. Pure copy or layout changes to menu rows do not need it, unless a row's `role` changes (`setupLogin`, `setupRetry`, `fetchRetry` are the clickable ones the model tracks).

## Coverage

Sync commit: `1431dc2` (last commit touching the covered files when the model was confirmed to describe them). After you confirm the model still describes the code at a newer commit, move this line forward. Never move it without that check.

`Sources/PDTBarCore/PDTBarCore.swift`:
- `PDTLaunchRuntime` 3815-4083: `launch` 3827, `completeCachedPulseLoad` 3832, `retryReadiness` 3861, `completeReadinessProbe` 3868, `beginLoginHandoff` 3897, `completeLoginHandoff` 3902, `retryFirstFetch` 3917, `firstFetchProgress` 3928, `completeFirstFetch` 3935, `beginBackgroundDetailRefresh` 3945, `backgroundDetailRefreshProgress` 3952, `completeBackgroundDetailRefresh` 3969, `publishPulse` 4009, `beginReadinessProbe` 4031, `startBackgroundDetailRefresh` 4037, `update` 4054.
- `ClaudeLoginAttemptGate` 2924.
- Clickable rows per state: `ClaudeLaunchFlow.descriptor(for:cachedPulse:)` 3170, `descriptorForBackgroundRefreshFailure` 3376, `descriptorForBackgroundDetailProgress` 3401, `descriptorForBackgroundDetailDegraded` 3417, `descriptor(forLoginFailure:)` 3451, `portfolioFetchFailureRows` 3743, `ClaudeSetupMenuDescriptor` 4241-4356, default pulse "Refresh now" row 4694.

`Sources/PDTBarApp/main.swift` (`AppDelegate`):
- `launch` 78, `startCachedPulseLoad` 102, `markPulseItemRead` 1022, `startClaudeReadinessProbe` 127, `finishClaudeReadinessProbe` 143, `returningLaunchBackgroundDetailRefreshEnabled` 155, `startFirstPortfolioFetch` 162, `finishFirstPortfolioFetch` 202, `updatePortfolioFetchProgress` 238, `retryPortfolioFetch` 256, `startBackgroundPortfolioRefresh` 263, `finishBackgroundPortfolioRefresh` 318, `retryClaudeReadiness` 333, `loginWithClaude` 340, `handleLaunchUpdate` 366, row-role-to-selector wiring in `makeMenuItem` 545.

To see whether a change touches covered code: `git diff 1431dc2 -- Sources/PDTBarCore/PDTBarCore.swift Sources/PDTBarApp/main.swift` and look for the names above.

## Run

```bash
formal/launch-runtime/check.sh        # model vs baseline, ~2 s
formal/launch-runtime/mutations.sh    # proves each passing invariant can still fail, ~10 s
```

`check.sh` exits 0 when every invariant passes except the open findings it lists. It exits 1 when a new invariant fails, or when an open finding stops failing. For the full trace, run `Scripts/formal/tlc.sh formal/launch-runtime/LaunchRuntime.tla` (it stops at the first violation, shortest path, single worker). Read every result with the `/statechart` skill. It turns a violation into its shortest path in plain words, and on a pass it charts how the launch moves between states.

Requires a JDK 11+ on PATH. The runner downloads the pinned `tla2tools.jar` 1.7.4 once and checks its SHA-256.

## What the model promises

Files: `formal/launch-runtime/LaunchRuntime.tla` (model), `LaunchRuntime.cfg` (bounds and invariants), `mutations.sh`, `check.sh`.

Passing today:
- `OneFetchAtATime`: a first fetch and a background refresh never run together. Harm if broken: two writers race on the same `SnapshotStore` and `PulseReadStore` files.
- `FirstFetchFlagMatchesWork`: `firstFetchInFlight` is true exactly while a first fetch runs. Harm if broken: every retry is refused and the progress UI never clears.
- `NoFullFetchOverCache`: a full first fetch never runs while a cached pulse exists. Harm if broken: a returning user pays the slow onboarding fetch instead of the background refresh.
- `NeverStranded`: something is running, or the menu offers Log in, Check again, or Try again / Refresh now. Harm if broken: the user is stuck with no way forward but quitting.
- `SetupReflectsLatestProbe`: a setup screen showing a probe result is never contradicted by a newer probe still running.
- `FetchingMenuTellsTruth`: a "Refreshing" / "Fetching" menu means a fetch is running.

Open findings (fail on the code at the sync commit; listed in `check.sh` as `OPEN_FINDINGS`):
- `BackgroundFlagMatchesWork` (shortest path 4 steps). On a returning launch the background refresh starts. The user clicks "Mark as read" on a pulse row, and `markPulseItemRead` republishes through `publishPulse`, which sets `backgroundDetailRefreshInFlight = false` while the refresh is still running. Progress rows stop, because `backgroundDetailRefreshProgress` drops updates once the flag is false. "Refresh now" reappears during the refresh. When the refresh finishes it publishes its own older read state (see `verify-pulse-read-state`, stale publish). Fix direction: republish a mark-read without touching the refresh flag or the progress descriptor.
- `ProbeResultNotLost` (shortest path 5 steps). The user clicks "Log in with Claude" during the launch probe, and the login succeeds, so probe #2 starts while probe #1 still runs. Probe #2 returns `ready` before the cached pulse has loaded, so `finishClaudeReadinessProbe` parks it in `pendingReadyProbeAfterCachedPulseLoad`. Stale probe #1 then returns `ready` and overwrites the slot. When the cache loads, the replayed attempt-1 result is discarded as stale by `completeReadinessProbe`, and the launch stays on "Checking Claude" with no probe running. With a cached pulse, the only way out is "Refresh now". The fix the model accepts is to never replace a parked result with an older attempt (`id < readinessAttemptID`).
- `ProbingMenuTellsTruth` and `SetupMenuMeansIdle` (shortest path 4 and 6 steps). On a returning launch, the cached pulse shown during "Checking Claude setup" keeps its "Refresh now" row. Clicking it calls `retryFirstFetch`, which starts a background refresh before readiness is known. When the probe then returns a setup result, a setup screen covers a refresh that is still running, and its progress callbacks flip the menu back. If the user clicks "Check again" and the probe returns `ready`, `completeReadinessProbe` takes the refresh-in-flight guard. That guard leaves `state == .probingClaude` with `readinessProbeInFlight == false`, so the menu says "Checking Claude setup" until the refresh reports. Changing the row to "Refreshing now" makes `FetchingMenuTellsTruth` fail. Hiding the row turns the `ProbeResultNotLost` path into a dead end (`NeverStranded` fails). Fix `ProbeResultNotLost` first, or in the same change.

When a fix lands, remove the invariant from `OPEN_FINDINGS` in both `check.sh` and `mutations.sh`, and update this list.

## Real bug or modelling error

When TLC reports a violation, replay its steps against the Swift code before you believe or dismiss it:
1. For each step, open the function named in the action's comment (file:line) and confirm that the code allows that step from that state. Check the guards, which rows the menu at that point offers, and whether the work is really still running.
2. If every step is possible in the code, it is a real bug. Report it as steps in the code's names (as in the open findings). Do not weaken the invariant or the model to make it pass.
3. If a step is impossible in the code, the model is wrong. Fix the action so it matches the code, and cite the line that rules the step out.
4. Where the runtime side can be driven without AppKit, confirm with a scratch swift-testing case that calls `PDTLaunchRuntime` in the same order (the `cachedQuietFixturePulse()` helper in `Tests/PDTBarTests/LaunchFlowTests.swift` gives a cached pulse). Delete the scratch test afterwards unless the user wants a regression test.

## Updating the model for an intended change

- One TLA+ action is one main-queue block that runs to completion. When the code adds a new async hop, split the action at that hop.
- Mirror the change in the action whose comment names the function. Update that comment's line anchor and the Coverage list above.
- A new menu button or role becomes a new `Can*` predicate plus a `Click*` action. A new background job becomes an in-flight counter or set plus a `*Returns` action.
- Add a mutation to `mutations.sh` for each new invariant, mirroring a one-line code break it must catch. Run it and confirm every line reports a violation.
- Rerun `check.sh`, then move the sync commit forward.

## Scope and bounds

Bounds (`LaunchRuntime.cfg`): at most 3 readiness attempts from "Check again", 2 login clicks, and 2 Try again / Refresh now clicks (`MaxProbes`, `MaxLogins`, `MaxRetries`), with `BackgroundAfterFirstFetch = TRUE` as on real launches. That covers 4,901 distinct states. Mark as read is unbounded (it is idempotent in this model). A pass covers these bounds only.

Modelled at this abstraction:
- Probe results are any of the five `ClaudeReadinessProbeResult` values.
- Fetch and refresh outcomes are success or failure. Degraded is the same as success for the launch menu.
- The cached load either finds a pulse or does not.
- Menus are reduced to their kind (setup or pulse), their state, and whether Refresh / Try again is clickable.

Left out:
- Fixture mode.
- What the background refresh does inside (see `verify-background-detail-refresh`).
- Login subprocess behavior (see `verify-claude-login-process`).
- Read-state writes (see `verify-pulse-read-state`).
- Settings re-renders. Mark-as-read is modelled only as a republish through `publishPulse`; its read-state writes belong to `verify-pulse-read-state`.
- Data health source facts on cached pulses.
- Timer cadence. A first-fetch progress tick may happen any time a first fetch is in flight.
- `PDTOnboardingCoordinator` / `PDTOnboardingRunner`, a synchronous test seam that the app does not use.
