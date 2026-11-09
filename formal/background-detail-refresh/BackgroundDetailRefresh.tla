------------------------------ MODULE BackgroundDetailRefresh ------------------------------
(***************************************************************************)
(* One run of PDTBackgroundDetailRefresh.refresh                            *)
(* (Sources/PDTBarCore/PDTBarCore.swift:7089). Line numbers below are in    *)
(* that file unless a path is given.                                        *)
(*                                                                          *)
(* The main thread walks the detail phases in order. Each phase is one      *)
(* Claude CLI tool call with retry (callDecodedWithRetry, :7683). Optional  *)
(* phases commit their slice to SnapshotStore when they finish; a failed    *)
(* optional phase records a diagnostic and degrades the refresh. In the     *)
(* price-history phase (priceSeries, :7566) the main thread starts          *)
(* workerCount workers that pull holdings from PDTPriceHistoryWorkTracker   *)
(* (:7837), record into PDTPriceHistoryAccumulator (:7779), and race a      *)
(* deadline. On timeout or an observed setup outage the main thread         *)
(* abandons unfinished holdings and moves on while late workers may still   *)
(* be running.                                                              *)
(*                                                                          *)
(* Slice values: "prior" = carried from the previous snapshot, "fresh" =    *)
(* refetched in this run, "none" = absent (performance is never carried).   *)
(***************************************************************************)
EXTENDS Naturals, Sequences, FiniteSets

CONSTANTS
    HoldingCount,       \* open holdings whose price history is fetched
    Limit,              \* PDTBackgroundDetailRefreshOptions.priceHistoryConcurrencyLimit
    RetryCount,         \* PDTBackgroundDetailRefreshOptions.optionalRetryCount
    FailureCategories,  \* PDTDetailRefreshFailureCategory values a call may fail with
    \* Code knobs. Both are FALSE in the shipped code. TRUE models the fix.
    PriceHistoryRetryDeadline,   \* priceSeries passes `retryDeadline: deadline` at :7602
    PriceHistoryOutageSetsSkip   \* refresh sets skipRemainingPhasesForUnavailableSetup after :7217

Holdings == 1 .. HoldingCount
Workers == 1 .. (IF Limit < HoldingCount THEN Limit ELSE HoldingCount)   \* workerCount, :7581
Slices == {"base", "allocation", "xRay", "income", "priceHistory", "performance"}
OptionalPhases == {"allocation", "xRay", "income", "priceHistory"}
RetriedCallPhases == {"base", "allocation", "xRay", "income"}

\* PDTDetailRefreshFailureCategory.isRetryable, :6986
IsRetryable(c) == c \in {"transientFailure", "timeout", "exit"}
\* PDTDetailRefreshFailureCategory.indicatesUnavailableSetup, :6997
IndicatesUnavailableSetup(c) == c \in {"setupUnavailable", "unavailable"}

\* The promise, stated apart from the code's classifier so a classifier change is caught.
RetryableByContract == {"transientFailure", "timeout", "exit"}

VARIABLES
    \* main thread
    phase,         \* current phase, "advance" between phases, or "returned" / "threw"
    justDone,      \* phase that just finished, read by Advance
    attempt,       \* `attempts` in callDecodedWithRetry for the current sequential call
    prevCat,       \* category of the failure that caused the current retry
    perfAvail,     \* performance tools were listed by availableReadTools
    skip,          \* skipRemainingPhasesForUnavailableSetup, :7132
    outcome,       \* PDTBackgroundDetailRefreshOutcome
    snap,          \* in-memory `snapshot` local in refresh()
    store,         \* SnapshotStore current snapshot on disk
    failedPhases,  \* optional phases that appended a diagnostic to `diagnostics`
    \* price-history pool, main side
    ph,            \* "idle" | "wait" | "decide" | "abandon" | "collect" | "done"
    pastDeadline,  \* Date() >= deadline (monotonic)
    timedOut,      \* `timedOut` at :7649
    toRecord,      \* abandoned holdings the main thread has not yet recorded, :7654
    resPoints, resFailed,   \* accumulator.result() as returned, :7676
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
    everFresh,     \* slices that have been committed fresh in this run
    outage,        \* some diagnostic with a setup/auth category has been recorded
    lateStart,     \* a phase started after an outage was recorded
    lateRetry,     \* a price-history retry run started after the deadline
    pulls          \* times each holding was handed out by nextQuoteID

mainVars == <<phase, justDone, attempt, prevCat, perfAvail, skip, outcome, snap, store, failedPhases>>
poolMainVars == <<ph, pastDeadline, timedOut, toRecord, resPoints, resFailed>>
trackerVars == <<pending, running, finished, abandoned>>
accVars == <<points, failedQ, accUnavail>>
workerVars == <<wpc, wq, wattempt, wres, wcat>>
ghostVars == <<phaseOk, everFresh, outage, lateStart, lateRetry, pulls>>
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
    /\ skip = FALSE
    /\ outcome = "none"
    /\ snap = [s \in Slices |-> "prior"]
    /\ store = [s \in Slices |-> "prior"]
    /\ failedPhases = {}
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
    /\ everFresh = {}
    /\ outage = FALSE
    /\ lateStart = FALSE
    /\ lateRetry = FALSE
    /\ pulls = [h \in Holdings |-> 0]

-----------------------------------------------------------------------------
(* Main thread, sequential phases                                          *)

\* refresh: clearLastDetailRefreshDiagnostic, availableReadTools, missing-tool guard, :7092-7110
Discover ==
    /\ phase = "discover"
    /\ \/ /\ phase' = "base"
          /\ attempt' = 1
          \* Set(PDTReadTools.performance).isSubset(of: availableTools), :7220
          /\ perfAvail' \in BOOLEAN
       \/ /\ phase' = "threw"
          /\ UNCHANGED <<attempt, perfAvail>>
    /\ UNCHANGED <<justDone, prevCat, skip, outcome, snap, store, failedPhases>>
    /\ UNCHANGED <<poolMainVars, trackerVars, accVars, workerVars, ghostVars>>

\* One CLI run in callDecodedWithRetry (:7683) fails and the retry guard at
\* :7709 starts another run. These phases pass no retryDeadline.
SeqRetry ==
    /\ phase \in RetriedCallPhases
    /\ \E c \in FailureCategories :
        /\ attempt <= RetryCount
        /\ IsRetryable(c)
        /\ attempt' = attempt + 1
        /\ prevCat' = c
    /\ UNCHANGED <<phase, justDone, perfAvail, skip, outcome, snap, store, failedPhases>>
    /\ UNCHANGED <<poolMainVars, trackerVars, accVars, workerVars, ghostVars>>

\* baseSnapshot returns; preserveOptionalDetails then commitCurrentSnapshot, :7118-7126, :7295
BaseSucceeds ==
    /\ phase = "base"
    /\ LET m == [s \in Slices |->
                   IF s = "base" THEN "fresh"
                   ELSE IF s = "performance" THEN "none"
                   ELSE store[s]] IN
       /\ snap' = m
       /\ store' = m
       /\ everFresh' = everFresh \cup Fresh(store')
    /\ phase' = "advance"
    /\ justDone' = "base"
    /\ UNCHANGED <<attempt, prevCat, perfAvail, skip, outcome, failedPhases>>
    /\ UNCHANGED <<poolMainVars, trackerVars, accVars, workerVars>>
    /\ UNCHANGED <<phaseOk, outage, lateStart, lateRetry, pulls>>

\* baseSnapshot throws after retries; saveLastDetailRefreshDiagnostic then rethrow, :7119-7123
BaseFails ==
    /\ phase = "base"
    /\ \E c \in FailureCategories :
        ~(attempt <= RetryCount /\ IsRetryable(c))
    /\ phase' = "threw"
    /\ UNCHANGED <<justDone, attempt, prevCat, perfAvail, skip, outcome, snap, store, failedPhases>>
    /\ UNCHANGED <<poolMainVars, trackerVars, accVars, workerVars, ghostVars>>

\* allocation / xRay / income call returns and the slice is committed:
\* :7148-7158, :7166-7168, :7179-7188
OptionalSucceeds ==
    /\ phase \in {"allocation", "xRay", "income"}
    /\ LET m == [snap EXCEPT ![phase] = "fresh"] IN
       /\ snap' = m
       /\ store' = m
       /\ everFresh' = everFresh \cup Fresh(store')
    /\ phaseOk' = phaseOk \cup {phase}
    /\ justDone' = phase
    /\ phase' = "advance"
    /\ UNCHANGED <<attempt, prevCat, perfAvail, skip, outcome, failedPhases>>
    /\ UNCHANGED <<poolMainVars, trackerVars, accVars, workerVars>>
    /\ UNCHANGED <<outage, lateStart, lateRetry, pulls>>

\* allocation / xRay / income throws after retries; recordOptionalPhaseFailure,
\* :7133-7144, called from :7160, :7170, :7191
OptionalFails ==
    /\ phase \in {"allocation", "xRay", "income"}
    /\ \E c \in FailureCategories :
        /\ ~(attempt <= RetryCount /\ IsRetryable(c))
        /\ failedPhases' = failedPhases \cup {phase}
        /\ skip' = (skip \/ IndicatesUnavailableSetup(c))
        /\ outage' = (outage \/ IndicatesUnavailableSetup(c))
    /\ justDone' = phase
    /\ phase' = "advance"
    /\ UNCHANGED <<attempt, prevCat, perfAvail, outcome, snap, store>>
    /\ UNCHANGED <<poolMainVars, trackerVars, accVars, workerVars>>
    /\ UNCHANGED <<phaseOk, everFresh, lateStart, lateRetry, pulls>>

NextOf(p) ==
    CASE p = "base" -> "allocation"
      [] p = "allocation" -> "xRay"
      [] p = "xRay" -> "income"
      [] p = "income" -> "priceHistory"
      [] p = "priceHistory" -> "performance"

\* The `if !skipRemainingPhasesForUnavailableSetup` gates at :7146, :7164,
\* :7177, :7195, and the performance gate at :7219-7220. Entering
\* priceHistory runs the priceSeries setup and launches workers, :7566-7590.
Advance ==
    /\ phase = "advance"
    /\ LET t == IF skip THEN "finalize"
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
    /\ UNCHANGED <<justDone, perfAvail, skip, outcome, snap, store, failedPhases>>
    /\ UNCHANGED <<pastDeadline, timedOut, toRecord, resPoints, resFailed>>
    /\ UNCHANGED <<running, finished, abandoned, accVars, wq, wattempt, wres, wcat>>
    /\ UNCHANGED <<phaseOk, everFresh, outage, lateRetry, pulls>>

\* performanceSummary (:7311) uses callDecoded with no retry. Success commits
\* (:7224-7225). Failure clears performance with no diagnostic (:7226-7231).
Performance ==
    /\ phase = "performance"
    /\ \/ LET m == [snap EXCEPT !["performance"] = "fresh"] IN
          /\ snap' = m
          /\ store' = m
          /\ everFresh' = everFresh \cup Fresh(store')
       \/ /\ snap' = [snap EXCEPT !["performance"] = "none"]
          /\ UNCHANGED <<store, everFresh>>
    /\ phase' = "finalize"
    /\ UNCHANGED <<justDone, attempt, prevCat, perfAvail, skip, outcome, failedPhases>>
    /\ UNCHANGED <<poolMainVars, trackerVars, accVars, workerVars>>
    /\ UNCHANGED <<phaseOk, outage, lateStart, lateRetry, pulls>>

\* outcome from `diagnostics.isEmpty` (:7236); PressureRunner.refreshedPulse
\* commits the snapshot (:7237); last diagnostic saved or cleared (:7246-7250).
Finalize ==
    /\ phase = "finalize"
    /\ outcome' = IF failedPhases = {} THEN "completed" ELSE "degraded"
    /\ store' = snap
    /\ everFresh' = everFresh \cup Fresh(store')
    /\ phase' = "returned"
    /\ UNCHANGED <<justDone, attempt, prevCat, perfAvail, skip, snap, failedPhases>>
    /\ UNCHANGED <<poolMainVars, trackerVars, accVars, workerVars>>
    /\ UNCHANGED <<phaseOk, outage, lateStart, lateRetry, pulls>>

-----------------------------------------------------------------------------
(* Price-history pool, main thread side (priceSeries, :7566)               *)

\* The deadline passes. Wall-clock time only moves forward.
Tick ==
    /\ ph /= "idle"
    /\ ~pastDeadline
    /\ pastDeadline' = TRUE
    /\ UNCHANGED <<mainVars, ph, timedOut, toRecord, resPoints, resFailed>>
    /\ UNCHANGED <<trackerVars, accVars, workerVars, ghostVars>>

\* group.wait returns because every worker left the group, :7649-7650
WaitAllExited ==
    /\ ph = "wait"
    /\ \A w \in Workers : wpc[w] = "exit"
    /\ timedOut' = pastDeadline
    /\ ph' = "decide"
    /\ UNCHANGED <<mainVars, pastDeadline, toRecord, resPoints, resFailed>>
    /\ UNCHANGED <<trackerVars, accVars, workerVars, ghostVars>>

\* group.wait times out. Its timeout starts after `deadline` was computed, so
\* it can only fire once the deadline has passed, :7649
WaitTimedOut ==
    /\ ph = "wait"
    /\ pastDeadline
    /\ timedOut' = TRUE
    /\ ph' = "decide"
    /\ UNCHANGED <<mainVars, pastDeadline, toRecord, resPoints, resFailed>>
    /\ UNCHANGED <<trackerVars, accVars, workerVars, ghostVars>>

\* accumulator.unavailableSetupCategory() then workTracker.markAbandoned()
\* (:7651-7654, markAbandoned :7873, one lock section)
Decide ==
    /\ ph = "decide"
    /\ IF timedOut \/ accUnavail
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
\* sorted order, :7655-7667. The appended category is the outage category or
\* .timeout, so accUnavail does not change.
RecordAbandoned ==
    /\ ph = "abandon"
    /\ toRecord /= {}
    /\ LET h == Min(toRecord) IN
       /\ failedQ' = failedQ \cup {h}
       /\ toRecord' = toRecord \ {h}
    /\ UNCHANGED <<mainVars, ph, pastDeadline, timedOut, resPoints, resFailed>>
    /\ UNCHANGED <<trackerVars, points, accUnavail, workerVars, ghostVars>>

\* accumulator.result() (:7676), then refresh merges the series with the
\* prior fallback and appends the diagnostics (:7206-7217). No commit here.
Collect ==
    /\ \/ ph = "collect"
       \/ ph = "abandon" /\ toRecord = {}
    /\ phase = "priceHistory"
    /\ resPoints' = points
    /\ resFailed' = failedQ
    /\ ph' = "done"
    /\ snap' = IF points /= {} THEN [snap EXCEPT !["priceHistory"] = "fresh"] ELSE snap
    /\ failedPhases' = IF failedQ /= {} THEN failedPhases \cup {"priceHistory"} ELSE failedPhases
    /\ phaseOk' = IF failedQ = {} THEN phaseOk \cup {"priceHistory"} ELSE phaseOk
    /\ outage' = (outage \/ accUnavail)
    /\ skip' = (skip \/ (PriceHistoryOutageSetsSkip /\ accUnavail))
    /\ justDone' = "priceHistory"
    /\ phase' = "advance"
    /\ UNCHANGED <<attempt, prevCat, perfAvail, outcome, store>>
    /\ UNCHANGED <<pastDeadline, timedOut, toRecord>>
    /\ UNCHANGED <<trackerVars, accVars, workerVars>>
    /\ UNCHANGED <<everFresh, lateStart, lateRetry, pulls>>

-----------------------------------------------------------------------------
(* Price-history workers (the queue.async closure at :7587-7646)           *)

\* while-condition: `Date() < deadline` and accumulator.unavailableSetupCategory() == nil,
\* :7594-7595. Both flags only ever turn on, so reading them in one step loses no outcome.
WCheck(w) ==
    /\ wpc[w] = "check"
    /\ wpc' = [wpc EXCEPT ![w] = IF ~pastDeadline /\ ~accUnavail THEN "pull" ELSE "exit"]
    /\ UNCHANGED <<mainVars, poolMainVars, trackerVars, accVars>>
    /\ UNCHANGED <<wq, wattempt, wres, wcat, ghostVars>>

\* workTracker.nextQuoteID() (:7596, :7848), then the first CLI run of
\* callDecodedWithRetry (:7602, :7692-7696). Nothing between the two reads shared state.
WPull(w) ==
    /\ wpc[w] = "pull"
    /\ IF pending /= <<>>
         THEN LET h == Head(pending) IN
              /\ pending' = Tail(pending)
              /\ running' = running \cup {h}
              /\ wq' = [wq EXCEPT ![w] = h]
              /\ wattempt' = [wattempt EXCEPT ![w] = 1]
              /\ wcat' = [wcat EXCEPT ![w] = "none"]
              /\ pulls' = [pulls EXCEPT ![h] = @ + 1]
              /\ wpc' = [wpc EXCEPT ![w] = "call"]
         ELSE /\ wpc' = [wpc EXCEPT ![w] = "exit"]
              /\ UNCHANGED <<pending, running, wq, wattempt, wcat, pulls>>
    /\ UNCHANGED <<mainVars, poolMainVars, finished, abandoned, accVars, wres>>
    /\ UNCHANGED <<phaseOk, everFresh, outage, lateStart, lateRetry>>

\* The CLI run returns. On failure, the retry guard at :7709-7714 either throws
\* or goes to backoff. The guard checks the deadline only when retryDeadline is passed.
WCallReturns(w) ==
    /\ wpc[w] = "call"
    /\ \/ /\ wres' = [wres EXCEPT ![w] = "ok"]
          /\ wpc' = [wpc EXCEPT ![w] = "complete"]
          /\ UNCHANGED wcat
       \/ \E c \in FailureCategories :
            IF /\ wattempt[w] <= RetryCount
               /\ IsRetryable(c)
               /\ (~PriceHistoryRetryDeadline \/ ~pastDeadline)
              THEN /\ wcat' = [wcat EXCEPT ![w] = c]
                   /\ wpc' = [wpc EXCEPT ![w] = "backoff"]
                   /\ UNCHANGED wres
              ELSE /\ wres' = [wres EXCEPT ![w] = c]
                   /\ wpc' = [wpc EXCEPT ![w] = "complete"]
                   /\ UNCHANGED wcat
    /\ UNCHANGED <<mainVars, poolMainVars, trackerVars, accVars, wq, wattempt, ghostVars>>

\* Thread.sleep backoff, the post-backoff deadline check, then the next loop
\* iteration starts another full CLI run, :7717-7727 then :7692-7696.
WBackoffEnds(w) ==
    /\ wpc[w] = "backoff"
    /\ IF PriceHistoryRetryDeadline /\ pastDeadline
         THEN /\ wres' = [wres EXCEPT ![w] = wcat[w]]
              /\ wpc' = [wpc EXCEPT ![w] = "complete"]
              /\ UNCHANGED <<wattempt, lateRetry>>
         ELSE /\ wattempt' = [wattempt EXCEPT ![w] = @ + 1]
              /\ wpc' = [wpc EXCEPT ![w] = "call"]
              /\ lateRetry' = (lateRetry \/ pastDeadline)
              /\ UNCHANGED wres
    /\ UNCHANGED <<mainVars, poolMainVars, trackerVars, accVars, wq, wcat>>
    /\ UNCHANGED <<phaseOk, everFresh, outage, lateStart, pulls>>

\* workTracker.complete(quoteID, record:) with the accumulator append inside the
\* tracker lock, :7618-7620 / :7635-7637, complete :7860, append :7812 / :7818.
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
    \/ Discover \/ SeqRetry \/ BaseSucceeds \/ BaseFails
    \/ OptionalSucceeds \/ OptionalFails \/ Advance \/ Performance \/ Finalize
    \/ Tick \/ WaitAllExited \/ WaitTimedOut \/ Decide \/ RecordAbandoned \/ Collect
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
    /\ running \subseteq Holdings /\ finished \subseteq Holdings /\ abandoned \subseteq Holdings

\* A slice committed fresh in this run is never overwritten by a later phase,
\* a later phase failure, or the final commit.
CommittedNeverLost == \A s \in everFresh : store[s] = "fresh"

\* Every optional phase that finished cleanly is on disk when refresh returns.
ReturnedHasSucceededPhases ==
    phase = "returned" => \A p \in phaseOk : store[p] = "fresh"

\* `degraded` exactly when some optional phase did not finish cleanly.
OutcomeHonest ==
    phase = "returned" => (outcome = "completed" <=> OptionalPhases \subseteq phaseOk)

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

\* The refresh always returns or throws.
Terminates == <>(phase \in {"returned", "threw"})

=============================================================================
