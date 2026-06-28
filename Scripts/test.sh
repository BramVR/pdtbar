#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHARD_INDEX="${CODEXBAR_TEST_SHARD_INDEX:-}"
SHARD_COUNT="${CODEXBAR_TEST_SHARD_COUNT:-}"

cd "$ROOT_DIR"

run_shard() {
  local shard="$1"
  case "$shard" in
    0)
      swift build
      swift run pdtbar-checks
      ;;
    1)
      swift run pdtbar-smoke scripted-pdt-connector
      ;;
    2)
      swift build --product pdtbar
      swift run pdtbar-smoke packaged-app --fixture docs/pdt/fixtures/quiet-no-pressure.json --snapshot-dir .build/pdtbar-smoke-artifacts/ci-packaged-snapshot
      ;;
    3)
      swift run pdtbar-smoke fixture-proof --fixture docs/pdt/fixtures/quiet-no-pressure.json --output .build/pdtbar-smoke-artifacts/ci-fixture-proof.svg
      swift run pdtbar-smoke live-pdt
      ;;
    *)
      printf 'Unknown shard index: %s\n' "$shard" >&2
      exit 2
      ;;
  esac
}

if [[ -n "$SHARD_INDEX" || -n "$SHARD_COUNT" ]]; then
  : "${SHARD_INDEX:?CODEXBAR_TEST_SHARD_COUNT requires CODEXBAR_TEST_SHARD_INDEX}"
  : "${SHARD_COUNT:?CODEXBAR_TEST_SHARD_INDEX requires CODEXBAR_TEST_SHARD_COUNT}"
  if [[ "$SHARD_COUNT" != "4" ]]; then
    printf 'Expected shard count 4, got %s\n' "$SHARD_COUNT" >&2
    exit 2
  fi
  run_shard "$SHARD_INDEX"
else
  for shard in 0 1 2 3; do
    run_shard "$shard"
  done
fi
