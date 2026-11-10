#!/usr/bin/env bash
# Replays each one-line code break against a scratch copy of the model and
# prints which property catches it. Every row must report a violation; "No
# error" means the model lost its teeth. A row's last column lists invariants
# dropped for that row, so the property under test is the one that reports.
# Usage: formal/claude-login-process/mutations.sh
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
runner="$here/../../Scripts/formal/tlc.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failures=0
mutate() {
  local name="$1" expect="$2" drop="$3" old="$4" new="$5"
  mkdir -p "$work/$name"
  python3 - "$here/ClaudeLoginProcess.tla" "$work/$name/ClaudeLoginProcess.tla" "$old" "$new" <<'PY'
import sys
src, dst, old, new = sys.argv[1:]
text = open(src).read()
if text.count(old) != 1:
    sys.exit(f"mutation anchor must occur exactly once: {old!r}")
open(dst, "w").write(text.replace(old, new))
PY
  grep -v -x -F "    $drop" "$here/ClaudeLoginProcess.cfg" > "$work/$name/ClaudeLoginProcess.cfg"
  local got
  got="$("$runner" "$work/$name/ClaudeLoginProcess.tla" "$work/$name/ClaudeLoginProcess.cfg" 2>&1 |
    grep -oE 'Invariant [A-Za-z]+ is violated|Temporal properties were violated|No error has been found' |
    head -1 || true)"
  printf '%-22s expect %-24s got %s\n' "$name" "$expect" "${got:-error}"
  if [[ "$got" != *"$expect"* ]]; then
    failures=$((failures + 1))
  fi
}

# The #271 shape: once root has exited, cleanup kills only what a root scan
# can reach, so a reparented or TERM-ignoring helper survives.
mutate rootDeadSkipsGroup NoOrphanOnReturn - \
  'IF kid[a] = "alive" THEN "dead" ELSE kid[a]]
    /\ root'"'"' = [root EXCEPT ![a] = "dead"]' \
  'IF kid[a] = "alive" /\ root[a] = "alive" THEN "dead" ELSE kid[a]]
    /\ root'"'"' = [root EXCEPT ![a] = "dead"]'

# No group SIGKILL at all (processGroup nil): only root is killed.
mutate noGroupKill NoOrphanOnReturn - \
  'IF kid[a] = "alive" THEN "dead" ELSE kid[a]]
    /\ root'"'"' = [root EXCEPT ![a] = "dead"]' \
  'kid[a]]
    /\ root'"'"' = [root EXCEPT ![a] = "dead"]'

# main.swift gate guard removed.
mutate noGateGuard StaleResultNeverApplied - \
  'IF gateActive = a' \
  'IF TRUE'

# SIGKILL escalation removed: waitpid hangs on a TERM-ignoring root.
mutate noKillEscalation "Temporal properties" NoOrphanOnReturn \
  '/\ root'"'"' = [root EXCEPT ![a] = "dead"]
    /\ exitStatus'"'"' = [exitStatus EXCEPT ![a] =
                       IF root[a] = "alive" THEN "signal" ELSE exitStatus[a]]
    /\ SetPC(a, "cleanReap")' \
  '/\ UNCHANGED <<root, exitStatus>>
    /\ SetPC(a, "cleanReap")'

# Child ended on errors only: a normal return skips end().
mutate cleanupOnErrorsOnly RootDeadOnReturn NoOrphanOnReturn \
  '    /\ SetPC(a, "cleanTerm")
    /\ SetOutcome(a,
         IF cancelled[a] THEN "cancelled"' \
  '    /\ SetPC(a, IF cancelled[a] THEN "cleanTerm" ELSE "returned")
    /\ SetOutcome(a,
         IF cancelled[a] THEN "cancelled"'

# runBlocking maps a timeout to .cancelled, which the handoff drops.
mutate timeoutAsCancelled "Temporal properties" - \
  'ELSE "timedOut")' \
  'ELSE "cancelled")'

exit "$failures"
