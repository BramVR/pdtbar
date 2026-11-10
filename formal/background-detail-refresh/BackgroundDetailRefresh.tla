------------------------------ MODULE BackgroundDetailRefresh ------------------------------
(***************************************************************************)
(* One run of PDTAPIBackgroundDetailRefresh.refresh                        *)
(* (Sources/PDTBarCore/PDTAPIBackgroundDetailRefresh.swift). Comments name *)
(* the Swift symbol or statement each action models.                       *)
(*                                                                         *)
(* The refresh is sequential. It fetches the base holdings, then the       *)
(* allocation, X-ray, and income facets, then price history in batches of  *)
(* PDTAPIResource.pricesBatchLimit quote ids, and fills one in-memory      *)
(* snapshot. PressureRunner.refreshedPulse writes the store once, after    *)
(* the last phase. Each request is one PDTAPIClient call whose own         *)
(* retries, pages, and backoff are folded into its final outcome: success  *)
(* or one PDTSyncFailure.Kind. A failure whose kind endsSync sets          *)
(* `syncEnded`, and every later phase and price batch is skipped without a *)
(* request.                                                                *)
(*                                                                         *)
(* Cancellation (PDTCancellation) is one flag that only turns on. The      *)
(* client checks it before every request, and fetch's catch rethrows it as *)
(* PDTAPIError.cancelled, so a request step in a cancelled run throws. The *)
(* explicit throwIfCancelled checkpoints run after the base, after each    *)
(* optional phase, after the price loop, and once more before the commit.  *)
(* A cancel that lands just after a step's checkpoint is the same as the   *)
(* step running first and Cancel after it.                                 *)
(*                                                                         *)
(* Slice values: "prior" = carried from the previous snapshot by           *)
(* preserveOptionalDetails or priceSeriesWithPriorFallback, "fresh" =      *)
(* fetched in this run, "none" = lost.                                     *)
(***************************************************************************)
EXTENDS Naturals, Sequences

CONSTANTS
    ChunkCount,   \* price-history batches of pricesBatchLimit open holdings
    Kinds         \* PDTSyncFailure.Kind values a request may end with

Facets == {"allocation", "xRay", "income"}
Chunks == 1 .. ChunkCount
FailurePhases == {"base", "priceHistory"} \cup Facets

\* PDTSyncFailure.Kind.endsSync.
EndsSync(k) == k \in {"reconnect", "readAccessMissing", "accessPaused", "forbidden", "credentialStore", "rateLimited"}

\* The promise, stated apart from the code's classifier so a classifier change
\* is caught: lost access, or a 429 that outlasted the client's retries.
EndsSyncByContract == {"reconnect", "readAccessMissing", "accessPaused", "forbidden", "credentialStore", "rateLimited"}

\* Statements that run before the final throwIfCancelled. A cancel that lands
\* here must stop the refresh before it writes anything.
BeforeFinalCheck == {"start", "base", "priceHistory", "priceChunk", "priceMerge", "performance"} \cup Facets
AfterCommit == {"readReset", "storeFailure", "returned"}

VARIABLES
    phase,          \* the statement refresh() runs next, or "returned" / "threw"
    chunk,          \* the price batch the loop is on
    cancelled,      \* the caller's PDTCancellation was cancelled
    started,        \* refresh() passed its first checkpoint
    syncEnded,      \* `syncEnded` local in refresh()
    failures,       \* `failures` local, the phase of each recorded PDTSyncFailure
    snap,           \* facets of the in-memory `snapshot` local
    chunkRes,       \* "pending" | "ok" | "failed": `points` / `failedQuoteIDs` per batch
    prices,         \* `snapshot.priceSeries`, per batch
    outcome,        \* PDTBackgroundDetailRefreshOutcome
    writes,         \* SnapshotStore snapshot writes in this run
    readReset,      \* refreshedPulse pruned the pulse read state
    storedFailure,  \* SnapshotStore.lastSyncFailure(): "earlierRun", "none", or a phase
    \* ghosts for properties
    ended,          \* a failure the contract says ends the sync was recorded
    lateRequest,    \* a request was sent after `ended`
    cancelEarly     \* Cancel landed before the final throwIfCancelled

vars == <<phase, chunk, cancelled, started, syncEnded, failures, snap, chunkRes, prices,
          outcome, writes, readReset, storedFailure, ended, lateRequest, cancelEarly>>

LastFailure == IF failures = <<>> THEN "none" ELSE failures[Len(failures)]

NextOf(p) ==
    CASE p = "allocation" -> "xRay"
      [] p = "xRay" -> "income"
      [] p = "income" -> "priceHistory"

\* record(_:): append the failure; a kind that endsSync sets syncEnded.
Record(p, k) ==
    /\ failures' = Append(failures, p)
    /\ syncEnded' = (syncEnded \/ EndsSync(k))
    /\ ended' = (ended \/ k \in EndsSyncByContract)

Init ==
    /\ phase = "start"
    /\ chunk = 1
    /\ cancelled = FALSE
    /\ started = FALSE
    /\ syncEnded = FALSE
    /\ failures = <<>>
    /\ snap = [f \in Facets |-> "prior"]
    /\ chunkRes = [c \in Chunks |-> "pending"]
    /\ prices = [c \in Chunks |-> "prior"]
    /\ outcome = "none"
    /\ writes = 0
    /\ readReset = FALSE
    /\ storedFailure = "earlierRun"
    /\ ended = FALSE
    /\ lateRequest = FALSE
    /\ cancelEarly = FALSE

-----------------------------------------------------------------------------
(* refresh()                                                               *)

\* The caller cancels: applicationWillTerminate calls PDTCancellation.cancel
\* (Sources/PDTBarApp/main.swift).
Cancel ==
    /\ ~cancelled
    /\ phase \notin {"returned", "threw"}
    /\ cancelled' = TRUE
    /\ cancelEarly' = (phase \in BeforeFinalCheck)
    /\ UNCHANGED <<phase, chunk, started, syncEnded, failures, snap, chunkRes, prices>>
    /\ UNCHANGED <<outcome, writes, readReset, storedFailure, ended, lateRequest>>

\* throwIfCancelled, setLastSyncFailure(nil), loadPriorSnapshotResult.
Start ==
    /\ phase = "start"
    /\ IF cancelled
         THEN /\ phase' = "threw"
              /\ UNCHANGED <<started, storedFailure>>
         ELSE /\ phase' = "base"
              /\ started' = TRUE
              /\ storedFailure' = "none"
    /\ UNCHANGED <<chunk, cancelled, syncEnded, failures, snap, chunkRes, prices>>
    /\ UNCHANGED <<outcome, writes, readReset, ended, lateRequest, cancelEarly>>

\* getAllReportingAttempts(.holdings()). Success, throwIfCancelled, then
\* preserveOptionalDetails, which keeps every prior facet and price series
\* (snap and prices start "prior"). A failure: the catch's throwIfCancelled,
\* setLastSyncFailure with the base failure, rethrow. No snapshot exists yet.
Base ==
    /\ phase = "base"
    /\ IF cancelled
         THEN /\ phase' = "threw"
              /\ UNCHANGED storedFailure
         ELSE \/ /\ phase' = "allocation"
                 /\ UNCHANGED storedFailure
              \/ /\ phase' = "threw"
                 /\ storedFailure' = "base"
    /\ UNCHANGED <<chunk, cancelled, started, syncEnded, failures, snap, chunkRes, prices>>
    /\ UNCHANGED <<outcome, writes, readReset, ended, lateRequest, cancelEarly>>

\* optionalPhase(.allocation / .xRay / .income): the `!syncEnded` guard skips
\* the phase with no request and no checkpoint. Otherwise fill() sends its
\* requests. Success sets the facet. A PhaseFailed is recorded and the facet
\* keeps the prior. Then throwIfCancelled. Income's two requests and X-ray's
\* pages are one call here.
Optional(p) ==
    /\ phase = p
    /\ IF syncEnded
         THEN /\ phase' = NextOf(p)
              /\ UNCHANGED <<syncEnded, failures, snap, ended, lateRequest>>
         ELSE IF cancelled
         THEN /\ phase' = "threw"
              /\ UNCHANGED <<syncEnded, failures, snap, ended, lateRequest>>
         ELSE /\ lateRequest' = (lateRequest \/ ended)
              /\ \/ /\ snap' = [snap EXCEPT ![p] = "fresh"]
                    /\ UNCHANGED <<syncEnded, failures, ended>>
                 \/ \E k \in Kinds :
                       /\ Record(p, k)
                       /\ UNCHANGED snap
              /\ phase' = NextOf(p)
    /\ UNCHANGED <<chunk, cancelled, started, chunkRes, prices>>
    /\ UNCHANGED <<outcome, writes, readReset, storedFailure, cancelEarly>>

\* `if !syncEnded` around the price-history block. Skipping it leaves the
\* preserved prior series in place.
PriceEnter ==
    /\ phase = "priceHistory"
    /\ phase' = IF syncEnded THEN "performance" ELSE "priceChunk"
    /\ UNCHANGED <<chunk, cancelled, started, syncEnded, failures, snap, chunkRes, prices>>
    /\ UNCHANGED <<outcome, writes, readReset, storedFailure, ended, lateRequest, cancelEarly>>

AdvanceChunk ==
    IF chunk = ChunkCount
      THEN /\ phase' = "priceMerge"
           /\ UNCHANGED chunk
      ELSE /\ chunk' = chunk + 1
           /\ UNCHANGED phase

\* One pass of the batch loop. Once syncEnded, the batch joins failedQuoteIDs
\* with no request. Otherwise fetch(.pricesBatch): success adds its points, a
\* PhaseFailed is recorded and the batch joins failedQuoteIDs. The loop has
\* no checkpoint of its own; only the client's cancel check runs.
PriceChunk ==
    /\ phase = "priceChunk"
    /\ IF syncEnded
         THEN /\ chunkRes' = [chunkRes EXCEPT ![chunk] = "failed"]
              /\ AdvanceChunk
              /\ UNCHANGED <<syncEnded, failures, ended, lateRequest>>
         ELSE IF cancelled
         THEN /\ phase' = "threw"
              /\ UNCHANGED <<chunk, chunkRes, syncEnded, failures, ended, lateRequest>>
         ELSE /\ lateRequest' = (lateRequest \/ ended)
              /\ \/ /\ chunkRes' = [chunkRes EXCEPT ![chunk] = "ok"]
                    /\ UNCHANGED <<syncEnded, failures, ended>>
                 \/ \E k \in Kinds :
                       /\ Record("priceHistory", k)
                       /\ chunkRes' = [chunkRes EXCEPT ![chunk] = "failed"]
              /\ AdvanceChunk
    /\ UNCHANGED <<cancelled, started, snap, prices>>
    /\ UNCHANGED <<outcome, writes, readReset, storedFailure, cancelEarly>>

\* throwIfCancelled after the loop, then priceSeriesWithPriorFallback: the
\* refreshed points plus the prior series of every failed quote id.
PriceMerge ==
    /\ phase = "priceMerge"
    /\ IF cancelled
         THEN /\ phase' = "threw"
              /\ UNCHANGED prices
         ELSE /\ phase' = "performance"
              /\ prices' = [c \in Chunks |-> IF chunkRes[c] = "ok" THEN "fresh" ELSE "prior"]
    /\ UNCHANGED <<chunk, cancelled, started, syncEnded, failures, snap, chunkRes>>
    /\ UNCHANGED <<outcome, writes, readReset, storedFailure, ended, lateRequest, cancelEarly>>

\* progress(.performance, "Performance unavailable"), then the last
\* throwIfCancelled. Nothing from here to the return checks the flag.
Performance ==
    /\ phase = "performance"
    /\ phase' = IF cancelled THEN "threw" ELSE "commit"
    /\ UNCHANGED <<chunk, cancelled, started, syncEnded, failures, snap, chunkRes, prices>>
    /\ UNCHANGED <<outcome, writes, readReset, storedFailure, ended, lateRequest, cancelEarly>>

\* `failures.isEmpty ? .completed : .degraded`, then PressureRunner.refreshedPulse
\* calls SnapshotStore.commitCurrentSnapshot: the re-crossed read marks go,
\* then the snapshot is written (formal/pulse-read-state checks that order).
Commit ==
    /\ phase = "commit"
    /\ outcome' = IF failures = <<>> THEN "completed" ELSE "degraded"
    /\ writes' = writes + 1
    /\ phase' = "readReset"
    /\ UNCHANGED <<chunk, cancelled, started, syncEnded, failures, snap, chunkRes, prices>>
    /\ UNCHANGED <<readReset, storedFailure, ended, lateRequest, cancelEarly>>

\* refreshedPulse: displayReadState, then lifecycleResult prunes stale read
\* marks (readStateAfterPruningStaleItems).
ReadReset ==
    /\ phase = "readReset"
    /\ readReset' = TRUE
    /\ phase' = "storeFailure"
    /\ UNCHANGED <<chunk, cancelled, started, syncEnded, failures, snap, chunkRes, prices>>
    /\ UNCHANGED <<outcome, writes, storedFailure, ended, lateRequest, cancelEarly>>

\* setLastSyncFailure(failures.last), then return.
StoreFailure ==
    /\ phase = "storeFailure"
    /\ storedFailure' = LastFailure
    /\ phase' = "returned"
    /\ UNCHANGED <<chunk, cancelled, started, syncEnded, failures, snap, chunkRes, prices>>
    /\ UNCHANGED <<outcome, writes, readReset, ended, lateRequest, cancelEarly>>

Finished ==
    /\ phase \in {"returned", "threw"}
    /\ UNCHANGED vars

Next ==
    \/ Cancel \/ Start \/ Base \/ \E p \in Facets : Optional(p)
    \/ PriceEnter \/ PriceChunk \/ PriceMerge \/ Performance
    \/ Commit \/ ReadReset \/ StoreFailure
    \/ Finished

Spec == Init /\ [][Next]_vars /\ WF_vars(Next)

-----------------------------------------------------------------------------
(* Properties                                                              *)

TypeOK ==
    /\ phase \in {"start", "base", "priceHistory", "priceChunk", "priceMerge", "performance",
                  "commit", "readReset", "storeFailure", "returned", "threw"} \cup Facets
    /\ chunk \in Chunks
    /\ failures \in Seq(FailurePhases)
    /\ snap \in [Facets -> {"prior", "fresh", "none"}]
    /\ chunkRes \in [Chunks -> {"pending", "ok", "failed"}]
    /\ prices \in [Chunks -> {"prior", "fresh", "none"}]
    /\ outcome \in {"none", "completed", "degraded"}
    /\ writes \in Nat
    /\ storedFailure \in {"earlierRun", "none"} \cup FailurePhases

\* The store is written at most once, and only by the commit after the last phase.
OneCommitAtEnd == writes <= 1 /\ (writes = 1 => phase \in AfterCommit)

\* A failed base, or a cancel before the final checkpoint, leaves the snapshot
\* and the read state as the last good run left them.
AbortWritesNothing == (phase = "threw" \/ cancelEarly) => (writes = 0 /\ ~readReset)

\* Once a failure that ends the sync is recorded, no later request is sent.
NoRequestAfterSyncEnded == ~lateRequest

\* "fresh" is only set by a successful fetch, so a facet or price batch that
\* failed or was skipped keeps the prior.
FailedSliceKeepsPrior ==
    /\ \A f \in Facets : snap[f] \in {"prior", "fresh"}
    /\ \A c \in Chunks : prices[c] \in {"prior", "fresh"}

\* `degraded` exactly when some facet or price batch was not refreshed.
OutcomeHonest ==
    outcome /= "none" =>
        (outcome = "completed" <=> (\A f \in Facets : snap[f] = "fresh") /\ (\A c \in Chunks : prices[c] = "fresh"))

\* After the first checkpoint, the stored failure is never an earlier run's,
\* and a returned refresh leaves its own last failure, or none.
StoredFailureIsThisRuns ==
    /\ started => storedFailure /= "earlierRun"
    /\ phase = "returned" => storedFailure = LastFailure

\* The refresh always returns or throws, cancelled or not.
Terminates == <>(phase \in {"returned", "threw"})

=============================================================================
