#!/usr/bin/env bash
# Replays each one-line code break against a scratch copy of the model and
# prints which property catches it. Every row must report a violation; "No
# error" means the model lost its teeth.
# Usage: formal/background-detail-refresh/mutations.sh
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
runner="$here/../../Scripts/formal/tlc.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failures=0
mutate() {
  local name="$1" expect="$2" old="$3" new="$4"
  mkdir -p "$work/$name"
  python3 - "$here/BackgroundDetailRefresh.tla" "$work/$name/BackgroundDetailRefresh.tla" "$old" "$new" <<'PY'
import sys
src, dst, old, new = sys.argv[1:]
text = open(src).read()
if text.count(old) != 1:
    sys.exit(f"mutation anchor must occur exactly once: {old!r}")
open(dst, "w").write(text.replace(old, new))
PY
  cp "$here/BackgroundDetailRefresh.cfg" "$work/$name/BackgroundDetailRefresh.cfg"
  local got
  got="$("$runner" "$work/$name/BackgroundDetailRefresh.tla" "$work/$name/BackgroundDetailRefresh.cfg" 2>&1 |
    grep -oE 'Invariant [A-Za-z]+ is violated|Temporal properties were violated|No error has been found' |
    head -1 || true)"
  printf '%-28s expect %-28s got %s\n' "$name" "$expect" "${got:-error}"
  if [[ "$got" != *"$expect"* ]]; then
    failures=$((failures + 1))
  fi
}

# The #272 shape: price history's returned diagnostics never reach the
# outage gate, so performance starts during an outage (21-state trace).
mutate priceOutageBypassesGate NoPhaseAfterOutage \
  "    /\\ diagOutage' = (diagOutage \\/ accUnavail)" \
  "    /\\ diagOutage' = diagOutage"

# A thrown optional-phase failure stops feeding the gate.
mutate thrownOutageBypassesGate NoPhaseAfterOutage \
  "        /\\ diagOutage' = (diagOutage \\/ IndicatesUnavailableSetup(c))" \
  "        /\\ diagOutage' = diagOutage"

# runOptionalPhase's guard removed.
mutate noOutageGuard NoPhaseAfterOutage \
  '    /\ LET t == IF diagOutage THEN "finalize"' \
  '    /\ LET t == IF FALSE THEN "finalize"'

# PressureRunner.refreshedPulse never commits the final snapshot.
mutate finalizeSkipsCommit ReturnedHasSucceededPhases \
  "    /\\ store' = snap
    /\\ everFresh' = everFresh \\cup Fresh(store')
    /\\ phase' = \"returned\"" \
  "    /\\ store' = store
    /\\ everFresh' = everFresh \\cup Fresh(store')
    /\\ phase' = \"returned\""

# Price-history diagnostics dropped before the outcome is computed.
mutate dropPriceDiagnostics OutcomeHonest \
  "    /\\ diagPhases' = IF failedQ /= {} THEN diagPhases \\cup {\"priceHistory\"} ELSE diagPhases" \
  "    /\\ diagPhases' = diagPhases"

# isRetryable starts retrying a deterministic decode failure.
mutate decodeRetryable NoDeterministicRetry \
  'IsRetryable(c) == c \in {"transientFailure", "timeout", "exit"}' \
  'IsRetryable(c) == c \in {"transientFailure", "timeout", "exit", "decode"}'

# workerCount ignores priceHistoryConcurrencyLimit.
mutate unboundedWorkers ConcurrencyBound \
  'Workers == 1 .. (IF Limit < HoldingCount THEN Limit ELSE HoldingCount)' \
  'Workers == 1 .. HoldingCount'

exit "$failures"
