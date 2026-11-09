---
name: verify-launch-runtime
description: "Check changes to PDTBar launch, readiness probe, login handoff, first fetch, cached pulse, or background refresh wiring against the TLA+ launch model."
---

# Verify launch runtime

A TLA+ model of the no-argument PDTBar launch: `PDTLaunchRuntime` plus the `AppDelegate` code that runs its effects on background queues and feeds results back on the main queue. TLC explores every order in which probes, the cached-pulse load, first fetch, background refresh, login and menu clicks can complete.

## When to use

Run it when a change touches any covered function below, the order of main-queue work in `AppDelegate`, which buttons a launch menu shows, or the meaning of `readinessProbe`, `readinessAttempt`, `cachedPulseLoading`, `firstFetchInFlight`, `backgroundDetailRefreshInFlight`, `portfolioRefreshInFlight`. Pure copy or layout changes to menu rows do not need it, unless a row's `role` changes (`setupLogin`, `setupRetry`, `fetchRetry` are the clickable ones the model tracks).

## Coverage

Sync commit: `1b6ffd4` (origin/main when the model was last confirmed to describe the covered code; the code was re-read after the #241 file split). After you confirm the model still describes the code at a newer commit, move this line forward. Never move it without that check.

`Sources/PDTBarCore/LaunchRuntime.swift`:
- `PDTReadinessAttempt` 1017. `PDTLaunchRuntime` 1022-1328: `launch` 1045, `launchWhileLoadingCachedPulse` 1052, `completeCachedPulseLoad` 1058, `installCachedPulse` 1070, `retryReadiness` 1096, `completeReadinessProbe` 1103, `applyReadiness` 1120, `beginLoginHandoff` 1143, `completeLoginHandoff` 1148, `retryFirstFetch` 1163, `firstFetchProgress` 1174, `completeFirstFetch` 1181, `beginBackgroundDetailRefresh` 1191, `backgroundDetailRefreshProgress` 1198, `completeBackgroundDetailRefresh` 1215, `publishPulse` 1255, `beginReadinessProbe` 1277, `startBackgroundDetailRefresh` 1283, `update` 1300.
- `ClaudeLoginAttemptGate` 118.
- Clickable rows per state: `ClaudeLaunchFlow.descriptor(for:cachedPulse:)` 364, `descriptorForBackgroundRefreshFailure` 572, `descriptorForBackgroundDetailProgress` 597, `descriptorForBackgroundDetailDegraded` 613, `descriptor(forLoginFailure:)` 647, `portfolioFetchFailureRows` 943, `ClaudeSetupMenuDescriptor` 1440-1556.

`Sources/PDTBarCore/MenuDescriptorRenderer.swift`: default pulse "Refresh now" row 277.

`Sources/PDTBarApp/main.swift` (`AppDelegate`):
- `launch` 80, `startCachedPulseLoad` 102, `startClaudeReadinessProbe` 125, `startFirstPortfolioFetch` 145, `finishFirstPortfolioFetch` 182, `updatePortfolioFetchProgress` 218, `retryPortfolioFetch` 236, `startBackgroundPortfolioRefresh` 243, `finishBackgroundPortfolioRefresh` 300, `retryClaudeReadiness` 317, `loginWithClaude` 324, `handleLaunchUpdate` 349, row-role-to-selector wiring in `makeMenuItem` 550, `markPulseItemRead` 1032, `backgroundDetailRefreshConfigured` 1103.

To see whether a change touches covered code: `git diff 1b6ffd4 -- Sources/PDTBarCore/LaunchRuntime.swift Sources/PDTBarCore/MenuDescriptorRenderer.swift Sources/PDTBarApp/main.swift` and look for the names above.

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
- `ProbeResultNotLost`: while the runtime waits for readiness attempt N, N's result is still running or parked until the cached pulse loads. Fixed in #274: every probe result must name its `PDTReadinessAttempt`, and `PDTLaunchRuntime` checks it before it parks a `ready`, so a superseded probe can no longer overwrite the parked result. Mutation `parkStaleProbe` restores the old order.

Open findings (fail on the code at the sync commit; listed in `check.sh` as `OPEN_FINDINGS`):
- `BackgroundFlagMatchesWork` (shortest path 4 steps). On a returning launch the background refresh starts. The user clicks "Mark as read" on a pulse row, and `markPulseItemRead` republishes through `publishPulse`, which sets `backgroundDetailRefreshInFlight = false` while the refresh is still running. Progress rows stop, because `backgroundDetailRefreshProgress` drops updates once the flag is false. "Refresh now" reappears during the refresh. When the refresh finishes it publishes its own older read state (see `verify-pulse-read-state`, stale publish). Fix direction: republish a mark-read without touching the refresh flag or the progress descriptor.
- `ProbingMenuTellsTruth` and `SetupMenuMeansIdle` (shortest path 4 and 6 steps). On a returning launch, the cached pulse shown during "Checking Claude setup" keeps its "Refresh now" row. Clicking it calls `retryFirstFetch`, which starts a background refresh before readiness is known. When the probe then returns a setup result, a setup screen covers a refresh that is still running, and its progress callbacks flip the menu back. If the user clicks "Check again" and the probe returns `ready`, `completeReadinessProbe` takes the refresh-in-flight guard. That guard leaves `state == .probingClaude` with `readinessProbe == .idle`, so the menu says "Checking Claude setup" until the refresh reports. Changing the row to "Refreshing now" makes `FetchingMenuTellsTruth` fail. Hiding the row was a dead end while `ProbeResultNotLost` failed (#274, now fixed); recheck `NeverStranded` when changing it.

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
- Quit-time refresh cancellation (`applicationWillTerminate`, main.swift 1117, #239): it only runs while the app exits.
- What the background refresh does inside (see `verify-background-detail-refresh`).
- Login subprocess behavior (see `verify-claude-login-process`).
- Read-state writes (see `verify-pulse-read-state`).
- Settings re-renders. Mark-as-read is modelled only as a republish through `publishPulse`; its read-state writes belong to `verify-pulse-read-state`.
- Data health source facts on cached pulses.
- Timer cadence. A first-fetch progress tick may happen any time a first fetch is in flight.
- `PDTOnboardingCoordinator` / `PDTOnboardingRunner`, a synchronous test seam that the app does not use.
