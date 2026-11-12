------------------------------ MODULE LaunchRuntime ------------------------------
(*
  PDTBar no-argument launch over the PDT REST connection (#248): PDTLaunchRuntime
  plus the AppDelegate code that runs its effects on background queues and feeds
  results back on the main queue.

  One TLA+ step = one main-queue block running to completion. Background work
  (cached pulse load, connection operations, first fetch, background detail
  refresh) is "in flight" bookkeeping whose completion is a later main-queue
  step, so TLC explores every completion order.

  Code anchors (Sources/PDTBarCore/LaunchRuntime.swift = Core, Sources/PDTBarApp/main.swift = App):
    PDTLaunchState offers* ......... Core:109-155 (which connection buttons a state shows)
    PDTLaunchMenu.descriptor ....... Core:228-353, notSavedRows Core:392, withConnectionActions Core:625
    PDTLaunchRuntime ............... Core:715-1034
    AppDelegate effect wiring ...... App:59-363
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
\* notConnected drops its signInWouldBe payload: a fact about the build that only changes the status row's detail.
ConnectionStates == {"notConnected", "needsReconnect", "subscriptionPaused", "keychainUnavailable"}
States == {"checkingConnection", "connecting", "disconnecting", "fetching", "fetchFailed", "current"} \cup ConnectionStates
\* How a connected credential is kept (PDTCredentialPersistence .saved / .thisSessionOnly).
Persistences == {"saved", "session"}
\* What a connection operation or a finished sync can report (PDTConnectionStatus).
ConnectedStatuses == {"connected:saved", "connected:session"}
Statuses == ConnectedStatuses \cup ConnectionStates
Persistence(s) == IF s = "connected:session" THEN "session" ELSE "saved"
OpKinds == {"check", "signIn", "token", "disconnect"}
\* What PDTConnection knows (#301, ADR-0003 decision 3). "none": nothing stored and nothing
\* held. "saved": the store holds a credential or a reconnect state. "session": PDT gave a
\* credential (a sign-in, a pasted token, a rotated pair) and the store refused it, so it
\* lives in PDTConnection.refused and is used from there until the process ends.
Creds == {"none", "saved", "session"}

VARIABLES
    \* PDTLaunchRuntime
    state, pulse, opInFlight, attemptID, cacheLoading, ffInFlight, bgInFlight,
    \* the PDTCredentialPersistence payload of .connected; "saved" while not connected
    kept,
    \* last menu installed by installMenuBarItem (what the user sees and can click)
    menu,
    \* background work actually running
    ops,          \* set of [id, kind] connection operations running (App runConnectionOperation)
    cacheLoad,    \* "running" | "done" (App startCachedPulseLoad)
    ffWorkers,    \* running first fetches (App startFirstPortfolioFetch)
    bgWorkers,    \* running background detail refreshes (App startBackgroundPortfolioRefresh)
    opsStarted, retries,
    \* PDTLaunchRuntime.uncommittedSync: "kept" while the record of a sync that committed
    \* nothing is shown in Data Health (Copy diagnostics), "none" otherwise.
    record,
    \* ghosts (#191): the last finished sync committed nothing, and no sync started since
    uncommitted,
    \* ghost (#191): a committed refresh reported lost access, and no connection result since
    lostAccess,
    \* ghost (#301): what PDTConnection knows, one of Creds
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
(* Menu descriptors (PDTLaunchMenu.descriptor + PDTLaunchRuntime.descriptor), abstracted
   to what the user can see and click. Every runtime update re-renders the menu. *)
Desc(st, p, k) ==
    [ kind       |-> IF p = "none" \/ (st = "notConnected" /\ "notConnectedShowsPulse" \notin Mutations)
                        \/ (st = "needsReconnect" /\ "reconnectHidesPulse" \in Mutations)
                     THEN "setup" ELSE "pulse",
      st         |-> st,
      signIn     |-> OffersSignIn(st) \/ ("fetchingOffersSignIn" \in Mutations /\ st = "fetching"),
      checkAgain |-> OffersCheckAgain(st),
      \* No state that offers Disconnect has work running behind it (a fetch is "fetching").
      disconnect |-> OffersDisconnect(st) \/ ("fetchingOffersDisconnect" \in Mutations /\ st = "fetching"),
      \* fetchFailed: "Try again" / "Fill details again"; current with a pulse: "Refresh now".
      \* Connection screens over a pulse render "Refresh now" as waitingForSetup (not clickable).
      refresh    |-> IF st = "fetchFailed" \/ (st = "current" /\ p # "none") THEN "available"
                     ELSE IF st = "fetching" THEN IF "fetchingOffersRefresh" \in Mutations THEN "available" ELSE "inProgress"
                     ELSE IF ("connectionScreenOffersRefresh" \in Mutations /\ p # "none") THEN "available"
                     ELSE "none",
      \* The "Connection not saved" row (pdtConnection.notSaved): on every connected screen,
      \* also the ones that do not offer Disconnect.
      notSaved   |-> Connected(st) /\ k = "session"
                     /\ ~("fetchingHidesNotSaved" \in Mutations /\ st = "fetching") ]

\* Re-render from the next state. Use inside an action after every runtime variable is primed.
Render == menu' = Desc(state', pulse', kept')

CanSignIn == menu.signIn
CanCheckAgain == menu.checkAgain
CanDisconnect == menu.disconnect
CanRetry == menu.refresh = "available"

---------------------------------------------------------------------------------
Init ==
    \* launch(): .checkingConnection, effect .loadCachedPulse (Core launch, App launch)
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
    \* A new process holds nothing: a credential the store refused died with the last one.
    /\ cred \in {"none", "saved"}

\* beginConnectionOperation: new attempt, operation slot taken, effect runs it.
BeginOp(st, kind) ==
    /\ record' = IF "connectionOpDropsRecord" \in Mutations THEN "none" ELSE record
    /\ attemptID' = attemptID + 1
    /\ opInFlight' = TRUE
    /\ state' = st
    /\ kept' = "saved"
    /\ ops' = ops \cup {[id |-> attemptID + 1, kind |-> kind]}
    /\ opsStarted' = opsStarted + 1

\* startBackgroundDetailRefresh (Core) + startBackgroundPortfolioRefresh (App)
\* Every sync start clears the uncommitted record (startFirstFetch / startBackgroundDetailRefresh).
SyncStarts == record' = "none" /\ uncommitted' = FALSE

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

\* apply(status): connected starts the one fetch that fits, kept the way the status says;
\* anything else is shown.
\* The guards in apply were removed with the parked readiness slot: nothing else runs here.
Apply(s, p) ==
    IF s \in ConnectedStatuses
    THEN /\ kept' = Persistence(s)
         /\ IF p # "none" /\ "ignoreCachedPulse" \notin Mutations
            THEN /\ StartBg /\ UNCHANGED <<ffInFlight, ffWorkers>>
            ELSE /\ StartFirstFetch /\ UNCHANGED <<bgInFlight, bgWorkers>>
    ELSE /\ state' = s /\ kept' = "saved"
         /\ UNCHANGED <<ffInFlight, ffWorkers, bgInFlight, bgWorkers, uncommitted>>
         /\ record' = IF "connectionScreenDropsRecord" \in Mutations THEN "none" ELSE record

\* startCachedPulseLoad main-queue block + completeCachedPulseLoad: install the pulse,
\* then begin the connection check (no check runs before the cache load returns).
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

\* What an operation can report, and what PDTConnection knows afterwards (c).
\* PDTConnection.status: a credential held for the session answers before the store: connected
\* for this session only, connected and saved once the retried save lands, or the reconnect
\* state PDT's rejection of it left. Otherwise the store answers, and another process may
\* have stored or deleted a credential since.
CheckAnswers(s, c) ==
    IF cred = "session" /\ "checkReadsStoreOnly" \notin Mutations
    THEN \/ s = "connected:session" /\ c = "session"
         \/ s = "connected:saved" /\ c = "saved"
         \/ s = "needsReconnect" /\ c \in {"session", "saved"}
    ELSE \/ s = "notConnected" /\ c = (IF cred = "session" THEN "session" ELSE "none")
         \/ s \in {"connected:saved", "needsReconnect", "subscriptionPaused"} /\ c = "saved"
         \/ s = "keychainUnavailable" /\ c = cred

\* PDTAppConnection.signIn / connect(token:): stored, or refused by the store and used for
\* the session. A sign-in that was declined, timed out, or cancelled changes nothing and
\* reports like a check.
SignInAnswers(s, c) ==
    \/ s = "connected:saved" /\ c = "saved"
    \/ s = "connected:session" /\ c = "session"
    \/ CheckAnswers(s, c)

\* PDTAppConnection.disconnect: a held credential is dropped at once. A delete the store
\* refused over a stored credential is never reported as removed.
DisconnectAnswers(s, c) ==
    \/ s = "notConnected" /\ c = "none"
    \/ s = "keychainUnavailable" /\ c = "saved"

\* How a finished sync reports the connection (PDTAppConnection.failure(for:) and
\* status(afterSyncEnding:), both over PDTConnection.status). r is the result, k how the
\* credential is kept when the sync leaves it connected: a rotated pair the store refused
\* during the sync is held, and a held credential the store took is saved. A sync cannot
\* find the store empty or unreadable while PDTConnection holds the credential.
SyncMayReport(r) ==
    r \in {"notConnected", "keychainUnavailable"} => (cred # "session" \/ "checkReadsStoreOnly" \in Mutations)
CredAfterSync(r, k) ==
    CASE r \in {"ok", "unavailable"} -> k
      [] r = "notConnected" -> IF cred = "session" THEN "session" ELSE "none"
      [] OTHER -> cred
\* What the runtime shows as kept after a sync that leaves it connected.
KeptAfterSync(k) ==
    IF "syncEndKeepsOldPersistence" \in Mutations THEN kept
    ELSE IF "syncEndReportsSaved" \in Mutations THEN "saved"
    ELSE k

\* runConnectionOperation result on the main queue + completeConnection (stale attempts dropped).
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

\* signIn(): Sign in with PDT -> .connecting, effect .signIn
ClickSignIn ==
    /\ CanSignIn /\ opsStarted < MaxOps
    /\ Idle(cacheLoading, opInFlight, ffInFlight, bgInFlight)
    /\ OffersSignIn(state)
    /\ BeginOp("connecting", "signIn")
    /\ UNCHANGED <<pulse, cacheLoading, ffInFlight, bgInFlight, cacheLoad, ffWorkers, bgWorkers, retries,
                   uncommitted, lostAccess, cred>>
    /\ Render

\* connect(token:): Use a PDT token -> .checkingConnection, effect .connectToken
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

\* retryFirstFetch(): accepted only while connected and idle. The new sync starts with the
\* persistence the state carries.
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

\* A committed sync that found access gone ("lost:<state>", #191): an optional phase lost it,
\* or the connection read after the sync says so. The pulse is published and the menu moves
\* to that connection state.
LostResults == {"lost:notConnected", "lost:needsReconnect", "lost:subscriptionPaused", "lost:keychainUnavailable"}
LostState(r) == CASE r = "lost:notConnected" -> "notConnected"
                  [] r = "lost:needsReconnect" -> "needsReconnect"
                  [] r = "lost:subscriptionPaused" -> "subscriptionPaused"
                  [] OTHER -> "keychainUnavailable"
\* The connection state a sync result names, if any.
ReportedState(r) == IF r \in LostResults THEN LostState(r) ELSE r

\* finishFirstPortfolioFetch (App) + completeFirstFetch (Core). Success publishes the
\* persisted pulse, then the App asks for the background detail refresh in the same block.
FirstFetchReturns ==
    /\ ffWorkers > 0
    /\ ffWorkers' = ffWorkers - 1
    /\ ffInFlight' = ("keepFirstFetchFlag" \in Mutations)
    /\ \E r \in {"ok", "unavailable"} \cup ConnectionStates \cup LostResults, k \in Persistences :
        /\ SyncMayReport(ReportedState(r))
        /\ cred' = CredAfterSync(ReportedState(r), k)
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

\* backgroundDetailRefreshProgress: re-renders progress while the refresh runs
BackgroundProgress ==
    /\ bgWorkers > 0 /\ bgInFlight /\ pulse # "none"
    /\ state' = "fetching"
    /\ UNCHANGED <<pulse, kept, opInFlight, attemptID, cacheLoading, ffInFlight, bgInFlight,
                   ops, cacheLoad, ffWorkers, bgWorkers, opsStarted, retries, record, uncommitted, lostAccess, cred>>
    /\ Render

\* finishBackgroundPortfolioRefresh (App) + completeBackgroundDetailRefresh (Core).
\* A base failure commits nothing: it keeps the pulse and its record, and a connection
\* failure moves to that connection state. A committed refresh that found access gone
\* publishes the pulse and moves to that connection state.
BackgroundReturns ==
    /\ bgWorkers > 0
    /\ bgWorkers' = bgWorkers - 1
    /\ bgInFlight' = FALSE
    /\ \E r \in {"ok", "unavailable"} \cup ConnectionStates \cup LostResults, k \in Persistences :
        /\ SyncMayReport(ReportedState(r))
        /\ cred' = CredAfterSync(ReportedState(r), k)
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

\* cancelSignIn(): the worker keeps the slot until it reports back, so nothing changes here.
\* markPulseItemRead + pulseReadStateDidChange: re-render only. Neither changes tracked state.

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

\* At most one piece of work runs at once: the cache load, one connection operation,
\* a first fetch, or a background refresh. Two fetches race on the same SnapshotStore;
\* a disconnect or sign-in under a fetch swaps the credential the fetch is reading with.
OneWorkAtATime ==
    Cardinality(ops) + ffWorkers + bgWorkers + (IF cacheLoad = "running" THEN 1 ELSE 0) <= 1

\* The runtime's in-flight flags describe real work. A flag left TRUE with no worker
\* refuses every later action and leaves progress rows up forever.
FirstFetchFlagMatchesWork == ffInFlight <=> ffWorkers > 0
BackgroundFlagMatchesWork == bgInFlight <=> bgWorkers > 0
OperationFlagMatchesWork == opInFlight <=> ops # {}

\* A returning user with a cached pulse never pays for a full first fetch.
NoFullFetchOverCache == ffInFlight => pulse = "none"

\* Portfolio requests only run while the connection is connected.
FetchOnlyWhenConnected == (ffWorkers + bgWorkers > 0) => state = "fetching"

\* "Checking", "Signing in", "Disconnecting" mean an operation (or the cache load before
\* the first check) is really running; "Fetching"/"Refreshing" means a fetch is.
ConnectionMenuTellsTruth ==
    menu.st \in {"checkingConnection", "connecting", "disconnecting"} => (ops # {} \/ cacheLoad = "running")
FetchingMenuTellsTruth == menu.st = "fetching" => ffWorkers + bgWorkers > 0
MenuTellsTruth == ConnectionMenuTellsTruth /\ FetchingMenuTellsTruth

\* ADR-0002 item 8: a reconnect or paused subscription keeps the cached pulse visible.
ProblemKeepsPulseVisible ==
    (menu.st \in {"needsReconnect", "subscriptionPaused", "keychainUnavailable"} /\ pulse # "none")
        => menu.kind = "pulse"

\* After a disconnect the menu is setup only: no portfolio is shown as if connected.
NotConnectedShowsSetup == menu.st = "notConnected" => menu.kind = "setup"

\* Every clickable connection or refresh row is accepted by the runtime; none is dead.
OfferedActionsAreLive ==
    LET idle == Idle(cacheLoading, opInFlight, ffInFlight, bgInFlight) IN
    /\ (CanSignIn => idle /\ OffersSignIn(state))
    /\ (CanCheckAgain => idle /\ OffersCheckAgain(state))
    /\ (CanDisconnect => idle /\ OffersDisconnect(state))
    /\ (CanRetry => idle /\ Connected(state))

\* #191: a committed sync that found access gone never leaves the menu saying connected
\* until a connection result says so again.
AccessLossLeavesConnected == lostAccess => ~Connected(state)

\* #191: the record of a sync that committed nothing stays copyable on every screen,
\* connection screens and connection operations included, until the next sync starts.
UncommittedRecordKept == uncommitted => record = "kept"

\* #301: only PDT or the user signs out. While PDTConnection holds a credential the store
\* refused, no check, failed sign-in, or sync turns the menu to Not connected.
SignedOutOnlyWithoutCredential == state = "notConnected" => cred = "none"

\* ADR-0003 decision 3: a credential the store refused is used for the session, and every
\* connected menu says so: the "Connection not saved" row is shown exactly while the
\* credential in use lives in this process only.
NotSavedRowTellsTruth == Connected(state) => (menu.notSaved <=> cred = "session")

\* The user is never stranded: something is running or the menu offers a way forward.
NeverStranded ==
    \/ ops # {} \/ ffWorkers > 0 \/ bgWorkers > 0 \/ cacheLoad = "running"
    \/ CanSignIn \/ CanCheckAgain \/ CanRetry \/ CanDisconnect
=================================================================================
