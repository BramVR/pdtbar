---
name: verify-launch-runtime
description: "Check changes to PDTBar launch, PDT connection check/sign-in/disconnect, first fetch, cached pulse, or background refresh wiring against the TLA+ launch model."
---

# Verify launch runtime

A TLA+ model of the no-argument PDTBar launch over the PDT REST connection (#248): `PDTLaunchRuntime` plus the `AppDelegate` code that runs its effects on background queues and feeds results back on the main queue. TLC explores every order in which the cached-pulse load, connection operations (check, sign-in, pasted token, disconnect), first fetch, background refresh and menu clicks can complete.

## When to use

Run it when a change touches any covered function below, the order of main-queue work in `AppDelegate`, which buttons a launch menu shows, or the meaning of `connectionOperationInFlight`, `connectionAttempt`, `cachedPulseLoading`, `firstFetchInFlight`, `backgroundDetailRefreshInFlight`, or `PDTLaunchState.offers*`. Pure copy or layout changes to menu rows do not need it, unless a row's `role` changes (`connectionSignIn`, `connectionToken`, `connectionCheck`, `connectionDisconnect`, `fetchRetry` are the clickable ones the model tracks).

## Coverage

Sync commit: the #248 PR head (`feat/248-pdt-api-onboarding`). After you confirm the model still describes the covered code at a newer commit, move this line forward. Never move it without that check.

`Sources/PDTBarCore/LaunchRuntime.swift`:
- `PDTLaunchState` 94 and its `offersSignIn` / `offersCheckAgain` / `offersDisconnect` 115-150.
- `PDTLaunchMenu.descriptor(for:cachedPulse:notice:fetchingElapsedSeconds:)` 207, `withDisconnectAction` 770.
- `PDTConnectionAttempt` 823. `PDTLaunchRuntime` 848: `launch` 878, `completeCachedPulseLoad` 883, `completeConnection` 894, `signIn` 903, `connect(token:)` 910, `cancelSignIn` 918, `checkAgain` 925, `disconnect` 932, `retryFirstFetch` 940, `firstFetchProgress` 951, `completeFirstFetch` 958, `beginBackgroundDetailRefresh` 976, `backgroundDetailRefreshProgress` 983, `completeBackgroundDetailRefresh` 992, `pulseReadStateDidChange` 1023, `apply` 1037, `beginConnectionOperation` 1049, `startBackgroundDetailRefresh` 1062, `descriptor` 1083.

`Sources/PDTBarCore/MenuDescriptorRenderer.swift`: default pulse "Refresh now" row 277, `refreshActionRow` 468 (`waitingForSetup` is shown but not clickable).

`Sources/PDTBarApp/main.swift` (`AppDelegate`): `launch` 60, `startCachedPulseLoad` 93, `runConnectionOperation` 111, `startSignIn` 128, `startFirstPortfolioFetch` 134, `finishFirstPortfolioFetch` 169, `startBackgroundPortfolioRefresh` 219, `finishBackgroundPortfolioRefresh` 265, connection selectors 280-327, `handleLaunchUpdate` 329, `connectionAction(for:)` role-to-selector wiring.

## Run

```bash
formal/launch-runtime/check.sh        # model vs baseline, ~2 s
formal/launch-runtime/mutations.sh    # proves each passing invariant can still fail, ~15 s
```

`check.sh` exits 0 when every invariant passes except the open findings it lists, and 1 otherwise. For the full trace, run `Scripts/formal/tlc.sh formal/launch-runtime/LaunchRuntime.tla`. Read every result with the `/statechart` skill. Requires a JDK 11+ on PATH; the runner downloads the pinned `tla2tools.jar` 1.7.4 once and checks its SHA-256.

## What the model promises

Passing today:
- `OneWorkAtATime`: the cache load, one connection operation, a first fetch, and a background refresh never overlap. Harm if broken: two writers race on `SnapshotStore`, or a sign-in/disconnect swaps the credential a fetch is using.
- `FirstFetchFlagMatchesWork`, `BackgroundFlagMatchesWork`, `OperationFlagMatchesWork`: each in-flight flag is true exactly while its work runs. Harm if broken: every later action is refused and progress never clears.
- `NoFullFetchOverCache`: a full first fetch never runs while a cached pulse exists. The connection check starts only after the cached pulse load returns, which is what replaced the old parked readiness result (mutation `checkDuringCacheLoad`).
- `FetchOnlyWhenConnected`: portfolio requests run only in `.connected(.fetching)`.
- `ConnectionMenuTellsTruth` / `FetchingMenuTellsTruth`: "Checking", "Signing in", "Disconnecting" mean an operation (or the first cache load) runs; "Fetching"/"Refreshing" means a fetch runs.
- `ProblemKeepsPulseVisible`: reconnect, paused subscription, and Keychain problems keep a cached pulse on screen (ADR-0002 item 8).
- `NotConnectedShowsSetup`: after a disconnect, or with no credential, the menu shows setup only.
- `OfferedActionsAreLive`: every clickable Sign in / Use a token / Check again / Disconnect / Try again / Refresh now row is accepted by the runtime.
- `NeverStranded`: something is running, or the menu offers a way forward.

The runtime also refuses connection actions while any work runs (`isIdle`). The state guard already covers that in every reachable state, so that guard is pinned by `LaunchFlowTests` rather than by a mutation here.

Open findings (listed in `check.sh` as `OPEN_FINDINGS`): none.

## Real bug or modelling error

When TLC reports a violation, replay its steps against the Swift code before you believe or dismiss it:
1. For each step, open the function named in the action's comment and confirm the code allows that step from that state: guards, which rows the menu offers, and whether the work is really still running.
2. If every step is possible in the code, it is a real bug. Report it as steps in the code's names. Do not weaken the invariant or the model to make it pass.
3. If a step is impossible in the code, the model is wrong. Fix the action to match the code and cite the line that rules the step out.
4. Where the runtime side can be driven without AppKit, confirm with a scratch swift-testing case that calls `PDTLaunchRuntime` in the same order.

## Updating the model for an intended change

- One TLA+ action is one main-queue block that runs to completion. When the code adds a new async hop, split the action at that hop.
- Mirror the change in the action whose comment names the function, and update the Coverage list above.
- A new menu button or role becomes a new `Can*` predicate plus a `Click*` action. A new background job becomes an in-flight counter or set plus a `*Returns` action.
- Add a mutation to `mutations.sh` for each new invariant. Run it and confirm every line reports a violation.
- Rerun `check.sh`, then move the sync commit forward.

## Scope and bounds

Bounds (`LaunchRuntime.cfg`): at most 4 connection operations started by clicks or the cache load (`MaxOps`) and 2 Try again / Refresh now clicks (`MaxRetries`). That covers 339 distinct states. A pass covers these bounds only.

Modelled at this abstraction:
- A connection operation reports any `PDTConnectionStatus`; a disconnect reports `notConnected` or `keychainUnavailable`.
- Fetch and refresh outcomes are success, `unavailable`, or one of the connection states (`PDTFetchFailure`). Degraded is the same as success for the launch menu.
- The cached load either finds a pulse or does not.
- Menus are reduced to their kind (setup or pulse), their state, and which connection and refresh rows are clickable.

Left out:
- Fixture mode.
- Cancel sign-in: the worker keeps the operation slot until it reports, so cancel changes nothing the model tracks.
- Sign-in notices and the revoke row (copy only).
- Quit-time refresh cancellation (`applicationWillTerminate`).
- What the background refresh does inside (see `verify-background-detail-refresh`), credential refresh and storage (`PDTConnection`, covered by `PDTSignInTests`), and read-state writes (see `verify-pulse-read-state`).
- Timer cadence: a first-fetch progress tick is a re-render only.
