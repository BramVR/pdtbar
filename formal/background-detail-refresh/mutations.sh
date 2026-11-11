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
  printf '%-26s expect %-24s got %s\n' "$name" "$expect" "${got:-error}"
  if [[ "$got" != *"$expect"* ]]; then
    failures=$((failures + 1))
  fi
}

# The Claude refresh's shape: an optional phase that refreshed its facet commits it.
mutate perPhaseCommit OneCommitAtEnd \
  "    /\\ UNCHANGED <<chunk, cancelled, chunkRes, prices>>
    /\\ UNCHANGED <<outcome, writes, readReset, storedFailure, cancelEarly>>" \
  "    /\\ UNCHANGED <<chunk, cancelled, chunkRes, prices>>
    /\\ writes' = IF snap' /= snap THEN writes + 1 ELSE writes
    /\\ UNCHANGED <<outcome, readReset, storedFailure, cancelEarly>>"

# optionalPhase loses its `guard !syncEnded`.
mutate optionalIgnoresSyncEnded NoRequestAfterSyncEnded \
  "    /\\ IF syncEnded
         THEN /\\ phase' = NextOf(p)" \
  "    /\\ IF FALSE
         THEN /\\ phase' = NextOf(p)"

# The price loop loses its per-batch `if syncEnded`.
mutate priceIgnoresSyncEnded NoRequestAfterSyncEnded \
  "    /\\ IF syncEnded
         THEN /\\ chunkRes' = [chunkRes EXCEPT ![chunk] = \"failed\"]" \
  "    /\\ IF FALSE
         THEN /\\ chunkRes' = [chunkRes EXCEPT ![chunk] = \"failed\"]"

# endsSync drops .rateLimited, so a 429 that outlasted the retries is followed by more requests.
mutate rateLimitKeepsSyncing NoRequestAfterSyncEnded \
  'EndsSync(k) == k \in {"reconnect", "readAccessMissing", "accessPaused", "forbidden", "credentialStore", "rateLimited"}' \
  'EndsSync(k) == k \in {"reconnect", "readAccessMissing", "accessPaused", "forbidden", "credentialStore"}'

# A failed optional phase clears its facet instead of keeping the prior.
mutate failedPhaseDropsPrior FailedSliceKeepsPrior \
  "                           /\\ Record(p, k)
                           /\\ UNCHANGED <<snap, pagesBehind>>" \
  "                           /\\ Record(p, k)
                           /\\ snap' = [snap EXCEPT ![p] = \"none\"]
                           /\\ UNCHANGED pagesBehind"

# The outcome stops reading `failures`.
mutate outcomeIgnoresFailures OutcomeHonest \
  "    /\\ outcome' = IF failures = <<>> THEN \"completed\" ELSE \"degraded\"" \
  "    /\\ outcome' = \"completed\""

# refresh() stops clearing the stored failure before it starts.
mutate noFailureClearAtStart StoredFailureIsThisRuns \
  "    /\\ storedFailure' = \"none\"" \
  "    /\\ storedFailure' = storedFailure"

# The #289 fix reverted: throwIfCancelled runs before setLastSyncFailure(nil).
mutate cancelBeforeFailureClear StoredFailureIsThisRuns \
  "    /\\ storedFailure' = \"none\"" \
  "    /\\ storedFailure' = IF cancelled THEN storedFailure ELSE \"none\""

# #275's shape: a call that read no page (a slow or failed first page) returns an empty list as success.
mutate zeroPageCommits FreshFacetReadEveryPage \
  "                    IF read = PagesOf(p)" \
  "                    IF read = PagesOf(p) \\/ (read = 0 /\\ PagesOf(p) > 1)"

# A call that failed after some pages returns the rows it collected as success.
mutate partialPagesCommit FreshFacetReadEveryPage \
  "                    IF read = PagesOf(p)" \
  "                    IF read > 0"

# The throwIfCancelled before refreshedPulse is dropped.
mutate noFinalCancelCheck AbortWritesNothing \
  "    /\\ phase' = IF cancelled THEN \"threw\" ELSE \"commit\"" \
  "    /\\ phase' = \"commit\""

exit "$failures"
