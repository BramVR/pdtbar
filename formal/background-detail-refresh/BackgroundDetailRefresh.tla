------------------------------ MODULE BackgroundDetailRefresh ------------------------------
(***************************************************************************)
(* One run of PDTBackgroundDetailRefresh.refresh                            *)
(* (Sources/PDTBarCore/PDTBackgroundDetailRefresh.swift:173). Line numbers  *)
(* below are in that file unless a path is given.                           *)
(*                                                                          *)
(* The main thread walks the detail phases in order. Each phase is one      *)
(* Claude CLI tool call with retry (callDecodedWithRetry, :1008). Optional  *)
(* phases commit their slice to SnapshotStore when they finish; a failed    *)
(* optional phase records a diagnostic and degrades the refresh. In the     *)
(* price-history phase (priceSeries, :853) the main thread starts           *)
(* workerCount workers that pull holdings from PDTPriceHistoryWorkTracker   *)
(* (:1193), record into PDTPriceHistoryAccumulator (:1135), and race a      *)
(* deadline. On timeout, cancellation, or an observed setup outage the main *)
(* thread abandons unfinished holdings and moves on while late workers may  *)
(* still be running.                                                        *)
(*                                                                          *)
(* Cancellation (PDTCancellation, Sources/PDTBarCore/PDTCancellation.swift) *)
(* is one flag that only turns on. Every throwIfCancelled checkpoint        *)
(* (:1085) is modeled: a step that passes a checkpoint needs the flag off,  *)
(* and CancelThrow / PriceCancelThrow throw once it is on.                  *)
(*                                                                          *)
(* Slice values: "prior" = carried from the previous snapshot, "fresh" =    *)
(* refetched in this run, "none" = absent (performance is never carried).   *)
(***************************************************************************)
EXTENDS Naturals, Sequences, FiniteSets

CONSTANTS
    HoldingCount,       \* open holdings whose price history is fetched
    Limit,              \* PDTBackgroundDetailRefreshOptions.priceHistoryConcurrencyLimit
    RetryCount,         \* PDTBackgroundDetailRefreshOptions.optionalRetryCount
    FailureCategories   \* PDTDetailRefreshFailureCategory values a call may fail with

Holdings == 1 .. HoldingCount
Workers == 1 .. (IF Limit < HoldingCount THEN Limit ELSE HoldingCount)   \* workerCount, :870
Slices == {"base", "allocation", "xRay", "income", "priceHistory", "performance"}
OptionalPhases == {"allocation", "xRay", "income", "priceHistory"}
RetriedCallPhases == {"base", "allocation", "xRay", "income"}
CancelCheckpointPhases == {"discover", "base", "allocation", "xRay", "income", "performance", "finalize"}

\* PDTDetailRefreshFailureCategory.isRetryable, :23
IsRetryable(c) == c \in {"transientFailure", "timeout", "exit"}
\* PDTDetailRefreshFailureCategory.indicatesUnavailableSetup, :34
IndicatesUnavailableSetup(c) == c \in {"setupUnavailable", "unavailable"}

\* The promise, stated apart from the code's classifier so a classifier change is caught.
RetryableByContract == {"transientFailure", "timeout", "exit"}

VARIABLES
    \* main thread
    phase,         \* current phase, "advance" between phases, or "returned" / "threw"
    justDone,      \* phase that just finished, read by Advance
    attempt,       \* `outerAttempts` in callDecodedWithRetry for the current sequential call
    prevCat,       \* category of the failure that caused the current retry
    perfAvail,     \* performance tools were listed by availableReadTools
    diagOutage,    \* `diagnostics` holds a setup/auth category; runOptionalPhase's guard, :432
    outcome,       \* PDTBackgroundDetailRefreshOutcome
    snap,          \* in-memory `snapshot` local in refresh()
    store,         \* SnapshotStore current snapshot on disk
    diagPhases,    \* phases that appended a diagnostic to `diagnostics`
    cancelled,     \* the caller's PDTCancellation was cancelled
    \* price-history pool, main side
    ph,            \* "idle" | "wait" | "decide" | "abandon" | "collect" | "done"
    pastDeadline,  \* now() >= deadline (monotonic)
    timedOut,      \* `timedOut` at :941
    toRecord,      \* abandoned holdings the main thread has not yet recorded, :959
    resPoints, resFailed,   \* accumulator.result() as returned, :980
    \* PDTPriceHistoryWorkTracker
    pending, running, finished, abandoned,
    \* PDTPriceHistoryAccumulator
    points,        \* holdings whose refreshed points were appended
    failedQ,       \* failedQuoteIDs
    accUnavail,    \* firstUnavailableSetupCategory != nil
    \* workers
    wpc, wq, wattempt, wres, wcat,
    \* ghosts for properties
    phaseOk,       \* optional phases that finished with no diagnostic
    perfDiag,      \* the performance phase appended a timeout diagnostic
    everFresh,     \* slices that have been committed fresh in this run
    outage,        \* some diagnostic with a setup/auth category has been recorded
    lateStart,     \* a phase started after an outage was recorded
    lateRetry,     \* a price-history retry run started after the deadline
    pulls          \* times each holding was handed out by nextQuoteID

mainVars == <<phase, justDone, attempt, prevCat, perfAvail, diagOutage, outcome, snap, store, diagPhases, cancelled>>
poolMainVars == <<ph, pastDeadline, timedOut, toRecord, resPoints, resFailed>>
trackerVars == <<pending, running, finished, abandoned>>
accVars == <<points, failedQ, accUnavail>>
workerVars == <<wpc, wq, wattempt, wres, wcat>>
ghostVars == <<phaseOk, perfDiag, everFresh, outage, lateStart, lateRetry, pulls>>
vars == <<mainVars, poolMainVars, trackerVars, accVars, workerVars, ghostVars>>

Range(s) == {s[i] : i \in DOMAIN s}
Min(S) == CHOOSE x \in S : \A y \in S : x <= y
Fresh(m) == {s \in Slices : m[s] = "fresh"}

Init ==
    /\ phase = "discover"
    /\ justDone = "none"
    /\ attempt = 0
    /\ prevCat = "none"
    /\ perfAvail = FALSE
    /\ diagOutage = FALSE
    /\ outcome = "none"
    /\ snap = [s \in Slices |-> "prior"]
    /\ store = [s \in Slices |-> "prior"]
    /\ diagPhases = {}
    /\ cancelled = FALSE
    /\ ph = "idle"
    /\ pastDeadline = FALSE
    /\ timedOut = FALSE
    /\ toRecord = {}
    /\ resPoints = {}
    /\ resFailed = {}
    /\ pending = <<>>
    /\ running = {}
    /\ finished = {}
    /\ abandoned = {}
    /\ points = {}
    /\ failedQ = {}
    /\ accUnavail = FALSE
    /\ wpc = [w \in Workers |-> "idle"]
    /\ wq = [w \in Workers |-> 0]
    /\ wattempt = [w \in Workers |-> 0]
    /\ wres = [w \in Workers |-> "none"]
    /\ wcat = [w \in Workers |-> "none"]
    /\ phaseOk = {}
    /\ perfDiag = FALSE
    /\ everFresh = {}
    /\ outage = FALSE
    /\ lateStart = FALSE
    /\ lateRetry = FALSE
    /\ pulls = [h \in Holdings |-> 0]

-----------------------------------------------------------------------------
(* Main thread, sequential phases                                          *)

\* refresh: throwIfCancelled, clearLastDetailRefreshDiagnostic, availableReadTools,
\* missing-tool guard, :178-202, availableReadTools :468
Discover ==
    /\ phase = "discover"
    /\ ~cancelled
    /\ \/ /\ phase' = "base"
          /\ attempt' = 1
          \* Set(PDTReadTools.performance).isSubset(of: availableTools), :344
          /\ perfAvail' \in BOOLEAN
       \/ /\ phase' = "threw"
          /\ UNCHANGED <<attempt, perfAvail>>
    /\ UNCHANGED <<justDone, prevCat, diagOutage, outcome, snap, store, diagPhases, cancelled>>
    /\ UNCHANGED <<poolMainVars, trackerVars, accVars, workerVars, ghostVars>>

\* The caller cancels the refresh: PDTCancellation.cancel from
\* Sources/PDTBarApp/main.swift:1118 (PDTCancellation.swift:16).
Cancel ==
    /\ ~cancelled
    /\ phase \notin {"returned", "threw"}
    /\ cancelled' = TRUE
    /\ UNCHANGED <<phase, justDone, attempt, prevCat, perfAvail, diagOutage, outcome, snap, store, diagPhases>>
    /\ UNCHANGED <<poolMainVars, trackerVars, accVars, workerVars, ghostVars>>

\* A throwIfCancelled checkpoint throws: refresh start :178, the base catch and
\* post-call checks :216/:226, the optional phases' post-call checks :249,
\* :273, :297, runOptionalPhase's catch :438, performance :357/:366, before the
\* outcome :388, and the top of callDecodedWithRetry :1019.
CancelThrow ==
    /\ cancelled
    /\ phase \in CancelCheckpointPhases
    /\ phase' = "threw"
    /\ UNCHANGED <<justDone, attempt, prevCat, perfAvail, diagOutage, outcome, snap, store, diagPhases, cancelled>>
    /\ UNCHANGED <<poolMainVars, trackerVars, accVars, workerVars, ghostVars>>

\* One CLI run in callDecodedWithRetry (:1008) fails and the retry guard at
\* :1057-1060 starts another run. The guard also needs `now() < retryDeadline`;
\* the sequential phases' deadlines are not modeled, so a guard that refuses on
\* the deadline shows up as a fail action below.
SeqRetry ==
    /\ phase \in RetriedCallPhases
    /\ ~cancelled
    /\ \E c \in FailureCategories :
        /\ attempt <= RetryCount
        /\ IsRetryable(c)
        /\ attempt' = attempt + 1
        /\ prevCat' = c
    /\ UNCHANGED <<phase, justDone, perfAvail, diagOutage, outcome, snap, store, diagPhases, cancelled>>
    /\ UNCHANGED <<poolMainVars, trackerVars, accVars, workerVars, ghostVars>>

\* baseSnapshot returns; throwIfCancelled, preserveOptionalDetails, then
\* commitCurrentSnapshot, :208-232, preserveOptionalDetails :495
BaseSucceeds ==
    /\ phase = "base"
    /\ ~cancelled
    /\ LET m == [s \in Slices |->
                   IF s = "base" THEN "fresh"
                   ELSE IF s = "performance" THEN "none"
                   ELSE store[s]] IN
       /\ snap' = m
       /\ store' = m
       /\ everFresh' = everFresh \cup Fresh(store')
    /\ phase' = "advance"
    /\ justDone' = "base"
    /\ UNCHANGED <<attempt, prevCat, perfAvail, diagOutage, outcome, diagPhases, cancelled>>
    /\ UNCHANGED <<poolMainVars, trackerVars, accVars, workerVars>>
    /\ UNCHANGED <<phaseOk, perfDiag, outage, lateStart, lateRetry, pulls>>

\* baseSnapshot throws; throwIfCancelled, saveLastDetailRefreshDiagnostic, then
\* rethrow, :215-224. Any category: a retryable one ends the call once the
\* retry budget or the call's deadline (:1026, :1060) runs out.
BaseFails ==
    /\ phase = "base"
    /\ ~cancelled
    /\ phase' = "threw"
    /\ UNCHANGED <<justDone, attempt, prevCat, perfAvail, diagOutage, outcome, snap, store, diagPhases, cancelled>>
    /\ UNCHANGED <<poolMainVars, trackerVars, accVars, workerVars, ghostVars>>

\* allocation / xRay / income call returns, throwIfCancelled, and the slice is
\* committed with no diagnostic: :240-258, :264-280, :288-305
OptionalSucceeds ==
    /\ phase \in {"allocation", "xRay", "income"}
    /\ ~cancelled
    /\ LET m == [snap EXCEPT ![phase] = "fresh"] IN
       /\ snap' = m
       /\ store' = m
       /\ everFresh' = everFresh \cup Fresh(store')
    /\ phaseOk' = phaseOk \cup {phase}
    /\ justDone' = phase
    /\ phase' = "advance"
    /\ UNCHANGED <<attempt, prevCat, perfAvail, diagOutage, outcome, diagPhases, cancelled>>
    /\ UNCHANGED <<poolMainVars, trackerVars, accVars, workerVars>>
    /\ UNCHANGED <<perfDiag, outage, lateStart, lateRetry, pulls>>

\* xRay / income return partial data with a .timeout diagnostic: pagination
\* truncated by the page cap or deadline (truncationDiagnostic,
\* Sources/PDTBarCore/PDTLiveDataSource.swift:615-631), or the income quote
\* scan ran out of time (:797). The slice is committed and the body returns the
\* diagnostic to runOptionalPhase, :280, :305, :436.
OptionalSucceedsWithDiagnostic ==
    /\ phase \in {"xRay", "income"}
    /\ ~cancelled
    /\ LET m == [snap EXCEPT ![phase] = "fresh"] IN
       /\ snap' = m
       /\ store' = m
       /\ everFresh' = everFresh \cup Fresh(store')
    /\ diagPhases' = diagPhases \cup {phase}
    /\ justDone' = phase
    /\ phase' = "advance"
    /\ UNCHANGED <<attempt, prevCat, perfAvail, diagOutage, outcome, cancelled>>
    /\ UNCHANGED <<poolMainVars, trackerVars, accVars, workerVars>>
    /\ UNCHANGED <<phaseOk, perfDiag, outage, lateStart, lateRetry, pulls>>

\* allocation / xRay / income throws; runOptionalPhase's catch runs
\* throwIfCancelled and appends the diagnostic, :437-439.
\* Any category, as in BaseFails.
OptionalFails ==
    /\ phase \in {"allocation", "xRay", "income"}
    /\ ~cancelled
    /\ \E c \in FailureCategories :
        /\ diagPhases' = diagPhases \cup {phase}
        /\ diagOutage' = (diagOutage \/ IndicatesUnavailableSetup(c))
        /\ outage' = (outage \/ IndicatesUnavailableSetup(c))
    /\ justDone' = phase
    /\ phase' = "advance"
    /\ UNCHANGED <<attempt, prevCat, perfAvail, outcome, snap, store, cancelled>>
    /\ UNCHANGED <<poolMainVars, trackerVars, accVars, workerVars>>
    /\ UNCHANGED <<phaseOk, perfDiag, everFresh, lateStart, lateRetry, pulls>>

NextOf(p) ==
    CASE p = "base" -> "allocation"
      [] p = "allocation" -> "xRay"
      [] p = "xRay" -> "income"
      [] p = "income" -> "priceHistory"
      [] p = "priceHistory" -> "performance"

\* runOptionalPhase's guard (:432), read before every optional phase, and the
\* performance tools gate (:344). Entering priceHistory
\* runs the priceSeries setup and launches workers, :853-879.
Advance ==
    /\ phase = "advance"
    /\ LET t == IF diagOutage THEN "finalize"
                ELSE IF NextOf(justDone) = "performance" /\ ~perfAvail THEN "finalize"
                ELSE NextOf(justDone) IN
       /\ phase' = t
       /\ attempt' = IF t = "finalize" \/ t = "priceHistory" THEN 0 ELSE 1
       /\ prevCat' = "none"
       /\ lateStart' = (lateStart \/ (outage /\ t /= "finalize"))
       /\ IF t = "priceHistory"
            THEN /\ ph' = "wait"
                 /\ pending' = [i \in Holdings |-> i]
                 /\ wpc' = [w \in Workers |-> "check"]
            ELSE UNCHANGED <<ph, pending, wpc>>
    /\ UNCHANGED <<justDone, perfAvail, diagOutage, outcome, snap, store, diagPhases, cancelled>>
    /\ UNCHANGED <<pastDeadline, timedOut, toRecord, resPoints, resFailed>>
    /\ UNCHANGED <<running, finished, abandoned, accVars, wq, wattempt, wres, wcat>>
    /\ UNCHANGED <<phaseOk, perfDiag, everFresh, outage, lateRetry, pulls>>

\* performanceSummary (:511) uses callDecoded with no refresh-layer retry.
\* Success commits (:351-364). Failure clears performance (:371) and returns a
\* diagnostic only when its category is .timeout (:374-379).
Performance ==
    /\ phase = "performance"
    /\ ~cancelled
    /\ \/ LET m == [snap EXCEPT !["performance"] = "fresh"] IN
          /\ snap' = m
          /\ store' = m
          /\ everFresh' = everFresh \cup Fresh(store')
          /\ UNCHANGED <<diagPhases, perfDiag>>
       \/ /\ snap' = [snap EXCEPT !["performance"] = "none"]
          /\ UNCHANGED <<store, everFresh, diagPhases, perfDiag>>
       \/ /\ snap' = [snap EXCEPT !["performance"] = "none"]
          /\ diagPhases' = diagPhases \cup {"performance"}
          /\ perfDiag' = TRUE
          /\ UNCHANGED <<store, everFresh>>
    /\ phase' = "finalize"
    /\ UNCHANGED <<justDone, attempt, prevCat, perfAvail, diagOutage, outcome, cancelled>>
    /\ UNCHANGED <<poolMainVars, trackerVars, accVars, workerVars>>
    /\ UNCHANGED <<phaseOk, outage, lateStart, lateRetry, pulls>>

\* throwIfCancelled (:388); outcome from `diagnostics.isEmpty` (:393);
\* PressureRunner.refreshedPulse commits the snapshot (:394); last diagnostic
\* saved or cleared (:403-407).
Finalize ==
    /\ phase = "finalize"
    /\ ~cancelled
    /\ outcome' = IF diagPhases = {} THEN "completed" ELSE "degraded"
    /\ store' = snap
    /\ everFresh' = everFresh \cup Fresh(store')
    /\ phase' = "returned"
    /\ UNCHANGED <<justDone, attempt, prevCat, perfAvail, diagOutage, snap, diagPhases, cancelled>>
    /\ UNCHANGED <<poolMainVars, trackerVars, accVars, workerVars>>
    /\ UNCHANGED <<phaseOk, perfDiag, outage, lateStart, lateRetry, pulls>>

-----------------------------------------------------------------------------
(* Price-history pool, main thread side (priceSeries, :853)                *)

\* The deadline passes. Wall-clock time only moves forward.
Tick ==
    /\ ph /= "idle"
    /\ ~pastDeadline
    /\ pastDeadline' = TRUE
    /\ UNCHANGED <<mainVars, ph, timedOut, toRecord, resPoints, resFailed>>
    /\ UNCHANGED <<trackerVars, accVars, workerVars, ghostVars>>

\* group.wait returns because every worker left the group, :941-942
WaitAllExited ==
    /\ ph = "wait"
    /\ \A w \in Workers : wpc[w] = "exit"
    /\ timedOut' = pastDeadline
    /\ ph' = "decide"
    /\ UNCHANGED <<mainVars, pastDeadline, toRecord, resPoints, resFailed>>
    /\ UNCHANGED <<trackerVars, accVars, workerVars, ghostVars>>

\* group.wait times out. Its timeout starts after `deadline` was computed, so
\* it can only fire once the deadline has passed, :941
WaitTimedOut ==
    /\ ph = "wait"
    /\ pastDeadline
    /\ timedOut' = TRUE
    /\ ph' = "decide"
    /\ UNCHANGED <<mainVars, pastDeadline, toRecord, resPoints, resFailed>>
    /\ UNCHANGED <<trackerVars, accVars, workerVars, ghostVars>>

\* `cancelled`, accumulator.unavailableSetupCategory(), then
\* workTracker.markAbandoned() (:943-955, markAbandoned :1229, one lock
\* section). priceCancellation.cancel() (:947) adds no state: workers already
\* stop on `pastDeadline \/ cancelled`, and timedOut implies pastDeadline. The
\* extra bounded group.wait (:952) only gives late workers time to finish,
\* which the interleavings already cover.
Decide ==
    /\ ph = "decide"
    /\ IF timedOut \/ cancelled \/ accUnavail
         THEN LET unfinished == ((Range(pending) \cup running) \ finished) \ abandoned IN
              /\ pending' = <<>>
              /\ running' = running \ unfinished
              /\ abandoned' = abandoned \cup unfinished
              /\ toRecord' = unfinished
              /\ ph' = "abandon"
         ELSE /\ ph' = "collect"
              /\ UNCHANGED <<pending, running, abandoned, toRecord>>
    /\ UNCHANGED <<mainVars, pastDeadline, timedOut, resPoints, resFailed>>
    /\ UNCHANGED <<finished, accVars, workerVars, ghostVars>>

\* accumulator.append(diagnostic:failedQuoteID:) for one abandoned holding, in
\* sorted order, :956-977. The appended category is the outage category or
\* .timeout, so accUnavail does not change.
RecordAbandoned ==
    /\ ph = "abandon"
    /\ toRecord /= {}
    /\ LET h == Min(toRecord) IN
       /\ failedQ' = failedQ \cup {h}
       /\ toRecord' = toRecord \ {h}
    /\ UNCHANGED <<mainVars, ph, pastDeadline, timedOut, resPoints, resFailed>>
    /\ UNCHANGED <<trackerVars, points, accUnavail, workerVars, ghostVars>>

PoolReturning ==
    \/ ph = "collect"
    \/ ph = "abandon" /\ toRecord = {}

\* accumulator.result() (:980), throwIfCancelled passes (:325), then the
\* body merges the series with the prior fallback and returns the diagnostics
\* to runOptionalPhase (:330-341, :436). No commit here.
Collect ==
    /\ PoolReturning
    /\ phase = "priceHistory"
    /\ ~cancelled
    /\ resPoints' = points
    /\ resFailed' = failedQ
    /\ ph' = "done"
    /\ snap' = IF points /= {} THEN [snap EXCEPT !["priceHistory"] = "fresh"] ELSE snap
    /\ diagPhases' = IF failedQ /= {} THEN diagPhases \cup {"priceHistory"} ELSE diagPhases
    /\ phaseOk' = IF failedQ = {} THEN phaseOk \cup {"priceHistory"} ELSE phaseOk
    /\ outage' = (outage \/ accUnavail)
    /\ diagOutage' = (diagOutage \/ accUnavail)
    /\ justDone' = "priceHistory"
    /\ phase' = "advance"
    /\ UNCHANGED <<attempt, prevCat, perfAvail, outcome, store, cancelled>>
    /\ UNCHANGED <<pastDeadline, timedOut, toRecord>>
    /\ UNCHANGED <<trackerVars, accVars, workerVars>>
    /\ UNCHANGED <<perfDiag, everFresh, lateStart, lateRetry, pulls>>

\* accumulator.result() (:980), then throwIfCancelled throws (:325).
PriceCancelThrow ==
    /\ PoolReturning
    /\ phase = "priceHistory"
    /\ cancelled
    /\ resPoints' = points
    /\ resFailed' = failedQ
    /\ ph' = "done"
    /\ phase' = "threw"
    /\ UNCHANGED <<justDone, attempt, prevCat, perfAvail, diagOutage, outcome, snap, store, diagPhases, cancelled>>
    /\ UNCHANGED <<pastDeadline, timedOut, toRecord>>
    /\ UNCHANGED <<trackerVars, accVars, workerVars, ghostVars>>

-----------------------------------------------------------------------------
(* Price-history workers (the queue.async closure at :876-938)             *)

\* while-condition: `now() < deadline`, `!priceCancellation.isCancelled` (it
\* inherits the caller's flag, PDTCancellation.swift:22-27), and
\* accumulator.unavailableSetupCategory() == nil, :883-885. The flags only
\* ever turn on, so reading them in one step loses no outcome.
WCheck(w) ==
    /\ wpc[w] = "check"
    /\ wpc' = [wpc EXCEPT ![w] = IF ~pastDeadline /\ ~cancelled /\ ~accUnavail THEN "pull" ELSE "exit"]
    /\ UNCHANGED <<mainVars, poolMainVars, trackerVars, accVars>>
    /\ UNCHANGED <<wq, wattempt, wres, wcat, ghostVars>>

\* workTracker.nextQuoteID() (:886, :1204), then the top of
\* callDecodedWithRetry (:1019-1034): throwIfCancelled and the deadline guard
\* throw .timeout without a CLI run; otherwise the first run starts (:1039).
\* Nothing between these reads shared state other than the two flags.
WPull(w) ==
    /\ wpc[w] = "pull"
    /\ IF pending /= <<>>
         THEN LET h == Head(pending) IN
              /\ pending' = Tail(pending)
              /\ running' = running \cup {h}
              /\ wq' = [wq EXCEPT ![w] = h]
              /\ wcat' = [wcat EXCEPT ![w] = "none"]
              /\ pulls' = [pulls EXCEPT ![h] = @ + 1]
              /\ IF cancelled \/ pastDeadline
                   THEN /\ wres' = [wres EXCEPT ![w] = "timeout"]
                        /\ wattempt' = [wattempt EXCEPT ![w] = 0]
                        /\ wpc' = [wpc EXCEPT ![w] = "complete"]
                   ELSE /\ wattempt' = [wattempt EXCEPT ![w] = 1]
                        /\ wpc' = [wpc EXCEPT ![w] = "call"]
                        /\ UNCHANGED wres
         ELSE /\ wpc' = [wpc EXCEPT ![w] = "exit"]
              /\ UNCHANGED <<pending, running, wq, wattempt, wcat, pulls, wres>>
    /\ UNCHANGED <<mainVars, poolMainVars, finished, abandoned, accVars>>
    /\ UNCHANGED <<phaseOk, perfDiag, everFresh, outage, lateStart, lateRetry>>

\* The CLI run returns. On failure, the retry guard at :1057-1060 either
\* throws or goes to backoff. It refuses after the deadline or a cancel.
WCallReturns(w) ==
    /\ wpc[w] = "call"
    /\ \/ /\ wres' = [wres EXCEPT ![w] = "ok"]
          /\ wpc' = [wpc EXCEPT ![w] = "complete"]
          /\ UNCHANGED wcat
       \/ \E c \in FailureCategories :
            IF /\ wattempt[w] <= RetryCount
               /\ IsRetryable(c)
               /\ ~cancelled
               /\ ~pastDeadline
              THEN /\ wcat' = [wcat EXCEPT ![w] = c]
                   /\ wpc' = [wpc EXCEPT ![w] = "backoff"]
                   /\ UNCHANGED wres
              ELSE /\ wres' = [wres EXCEPT ![w] = c]
                   /\ wpc' = [wpc EXCEPT ![w] = "complete"]
                   /\ UNCHANGED wcat
    /\ UNCHANGED <<mainVars, poolMainVars, trackerVars, accVars, wq, wattempt, ghostVars>>

\* Thread.sleep backoff capped at the deadline (:1067-1073), throwIfCancelled
\* (:1074), then the next loop iteration's throwIfCancelled and deadline guard
\* (:1019-1034) throw .timeout, or another full CLI run starts (:1039).
WBackoffEnds(w) ==
    /\ wpc[w] = "backoff"
    /\ IF cancelled \/ pastDeadline
         THEN /\ wres' = [wres EXCEPT ![w] = "timeout"]
              /\ wpc' = [wpc EXCEPT ![w] = "complete"]
              /\ UNCHANGED <<wattempt, lateRetry>>
         ELSE /\ wattempt' = [wattempt EXCEPT ![w] = @ + 1]
              /\ wpc' = [wpc EXCEPT ![w] = "call"]
              /\ lateRetry' = (lateRetry \/ pastDeadline)
              /\ UNCHANGED wres
    /\ UNCHANGED <<mainVars, poolMainVars, trackerVars, accVars, wq, wcat>>
    /\ UNCHANGED <<phaseOk, perfDiag, everFresh, outage, lateStart, pulls>>

\* workTracker.complete(quoteID, record:) with the accumulator append inside the
\* tracker lock, :910-912 / :927-929, complete :1216, append :1168 / :1174.
\* markCompleted and the progress callback after it are not modeled.
WComplete(w) ==
    /\ wpc[w] = "complete"
    /\ LET h == wq[w]
           record == h \notin abandoned /\ h \notin finished IN
       /\ running' = running \ {h}
       /\ finished' = IF record THEN finished \cup {h} ELSE finished
       /\ points' = IF record /\ wres[w] = "ok" THEN points \cup {h} ELSE points
       /\ failedQ' = IF record /\ wres[w] /= "ok" THEN failedQ \cup {h} ELSE failedQ
       /\ accUnavail' = (accUnavail \/ (record /\ IndicatesUnavailableSetup(wres[w])))
    /\ wpc' = [wpc EXCEPT ![w] = "check"]
    /\ wq' = [wq EXCEPT ![w] = 0]
    /\ wattempt' = [wattempt EXCEPT ![w] = 0]
    /\ wres' = [wres EXCEPT ![w] = "none"]
    /\ wcat' = [wcat EXCEPT ![w] = "none"]
    /\ UNCHANGED <<mainVars, poolMainVars, pending, abandoned, ghostVars>>

-----------------------------------------------------------------------------

\* The refresh returned or threw and every worker has left the loop.
Finished ==
    /\ phase \in {"returned", "threw"}
    /\ \A w \in Workers : wpc[w] \in {"idle", "exit"}
    /\ UNCHANGED vars

Next ==
    \/ Discover \/ Cancel \/ CancelThrow \/ SeqRetry \/ BaseSucceeds \/ BaseFails
    \/ OptionalSucceeds \/ OptionalSucceedsWithDiagnostic \/ OptionalFails
    \/ Advance \/ Performance \/ Finalize
    \/ Tick \/ WaitAllExited \/ WaitTimedOut \/ Decide \/ RecordAbandoned
    \/ Collect \/ PriceCancelThrow
    \/ \E w \in Workers : WCheck(w) \/ WPull(w) \/ WCallReturns(w) \/ WBackoffEnds(w) \/ WComplete(w)
    \/ Finished

Spec == Init /\ [][Next]_vars /\ WF_vars(Next)

-----------------------------------------------------------------------------
(* Properties                                                              *)

TypeOK ==
    /\ phase \in {"discover", "base", "allocation", "xRay", "income", "priceHistory",
                  "performance", "advance", "finalize", "returned", "threw"}
    /\ attempt \in 0 .. (RetryCount + 1)
    /\ \A w \in Workers : wattempt[w] \in 0 .. (RetryCount + 1)
    /\ store \in [Slices -> {"prior", "fresh", "none"}]
    /\ cancelled \in BOOLEAN
    /\ running \subseteq Holdings /\ finished \subseteq Holdings /\ abandoned \subseteq Holdings

\* A slice committed fresh in this run is never overwritten by a later phase,
\* a later phase failure, a cancel, or the final commit.
CommittedNeverLost == \A s \in everFresh : store[s] = "fresh"

\* Every optional phase that finished cleanly is on disk when refresh returns.
ReturnedHasSucceededPhases ==
    phase = "returned" => \A p \in phaseOk : store[p] = "fresh"

\* `degraded` exactly when some optional phase did not finish cleanly or the
\* performance phase timed out.
OutcomeHonest ==
    phase = "returned" =>
        (outcome = "completed" <=> (OptionalPhases \subseteq phaseOk /\ ~perfDiag))

\* Only transient failures are ever retried, in the phase calls and the price workers.
NoDeterministicRetry ==
    /\ (phase \in RetriedCallPhases /\ attempt > 1) => prevCat \in RetryableByContract
    /\ \A w \in Workers : wattempt[w] > 1 => wcat[w] \in RetryableByContract

\* Once an auth/setup outage has been recorded, no later detail phase starts.
NoPhaseAfterOutage == ~lateStart

\* At most Limit price-history CLI runs are in flight at once.
ConcurrencyBound == Cardinality({w \in Workers : wpc[w] = "call"}) <= Limit

\* nextQuoteID hands each holding out at most once.
PullAtMostOnce == \A h \in Holdings : pulls[h] <= 1

\* Each holding is in exactly one of refreshed or failed when priceSeries returns.
ExactlyOnceAtReturn ==
    ph = "done" => /\ resPoints \cap resFailed = {}
                   /\ resPoints \cup resFailed = Holdings

\* Late workers never change the accumulator after priceSeries returned it.
ResultFrozen == ph = "done" => (points = resPoints /\ failedQ = resFailed)

\* No price-history retry starts a new CLI run after the deadline.
NoRetryAfterDeadline == ~lateRetry

\* The refresh always returns or throws, cancelled or not.
Terminates == <>(phase \in {"returned", "threw"})

=============================================================================
