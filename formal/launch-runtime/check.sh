#!/usr/bin/env bash
# One-command check for the launch-runtime model.
# Exit 0: every invariant passes except the open findings listed below (baseline).
# Exit 1: a new invariant fails, or an open finding stopped failing (update the list + skill).
set -euo pipefail
cd "$(dirname "$0")"
OPEN_FINDINGS="BackgroundFlagMatchesWork ProbingMenuTellsTruth SetupMenuMeansIdle"

out="$(../../Scripts/formal/tlc.sh LaunchRuntime.tla -continue 2>&1)"
echo "$out" | grep -E 'distinct states found' || { echo "$out"; exit 1; }
violated="$(echo "$out" | grep -oE 'Invariant [A-Za-z]+ is violated' | awk '{print $2}' | sort -u | tr '\n' ' ' | sed 's/ $//')"
expected="$(echo $OPEN_FINDINGS | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ $//')"
echo "violated: ${violated:-none}"
echo "expected: $expected"
if [[ "$violated" != "$expected" ]]; then
  echo "launch-runtime: result differs from baseline; read the trace with /statechart" >&2
  exit 1
fi
echo "launch-runtime: baseline holds"
