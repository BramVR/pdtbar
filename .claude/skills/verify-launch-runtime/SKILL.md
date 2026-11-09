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
- `PDTReadinessAttempt` 1017. `PDTLaunchRuntime` 1022-1334: `launch` 1045, `launchWhileLoadingCachedPulse` 1052, `completeCachedPulseLoad` 1058, `installCachedPulse` 1070, `retryReadiness` 1096, `completeReadinessProbe` 1103, `applyReadiness` 1120, `beginLoginHandoff` 1143, `completeLoginHandoff` 1148, `retryFirstFetch` 1164, `firstFetchProgress` 1176, `completeFirstFetch` 1183, `beginBackgroundDetailRefresh` 1193, `backgroundDetailRefreshProgress` 1200, `completeBackgroundDetailRefresh` 1217, `publishPulse` 1257 (replaced after the sync commit by `pulseReadStateDidChange` for mark-read and `publishFetchedPulse` for the first fetch, #268), `beginReadinessProbe` 1283, `startBackgroundDetailRefresh` 1289, `update` 1306.
- `ClaudeLoginAttemptGate` 118.
- Clickable rows per state: `ClaudeLaunchFlow.descriptor(for:cachedPulse:)` 364, `descriptorForBackgroundRefreshFailure` 572, `descriptorForBackgroundDetailProgress` 597, `descriptorForBackgroundDetailDegraded` 613, `descriptor(forLoginFailure:)` 647, `portfolioFetchFailureRows` 943, `ClaudeSetupMenuDescriptor` 1492-1610.

`Sources/PDTBarCore/MenuDescriptorRenderer.swift`: default pulse "Refresh now" row 277, `refreshActionRow` 468 (`waitingForSetup` is shown but not clickable).

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
- `ProbingMenuTellsTruth`: "Checking Claude setup" means the newest readiness result is still on its way.
- `SetupMenuMeansIdle`: a setup screen is shown only when no fetch runs behind it.
- `CheckBeforeWork`: no fetch runs while a readiness check is pending. Fixed in #267: `retryFirstFetch` refuses until readiness came back ready, the cached pulse shown during the check renders "Refresh now" as not clickable (`waitingForSetup`), and a fetched pulse published during the check keeps `.probingClaude`. Since #268 a mark-read changes no launch state, so `republishSkipsCheck` is paired with `markReadPublishes` in `mutations.sh` to reach that branch. The menu is mutated in place (main.swift 485), so no model path reaches `retryFirstFetch` without a clickable row; its refusal is the runtime's own rule, pinned by `LaunchFlowTests`. This also makes the refresh-in-flight guard in `applyReadiness` unreachable.
- `RefreshOfferIsLive`: every clickable "Refresh now" / "Try again" is accepted by `retryFirstFetch`. Mutation `probingOffersRefresh` shows a dead button.
- `BackgroundFlagMatchesWork`: `backgroundDetailRefreshInFlight` is true exactly while a background refresh runs. Fixed in #268: mark-read used to republish through `publishPulse`, which cleared the flag mid-refresh, so progress rows stopped and "Refresh now" came back. Mark-read now calls `pulseReadStateDidChange`, which only re-renders the pulse rows. Mutation `markReadPublishes` restores the old path. That old path was also the only way to click a fetch retry during a refresh, so the `noRetryGuard` row adds it too.
- `ProbeResultNotLost`: while the runtime waits for readiness attempt N, N's result is still running or parked until the cached pulse loads. Fixed in #274: every probe result must name its `PDTReadinessAttempt`, and `PDTLaunchRuntime` checks it before it parks a `ready`, so a superseded probe can no longer overwrite the parked result. Mutation `parkStaleProbe` restores the old order.

Open findings (listed in `check.sh` as `OPEN_FINDINGS`): none.

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

Bounds (`LaunchRuntime.cfg`): at most 3 readiness attempts from "Check again", 2 login clicks, and 2 Try again / Refresh now clicks (`MaxProbes`, `MaxLogins`, `MaxRetries`), with `BackgroundAfterFirstFetch = TRUE` as on real launches. That covers 1,627 distinct states. Mark as read is unbounded (it changes nothing this model tracks). A pass covers these bounds only.

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
- Settings re-renders. Mark-as-read is modelled only as a re-render that keeps state, flags, and menu; its read-state writes belong to `verify-pulse-read-state`.
- Data health source facts on cached pulses.
- Timer cadence. A first-fetch progress tick may happen any time a first fetch is in flight.
- `PDTOnboardingCoordinator` / `PDTOnboardingRunner`, a synchronous test seam that the app does not use.
