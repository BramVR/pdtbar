------------------------------ MODULE LaunchRuntime ------------------------------
(*
  PDTBar no-argument (Claude-first) launch: PDTLaunchRuntime plus the AppDelegate
  code that runs its effects on background queues and feeds results back on the
  main queue.

  One TLA+ step = one main-queue block running to completion. Background work
  (readiness probe, cached pulse load, first fetch, background detail refresh,
  login handoff) is modelled as "in flight" bookkeeping whose completion is a
  later main-queue step, so TLC explores every completion order.

  Code anchors (Sources/PDTBarCore/LaunchRuntime.swift = Core, Sources/PDTBarApp/main.swift = App):
    PDTLaunchRuntime ................. Core:1015-1282
    ClaudeLaunchFlow.descriptor ...... Core:364-539 (which buttons a menu shows)
    ClaudeLoginAttemptGate ........... Core:118-146
    AppDelegate effect wiring ........ App:82-384
*)
EXTENDS Naturals, Sequences, FiniteSets

CONSTANTS
    MaxProbes,          \* bound on readiness attempts (readinessAttemptID)
    MaxLogins,          \* bound on login clicks
    MaxRetries,         \* bound on "Try again" / "Refresh now" clicks
    BackgroundAfterFirstFetch, \* FirstFetchConnectorConfiguration.shouldStartBackgroundRefresh (real launches: TRUE)
    Mutations   \* {} for the real code; names replay one-line code breaks (see mutations.sh)

States == {"probingClaude", "loggedOut", "openingClaude", "missingClaude",
           "missingClaudeLogin", "missingPDTMCP", "probeFailed",
           "fetchingPortfolio", "portfolioFetchFailed"}
ProbeResults == {"ready", "notReady", "missingClaudeLogin", "missingPDTMCP", "failed"}
NoPending == [result |-> "none", id |-> 0]

VARIABLES
    \* PDTLaunchRuntime (Core:1016-1022)
    state, pulse, probeInFlight, attemptID, ffInFlight, bgInFlight,
    \* AppDelegate (App:44-56)
    cacheLoadFinished, pending, refreshInFlight, loginNext, loginActive,
    \* last menu installed by installMenuBarItem (what the user sees and can click)
    menu,
    \* background work actually running
    probes,       \* set of readiness attempt IDs whose probe.check() is running (App:131)
    cacheLoad,    \* "running" | "done" (App:106)
    ffWorkers,    \* number of running first-fetch blocks (App:159)
    bgWorkers,    \* number of running PDTBackgroundDetailRefresh blocks (App:257)
    logins,       \* set of login attempt numbers whose handoff is running (App:344)
    retries

vars == <<state, pulse, probeInFlight, attemptID, ffInFlight, bgInFlight,
          cacheLoadFinished, pending, refreshInFlight, loginNext, loginActive,
          menu, probes, cacheLoad, ffWorkers, bgWorkers, logins, retries>>

---------------------------------------------------------------------------------
(* Menu descriptors, abstracted to what the user can click.
   kind: "setup" (setup/login screen, pulse hidden) or "pulse" (pulse visible).
   refresh: "available" (Refresh now / Try again clickable), "inProgress", "none". *)

\* ClaudeLaunchFlow.descriptor(for:cachedPulse:) Core:364-539
Desc(st, p) ==
    IF p # "none" /\ st = "probingClaude"        THEN [kind |-> "pulse", st |-> st, refresh |-> "available"]   \* cached pulse keeps its "Refresh now" row (MenuDescriptorRenderer.swift:277)
    ELSE IF p # "none" /\ st = "fetchingPortfolio" THEN [kind |-> "pulse", st |-> st, refresh |-> "inProgress"] \* .withRefreshAction(.inProgress) Core:394
    ELSE IF p # "none" /\ st = "portfolioFetchFailed" THEN [kind |-> "pulse", st |-> st, refresh |-> "available"] \* descriptorForBackgroundRefreshFailure Core:572
    ELSE IF st = "portfolioFetchFailed"            THEN [kind |-> "setup", st |-> st, refresh |-> "available"]   \* portfolioFetchFailureRows "Try again" Core:943
    ELSE                                                [kind |-> "setup", st |-> st, refresh |-> "none"]

ProgressMenu  == [kind |-> "pulse", st |-> "fetchingPortfolio", refresh |-> "inProgress"]  \* descriptorForBackgroundDetailProgress Core:597
RefreshedMenu == [kind |-> "pulse", st |-> "fetchingPortfolio", refresh |-> "available"]   \* descriptorWithRefreshDetailsAction / Degraded Core:540,3417

\* setupLogin rows: every setup screen except no-pulse fetching (Core:416-539, 4241-4356, 3743)
CanLogin == menu.kind = "setup" /\ menu.st # "fetchingPortfolio"
            /\ ~("noProbeFailedLogin" \in Mutations /\ menu.st = "probeFailed")
\* setupRetry rows: only missingClaudeLogin / missingPDTMCP (Core:1493-1556)
CanCheckAgain == menu.kind = "setup" /\ menu.st \in {"missingClaudeLogin", "missingPDTMCP"}
\* fetchRetry rows ("Try again", "Refresh now", "Fill details again")
CanRetry == menu.refresh = "available"

---------------------------------------------------------------------------------
(* Runtime transitions. Each returns the effect handleLaunchUpdate (App:370) runs. *)

\* PDTLaunchRuntime.update(state:) Core:1254 + installMenuBarItem
Show(st) == /\ state' = st /\ menu' = Desc(st, pulse)   \* callers never change pulse

\* handleLaunchUpdate effects (App:370-384)
StartProbe(id) == probes' = probes \cup {id}
StartFirstFetch == ffWorkers' = ffWorkers + 1
\* startBackgroundPortfolioRefresh (App:257): AppDelegate drops the start when its own flag is set
StartBackground ==
    IF refreshInFlight /\ "noAppDedupe" \notin Mutations THEN UNCHANGED <<refreshInFlight, bgWorkers>>
    ELSE /\ refreshInFlight' = TRUE /\ bgWorkers' = bgWorkers + 1

\* beginReadinessProbe Core:1231
BeginProbe ==
    /\ attemptID' = attemptID + 1
    /\ probeInFlight' = TRUE
    /\ Show("probingClaude")
    /\ StartProbe(attemptID + 1)

\* startBackgroundDetailRefresh Core:1237
StartBg ==
    /\ ffInFlight' = FALSE
    /\ bgInFlight' = TRUE
    /\ state' = "fetchingPortfolio"
    /\ menu' = ProgressMenu
    /\ StartBackground

---------------------------------------------------------------------------------
Init ==
    \* launch(): launchRuntime.launch(cachedPulse: nil), startCachedPulseLoad, startClaudeReadinessProbe (App:82-91)
    /\ state = "probingClaude"
    /\ pulse = "none"
    /\ probeInFlight = TRUE
    /\ attemptID = 1
    /\ ffInFlight = FALSE
    /\ bgInFlight = FALSE
    /\ cacheLoadFinished = FALSE
    /\ pending = NoPending
    /\ refreshInFlight = FALSE
    /\ loginNext = 0
    /\ loginActive = 0
    /\ menu = Desc("probingClaude", "none")
    /\ probes = {1}
    /\ cacheLoad = "running"
    /\ ffWorkers = 0
    /\ bgWorkers = 0
    /\ logins = {}
    /\ retries = 0

\* completeReadinessProbe(_:attemptID:allowsBackgroundDetailRefresh:) Core:1068-1095
CompleteProbe(r, id) ==
    IF ~(probeInFlight /\ id = attemptID) /\ "noAttemptCheck" \notin Mutations
    THEN UNCHANGED <<state, pulse, probeInFlight, attemptID, ffInFlight, bgInFlight, menu,
                     refreshInFlight, bgWorkers, ffWorkers>>          \* stale: currentUpdate()
    ELSE IF r # "ready"
    THEN /\ probeInFlight' = FALSE
         /\ UNCHANGED <<pulse, attemptID, ffInFlight, bgInFlight, refreshInFlight, bgWorkers, ffWorkers>>
         /\ Show(CASE r = "notReady" -> "loggedOut"
                   [] r = "missingClaudeLogin" -> "missingClaudeLogin"
                   [] r = "missingPDTMCP" -> "missingPDTMCP"
                   [] r = "failed" -> "probeFailed")
    ELSE IF ffInFlight \/ bgInFlight
    THEN /\ probeInFlight' = FALSE                                    \* guard returns currentUpdate()
         /\ UNCHANGED <<state, pulse, attemptID, ffInFlight, bgInFlight, menu, refreshInFlight, bgWorkers, ffWorkers>>
    ELSE IF pulse # "none" /\ "ignoreCachedPulse" \notin Mutations          \* allowsBackgroundDetailRefresh (App:1101) is TRUE once a pulse exists
    THEN /\ probeInFlight' = FALSE
         /\ UNCHANGED <<pulse, attemptID, ffWorkers>>
         /\ StartBg
    ELSE /\ probeInFlight' = FALSE
         /\ ffInFlight' = TRUE
         /\ UNCHANGED <<pulse, attemptID, bgInFlight, refreshInFlight, bgWorkers>>
         /\ Show("fetchingPortfolio")
         /\ StartFirstFetch

\* finishClaudeReadinessProbe App:147-157
FinishProbe(r, id) ==
    IF r = "ready" /\ ~cacheLoadFinished /\ "noCacheParking" \notin Mutations
    THEN /\ pending' = [result |-> r, id |-> id]
         /\ UNCHANGED <<state, pulse, probeInFlight, attemptID, ffInFlight, bgInFlight, menu,
                        refreshInFlight, bgWorkers, ffWorkers>>
    ELSE /\ CompleteProbe(r, id)
         /\ UNCHANGED pending

\* probe.check() returns on the main queue (App:136-143)
ProbeReturns ==
    \E id \in probes, r \in ProbeResults :
        /\ probes' = probes \ {id}
        /\ FinishProbe(r, id)
        /\ UNCHANGED <<cacheLoadFinished, loginNext, loginActive, cacheLoad, logins, retries>>

\* startCachedPulseLoad main-queue block App:115-126 + completeCachedPulseLoad Core:1032-1058
CacheLoadReturns ==
    /\ cacheLoad = "running"
    /\ cacheLoad' = "done"
    /\ cacheLoadFinished' = TRUE
    /\ \E hasCache \in BOOLEAN :
         LET installs == hasCache /\ (pulse = "none" \/ pulse = "cached")
             p1 == IF installs THEN "cached" ELSE pulse
             m1 == IF ~installs THEN menu
                   ELSE IF bgInFlight # ("invertCacheLoadRefreshCheck" \in Mutations) THEN ProgressMenu
                   ELSE Desc(state, "cached")
         IN IF pending = NoPending
            THEN /\ pulse' = p1 /\ menu' = m1
                 /\ UNCHANGED <<state, probeInFlight, attemptID, ffInFlight, bgInFlight, pending,
                                refreshInFlight, bgWorkers, ffWorkers, probes>>
            ELSE \* pending ready probe is replayed in the same block, after the pulse is installed
                 LET id == pending.id IN
                 /\ pending' = NoPending
                 /\ IF ~(probeInFlight /\ id = attemptID)
                    THEN /\ pulse' = p1 /\ menu' = m1
                         /\ UNCHANGED <<state, probeInFlight, attemptID, ffInFlight, bgInFlight,
                                        refreshInFlight, bgWorkers, ffWorkers, probes>>
                    ELSE IF ffInFlight \/ bgInFlight
                    THEN /\ pulse' = p1 /\ menu' = m1 /\ probeInFlight' = FALSE
                         /\ UNCHANGED <<state, attemptID, ffInFlight, bgInFlight, refreshInFlight, bgWorkers, ffWorkers, probes>>
                    ELSE IF p1 # "none"
                    THEN /\ pulse' = p1 /\ probeInFlight' = FALSE
                         /\ UNCHANGED <<attemptID, ffWorkers, probes>>
                         /\ StartBg
                    ELSE /\ pulse' = p1 /\ probeInFlight' = FALSE /\ ffInFlight' = TRUE
                         /\ UNCHANGED <<attemptID, bgInFlight, refreshInFlight, bgWorkers, probes>>
                         /\ state' = "fetchingPortfolio" /\ menu' = Desc("fetchingPortfolio", p1)
                         /\ StartFirstFetch
    /\ UNCHANGED <<loginNext, loginActive, logins, retries>>

\* publishPulse Core:1209-1220
Publish(newPulse) ==
    /\ bgInFlight' = FALSE
    /\ pulse' = newPulse
    /\ state' = "fetchingPortfolio"
    /\ menu' = RefreshedMenu

\* finishFirstPortfolioFetch App:196-211 + completeFirstFetch Core:1135-1143
FirstFetchReturns ==
    /\ ffWorkers > 0
    /\ \E ok \in BOOLEAN :
        IF ok
        THEN IF BackgroundAfterFirstFetch
             THEN \* completeFirstFetch(.succeeded) then beginBackgroundDetailRefresh() (Core:1145) in one block
                  /\ pulse' = "live"
                  /\ StartBg
                  /\ ffWorkers' = ffWorkers - 1
             ELSE /\ ffInFlight' = FALSE
                  /\ Publish("live")
                  /\ ffWorkers' = ffWorkers - 1
                  /\ UNCHANGED <<refreshInFlight, bgWorkers>>
        ELSE /\ ffInFlight' = ("keepFirstFetchFlag" \in Mutations)
             /\ ffWorkers' = ffWorkers - 1
             /\ UNCHANGED <<pulse, bgInFlight, refreshInFlight, bgWorkers>>
             /\ Show("portfolioFetchFailed")
    /\ UNCHANGED <<probeInFlight, attemptID, cacheLoadFinished, pending, loginNext, loginActive,
                   probes, cacheLoad, logins, retries>>

\* refresh progress callback App:292-302 + backgroundDetailRefreshProgress Core:1152-1167
BackgroundProgress ==
    /\ bgWorkers > 0
    /\ refreshInFlight /\ bgInFlight /\ pulse # "none"
    /\ state' = "fetchingPortfolio"
    /\ menu' = ProgressMenu
    /\ UNCHANGED <<pulse, probeInFlight, attemptID, ffInFlight, bgInFlight, cacheLoadFinished, pending,
                   refreshInFlight, loginNext, loginActive, probes, cacheLoad, ffWorkers, bgWorkers, logins, retries>>

\* finishBackgroundPortfolioRefresh App:320-335 + completeBackgroundDetailRefresh Core:1169-1207
BackgroundReturns ==
    /\ bgWorkers > 0
    /\ bgWorkers' = bgWorkers - 1
    /\ refreshInFlight' = FALSE
    /\ bgInFlight' = FALSE
    /\ \E ok \in BOOLEAN :
        IF ok
        THEN /\ pulse' = "live" /\ state' = "fetchingPortfolio" /\ menu' = RefreshedMenu
        ELSE /\ UNCHANGED pulse
             /\ Show("portfolioFetchFailed")
    /\ UNCHANGED <<probeInFlight, attemptID, ffInFlight, cacheLoadFinished, pending, loginNext, loginActive,
                   probes, cacheLoad, ffWorkers, logins, retries>>

\* updatePortfolioFetchProgress timer App:232-238 + firstFetchProgress Core:1128-1133
FetchTimerTick ==
    /\ ffInFlight
    /\ Show("fetchingPortfolio")
    /\ UNCHANGED <<pulse, probeInFlight, attemptID, ffInFlight, bgInFlight, cacheLoadFinished, pending,
                   refreshInFlight, loginNext, loginActive, probes, cacheLoad, ffWorkers, bgWorkers, logins, retries>>

\* loginWithClaude click App:344-347 + beginLoginHandoff Core:1097-1100
ClickLogin ==
    /\ CanLogin
    /\ loginNext < MaxLogins
    /\ pending' = NoPending
    /\ loginNext' = loginNext + 1
    /\ loginActive' = loginNext + 1
    /\ logins' = logins \cup {loginNext + 1}
    /\ probeInFlight' = FALSE
    /\ Show("openingClaude")
    /\ UNCHANGED <<pulse, attemptID, ffInFlight, bgInFlight, cacheLoadFinished, refreshInFlight,
                   probes, cacheLoad, ffWorkers, bgWorkers, retries>>

\* login completion App:348-367, ClaudeLoginAttemptGate.finish Core:135 + completeLoginHandoff Core:1102-1115
LoginReturns ==
    \E a \in logins, ok \in BOOLEAN :
        /\ logins' = logins \ {a}
        /\ IF a # loginActive
           THEN UNCHANGED <<state, pulse, probeInFlight, attemptID, ffInFlight, bgInFlight, menu, loginActive, probes>>
           ELSE /\ loginActive' = 0
                /\ IF ok
                   THEN /\ UNCHANGED <<pulse, ffInFlight, bgInFlight>> /\ BeginProbe
                   ELSE /\ UNCHANGED <<pulse, probeInFlight, attemptID, ffInFlight, bgInFlight, probes>>
                        /\ state' = "missingClaude"
                        /\ menu' = [kind |-> "setup", st |-> "missingClaude", refresh |-> "none"]  \* descriptor(forLoginFailure:) Core:647
        /\ UNCHANGED <<cacheLoadFinished, pending, refreshInFlight, loginNext, cacheLoad, ffWorkers, bgWorkers, retries>>

\* retryClaudeReadiness click App:337-342 + retryReadiness Core:1061-1066
ClickCheckAgain ==
    /\ CanCheckAgain
    /\ ~probeInFlight
    /\ attemptID < MaxProbes
    /\ UNCHANGED <<pulse, ffInFlight, bgInFlight>>
    /\ BeginProbe
    /\ UNCHANGED <<cacheLoadFinished, pending, refreshInFlight, loginNext, loginActive, cacheLoad,
                   ffWorkers, bgWorkers, logins, retries>>

\* retryPortfolioFetch click App:250-255 + retryFirstFetch Core:1117-1126
ClickRetry ==
    /\ CanRetry
    /\ retries < MaxRetries
    /\ retries' = retries + 1
    /\ ("noRetryGuard" \in Mutations \/ (~ffInFlight /\ ~bgInFlight))
    /\ IF pulse # "none"
       THEN /\ UNCHANGED <<ffWorkers>> /\ StartBg
       ELSE /\ ffInFlight' = TRUE
            /\ UNCHANGED <<bgInFlight, refreshInFlight, bgWorkers>>
            /\ Show("fetchingPortfolio")
            /\ StartFirstFetch
    /\ UNCHANGED <<pulse, probeInFlight, attemptID, cacheLoadFinished, pending, loginNext, loginActive,
                   probes, cacheLoad, logins>>

\* markPulseItemRead click App:1031-1054: pulse rows carry "Mark as read"; the
\* republish goes through publishPulse Core:1209, whatever else is running.
ClickMarkRead ==
    /\ menu.kind = "pulse"
    /\ pulse # "none"
    /\ Publish(pulse)
    /\ UNCHANGED <<probeInFlight, attemptID, ffInFlight, cacheLoadFinished, pending, refreshInFlight,
                   loginNext, loginActive, probes, cacheLoad, ffWorkers, bgWorkers, logins, retries>>

Next ==
    \/ ClickMarkRead
    \/ ProbeReturns
    \/ CacheLoadReturns
    \/ FirstFetchReturns
    \/ BackgroundProgress
    \/ BackgroundReturns
    \/ FetchTimerTick
    \/ ClickLogin
    \/ LoginReturns
    \/ ClickCheckAgain
    \/ ClickRetry

Spec == Init /\ [][Next]_vars

\* Keeps the state space finite: probes spawned by login success also count.
Bounded == attemptID <= MaxProbes + MaxLogins

---------------------------------------------------------------------------------
(* Properties *)

TypeOK ==
    /\ state \in States
    /\ pulse \in {"none", "cached", "live"}
    /\ ffWorkers \in 0..3 /\ bgWorkers \in 0..3

\* At most one portfolio fetch of any kind runs at once (two would race on the
\* same SnapshotStore / PulseReadStore files).
OneFetchAtATime == ffWorkers + bgWorkers <= 1

\* The runtime's in-flight flags describe real work. A flag left TRUE with no
\* worker blocks every retry and leaves the progress UI up forever.
FirstFetchFlagMatchesWork == ffInFlight <=> ffWorkers > 0

\* Same promise for the background refresh. Also keeps progress rows coming
\* (backgroundDetailRefreshProgress drops updates once the flag is FALSE) and
\* keeps "Refresh now" hidden while a refresh runs.
BackgroundFlagMatchesWork == bgInFlight <=> bgWorkers > 0

\* A returning user with a cached pulse never pays for a full first fetch.
NoFullFetchOverCache == ffInFlight => pulse = "none"

\* What the menu says is happening is happening.
\*  "Checking Claude setup" => a probe is running (or parked waiting for the cache load).
\*  "Refreshing ..." / spinner => a fetch is running.
ProbingMenuTellsTruth ==
    menu.st = "probingClaude" => (probeInFlight /\ (attemptID \in probes \/ pending.id = attemptID))

FetchingMenuTellsTruth ==
    (menu.refresh = "inProgress" \/ (menu.kind = "setup" /\ menu.st = "fetchingPortfolio"))
        => (ffWorkers + bgWorkers > 0)

\* Setup screens are only shown when no portfolio fetch is running behind them
\* (otherwise its progress callbacks flip the menu back and forth).
SetupMenuMeansIdle ==
    (menu.kind = "setup" /\ menu.st \notin {"fetchingPortfolio", "portfolioFetchFailed"})
        => bgWorkers = 0

MenuTellsTruth == ProbingMenuTellsTruth /\ FetchingMenuTellsTruth /\ SetupMenuMeansIdle

\* While the runtime waits for readiness attempt N (probeInFlight), N's result is
\* still on its way: its probe is running or its ready result is parked until the
\* cached pulse loads (App:148-150). A lost result leaves "Checking Claude" up forever.
ProbeResultNotLost == probeInFlight => (attemptID \in probes \/ pending.id = attemptID)

\* A setup screen that reports a probe result is never contradicted by a newer
\* probe that is still running (a late, superseded probe must not overwrite it).
SetupReflectsLatestProbe ==
    (menu.kind = "setup" /\ menu.st \in {"loggedOut", "missingClaudeLogin", "missingPDTMCP", "probeFailed"})
        => attemptID \notin probes

\* The user is never stranded: either something is running or the menu offers a way forward.
NeverStranded ==
    \/ probes # {} \/ ffWorkers > 0 \/ bgWorkers > 0 \/ logins # {} \/ cacheLoad = "running"
    \/ CanLogin \/ CanCheckAgain \/ CanRetry
=================================================================================
