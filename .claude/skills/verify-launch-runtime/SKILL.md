---
name: verify-launch-runtime
description: "Check changes to PDTBar launch, PDT connection check/sign-in/disconnect, first fetch, cached pulse, or background refresh wiring against the TLA+ launch model."
---

# Verify launch runtime

A TLA+ model of the no-argument PDTBar launch over the PDT REST connection (#248): `PDTLaunchRuntime` plus the `AppDelegate` code that runs its effects on background queues and feeds results back on the main queue. TLC explores every order in which the cached-pulse load, connection operations (check, sign-in, pasted token, disconnect), first fetch, background refresh and menu clicks can complete.

## When to use

Run it when a change touches any covered function below, the order of main-queue work in `AppDelegate`, which buttons a launch menu shows, or the meaning of `connectionOperationInFlight`, `connectionAttempt`, `cachedPulseLoading`, `firstFetchInFlight`, `backgroundDetailRefreshInFlight`, or `PDTLaunchState.offers*`. Pure copy or layout changes to menu rows do not need it, unless a row's `role` changes (`connectionSignIn`, `connectionToken`, `connectionCheck`, `connectionDisconnect`, `fetchRetry` are the clickable ones the model tracks).

## Coverage

Sync commit: `fix(auth): a held connection change yields to a newer one from another process`. After you confirm the model still describes the covered code at a newer commit, move this line forward. Never move it without that check.

`Sources/PDTBarCore/LaunchRuntime.swift`:
- `PDTLaunchState` 109 and its `offersSignIn` / `offersCheckAgain` / `offersDisconnect` 135-155.
- `PDTLaunchMenu.descriptor(for:cachedPulse:notice:fetchingElapsedSeconds:syncFailure:)` 228, `notSavedRows` 392, `withConnectionActions` 625.
- `PDTConnectionAttempt` 690. `PDTLaunchRuntime` 715: `launch` 752, `completeCachedPulseLoad` 757, `completeConnection` 768, `signIn` 777, `connect(token:)` 784, `cancelSignIn` 792, `checkAgain` 799, `disconnect` 806, `retryFirstFetch` 814, `firstFetchProgress` 824, `completeFirstFetch` 831, `beginBackgroundDetailRefresh` 845, `backgroundDetailRefreshProgress` 852, `completeBackgroundDetailRefresh` 860, `pulseReadStateDidChange` 882, `apply` 896, `endCommitted` 911, `endUncommitted` 922, `beginConnectionOperation` 938, `startBackgroundDetailRefresh` 951, `descriptor` 976.

`Sources/PDTBarCore/MenuDescriptorRenderer.swift`: `refreshActionRow` 486 with its "Refresh now" rows (`waitingForSetup` is shown but not clickable).

`Sources/PDTBarApp/main.swift` (`AppDelegate`): `launch` 59, `startCachedPulseLoad` 92, `runConnectionOperation` 110, `startSignIn` 127, `startFirstPortfolioFetch` 133, `finishFirstPortfolioFetch` 174, `startBackgroundPortfolioRefresh` 225, `finishBackgroundPortfolioRefresh` 275, connection selectors 289-336, `handleLaunchUpdate` 338, `connectionAction(for:)` 960 role-to-selector wiring.

`Sources/PDTBarCore/PDTConnection.swift` and `Sources/PDTBarAppSupport/PDTAppConnection.swift`, only as the `cred` ghost: what `status`, `replace`, `record`, and `commit` let `check`, `signIn`, `connect(token:)`, `disconnect`, `failure(for:)`, and `status(afterSyncEnding:)` report while a credential the store refused is held and used (#301, ADR-0003 decision 3). Run the model when that changes.

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
- `AccessLossLeavesConnected` (#191): a committed first fetch or refresh that found access gone (an optional phase's 401, `INSUFFICIENT_SCOPE`, `API_ACCESS_PAUSED`, or the connection read after the sync) moves to that connection state; the menu never says connected until a connection result does (mutation `optionalAccessLossStaysConnected`).
- `UncommittedRecordKept` (#191): the failure record of a sync that committed nothing stays in Data Health on connection screens and through connection operations until the next sync starts (mutations `connectionScreenDropsRecord`, `connectionOpDropsRecord`).
- `SignedOutOnlyWithoutCredential` (#301): the menu says `Not connected` only when `PDTConnection` holds and stores nothing. While it holds a credential the store refused, no check, failed sign-in, or sync signs the user out (mutation `checkReadsStoreOnly`, the #301 bug: a check that reads the store past the held credential). A disconnect in another process drops the held credential first, so the menu then says `Not connected` with nothing held.
- `NotSavedRowTellsTruth` (ADR-0003 decision 3): on every connected screen the `Connection not saved` row is shown exactly while the credential in use lives in this process only. Harm if broken: a user quits believing the sign-in is saved, or keeps reading a warning that no longer holds. Mutations: `fetchingHidesNotSaved` (the row only where Disconnect is offered), `syncEndReportsSaved` (a finished sync reports a hand-built saved connection), `syncEndKeepsOldPersistence` (a finished sync keeps what the state said before it), `retryForgetsNotSaved` (a retry starts as saved).

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

Bounds (`LaunchRuntime.cfg`): at most 4 connection operations started by clicks or the cache load (`MaxOps`) and 2 Try again / Refresh now clicks (`MaxRetries`). That covers 1098 distinct states. A pass covers these bounds only.

Modelled at this abstraction:
- The ghost `cred` is what `PDTConnection` knows: `none`, `saved`, or `session` (a sign-in, token, or rotated pair the store refused, used from memory). A check answers from a session credential first (`connected:session`, `connected:saved` once the retried save lands, or the reconnect state a rejection left). The session credential gives way only to a sign-in, token, or disconnect another process stored after it: it is dropped and the store answers, which after a disconnect there is `notConnected` with nothing held, and `keychainUnavailable` when the store stops reading right after. Otherwise a check answers from the store, which another process may have changed. A sign-in or token ends saved or session, or changes nothing. A disconnect reports `notConnected` or `keychainUnavailable`. A new process starts with nothing held.
- `kept` is the persistence payload of `.connected`. Every connection result and every sync end that leaves the menu connected sets it from what `PDTConnection` says then; a retry carries it into the next sync.
- Fetch and refresh outcomes are success, `unavailable`, one of the connection states (`PDTFetchFailure`), or committed with access gone. A sync that ends connected may have changed how the credential is kept: a rotated pair the store refused is held, and a held credential the store took is saved. The model puts that change at the sync's end, where the code reads it; a row shown while the sync still runs is as old as the sync's start. A sync finds the store not connected or unreadable past a held credential only after another process stored a sign-in, token, or disconnect, which drops the held credential. Degraded is the same as success for the launch menu.
- The cached load either finds a pulse or does not.
- Menus are reduced to their kind (setup or pulse), their state, and which connection and refresh rows are clickable.

Left out:
- Fixture mode.
- Cancel sign-in: the worker keeps the operation slot until it reports, so cancel changes nothing the model tracks.
- Sign-in notices and the revoke row (copy only).
- What `notConnected` says about saving a sign-in (`signInWouldBe`): a fact about the build's signature that `PDTConnection.status` copies from the store into every not-connected status. The runtime only carries it to the status row's detail, so it changes no state, row, or guard the model tracks. `SignInPersistenceTests` covers it.
- Quit-time refresh cancellation (`applicationWillTerminate`).
- What the background refresh does inside (see `verify-background-detail-refresh`), credential refresh, storage, and the replay of a change the store refused (`PDTConnection`, covered by `PDTSignInTests`, `SignInPersistenceTests`, and `HeldConnectionChangeTests`, which also holds the stored generation rule), and read-state writes (see `verify-pulse-read-state`).
- Timer cadence: a first-fetch progress tick is a re-render only.
