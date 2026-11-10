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
(* Persistence.swift:126). Paths are Swift file:line at commit 1b6ffd4,    *)
(* under Sources/PDTBarCore/ unless they say main.swift (PDTBarApp). The   *)
(* mark-read and publish actions cite the code after the #268/#269 fix,   *)
(* the commit and reset actions the code after the #270 fix.              *)
(***************************************************************************)
EXTENDS FiniteSets

CONSTANTS
    \* TRUE is current code (#269): every pulse PDTLaunchRuntime shows goes
    \* through DisplayedPulse.show (LaunchRuntime.swift:1033), which re-reads
    \* the store, the background refresh result included. FALSE replays the
    \* code before #269, which published the worker's read state.
    ReapplyOnBgPublish,
    \* TRUE is current code (#270): SnapshotStore.commitCurrentSnapshot
    \* (Persistence.swift:660) removes the read marks of items that re-cross
    \* against the snapshot on disk (664), then writes the snapshot (668). The
    \* reset after the commit only prunes stale marks (569). FALSE replays the
    \* code before #270, which reset re-crossed marks after the commit.
    ResetBeforeSnapshotCommit,
    \* TRUE is current code: PulseReadStore.markRead runs its load and save
    \* inside PulseReadStore.mutationQueue (Persistence.swift:20, 38).
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

\* PressureEngine.concentrationItems, PressureEngine.swift:210.
ConcItem(s, p, r) ==
    IF s.conc = "below" THEN "none"
    ELSE IF p = NoSnap THEN s.conc
    ELSE IF p.conc = "below" THEN s.conc
    ELSE IF \E f \in r \cap ConcFps : f # s.conc THEN s.conc
    ELSE "none"

\* freshItem.resetsReadState = true, PressureEngine.swift:233.
Resets(s, p) == s.conc \in ConcFps /\ p # NoSnap /\ p.conc = "below"

Reappeared(s, p) == IF Resets(s, p) THEN {s.conc} ELSE {}

\* PressureRunner.staleReadFingerprints, Persistence.swift:586.
Stale(s, loaded) ==
    IF s.inc = "none" THEN {} ELSE {f \in loaded \cap IncFps : f # s.inc}

\* What the reset after the commit removes. Since #270 the re-crossed marks
\* are already gone by then, so only stale marks remain.
ToRemove(s, p, loaded) ==
    IF ResetBeforeSnapshotCommit THEN Stale(s, loaded)
    ELSE Reappeared(s, p) \cup Stale(s, loaded)

Pulse(s, p, r, read) ==
    [shown |-> TRUE, inc |-> s.inc, conc |-> ConcItem(s, p, r), read |-> read]

\* PressureRunner.cachedPulse, Persistence.swift:343: no prior, no reset (366).
\* The runtime installs it through DisplayedPulse.show (LaunchRuntime.swift:1033),
\* which joins the store again on the main thread.
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
    \* AppDelegate.startCachedPulseLoad, main.swift:106. Refreshes wait for it.
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
(* Main thread: markPulseItemRead, main.swift:1031.                        *)

\* main.swift:1038 try readStore.markRead(fingerprint), with
\* PulseReadStore.markRead, Persistence.swift:38, under mutationQueue. The
\* menu row resolves its fingerprint from currentPulse.unfilteredModel by
\* attention ID when the menu is built (main.swift:573), so f is a shown row.
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

\* Broken variant: PulseReadStore.markRead load step (Persistence.swift:40)
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

\* Broken variant: PulseReadStore.markRead save step (Persistence.swift:45)
\* outside mutationQueue.
MarkReadSave ==
    /\ mainPc = "saving"
    /\ store' = mainLoaded \cup {mainFp}
    /\ intended' = intended \cup {mainFp}
    /\ mainPc' = "reloading"
    /\ UNCHANGED <<pdt, snap, display, wPc, wPrior, wNew, wLoaded, wRead,
                   mainFp, mainLoaded, owed>>

\* main.swift:1027 PDTLaunchRuntime.pulseReadStateDidChange,
\* LaunchRuntime.swift:1245, which applies readStore.load() through
\* DisplayedPulse.show (1033).
MarkReadReload ==
    /\ mainPc = "reloading"
    /\ display' = [display EXCEPT !.read = store]
    /\ ClearMain
    /\ UNCHANGED <<pdt, snap, store, wPc, wPrior, wNew, wLoaded, wRead,
                   intended, owed>>

-----------------------------------------------------------------------------
(* Shared worker steps.                                                    *)

\* PulseReadStore.removeReadFingerprints, Persistence.swift:49, called from
\* PressureRunner.readStateAfterPruningStaleItems, Persistence.swift:569
\* (readStateAfterResettingReappearedItems before #270). With nothing to
\* remove the result keeps the loaded state.
ResetEffect(to) ==
    /\ LET rm == ToRemove(wNew, wPrior, wLoaded) IN
         IF rm = {}
         THEN /\ wRead' = wLoaded
              /\ UNCHANGED <<store, intended>>
         ELSE /\ store' = store \ rm
              /\ intended' = intended \ rm
              /\ wRead' = store \ rm
    \* The owed reset is paid only once its mark is actually gone.
    /\ owed' = IF owed \in store' THEN owed ELSE "none"
    /\ wPc' = to
    /\ UNCHANGED <<pdt, snap, display, wPrior, wNew, wLoaded, mainPc, mainFp,
                   mainLoaded>>

\* SnapshotStore.commitCurrentSnapshot, Persistence.swift:661-666: drop the
\* marks of items that re-cross against the snapshot on disk, in one
\* removeReadFingerprints write, before the snapshot write (668). Only the
\* running worker writes the snapshot, so snap here is the prior it loaded.
EarlyResetEffect(to) ==
    /\ store' = store \ Reappeared(wNew, snap)
    /\ intended' = intended \ Reappeared(wNew, snap)
    /\ wPc' = to
    /\ UNCHANGED <<pdt, snap, display, wPrior, wNew, wLoaded, wRead, mainPc,
                   mainFp, mainLoaded, owed>>

\* SnapshotStore.commitCurrentSnapshot, Persistence.swift:668 snapshot write.
CommitEffect(to) ==
    /\ snap' = wNew
    \* A reset is owed when this write records a crossing against the
    \* snapshot on disk while the crossing's old mark is still stored.
    /\ owed' = IF Resets(wNew, snap) /\ wNew.conc \in store
               THEN wNew.conc ELSE owed
    /\ wPc' = to
    /\ UNCHANGED <<pdt, store, display, wPrior, wNew, wLoaded, wRead, mainPc,
                   mainFp, mainLoaded, intended>>

-----------------------------------------------------------------------------
(* First fetch: startFirstPortfolioFetch, main.swift:159, running          *)
(* PDTCoalescedFirstPortfolioFetch.fetch, PDTLiveDataSource.swift:416,     *)
(* which runs PressureRunner.run, Persistence.swift:411. It takes no       *)
(* cancellation.                                                           *)

\* main.swift:159 startFirstPortfolioFetch, effect of
\* PDTLaunchRuntime.completeReadinessProbe, LaunchRuntime.swift:1068, when no
\* pulse is shown.
FirstFetchStart ==
    /\ wPc = "idle"
    /\ mainPc = "idle"
    /\ ~display.shown
    /\ wPc' = "ffLoad"
    /\ UNCHANGED <<pdt, snap, store, display, wPrior, wNew, wLoaded, wRead,
                   mainPc, mainFp, mainLoaded, intended, owed>>

\* PressureRunner.run, Persistence.swift:417-428: fetch, load prior. Since
\* #270 displayReadState loads after the commit (430). Only the publish and
\* the changed-bucket check read it, and the publish re-reads the store, so
\* loading it here keeps the model smaller without changing any property.
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

\* PressureRunner.run, Persistence.swift:429 commitCurrentSnapshot.
FirstFetchCommit ==
    /\ wPc = "ffCommit"
    /\ CommitEffect("ffReset")

\* PressureRunner.lifecycleResult, Persistence.swift:508, reset branch.
FirstFetchReset ==
    /\ wPc = "ffReset"
    /\ ResetEffect("ffReady")

\* main.swift:184 finishFirstPortfolioFetch, then completeFirstFetch
\* (LaunchRuntime.swift:1193), whose DisplayedPulse.show (1033) re-reads the store.
FirstFetchPublish ==
    /\ wPc = "ffReady"
    /\ mainPc = "idle"
    /\ display' = Pulse(wNew, wPrior, wLoaded, store)
    /\ ClearWorker
    /\ UNCHANGED <<pdt, snap, store, mainPc, mainFp, mainLoaded, intended, owed>>

-----------------------------------------------------------------------------
(* Background detail refresh: startBackgroundPortfolioRefresh,             *)
(* main.swift:257, running PDTBackgroundDetailRefresh.refresh,             *)
(* PDTBackgroundDetailRefresh.swift:166, with a PDTCancellation that only  *)
(* applicationWillTerminate cancels (main.swift:1117). A cancelled refresh *)
(* throws at its next throwIfCancelled check and touches no file after     *)
(* that, so cancellation is one way the worker stops: see Relaunch.        *)

\* main.swift:257 startBackgroundPortfolioRefresh, from completeReadinessProbe
\* (LaunchRuntime.swift:1068), retryFirstFetch (1117), or the refresh action.
BgStart ==
    /\ wPc = "idle"
    /\ mainPc = "idle"
    /\ display.shown
    /\ wPc' = "bgLoadPrior"
    /\ UNCHANGED <<pdt, snap, store, display, wPrior, wNew, wLoaded, wRead,
                   mainPc, mainFp, mainLoaded, intended, owed>>

\* PDTBackgroundDetailRefresh.refresh, PDTBackgroundDetailRefresh.swift:198
\* originalPriorSnapshot, then 202 baseSnapshot. Only this worker writes the
\* snapshot while it runs, so the prior cannot change between the two.
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

\* PDTBackgroundDetailRefresh.swift:232 base-holdings commit. The
\* allocation/xRay/income/performance phase commits (271, 295, 329, 386)
\* rewrite the same holdings against the base already on disk, so their
\* early reset finds no crossing. They are folded into bgDetails, as are
\* the throwIfCancelled checks between them (256-410).
BgBaseCommit ==
    /\ wPc = "bgBaseCommit"
    /\ CommitEffect("bgDetails")

\* PDTBackgroundDetailRefresh.swift:413 calls PressureRunner.refreshedPulse,
\* Persistence.swift:468 commitCurrentSnapshot of the same holdings, whose
\* early reset finds no crossing against the base on disk, then 469
\* displayReadState. No cancellation check runs from here to the return.
BgLoadReadState ==
    /\ wPc = "bgDetails"
    /\ wLoaded' = store
    /\ snap' = wNew
    /\ wPc' = "bgReset"
    /\ UNCHANGED <<pdt, store, display, wPrior, wNew, wRead, mainPc, mainFp,
                   mainLoaded, intended, owed>>

\* PressureRunner.lifecycleResult, Persistence.swift:508, reset branch.
BgReset ==
    /\ wPc = "bgReset"
    /\ ResetEffect("bgReady")

\* main.swift:301 finishBackgroundPortfolioRefresh and
\* PDTLaunchRuntime.completeBackgroundDetailRefresh, LaunchRuntime.swift:1219,
\* shows the pulse through DisplayedPulse.show, which re-reads the store (1033).
BgPublish ==
    /\ wPc = "bgReady"
    /\ mainPc = "idle"
    /\ display' = Pulse(wNew, wPrior, wLoaded,
                        IF ReapplyOnBgPublish THEN store ELSE wRead)
    /\ ClearWorker
    /\ UNCHANGED <<pdt, snap, store, mainPc, mainFp, mainLoaded, intended, owed>>

-----------------------------------------------------------------------------
\* The app quits or crashes at any point and launches again. In-flight work
\* is lost; files stay. A normal quit runs applicationWillTerminate
\* (main.swift:1117-1119): it cancels a background refresh and waits up to
\* 4 s, so a refresh in bgDetails stops at its next throwIfCancelled, before
\* refreshedPulse, and its finishBackgroundPortfolioRefresh never runs. A
\* crash, force quit, or the 4 s timeout can stop the worker at any step.
\* Then AppDelegate.launch, main.swift:82, and startCachedPulseLoad, 106.
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
