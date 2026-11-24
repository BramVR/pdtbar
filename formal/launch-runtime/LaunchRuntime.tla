------------------------------ MODULE LaunchRuntime ------------------------------
(*
  PDTBar no-argument launch over the PDT REST connection (#248): PDTLaunchRuntime
  plus the AppDelegate code that runs its effects on background queues and feeds
  results back on the main queue.

  One TLA+ step = one main-queue block running to completion. Background work
  (cached pulse load, connection operations, first fetch, background detail
  refresh) is "in flight" bookkeeping whose completion is a later main-queue
  step, so TLC explores every completion order.

  Code anchors name symbols, never line numbers (pdtbar-checks checks them):
    PDTLaunchState.offersSignIn / offersCheckAgain / offersDisconnect (which connection buttons a state shows)
    PDTLaunchMenu.descriptor, PDTLaunchMenu.notSavedRows, PDTLaunchMenu.withConnectionRows
    PDTLaunchRuntime ............... Sources/PDTBarCore/LaunchRuntime.swift
    AppDelegate effect wiring ...... Sources/PDTBarApp/main.swift
    PDTConnection (the cred ghost) . Sources/PDTBarCore/PDTConnection.swift: status, replace, record, commit;
                                     PDTAppConnection.check / signIn / connect / disconnect /
                                     failure(for:) / status(afterSyncEnding:)
*)
EXTENDS Naturals, FiniteSets

CONSTANTS
    MaxOps,       \* bound on connection operations (check, sign-in, token, disconnect)
    MaxRetries,   \* bound on "Try again" / "Refresh now" / "Fill details again" clicks
    Mutations     \* {} for the real code; names replay one-line code breaks (see mutations.sh)

\* The connected states are flattened: fetching, fetchFailed, current = .connected(.fetching/.failed/.current, kept).
ConnectionStates == {"notConnected", "needsReconnect", "subscriptionPaused", "keychainUnavailable"}
States == {"checkingConnection", "connecting", "disconnecting", "fetching", "fetchFailed", "current"} \cup ConnectionStates
\* PDTCredentialPersistence .saved / .thisSessionOnly
Persistences == {"saved", "session"}
\* PDTConnectionStatus
ConnectedStatuses == {"connected:saved", "connected:session"}
Statuses == ConnectedStatuses \cup ConnectionStates
Persistence(s) == IF s = "connected:session" THEN "session" ELSE "saved"
OpKinds == {"check", "signIn", "token", "disconnect"}
\* What PDTConnection knows. "session": the credential in PDTConnection.refused.
Creds == {"none", "saved", "session"}

VARIABLES
    \* PDTLaunchRuntime
    state, pulse, opInFlight, attemptID, cacheLoading, ffInFlight, bgInFlight,
    \* the PDTCredentialPersistence payload of .connected
    kept,
    \* last menu installed by installMenuBarItem (what the user sees and can click)
    menu,
    \* background work actually running
    ops,          \* set of [id, kind] connection operations running (App runConnectionOperation)
    cacheLoad,    \* "running" | "done" (App startCachedPulseLoad)
    ffWorkers,    \* running first fetches (App startFirstPortfolioFetch)
    bgWorkers,    \* running background detail refreshes (App startBackgroundPortfolioRefresh)
    opsStarted, retries,
    \* PDTLaunchRuntime.uncommittedSync
    record,
    \* ghosts
    uncommitted,
    lostAccess,
    cred

vars == <<state, pulse, opInFlight, attemptID, cacheLoading, ffInFlight, bgInFlight, kept,
          menu, ops, cacheLoad, ffWorkers, bgWorkers, opsStarted, retries,
          record, uncommitted, lostAccess, cred>>

---------------------------------------------------------------------------------
(* Runtime predicates, Core PDTLaunchState / PDTLaunchRuntime.isIdle *)

OffersSignIn(st) == st \in {"notConnected", "needsReconnect", "subscriptionPaused"}
OffersCheckAgain(st) == st \in {"needsReconnect", "subscriptionPaused", "keychainUnavailable"}
OffersDisconnect(st) == st \in {"needsReconnect", "subscriptionPaused", "fetchFailed", "current"}
Idle(cl, op, ff, bg) == ~cl /\ ~op /\ ~ff /\ ~bg
Connected(st) == st \in {"fetching", "fetchFailed", "current"}

---------------------------------------------------------------------------------
(* PDTLaunchMenu.descriptor + PDTLaunchRuntime.descriptor *)
Desc(st, p, k) ==
    [ kind       |-> IF p = "none" \/ (st = "notConnected" /\ "notConnectedShowsPulse" \notin Mutations)
                        \/ (st = "needsReconnect" /\ "reconnectHidesPulse" \in Mutations)
                     THEN "setup" ELSE "pulse",
      st         |-> st,
      signIn     |-> OffersSignIn(st) \/ ("fetchingOffersSignIn" \in Mutations /\ st = "fetching"),
      checkAgain |-> OffersCheckAgain(st),
      disconnect |-> OffersDisconnect(st) \/ ("fetchingOffersDisconnect" \in Mutations /\ st = "fetching"),
      \* "Try again" / "Fill details again" / "Refresh now"; waitingForSetup is not clickable.
      refresh    |-> IF st = "fetchFailed" \/ (st = "current" /\ p # "none") THEN "available"
                     ELSE IF st = "fetching" THEN IF "fetchingOffersRefresh" \in Mutations THEN "available" ELSE "inProgress"
                     ELSE IF ("connectionScreenOffersRefresh" \in Mutations /\ p # "none") THEN "available"
                     ELSE "none",
      \* The "Connection not saved" row (pdtConnection.notSaved), wherever it sits.
      notSaved   |-> Connected(st) /\ k = "session"
                     /\ ~("fetchingHidesNotSaved" \in Mutations /\ st = "fetching") ]

\* Put after every runtime variable is primed: TLC must know each value Desc reads.
Render == menu' = Desc(state', pulse', kept')

CanSignIn == menu.signIn
CanCheckAgain == menu.checkAgain
CanDisconnect == menu.disconnect
CanRetry == menu.refresh = "available"

---------------------------------------------------------------------------------
Init ==
    \* PDTLaunchRuntime.launch + AppDelegate.launch
    /\ state = "checkingConnection"
    /\ pulse = "none"
    /\ opInFlight = FALSE
    /\ attemptID = 0
    /\ cacheLoading = TRUE
    /\ ffInFlight = FALSE
    /\ bgInFlight = FALSE
    /\ kept = "saved"
    /\ menu = Desc("checkingConnection", "none", "saved")
    /\ ops = IF "checkDuringCacheLoad" \in Mutations THEN {[id |-> 0, kind |-> "check"]} ELSE {}
    /\ cacheLoad = "running"
    /\ ffWorkers = 0
    /\ bgWorkers = 0
    /\ opsStarted = 0
    /\ retries = 0
    /\ record = "none"
    /\ uncommitted = FALSE
    /\ lostAccess = FALSE
    /\ cred \in {"none", "saved"}

\* beginConnectionOperation
BeginOp(st, kind) ==
    /\ record' = IF "connectionOpDropsRecord" \in Mutations THEN "none" ELSE record
    /\ attemptID' = attemptID + 1
    /\ opInFlight' = TRUE
    /\ state' = st
    /\ kept' = "saved"
    /\ ops' = ops \cup {[id |-> attemptID + 1, kind |-> kind]}
    /\ opsStarted' = opsStarted + 1

\* startFirstFetch / startBackgroundDetailRefresh
SyncStarts == record' = "none" /\ uncommitted' = FALSE

\* startBackgroundDetailRefresh (Core) + startBackgroundPortfolioRefresh (App)
StartBg ==
    /\ SyncStarts
    /\ bgInFlight' = TRUE
    /\ bgWorkers' = bgWorkers + 1
    /\ state' = "fetching"

StartFirstFetch ==
    /\ SyncStarts
    /\ ffInFlight' = TRUE
    /\ ffWorkers' = ffWorkers + 1
    /\ state' = "fetching"

\* apply(status)
Apply(s, p) ==
    IF s \in ConnectedStatuses
    THEN /\ kept' = Persistence(s)
         /\ IF p # "none" /\ "ignoreCachedPulse" \notin Mutations
            THEN /\ StartBg /\ UNCHANGED <<ffInFlight, ffWorkers>>
            ELSE /\ StartFirstFetch /\ UNCHANGED <<bgInFlight, bgWorkers>>
    ELSE /\ state' = s /\ kept' = "saved"
         /\ UNCHANGED <<ffInFlight, ffWorkers, bgInFlight, bgWorkers, uncommitted>>
         /\ record' = IF "connectionScreenDropsRecord" \in Mutations THEN "none" ELSE record

\* startCachedPulseLoad main-queue block + completeCachedPulseLoad
CacheLoadReturns ==
    /\ cacheLoad = "running"
    /\ cacheLoad' = "done"
    /\ cacheLoading' = FALSE
    /\ \E hasCache \in BOOLEAN :
         /\ pulse' = IF hasCache /\ pulse = "none" THEN "cached" ELSE pulse
         /\ IF "checkDuringCacheLoad" \in Mutations
            THEN UNCHANGED <<state, kept, opInFlight, attemptID, ops, opsStarted, record>>
            ELSE BeginOp("checkingConnection", "check")
    /\ UNCHANGED <<ffInFlight, bgInFlight, ffWorkers, bgWorkers, retries, uncommitted, lostAccess, cred>>
    /\ Render

\* PDTConnection.status and PDTConnection.Change.applied; c is cred afterwards.
CheckAnswers(s, c) ==
    IF cred = "session" /\ "checkReadsStoreOnly" \notin Mutations
    THEN \/ s = "connected:session" /\ c = "session"
         \/ s = "connected:saved" /\ c = "saved"
         \/ s = "needsReconnect" /\ c \in {"session", "saved"}
         \/ s = "notConnected" /\ c = "none"
         \/ s = "keychainUnavailable" /\ c \in {"none", "saved"}
    ELSE \/ s = "notConnected" /\ c = (IF cred = "session" THEN "session" ELSE "none")
         \/ s \in {"connected:saved", "needsReconnect", "subscriptionPaused"} /\ c = "saved"
         \/ s = "keychainUnavailable" /\ c = cred

\* PDTAppConnection.signIn / connect(token:)
SignInAnswers(s, c) ==
    \/ s = "connected:saved" /\ c = "saved"
    \/ s = "connected:session" /\ c = "session"
    \/ CheckAnswers(s, c)

\* PDTAppConnection.disconnect
DisconnectAnswers(s, c) ==
    \/ s = "notConnected" /\ c = "none"
    \/ s = "keychainUnavailable" /\ c = "saved"

\* PDTAppConnection.failure(for:) / status(afterSyncEnding:) over PDTConnection.status.
\* r: the reported state; k: the persistence if the sync leaves it connected.
CredsAfterSync(r, k) ==
    CASE r \in {"ok", "unavailable"} -> {k}
      [] cred = "session" /\ "checkReadsStoreOnly" \in Mutations -> {"session"}
      [] r = "notConnected" -> {"none"}
      [] r = "keychainUnavailable" /\ cred = "session" -> {"none", "saved"}
      [] OTHER -> {cred}
KeptAfterSync(k) ==
    IF "syncEndKeepsOldPersistence" \in Mutations THEN kept
    ELSE IF "syncEndReportsSaved" \in Mutations THEN "saved"
    ELSE k

\* runConnectionOperation result on the main queue + completeConnection
OpReturns ==
    \E op \in ops, s \in Statuses, c \in Creds :
        /\ CASE op.kind = "disconnect" -> DisconnectAnswers(s, c)
             [] op.kind = "check" -> CheckAnswers(s, c)
             [] OTHER -> SignInAnswers(s, c)
        /\ cred' = c
        /\ ops' = ops \ {op}
        /\ UNCHANGED <<attemptID, cacheLoading, cacheLoad, opsStarted, retries>>
        /\ IF ~(opInFlight /\ op.id = attemptID) /\ "checkDuringCacheLoad" \notin Mutations
           THEN UNCHANGED <<state, kept, pulse, opInFlight, ffInFlight, bgInFlight, ffWorkers, bgWorkers, menu,
                            record, uncommitted, lostAccess>>
           ELSE /\ opInFlight' = FALSE
                /\ lostAccess' = FALSE
                /\ UNCHANGED pulse
                /\ Apply(s, pulse)
                /\ Render

\* signIn()
ClickSignIn ==
    /\ CanSignIn /\ opsStarted < MaxOps
    /\ Idle(cacheLoading, opInFlight, ffInFlight, bgInFlight)
    /\ OffersSignIn(state)
    /\ BeginOp("connecting", "signIn")
    /\ UNCHANGED <<pulse, cacheLoading, ffInFlight, bgInFlight, cacheLoad, ffWorkers, bgWorkers, retries,
                   uncommitted, lostAccess, cred>>
    /\ Render

\* connect(token:)
ClickToken ==
    /\ CanSignIn /\ opsStarted < MaxOps
    /\ Idle(cacheLoading, opInFlight, ffInFlight, bgInFlight)
    /\ OffersSignIn(state)
    /\ BeginOp("checkingConnection", "token")
    /\ UNCHANGED <<pulse, cacheLoading, ffInFlight, bgInFlight, cacheLoad, ffWorkers, bgWorkers, retries,
                   uncommitted, lostAccess, cred>>
    /\ Render

\* checkAgain()
ClickCheckAgain ==
    /\ CanCheckAgain /\ opsStarted < MaxOps
    /\ Idle(cacheLoading, opInFlight, ffInFlight, bgInFlight)
    /\ OffersCheckAgain(state)
    /\ BeginOp("checkingConnection", "check")
    /\ UNCHANGED <<pulse, cacheLoading, ffInFlight, bgInFlight, cacheLoad, ffWorkers, bgWorkers, retries,
                   uncommitted, lostAccess, cred>>
    /\ Render

\* disconnect()
ClickDisconnect ==
    /\ CanDisconnect /\ opsStarted < MaxOps
    /\ Idle(cacheLoading, opInFlight, ffInFlight, bgInFlight)
    /\ OffersDisconnect(state)
    /\ BeginOp("disconnecting", "disconnect")
    /\ UNCHANGED <<pulse, cacheLoading, ffInFlight, bgInFlight, cacheLoad, ffWorkers, bgWorkers, retries,
                   uncommitted, lostAccess, cred>>
    /\ Render

\* retryFirstFetch()
ClickRetry ==
    /\ CanRetry /\ retries < MaxRetries
    /\ retries' = retries + 1
    /\ Connected(state)
    /\ kept' = IF "retryForgetsNotSaved" \in Mutations THEN "saved" ELSE kept
    /\ (Idle(cacheLoading, opInFlight, ffInFlight, bgInFlight) \/ "noRetryGuard" \in Mutations)
    /\ IF pulse # "none"
       THEN /\ StartBg /\ UNCHANGED <<ffInFlight, ffWorkers>>
       ELSE /\ StartFirstFetch /\ UNCHANGED <<bgInFlight, bgWorkers>>
    /\ UNCHANGED <<pulse, opInFlight, attemptID, cacheLoading, ops, cacheLoad, opsStarted, lostAccess, cred>>
    /\ Render

LostResults == {"lost:notConnected", "lost:needsReconnect", "lost:subscriptionPaused", "lost:keychainUnavailable"}
LostState(r) == CASE r = "lost:notConnected" -> "notConnected"
                  [] r = "lost:needsReconnect" -> "needsReconnect"
                  [] r = "lost:subscriptionPaused" -> "subscriptionPaused"
                  [] OTHER -> "keychainUnavailable"
ReportedState(r) == IF r \in LostResults THEN LostState(r) ELSE r

\* finishFirstPortfolioFetch (App) + completeFirstFetch (Core); on success the App starts
\* the background detail refresh in the same main-queue block.
FirstFetchReturns ==
    /\ ffWorkers > 0
    /\ ffWorkers' = ffWorkers - 1
    /\ ffInFlight' = ("keepFirstFetchFlag" \in Mutations)
    /\ \E r \in {"ok", "unavailable"} \cup ConnectionStates \cup LostResults, k \in Persistences :
        /\ cred' \in CredsAfterSync(ReportedState(r), k)
        /\ CASE r = "ok" ->
                  /\ pulse' = "live" /\ kept' = KeptAfterSync(k) /\ UNCHANGED lostAccess
                  /\ IF "keepFirstFetchFlag" \in Mutations
                     THEN /\ state' = "current" /\ UNCHANGED <<bgInFlight, bgWorkers, record, uncommitted>>
                     ELSE /\ bgInFlight' = TRUE /\ bgWorkers' = bgWorkers + 1 /\ state' = "fetching"
                          /\ SyncStarts
             [] r \in LostResults ->
                  /\ pulse' = "live" /\ state' = LostState(r) /\ kept' = "saved"
                  /\ UNCHANGED <<bgInFlight, bgWorkers, record, uncommitted>> /\ lostAccess' = TRUE
             [] r = "unavailable" ->
                  /\ UNCHANGED <<pulse, bgInFlight, bgWorkers, lostAccess>> /\ state' = "fetchFailed"
                  /\ kept' = KeptAfterSync(k)
                  /\ record' = "kept" /\ uncommitted' = TRUE
             [] OTHER ->
                  /\ UNCHANGED <<pulse, bgInFlight, bgWorkers, lostAccess>> /\ state' = r /\ kept' = "saved"
                  /\ record' = IF "connectionScreenDropsRecord" \in Mutations THEN "none" ELSE "kept"
                  /\ uncommitted' = TRUE
    /\ UNCHANGED <<opInFlight, attemptID, cacheLoading, ops, cacheLoad, opsStarted, retries>>
    /\ Render

\* backgroundDetailRefreshProgress
BackgroundProgress ==
    /\ bgWorkers > 0 /\ bgInFlight /\ pulse # "none"
    /\ state' = "fetching"
    /\ UNCHANGED <<pulse, kept, opInFlight, attemptID, cacheLoading, ffInFlight, bgInFlight,
                   ops, cacheLoad, ffWorkers, bgWorkers, opsStarted, retries, record, uncommitted, lostAccess, cred>>
    /\ Render

\* finishBackgroundPortfolioRefresh (App) + completeBackgroundDetailRefresh (Core)
BackgroundReturns ==
    /\ bgWorkers > 0
    /\ bgWorkers' = bgWorkers - 1
    /\ bgInFlight' = FALSE
    /\ \E r \in {"ok", "unavailable"} \cup ConnectionStates \cup LostResults, k \in Persistences :
        /\ cred' \in CredsAfterSync(ReportedState(r), k)
        /\ CASE r = "ok" -> /\ pulse' = "live" /\ state' = "current" /\ kept' = KeptAfterSync(k)
                            /\ UNCHANGED <<record, uncommitted>> /\ lostAccess' = FALSE
             [] r \in LostResults ->
                  /\ pulse' = "live"
                  /\ IF "optionalAccessLossStaysConnected" \in Mutations
                     THEN state' = "current" /\ UNCHANGED kept
                     ELSE state' = LostState(r) /\ kept' = "saved"
                  /\ UNCHANGED <<record, uncommitted>> /\ lostAccess' = TRUE
             [] r = "unavailable" -> /\ UNCHANGED pulse /\ state' = "fetchFailed" /\ kept' = KeptAfterSync(k)
                  /\ record' = "kept" /\ uncommitted' = TRUE /\ lostAccess' = FALSE
             [] OTHER -> /\ UNCHANGED pulse
                         /\ IF "failureStaysFetching" \in Mutations
                            THEN state' = "fetching" /\ UNCHANGED kept
                            ELSE state' = r /\ kept' = "saved"
                         /\ record' = IF "connectionScreenDropsRecord" \in Mutations THEN "none" ELSE "kept"
                         /\ uncommitted' = TRUE /\ lostAccess' = FALSE
    /\ UNCHANGED <<opInFlight, attemptID, cacheLoading, ffInFlight, ops, cacheLoad, ffWorkers, opsStarted, retries>>
    /\ Render

Next ==
    \/ CacheLoadReturns
    \/ OpReturns
    \/ ClickSignIn
    \/ ClickToken
    \/ ClickCheckAgain
    \/ ClickDisconnect
    \/ ClickRetry
    \/ FirstFetchReturns
    \/ BackgroundProgress
    \/ BackgroundReturns

Spec == Init /\ [][Next]_vars

---------------------------------------------------------------------------------
(* Properties *)

TypeOK ==
    /\ state \in States
    /\ record \in {"none", "kept"}
    /\ pulse \in {"none", "cached", "live"}
    /\ cred \in Creds
    /\ kept \in Persistences
    /\ ffWorkers \in 0..3 /\ bgWorkers \in 0..3

OneWorkAtATime ==
    Cardinality(ops) + ffWorkers + bgWorkers + (IF cacheLoad = "running" THEN 1 ELSE 0) <= 1

FirstFetchFlagMatchesWork == ffInFlight <=> ffWorkers > 0
BackgroundFlagMatchesWork == bgInFlight <=> bgWorkers > 0
OperationFlagMatchesWork == opInFlight <=> ops # {}

\* A returning user with a cached pulse never pays for a full first fetch.
NoFullFetchOverCache == ffInFlight => pulse = "none"

FetchOnlyWhenConnected == (ffWorkers + bgWorkers > 0) => state = "fetching"

ConnectionMenuTellsTruth ==
    menu.st \in {"checkingConnection", "connecting", "disconnecting"} => (ops # {} \/ cacheLoad = "running")
FetchingMenuTellsTruth == menu.st = "fetching" => ffWorkers + bgWorkers > 0
MenuTellsTruth == ConnectionMenuTellsTruth /\ FetchingMenuTellsTruth

ProblemKeepsPulseVisible ==
    (menu.st \in {"needsReconnect", "subscriptionPaused", "keychainUnavailable"} /\ pulse # "none")
        => menu.kind = "pulse"

NotConnectedShowsSetup == menu.st = "notConnected" => menu.kind = "setup"

OfferedActionsAreLive ==
    LET idle == Idle(cacheLoading, opInFlight, ffInFlight, bgInFlight) IN
    /\ (CanSignIn => idle /\ OffersSignIn(state))
    /\ (CanCheckAgain => idle /\ OffersCheckAgain(state))
    /\ (CanDisconnect => idle /\ OffersDisconnect(state))
    /\ (CanRetry => idle /\ Connected(state))

AccessLossLeavesConnected == lostAccess => ~Connected(state)

UncommittedRecordKept == uncommitted => record = "kept"

SignedOutOnlyWithoutCredential == state = "notConnected" => cred = "none"

NotSavedRowTellsTruth == Connected(state) => (menu.notSaved <=> cred = "session")

NeverStranded ==
    \/ ops # {} \/ ffWorkers > 0 \/ bgWorkers > 0 \/ cacheLoad = "running"
    \/ CanSignIn \/ CanCheckAgain \/ CanRetry \/ CanDisconnect
=================================================================================
