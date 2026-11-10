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
    PDTLaunchState offers* ......... Core:94-150 (which connection buttons a state shows)
    PDTLaunchMenu.descriptor ....... Core:207-330, withDisconnectAction Core:771
    PDTLaunchRuntime ............... Core:849-1105
    AppDelegate effect wiring ...... App:60-355
*)
EXTENDS Naturals, FiniteSets

CONSTANTS
    MaxOps,       \* bound on connection operations (check, sign-in, token, disconnect)
    MaxRetries,   \* bound on "Try again" / "Refresh now" / "Fill details again" clicks
    Mutations     \* {} for the real code; names replay one-line code breaks (see mutations.sh)

\* The connected states are flattened: fetching, fetchFailed, current = .connected(.fetching/.failed/.current).
ConnectionStates == {"notConnected", "needsReconnect", "subscriptionPaused", "keychainUnavailable"}
States == {"checkingConnection", "connecting", "disconnecting", "fetching", "fetchFailed", "current"} \cup ConnectionStates
\* What a connection operation can report (PDTConnectionStatus).
Statuses == {"connected"} \cup ConnectionStates
OpKinds == {"check", "signIn", "token", "disconnect"}

VARIABLES
    \* PDTLaunchRuntime
    state, pulse, opInFlight, attemptID, cacheLoading, ffInFlight, bgInFlight,
    \* last menu installed by installMenuBarItem (what the user sees and can click)
    menu,
    \* background work actually running
    ops,          \* set of [id, kind] connection operations running (App runConnectionOperation)
    cacheLoad,    \* "running" | "done" (App startCachedPulseLoad)
    ffWorkers,    \* running first fetches (App startFirstPortfolioFetch)
    bgWorkers,    \* running background detail refreshes (App startBackgroundPortfolioRefresh)
    opsStarted, retries

vars == <<state, pulse, opInFlight, attemptID, cacheLoading, ffInFlight, bgInFlight,
          menu, ops, cacheLoad, ffWorkers, bgWorkers, opsStarted, retries>>

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
Desc(st, p) ==
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
                     ELSE "none" ]

\* Re-render from the next state. Use inside an action after every runtime variable is primed.
Render == menu' = Desc(state', pulse')

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
    /\ menu = Desc("checkingConnection", "none")
    /\ ops = IF "checkDuringCacheLoad" \in Mutations THEN {[id |-> 0, kind |-> "check"]} ELSE {}
    /\ cacheLoad = "running"
    /\ ffWorkers = 0
    /\ bgWorkers = 0
    /\ opsStarted = 0
    /\ retries = 0

\* beginConnectionOperation: new attempt, operation slot taken, effect runs it.
BeginOp(st, kind) ==
    /\ attemptID' = attemptID + 1
    /\ opInFlight' = TRUE
    /\ state' = st
    /\ ops' = ops \cup {[id |-> attemptID + 1, kind |-> kind]}
    /\ opsStarted' = opsStarted + 1

\* startBackgroundDetailRefresh (Core) + startBackgroundPortfolioRefresh (App)
StartBg ==
    /\ bgInFlight' = TRUE
    /\ bgWorkers' = bgWorkers + 1
    /\ state' = "fetching"

StartFirstFetch ==
    /\ ffInFlight' = TRUE
    /\ ffWorkers' = ffWorkers + 1
    /\ state' = "fetching"

\* apply(status): connected starts the one fetch that fits; anything else is shown.
\* The guards in apply were removed with the parked readiness slot: nothing else runs here.
Apply(s, p) ==
    IF s = "connected"
    THEN IF p # "none" /\ "ignoreCachedPulse" \notin Mutations
         THEN /\ StartBg /\ UNCHANGED <<ffInFlight, ffWorkers>>
         ELSE /\ StartFirstFetch /\ UNCHANGED <<bgInFlight, bgWorkers>>
    ELSE /\ state' = s /\ UNCHANGED <<ffInFlight, ffWorkers, bgInFlight, bgWorkers>>

\* startCachedPulseLoad main-queue block + completeCachedPulseLoad: install the pulse,
\* then begin the connection check (no check runs before the cache load returns).
CacheLoadReturns ==
    /\ cacheLoad = "running"
    /\ cacheLoad' = "done"
    /\ cacheLoading' = FALSE
    /\ \E hasCache \in BOOLEAN :
         /\ pulse' = IF hasCache /\ pulse = "none" THEN "cached" ELSE pulse
         /\ IF "checkDuringCacheLoad" \in Mutations
            THEN UNCHANGED <<state, opInFlight, attemptID, ops, opsStarted>>
            ELSE BeginOp("checkingConnection", "check")
    /\ UNCHANGED <<ffInFlight, bgInFlight, ffWorkers, bgWorkers, retries>>
    /\ Render

\* runConnectionOperation result on the main queue + completeConnection (stale attempts dropped).
OpReturns ==
    \E op \in ops, s \in Statuses :
        /\ (op.kind = "disconnect" => s \in {"notConnected", "keychainUnavailable"})
        /\ ops' = ops \ {op}
        /\ UNCHANGED <<attemptID, cacheLoading, cacheLoad, opsStarted, retries>>
        /\ IF ~(opInFlight /\ op.id = attemptID) /\ "checkDuringCacheLoad" \notin Mutations
           THEN UNCHANGED <<state, pulse, opInFlight, ffInFlight, bgInFlight, ffWorkers, bgWorkers, menu>>
           ELSE /\ opInFlight' = FALSE
                /\ UNCHANGED pulse
                /\ Apply(s, pulse)
                /\ Render

\* signIn(): Sign in with PDT -> .connecting, effect .signIn
ClickSignIn ==
    /\ CanSignIn /\ opsStarted < MaxOps
    /\ Idle(cacheLoading, opInFlight, ffInFlight, bgInFlight)
    /\ OffersSignIn(state)
    /\ BeginOp("connecting", "signIn")
    /\ UNCHANGED <<pulse, cacheLoading, ffInFlight, bgInFlight, cacheLoad, ffWorkers, bgWorkers, retries>>
    /\ Render

\* connect(token:): Use a PDT token -> .checkingConnection, effect .connectToken
ClickToken ==
    /\ CanSignIn /\ opsStarted < MaxOps
    /\ Idle(cacheLoading, opInFlight, ffInFlight, bgInFlight)
    /\ OffersSignIn(state)
    /\ BeginOp("checkingConnection", "token")
    /\ UNCHANGED <<pulse, cacheLoading, ffInFlight, bgInFlight, cacheLoad, ffWorkers, bgWorkers, retries>>
    /\ Render

\* checkAgain()
ClickCheckAgain ==
    /\ CanCheckAgain /\ opsStarted < MaxOps
    /\ Idle(cacheLoading, opInFlight, ffInFlight, bgInFlight)
    /\ OffersCheckAgain(state)
    /\ BeginOp("checkingConnection", "check")
    /\ UNCHANGED <<pulse, cacheLoading, ffInFlight, bgInFlight, cacheLoad, ffWorkers, bgWorkers, retries>>
    /\ Render

\* disconnect()
ClickDisconnect ==
    /\ CanDisconnect /\ opsStarted < MaxOps
    /\ Idle(cacheLoading, opInFlight, ffInFlight, bgInFlight)
    /\ OffersDisconnect(state)
    /\ BeginOp("disconnecting", "disconnect")
    /\ UNCHANGED <<pulse, cacheLoading, ffInFlight, bgInFlight, cacheLoad, ffWorkers, bgWorkers, retries>>
    /\ Render

\* retryFirstFetch(): accepted only while connected and idle
ClickRetry ==
    /\ CanRetry /\ retries < MaxRetries
    /\ retries' = retries + 1
    /\ Connected(state)
    /\ (Idle(cacheLoading, opInFlight, ffInFlight, bgInFlight) \/ "noRetryGuard" \in Mutations)
    /\ IF pulse # "none"
       THEN /\ StartBg /\ UNCHANGED <<ffInFlight, ffWorkers>>
       ELSE /\ StartFirstFetch /\ UNCHANGED <<bgInFlight, bgWorkers>>
    /\ UNCHANGED <<pulse, opInFlight, attemptID, cacheLoading, ops, cacheLoad, opsStarted>>
    /\ Render

\* finishFirstPortfolioFetch (App) + completeFirstFetch (Core). Success publishes the
\* persisted pulse, then the App asks for the background detail refresh in the same block.
FirstFetchReturns ==
    /\ ffWorkers > 0
    /\ ffWorkers' = ffWorkers - 1
    /\ ffInFlight' = ("keepFirstFetchFlag" \in Mutations)
    /\ \E r \in {"ok", "unavailable"} \cup ConnectionStates :
        CASE r = "ok" ->
                /\ pulse' = "live"
                /\ IF "keepFirstFetchFlag" \in Mutations
                   THEN /\ state' = "current" /\ UNCHANGED <<bgInFlight, bgWorkers>>
                   ELSE /\ bgInFlight' = TRUE /\ bgWorkers' = bgWorkers + 1 /\ state' = "fetching"
          [] r = "unavailable" ->
                /\ UNCHANGED <<pulse, bgInFlight, bgWorkers>> /\ state' = "fetchFailed"
          [] OTHER ->
                /\ UNCHANGED <<pulse, bgInFlight, bgWorkers>> /\ state' = r
    /\ UNCHANGED <<opInFlight, attemptID, cacheLoading, ops, cacheLoad, opsStarted, retries>>
    /\ Render

\* backgroundDetailRefreshProgress: re-renders progress while the refresh runs
BackgroundProgress ==
    /\ bgWorkers > 0 /\ bgInFlight /\ pulse # "none"
    /\ state' = "fetching"
    /\ UNCHANGED <<pulse, opInFlight, attemptID, cacheLoading, ffInFlight, bgInFlight,
                   ops, cacheLoad, ffWorkers, bgWorkers, opsStarted, retries>>
    /\ Render

\* finishBackgroundPortfolioRefresh (App) + completeBackgroundDetailRefresh (Core).
\* A connection failure moves to that connection state and keeps the pulse.
BackgroundReturns ==
    /\ bgWorkers > 0
    /\ bgWorkers' = bgWorkers - 1
    /\ bgInFlight' = FALSE
    /\ \E r \in {"ok", "unavailable"} \cup ConnectionStates :
        CASE r = "ok" -> /\ pulse' = "live" /\ state' = "current"
          [] r = "unavailable" -> /\ UNCHANGED pulse /\ state' = "fetchFailed"
          [] OTHER -> /\ UNCHANGED pulse
                      /\ state' = IF "failureStaysFetching" \in Mutations THEN "fetching" ELSE r
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
    /\ pulse \in {"none", "cached", "live"}
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

\* The user is never stranded: something is running or the menu offers a way forward.
NeverStranded ==
    \/ ops # {} \/ ffWorkers > 0 \/ bgWorkers > 0 \/ cacheLoad = "running"
    \/ CanSignIn \/ CanCheckAgain \/ CanRetry \/ CanDisconnect
=================================================================================
