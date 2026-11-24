#!/usr/bin/env bash
# Replays each one-line code break against the model and prints which invariant catches it.
# Exits nonzero unless every row reports the invariant it expects.
# Invariants that already fail on the real code (open findings) are dropped first,
# so each mutation is judged only by the invariants that pass today. A row's third
# column lists invariants to drop for that row only.
FINDINGS=()
set -euo pipefail
failures=0
cd "$(dirname "$0")"
runner=../../Scripts/formal/tlc.sh
while read -r name expect drop; do
  [[ -z "$name" || "$name" == \#* ]] && continue
  sed "s/Mutations = {}/Mutations = {$name}/" LaunchRuntime.cfg > .mutation.cfg
  for f in ${FINDINGS[@]+"${FINDINGS[@]}"} $drop; do sed -i.bak "/^    $f\$/d" .mutation.cfg; done
  got="$("$runner" LaunchRuntime.tla .mutation.cfg 2>&1 | grep -oE 'Invariant [A-Za-z]+ is violated|No error has been found' | head -1 || true)"
  printf '%-48s expect %-24s got %s\n' "$name" "$expect" "${got:-error}"
  [[ "$got" == "Invariant $expect is violated" ]] || failures=$((failures + 1))
done <<'LIST'
# Mutations set                                  invariant expected to catch it  dropped for this row
"fetchingOffersSignIn"                           OfferedActionsAreLive
"fetchingOffersDisconnect"                       OfferedActionsAreLive
"fetchingOffersRefresh"                          OfferedActionsAreLive
"fetchingOffersRefresh","noRetryGuard"           OneWorkAtATime           OfferedActionsAreLive
"ignoreCachedPulse"                              NoFullFetchOverCache
"checkDuringCacheLoad"                           OneWorkAtATime
"keepFirstFetchFlag"                             FirstFetchFlagMatchesWork
"failureStaysFetching"                           FetchingMenuTellsTruth
"reconnectHidesPulse"                            ProblemKeepsPulseVisible
"notConnectedShowsPulse"                         NotConnectedShowsSetup
"connectionScreenOffersRefresh"                  OfferedActionsAreLive
"optionalAccessLossStaysConnected"               AccessLossLeavesConnected
"connectionScreenDropsRecord"                    UncommittedRecordKept
"connectionOpDropsRecord"                        UncommittedRecordKept
"checkReadsStoreOnly"                            SignedOutOnlyWithoutCredential
"fetchingHidesNotSaved"                          NotSavedRowTellsTruth
"syncEndReportsSaved"                            NotSavedRowTellsTruth
"syncEndKeepsOldPersistence"                     NotSavedRowTellsTruth
"retryForgetsNotSaved"                           NotSavedRowTellsTruth
LIST
rm -f .mutation.cfg .mutation.cfg.bak
exit "$failures"
