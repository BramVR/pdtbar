#!/usr/bin/env bash
# Replays each one-line code break against the model and prints which invariant catches it.
# Every line must show a violation; "No error" means the model lost its teeth.
# Invariants that already fail on the real code (open findings) are dropped first,
# so each mutation is judged only by the invariants that pass today.
FINDINGS=(BackgroundFlagMatchesWork ProbingMenuTellsTruth SetupMenuMeansIdle ProbeResultNotLost)
set -euo pipefail
cd "$(dirname "$0")"
runner=../../Scripts/formal/tlc.sh
while read -r name expect; do
  [[ -z "$name" || "$name" == \#* ]] && continue
  sed "s/Mutations = {}/Mutations = {$name}/" LaunchRuntime.cfg > .mutation.cfg
  for f in "${FINDINGS[@]}"; do sed -i.bak "/^    $f\$/d" .mutation.cfg; done
  got="$("$runner" LaunchRuntime.tla .mutation.cfg 2>&1 | grep -oE 'Invariant [A-Za-z]+ is violated|No error has been found' | head -1 || true)"
  printf '%-48s expect %-24s got %s\n' "$name" "$expect" "$got"
done <<'LIST'
# Mutations set                                  invariant expected to catch it
"ignoreCachedPulse"                              NoFullFetchOverCache
"noCacheParking"                                 NoFullFetchOverCache
"keepFirstFetchFlag"                             FirstFetchFlagMatchesWork
"noProbeFailedLogin"                             NeverStranded
"noAttemptCheck"                                 SetupReflectsLatestProbe
"noRetryGuard","noAppDedupe"                     OneFetchAtATime
"invertCacheLoadRefreshCheck"                    FetchingMenuTellsTruth
LIST
rm -f .mutation.cfg .mutation.cfg.bak
