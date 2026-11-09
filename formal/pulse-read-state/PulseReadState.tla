---------------------------- MODULE PulseReadState ----------------------------
(***************************************************************************)
(* Pulse read state across the main thread and the refresh worker.         *)
(*                                                                         *)
(* The user marks attention rows read on the main thread                   *)
(* (markPulseItemRead). A first fetch or background detail refresh runs    *)
(* PressureRunner on a global queue against the same pulse-read-state.json *)
(* and latest-portfolio-snapshot.json, resets read marks for re-crossed    *)
(* concentration items, prunes stale income/big-mover marks, and hands a   *)
(* PulseLifecycleResult back to the main thread.                           *)
(*                                                                         *)
(* Abstraction. One income/big-mover row ("inc") whose fingerprint is its  *)
(* value, and one concentration row ("conc") that is below the threshold  *)
(* or above it in one of two weight buckets. Fingerprints are the values.  *)
(* File writes are atomic (OwnerOnlyLocalStore.write renames a temp file,  *)
(* PDTBarCore.swift:781). Code paths are Swift file:line at commit 032058b.*)
(***************************************************************************)
EXTENDS FiniteSets

CONSTANTS
    \* TRUE models a fix: finishBackgroundPortfolioRefresh re-reads the store
    \* before publishing, as finishFirstPortfolioFetch already does.
    ReapplyOnBgPublish,
    \* TRUE models a fix: the re-crossing reset runs before the snapshot that
    \* records the crossing is committed.
    ResetBeforeSnapshotCommit,
    \* TRUE is current code: PulseReadStore.markRead runs its load and save
    \* inside PulseReadStore.mutationQueue (PDTBarCore.swift:675, 693).
    MarkReadSerialized

ASSUME ReapplyOnBgPublish \in BOOLEAN
ASSUME ResetBeforeSnapshotCommit \in BOOLEAN
ASSUME MarkReadSerialized \in BOOLEAN

IncVals  == {"none", "i1", "i2"}
ConcVals == {"below", "c1", "c2"}
IncFps   == {"i1", "i2"}
ConcFps  == {"c1", "c2"}
FP       == IncFps \cup ConcFps

Snapshots == [inc : IncVals, conc : ConcVals]
NoSnap    == [inc |-> "none", conc |-> "noSnapshot"]
SnapVals  == Snapshots \cup {NoSnap}

Displays  == [shown : BOOLEAN, inc : IncVals, conc : ConcFps \cup {"none"}, read : SUBSET FP]
NoDisplay == [shown |-> FALSE, inc |-> "none", conc |-> "none", read |-> {}]

WorkerPcs == {"idle",
              "ffLoad", "ffEarlyReset", "ffCommit", "ffReset", "ffReady",
              "bgLoadPrior", "bgEarlyReset", "bgBaseCommit", "bgDetails",
              "bgReset", "bgReady"}

\* Worker states after the crossing snapshot is on disk and before the reset.
AwaitingReset == {"ffReset", "bgDetails", "bgReset"}

VARIABLES
    pdt,        \* portfolio values PDT would return now
    snap,       \* latest-portfolio-snapshot.json (SnapshotStore)
    store,      \* pulse-read-state.json readFingerprints (PulseReadStore)
    display,    \* PDTLaunchRuntime.currentPulse as shown in the menu
    wPc,        \* refresh worker program counter
    wPrior,     \* worker: prior snapshot it loaded
    wNew,       \* worker: snapshot it fetched
    wLoaded,    \* worker: displayReadState it loaded
    wRead,      \* worker: PulseLifecycleResult.readState it will hand back
    mainPc,     \* main thread inside markPulseItemRead
    mainFp,     \* main: fingerprint being marked
    mainLoaded, \* main: store loaded by an unserialized markRead
    intended,   \* ghost: store if every read-state write applied atomically
    owed        \* ghost: conc fingerprint whose re-crossing reset is still owed

vars == <<pdt, snap, store, display, wPc, wPrior, wNew, wLoaded, wRead,
          mainPc, mainFp, mainLoaded, intended, owed>>

-----------------------------------------------------------------------------
(* Pure pressure-engine helpers.                                           *)

\* PressureEngine.concentrationItems, PDTBarCore.swift:5608.
ConcItem(s, p, r) ==
    IF s.conc = "below" THEN "none"
    ELSE IF p = NoSnap THEN s.conc
    ELSE IF p.conc = "below" THEN s.conc
    ELSE IF \E f \in r \cap ConcFps : f # s.conc THEN s.conc
    ELSE "none"

\* freshItem.resetsReadState = true, PDTBarCore.swift:5631.
Resets(s, p) == s.conc \in ConcFps /\ p # NoSnap /\ p.conc = "below"

Reappeared(s, p) == IF Resets(s, p) THEN {s.conc} ELSE {}

\* PressureRunner.staleReadFingerprints, PDTBarCore.swift:8437.
Stale(s, loaded) ==
    IF s.inc = "none" THEN {} ELSE {f \in loaded \cap IncFps : f # s.inc}

ToRemove(s, p, loaded) == Reappeared(s, p) \cup Stale(s, loaded)

Pulse(s, p, r, read) ==
    [shown |-> TRUE, inc |-> s.inc, conc |-> ConcItem(s, p, r), read |-> read]

\* PressureRunner.cachedPulse, PDTBarCore.swift:8188: no prior, no reset.
CachedDisplay ==
    IF snap = NoSnap THEN NoDisplay ELSE Pulse(snap, NoSnap, store, store)

DisplayedFps(d) == ({d.inc} \cap IncFps) \cup ({d.conc} \cap ConcFps)
UnreadShown(d)  == {f \in DisplayedFps(d) : f \notin d.read}

\* Worker and main-thread locals go back to defaults when their work ends,
\* so finished work does not multiply states.
ClearWorker ==
    /\ wPc' = "idle"
    /\ wPrior' = NoSnap
    /\ wNew' = NoSnap
    /\ wLoaded' = {}
    /\ wRead' = {}

ClearMain ==
    /\ mainPc' = "idle"
    /\ mainFp' = "i1"
    /\ mainLoaded' = {}

-----------------------------------------------------------------------------
Init ==
    /\ pdt \in Snapshots
    /\ snap \in SnapVals
    /\ store \in SUBSET FP
    /\ intended = store
    \* AppDelegate.startCachedPulseLoad, main.swift:102. Refreshes wait for it.
    /\ display = CachedDisplay
    /\ wPc = "idle"
    /\ wPrior = NoSnap
    /\ wNew = NoSnap
    /\ wLoaded = {}
    /\ wRead = {}
    /\ mainPc = "idle"
    /\ mainFp = "i1"
    /\ mainLoaded = {}
    /\ owed = "none"

\* The user's portfolio moves on the PDT side.
PdtChanges ==
    /\ pdt' \in Snapshots \ {pdt}
    /\ UNCHANGED <<snap, store, display, wPc, wPrior, wNew, wLoaded, wRead,
                   mainPc, mainFp, mainLoaded, intended, owed>>

-----------------------------------------------------------------------------
(* Main thread: markPulseItemRead, main.swift:1022.                        *)

\* main.swift:1029 try readStore.markRead(fingerprint), with
\* PulseReadStore.markRead, PDTBarCore.swift:693, under mutationQueue.
MarkRead(f) ==
    /\ MarkReadSerialized
    /\ mainPc = "idle"
    /\ display.shown
    /\ f \in UnreadShown(display)
    /\ store' = store \cup {f}
    /\ intended' = intended \cup {f}
    /\ mainPc' = "reloading"
    /\ mainFp' = f
    /\ UNCHANGED <<pdt, snap, display, wPc, wPrior, wNew, wLoaded, wRead,
                   mainLoaded, owed>>

\* Broken variant: PulseReadStore.markRead load step (PDTBarCore.swift:695)
\* outside mutationQueue.
MarkReadLoad(f) ==
    /\ ~MarkReadSerialized
    /\ mainPc = "idle"
    /\ display.shown
    /\ f \in UnreadShown(display)
    /\ mainLoaded' = store
    /\ mainFp' = f
    /\ mainPc' = "saving"
    /\ UNCHANGED <<pdt, snap, store, display, wPc, wPrior, wNew, wLoaded,
                   wRead, intended, owed>>

\* Broken variant: PulseReadStore.markRead save step (PDTBarCore.swift:700)
\* outside mutationQueue.
MarkReadSave ==
    /\ mainPc = "saving"
    /\ store' = mainLoaded \cup {mainFp}
    /\ intended' = intended \cup {mainFp}
    /\ mainPc' = "reloading"
    /\ UNCHANGED <<pdt, snap, display, wPc, wPrior, wNew, wLoaded, wRead,
                   mainFp, mainLoaded, owed>>

\* main.swift:1031-1032 currentPulse.applyingReadState(readStore.load()) and
\* PDTLaunchRuntime.publishPulse, PDTBarCore.swift:4009.
MarkReadReload ==
    /\ mainPc = "reloading"
    /\ display' = [display EXCEPT !.read = store]
    /\ ClearMain
    /\ UNCHANGED <<pdt, snap, store, wPc, wPrior, wNew, wLoaded, wRead,
                   intended, owed>>

-----------------------------------------------------------------------------
(* Shared worker steps.                                                    *)

\* PulseReadStore.removeReadFingerprints, PDTBarCore.swift:704, called from
\* PressureRunner.readStateAfterResettingReappearedItems, PDTBarCore.swift:8414.
\* With nothing to remove the result keeps the loaded state (8431-8433).
ResetEffect(to) ==
    /\ LET rm == ToRemove(wNew, wPrior, wLoaded) IN
         IF rm = {}
         THEN /\ wRead' = wLoaded
              /\ UNCHANGED <<store, intended>>
         ELSE /\ store' = store \ rm
              /\ intended' = intended \ rm
              /\ wRead' = store \ rm
    /\ owed' = "none"
    /\ wPc' = to
    /\ UNCHANGED <<pdt, snap, display, wPrior, wNew, wLoaded, mainPc, mainFp,
                   mainLoaded>>

\* Fixed variant only: drop the re-crossed mark before the snapshot that
\* records the crossing reaches disk.
EarlyResetEffect(to) ==
    /\ store' = store \ Reappeared(wNew, wPrior)
    /\ intended' = intended \ Reappeared(wNew, wPrior)
    /\ wPc' = to
    /\ UNCHANGED <<pdt, snap, display, wPrior, wNew, wLoaded, wRead, mainPc,
                   mainFp, mainLoaded, owed>>

\* SnapshotStore.commitCurrentSnapshot, PDTBarCore.swift:8507.
CommitEffect(to) ==
    /\ snap' = wNew
    /\ owed' = IF Resets(wNew, wPrior) /\ ~ResetBeforeSnapshotCommit
               THEN wNew.conc ELSE owed
    /\ wPc' = to
    /\ UNCHANGED <<pdt, store, display, wPrior, wNew, wLoaded, wRead, mainPc,
                   mainFp, mainLoaded, intended>>

-----------------------------------------------------------------------------
(* First fetch: startFirstPortfolioFetch, main.swift:162, running          *)
(* PDTCoalescedFirstPortfolioFetch.fetch, PDTBarCore.swift:6790, which     *)
(* runs PressureRunner.run, PDTBarCore.swift:8256.                         *)

\* main.swift:162 startFirstPortfolioFetch, effect of
\* PDTLaunchRuntime.completeReadinessProbe, PDTBarCore.swift:3868, when no
\* pulse is shown.
FirstFetchStart ==
    /\ wPc = "idle"
    /\ mainPc = "idle"
    /\ ~display.shown
    /\ wPc' = "ffLoad"
    /\ UNCHANGED <<pdt, snap, store, display, wPrior, wNew, wLoaded, wRead,
                   mainPc, mainFp, mainLoaded, intended, owed>>

\* PressureRunner.run, PDTBarCore.swift:8257-8274: fetch, load prior,
\* displayReadState.
FirstFetchLoad ==
    /\ wPc = "ffLoad"
    /\ wNew' = pdt
    /\ wPrior' = snap
    /\ wLoaded' = store
    /\ wPc' = IF ResetBeforeSnapshotCommit THEN "ffEarlyReset" ELSE "ffCommit"
    /\ UNCHANGED <<pdt, snap, store, display, wRead, mainPc, mainFp,
                   mainLoaded, intended, owed>>

FirstFetchEarlyReset ==
    /\ wPc = "ffEarlyReset"
    /\ EarlyResetEffect("ffCommit")

\* PressureRunner.run, PDTBarCore.swift:8275 commitCurrentSnapshot.
FirstFetchCommit ==
    /\ wPc = "ffCommit"
    /\ CommitEffect("ffReset")

\* PressureRunner.lifecycleResult, PDTBarCore.swift:8353, reset branch.
FirstFetchReset ==
    /\ wPc = "ffReset"
    /\ ResetEffect("ffReady")

\* main.swift:202 finishFirstPortfolioFetch: pulseApplyingCurrentReadState
\* (main.swift:438) re-reads the store, then completeFirstFetch.
FirstFetchPublish ==
    /\ wPc = "ffReady"
    /\ mainPc = "idle"
    /\ display' = Pulse(wNew, wPrior, wLoaded, store)
    /\ ClearWorker
    /\ UNCHANGED <<pdt, snap, store, mainPc, mainFp, mainLoaded, intended, owed>>

-----------------------------------------------------------------------------
(* Background detail refresh: startBackgroundPortfolioRefresh,             *)
(* main.swift:263, running PDTBackgroundDetailRefresh.refresh,             *)
(* PDTBarCore.swift:7089.                                                  *)

\* main.swift:263 startBackgroundPortfolioRefresh, from completeReadinessProbe
\* (PDTBarCore.swift:3868), retryFirstFetch (3917), or the refresh action.
BgStart ==
    /\ wPc = "idle"
    /\ mainPc = "idle"
    /\ display.shown
    /\ wPc' = "bgLoadPrior"
    /\ UNCHANGED <<pdt, snap, store, display, wPrior, wNew, wLoaded, wRead,
                   mainPc, mainFp, mainLoaded, intended, owed>>

\* PDTBackgroundDetailRefresh.refresh, PDTBarCore.swift:7113-7125:
\* originalPriorSnapshot, then baseSnapshot.
BgLoadPrior ==
    /\ wPc = "bgLoadPrior"
    /\ wPrior' = snap
    /\ wNew' = pdt
    /\ wPc' = IF ResetBeforeSnapshotCommit THEN "bgEarlyReset" ELSE "bgBaseCommit"
    /\ UNCHANGED <<pdt, snap, store, display, wLoaded, wRead, mainPc, mainFp,
                   mainLoaded, intended, owed>>

BgEarlyReset ==
    /\ wPc = "bgEarlyReset"
    /\ EarlyResetEffect("bgBaseCommit")

\* PDTBackgroundDetailRefresh.refresh, PDTBarCore.swift:7126: base-holdings
\* commit. The allocation/xRay/income/performance phase commits
\* (7158, 7168, 7188, 7225) rewrite the same holdings and are folded into
\* bgDetails.
BgBaseCommit ==
    /\ wPc = "bgBaseCommit"
    /\ CommitEffect("bgDetails")

\* PressureRunner.refreshedPulse, PDTBarCore.swift:8306 displayReadState and
\* 8314 commitCurrentSnapshot of the same holdings.
BgLoadReadState ==
    /\ wPc = "bgDetails"
    /\ wLoaded' = store
    /\ snap' = wNew
    /\ wPc' = "bgReset"
    /\ UNCHANGED <<pdt, store, display, wPrior, wNew, wRead, mainPc, mainFp,
                   mainLoaded, intended, owed>>

\* PressureRunner.lifecycleResult, PDTBarCore.swift:8353, reset branch.
BgReset ==
    /\ wPc = "bgReset"
    /\ ResetEffect("bgReady")

\* main.swift:318 finishBackgroundPortfolioRefresh and
\* PDTLaunchRuntime.completeBackgroundDetailRefresh, PDTBarCore.swift:3969:
\* currentPulse = pulse with the worker's readState.
BgPublish ==
    /\ wPc = "bgReady"
    /\ mainPc = "idle"
    /\ display' = Pulse(wNew, wPrior, wLoaded,
                        IF ReapplyOnBgPublish THEN store ELSE wRead)
    /\ ClearWorker
    /\ UNCHANGED <<pdt, snap, store, mainPc, mainFp, mainLoaded, intended, owed>>

-----------------------------------------------------------------------------
\* The app quits or crashes at any point and launches again. In-flight work
\* is lost; files stay. AppDelegate.launch, main.swift:78, then
\* startCachedPulseLoad, main.swift:102.
Relaunch ==
    /\ ClearWorker
    /\ ClearMain
    /\ display' = CachedDisplay
    /\ UNCHANGED <<pdt, snap, store, intended, owed>>

Next ==
    \/ PdtChanges
    \/ \E f \in FP : MarkRead(f) \/ MarkReadLoad(f)
    \/ MarkReadSave
    \/ MarkReadReload
    \/ FirstFetchStart \/ FirstFetchLoad \/ FirstFetchEarlyReset
    \/ FirstFetchCommit \/ FirstFetchReset \/ FirstFetchPublish
    \/ BgStart \/ BgLoadPrior \/ BgEarlyReset \/ BgBaseCommit
    \/ BgLoadReadState \/ BgReset \/ BgPublish
    \/ Relaunch

Spec == Init /\ [][Next]_vars

-----------------------------------------------------------------------------
(* Properties.                                                             *)

TypeOK ==
    /\ pdt \in Snapshots
    /\ snap \in SnapVals
    /\ store \in SUBSET FP
    /\ intended \in SUBSET FP
    /\ display \in Displays
    /\ wPc \in WorkerPcs
    /\ wPrior \in SnapVals
    /\ wNew \in SnapVals
    /\ wLoaded \in SUBSET FP
    /\ wRead \in SUBSET FP
    /\ mainPc \in {"idle", "saving", "reloading"}
    /\ mainFp \in FP
    /\ mainLoaded \in SUBSET FP
    /\ owed \in ConcFps \cup {"none"}

\* No read-state write is lost: the file always equals the result of applying
\* every markRead and reset in the order they wrote.
NoLostReadStateUpdate == store = intended

\* Once nothing is in flight, a row shows read exactly when the store says so.
DisplayMatchesStoreWhenIdle ==
    (wPc = "idle" /\ mainPc = "idle" /\ display.shown) =>
        \A f \in DisplayedFps(display) : (f \in display.read) <=> (f \in store)

\* If a committed snapshot records a concentration re-crossing whose old read
\* mark is still stored, a running worker still owes the reset.
ReadMarkClearedOnRecrossing ==
    (owed # "none" /\ owed \in store) => wPc \in AwaitingReset

=============================================================================
