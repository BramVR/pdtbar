#!/usr/bin/env bash
# Run every pulse-read-state config and compare each against its expected result.
# Usage: formal/pulse-read-state/check.sh
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
tlc="$root/Scripts/formal/tlc.sh"
spec="$here/PulseReadState.tla"

# config | expected: "pass" or the invariant TLC must report violated
expectations=(
  "PulseReadState_store.cfg|pass"
  "PulseReadState_fixed.cfg|pass"
  "PulseReadState_stale_publish.cfg|pass"
  "PulseReadState_lost_reset.cfg|ReadMarkClearedOnRecrossing"
  "PulseReadState_broken_markread.cfg|NoLostReadStateUpdate"
  "PulseReadState_broken_bgpublish.cfg|DisplayMatchesStoreWhenIdle"
)

failures=0
for entry in "${expectations[@]}"; do
  cfg="${entry%%|*}"
  want="${entry##*|}"
  out="$("$tlc" "$spec" "$here/$cfg" 2>&1)"
  if grep -q "^Model checking completed. No error has been found." <<<"$out"; then
    got="pass"
  else
    got="$(sed -n 's/^Error: Invariant \([A-Za-z]*\) is violated\./\1/p' <<<"$out" | head -1)"
    got="${got:-error}"
  fi
  states="$(grep -E "distinct states found" <<<"$out" | tail -1)"
  if [[ "$got" == "$want" ]]; then
    echo "ok    $cfg: $got ($states)"
  else
    echo "FAIL  $cfg: expected $want, got $got"
    [[ "$got" == "error" ]] && grep -E "^Error|error" <<<"$out" | head -5
    failures=$((failures + 1))
  fi
done

exit "$failures"
