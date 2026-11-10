------------------------------ MODULE ClaudeLoginProcess ------------------------------
(***************************************************************************)
(* "Log in with Claude" from click to cleanup.                            *)
(*                                                                         *)
(* PDTBarApp.loginWithClaude takes a ClaudeLoginAttemptGate ticket and     *)
(* calls ClaudeCLILoginHandoff.startLogin, which cancels the previous     *)
(* attempt and runs ClaudeLocalLoginRunner on a detached task. The runner *)
(* drives `claude auth login` in a PTY (TTYCommandRunner.run). The child *)
(* is a ChildProcessGroup: on every exit path after launch, end() or its  *)
(* deinit signals the whole process group and reaps root last. The result *)
(* goes back to the main queue, where the gate drops it unless it is      *)
(* still the latest.                                                       *)
(*                                                                         *)
(* Files: Sources/PDTBarApp/main.swift (M),                               *)
(*        Sources/PDTBarAppSupport/ClaudeLocalConnection.swift (C),       *)
(*        Sources/PDTBarAppSupport/ChildProcessGroup.swift (G),           *)
(*        Sources/PDTBarCore/LaunchRuntime.swift (L).                     *)
(*                                                                         *)
(* The `claude auth login` process is `root`. `kid` stands for any        *)
(* process root spawns (a helper, a browser opener). It inherits root's   *)
(* process group, which posix_spawn creates with root's pid (G:48). Root  *)
(* stays unreaped until CleanReap, so that group id stays reserved and a  *)
(* group signal reaches kid even after kid is reparented to launchd.      *)
(***************************************************************************)
EXTENDS Naturals

CONSTANTS
    MaxClicks             \* how many "Log in with Claude" clicks to explore

Attempts == 1..MaxClicks
None == 0
Finished == {"returned", "done"}

VARIABLES
    clicks,        \* ClaudeLoginAttemptGate.nextAttempt (L:120)
    gateActive,    \* ClaudeLoginAttemptGate.activeAttempt, None = nil (L:121)
    handoffActive, \* ClaudeCLILoginHandoff.activeCancellation by attempt (M:1141)
    cancelled,     \* PDTCancellation.cancelled per attempt (PDTCancellation.swift:6)
    pc,            \* where each attempt's runner thread is
    root,          \* `claude auth login`: "none" | "alive" | "dead"
    kid,           \* a process root spawned: "none" | "alive" | "dead"
    marker,        \* root printed a success substring (C:851 successSubstrings)
    exitStatus,    \* root's exit: "none" | "zero" | "nonzero" | "signal"
    outcome,       \* ClaudeLocalLoginOutcome per attempt (C:764)
    pending,       \* completion queued on DispatchQueue.main (M:330)
    applied,       \* times the app applied this attempt's result (M:334-345)
    staleApplied   \* history: a result was applied while a newer click existed

vars == <<clicks, gateActive, handoffActive, cancelled, pc, root, kid,
          marker, exitStatus, outcome, pending, applied, staleApplied>>

PCs == {"idle", "start", "launch", "delay", "loop", "postloop",
        "cleanTerm", "cleanWait", "cleanReap", "returned", "done"}
Outcomes == {"none", "success", "failed", "timedOut", "cancelled"}

TypeOK ==
    /\ clicks \in 0..MaxClicks
    /\ gateActive \in Attempts \cup {None}
    /\ handoffActive \in Attempts \cup {None}
    /\ cancelled \in [Attempts -> BOOLEAN]
    /\ pc \in [Attempts -> PCs]
    /\ root \in [Attempts -> {"none", "alive", "dead"}]
    /\ kid \in [Attempts -> {"none", "alive", "dead"}]
    /\ marker \in [Attempts -> BOOLEAN]
    /\ exitStatus \in [Attempts -> {"none", "zero", "nonzero", "signal"}]
    /\ outcome \in [Attempts -> Outcomes]
    /\ pending \in [Attempts -> BOOLEAN]
    /\ applied \in [Attempts -> 0..2]
    /\ staleApplied \in BOOLEAN

Init ==
    /\ clicks = 0
    /\ gateActive = None
    /\ handoffActive = None
    /\ cancelled = [a \in Attempts |-> FALSE]
    /\ pc = [a \in Attempts |-> "idle"]
    /\ root = [a \in Attempts |-> "none"]
    /\ kid = [a \in Attempts |-> "none"]
    /\ marker = [a \in Attempts |-> FALSE]
    /\ exitStatus = [a \in Attempts |-> "none"]
    /\ outcome = [a \in Attempts |-> "none"]
    /\ pending = [a \in Attempts |-> FALSE]
    /\ applied = [a \in Attempts |-> 0]
    /\ staleApplied = FALSE

SetPC(a, s) == pc' = [pc EXCEPT ![a] = s]
SetOutcome(a, o) == outcome' = [outcome EXCEPT ![a] = o]

(***************************************************************************)
(* Main thread: the click.                                                 *)
(***************************************************************************)

\* M:326 loginWithClaude -> L:125 ClaudeLoginAttemptGate.begin, then
\* M:1153 startLogin: cancel the previous attempt (M:1156), install the new
\* cancellation (M:1157), and start the detached task (M:1159).
Click ==
    /\ clicks < MaxClicks
    /\ LET a == clicks + 1 IN
         /\ clicks' = a
         /\ gateActive' = a
         /\ cancelled' = IF handoffActive = None THEN cancelled
                         ELSE [cancelled EXCEPT ![handoffActive] = TRUE]
         /\ handoffActive' = a
         /\ SetPC(a, "start")
    /\ UNCHANGED <<root, kid, marker, exitStatus, outcome, pending,
                   applied, staleApplied>>

(***************************************************************************)
(* Runner thread, one per attempt.                                         *)
(***************************************************************************)

\* C:848 runPTY's guard and C:1177 TTYCommandRunner.run's first check.
Start(a) ==
    /\ pc[a] = "start"
    /\ IF cancelled[a]
         THEN SetPC(a, "returned") /\ SetOutcome(a, "cancelled")
         ELSE SetPC(a, "launch") /\ UNCHANGED outcome
    /\ UNCHANGED <<clicks, gateActive, handoffActive, cancelled, root, kid,
                   marker, exitStatus, pending, applied, staleApplied>>

\* C:1241 ChildProcessGroup.spawn succeeds. From here the child owns root's
\* group. No cancellation check sits between Start and here, so a click can
\* cancel in between.
Launch(a) ==
    /\ pc[a] = "launch"
    /\ SetPC(a, "delay")
    /\ root' = [root EXCEPT ![a] = "alive"]
    /\ UNCHANGED <<clicks, gateActive, handoffActive, cancelled, kid,
                   marker, exitStatus, outcome, pending, applied, staleApplied>>

\* C:1188 binaryNotFound, C:1196 openpty failure, or C:1251 launchFailed.
\* Nothing launched, so no child exists to end. C:833-837 maps a generic
\* launch error to .cancelled when the attempt was cancelled.
LaunchFails(a) ==
    /\ pc[a] = "launch"
    /\ SetPC(a, "returned")
    /\ SetOutcome(a, IF cancelled[a] THEN "cancelled" ELSE "failed")
    /\ UNCHANGED <<clicks, gateActive, handoffActive, cancelled, root, kid,
                   marker, exitStatus, pending, applied, staleApplied>>

\* C:1297 cancellation check after the initial delay. A throw ends the
\* child through its deinit (G:111) before run() returns.
AfterDelay(a) ==
    /\ pc[a] = "delay"
    /\ IF cancelled[a]
         THEN SetPC(a, "cleanTerm") /\ SetOutcome(a, "cancelled")
         ELSE SetPC(a, "loop") /\ UNCHANGED outcome
    /\ UNCHANGED <<clicks, gateActive, handoffActive, cancelled, root, kid,
                   marker, exitStatus, pending, applied, staleApplied>>

\* C:1403 cancellation check at the top of the read loop.
LoopCancelled(a) ==
    /\ pc[a] = "loop"
    /\ cancelled[a]
    /\ SetPC(a, "cleanTerm")
    /\ SetOutcome(a, "cancelled")
    /\ UNCHANGED <<clicks, gateActive, handoffActive, cancelled, root, kid,
                   marker, exitStatus, pending, applied, staleApplied>>

\* C:1418 processChunk matched a stopOnSubstrings needle: stoppedEarly.
LoopStopOnMarker(a) ==
    /\ pc[a] = "loop"
    /\ marker[a]
    /\ SetPC(a, "postloop")
    /\ UNCHANGED <<clicks, gateActive, handoffActive, cancelled, root, kid,
                   marker, exitStatus, outcome, pending, applied,
                   staleApplied>>

\* C:1435 `if !child.isRunning { break }`, a non-reaping poll (G:99).
LoopProcessExited(a) ==
    /\ pc[a] = "loop"
    /\ root[a] = "dead"
    /\ SetPC(a, "postloop")
    /\ UNCHANGED <<clicks, gateActive, handoffActive, cancelled, root, kid,
                   marker, exitStatus, outcome, pending, applied,
                   staleApplied>>

\* C:1402 `while Date() < deadline` ends (120 s, M:1164).
LoopDeadline(a) ==
    /\ pc[a] = "loop"
    /\ SetPC(a, "postloop")
    /\ UNCHANGED <<clicks, gateActive, handoffActive, cancelled, root, kid,
                   marker, exitStatus, outcome, pending, applied,
                   staleApplied>>

\* C:1439 cancellation check after the loop, then C:1472-1482 build the
\* Result from end()'s natural exit status and C:820-826 runBlocking
\* classifies it. end() reads that status (G:116) before it signals, so it
\* matches root's state here. The settle (C:1445) and drain (C:1464) read
\* any marker already written, so `marker` stands for "the buffer holds a
\* success substring".
PostLoop(a) ==
    /\ pc[a] = "postloop"
    /\ SetPC(a, "cleanTerm")
    /\ SetOutcome(a,
         IF cancelled[a] THEN "cancelled"
         ELSE IF marker[a] THEN "success"
         ELSE IF root[a] = "dead"
           THEN IF exitStatus[a] = "zero" THEN "success" ELSE "failed"
         ELSE "timedOut")
    /\ UNCHANGED <<clicks, gateActive, handoffActive, cancelled, root, kid,
                   marker, exitStatus, pending, applied, staleApplied>>

\* G:115 terminate(), reached from end() (C:1472) or, on a throw, from the
\* deinit (G:111). G:116 reads root's natural exit, then G:117
\* kill(-pid, SIGTERM) signals the whole group. Each live process may exit
\* now or keep running (it handles or ignores SIGTERM).
CleanTerm(a) ==
    /\ pc[a] = "cleanTerm"
    /\ \E rootDies, kidDies \in BOOLEAN :
         /\ root' = [root EXCEPT ![a] =
                       IF root[a] = "alive" /\ rootDies THEN "dead" ELSE root[a]]
         /\ exitStatus' = [exitStatus EXCEPT ![a] =
                       IF root[a] = "alive" /\ rootDies THEN "signal"
                       ELSE exitStatus[a]]
         /\ kid' = [kid EXCEPT ![a] =
                       IF kid[a] = "alive" /\ kidDies THEN "dead" ELSE kid[a]]
    /\ SetPC(a, "cleanWait")
    /\ UNCHANGED <<clicks, gateActive, handoffActive, cancelled, marker,
                   outcome, pending, applied, staleApplied>>

\* G:118-122 wait up to 2 s for root to exit, then G:125 kill(-pid, SIGKILL)
\* on every path, whether or not root is still running.
CleanWait(a) ==
    /\ pc[a] = "cleanWait"
    /\ kid' = [kid EXCEPT ![a] = IF kid[a] = "alive" THEN "dead" ELSE kid[a]]
    /\ root' = [root EXCEPT ![a] = "dead"]
    /\ exitStatus' = [exitStatus EXCEPT ![a] =
                       IF root[a] = "alive" THEN "signal" ELSE exitStatus[a]]
    /\ SetPC(a, "cleanReap")
    /\ UNCHANGED <<clicks, gateActive, handoffActive, cancelled, marker,
                   outcome, pending, applied, staleApplied>>

\* G:127 waitpid reaps root, which releases the group id; then run()
\* returns or rethrows.
CleanReap(a) ==
    /\ pc[a] = "cleanReap"
    /\ root[a] # "alive"
    /\ SetPC(a, "returned")
    /\ UNCHANGED <<clicks, gateActive, handoffActive, cancelled, root, kid,
                   marker, exitStatus, outcome, pending, applied,
                   staleApplied>>

\* M:1170 clearActiveCancellation, then M:1171-1176: success and failure
\* call the completion, which queues onto the main queue (M:330); .cancelled
\* is dropped (M:1174).
Deliver(a) ==
    /\ pc[a] = "returned"
    /\ SetPC(a, "done")
    /\ handoffActive' = IF handoffActive = a THEN None ELSE handoffActive
    /\ pending' = [pending EXCEPT ![a] = (outcome[a] # "cancelled")]
    /\ UNCHANGED <<clicks, gateActive, cancelled, root, kid, marker,
                   exitStatus, outcome, applied, staleApplied>>

(***************************************************************************)
(* Main thread: applying the result.                                      *)
(***************************************************************************)

\* M:331 `guard self.claudeLoginAttemptGate.finish(attempt)` (L:135):
\* applied only while this attempt is still the gate's active one, then
\* M:334-345 completeLoginHandoff.
ApplyOnMain(a) ==
    /\ pending[a]
    /\ pending' = [pending EXCEPT ![a] = FALSE]
    /\ IF gateActive = a
         THEN /\ gateActive' = None
              /\ applied' = [applied EXCEPT ![a] = @ + 1]
              /\ staleApplied' = (staleApplied \/ a # clicks)
         ELSE UNCHANGED <<gateActive, applied, staleApplied>>
    /\ UNCHANGED <<clicks, handoffActive, cancelled, pc, root, kid,
                   marker, exitStatus, outcome>>

(***************************************************************************)
(* The `claude auth login` process tree. No fairness: the CLI may never   *)
(* print success, never exit, and spawn a helper at any time.             *)
(***************************************************************************)

RootSpawnsKid(a) ==
    /\ root[a] = "alive"
    /\ kid[a] = "none"
    /\ kid' = [kid EXCEPT ![a] = "alive"]
    /\ UNCHANGED <<clicks, gateActive, handoffActive, cancelled, pc, root,
                   marker, exitStatus, outcome, pending, applied,
                   staleApplied>>

RootPrintsSuccess(a) ==
    /\ root[a] = "alive"
    /\ ~marker[a]
    /\ marker' = [marker EXCEPT ![a] = TRUE]
    /\ UNCHANGED <<clicks, gateActive, handoffActive, cancelled, pc, root,
                   kid, exitStatus, outcome, pending, applied,
                   staleApplied>>

RootExits(a) ==
    /\ root[a] = "alive"
    /\ \E s \in {"zero", "nonzero"} :
         /\ root' = [root EXCEPT ![a] = "dead"]
         /\ exitStatus' = [exitStatus EXCEPT ![a] = s]
    /\ UNCHANGED <<clicks, gateActive, handoffActive, cancelled, pc, kid,
                   marker, outcome, pending, applied, staleApplied>>

Runner(a) ==
    \/ Start(a) \/ Launch(a) \/ LaunchFails(a) \/ AfterDelay(a)
    \/ LoopCancelled(a) \/ LoopStopOnMarker(a) \/ LoopProcessExited(a)
    \/ LoopDeadline(a) \/ PostLoop(a)
    \/ CleanTerm(a) \/ CleanWait(a) \/ CleanReap(a)

Process(a) == RootSpawnsKid(a) \/ RootPrintsSuccess(a) \/ RootExits(a)

\* Every click explored and every attempt fully handled: stop without a
\* deadlock report.
AllSettled ==
    /\ clicks = MaxClicks
    /\ \A a \in Attempts : pc[a] = "done" /\ ~pending[a]
    /\ UNCHANGED vars

Next ==
    \/ Click
    \/ \E a \in Attempts : Runner(a) \/ Deliver(a) \/ ApplyOnMain(a) \/ Process(a)
    \/ AllSettled

\* The runner thread, the detached task, and the main queue make progress.
\* Time passing is fair (the deadline and the 2 s wait end), so the
\* loop and cleanup cannot stall unless blocked on root.
Fairness ==
    \A a \in Attempts :
        /\ WF_vars(Runner(a))
        /\ WF_vars(Deliver(a))
        /\ WF_vars(ApplyOnMain(a))

Spec == Init /\ [][Next]_vars /\ Fairness

(***************************************************************************)
(* Properties.                                                             *)
(***************************************************************************)

\* A login result reaches the menu only from the most recent click.
StaleResultNeverApplied == ~staleApplied

\* When run() has returned, `claude auth login` itself is gone.
RootDeadOnReturn ==
    \A a \in Attempts : pc[a] \in Finished => root[a] # "alive"

\* When run() has returned, nothing root spawned is still running.
NoOrphanOnReturn ==
    \A a \in Attempts : pc[a] \in Finished => kid[a] # "alive"

\* Every started attempt returns exactly once; the runner never hangs.
EveryAttemptReturns ==
    \A a \in Attempts : (pc[a] = "start") ~> (pc[a] = "done")

\* The latest click always resolves in the menu: its success or failure is
\* applied, unless a newer click superseded it.
LatestAttemptResolves ==
    \A a \in Attempts : (pc[a] = "start") ~> (applied[a] = 1 \/ clicks > a)

=============================================================================
