#!/usr/bin/env bash
# The background-detail-refresh model must pass every invariant and property.
set -euo pipefail
cd "$(dirname "$0")"
out="$(../../Scripts/formal/tlc.sh BackgroundDetailRefresh.tla 2>&1)" || true
grep -E 'distinct states found' <<<"$out" | tail -1
if ! grep -q '^Model checking completed. No error has been found.' <<<"$out"; then
  echo "$out" | grep -E '^Error' | head -5
  echo "background-detail-refresh: model fails; read the trace with /statechart" >&2
  exit 1
fi
echo "background-detail-refresh: passes"
