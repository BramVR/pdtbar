#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GROUP_SIZE="${PDTBAR_TEST_GROUP_SIZE:-12}"
SUITE_TIMEOUT="${PDTBAR_TEST_SUITE_TIMEOUT:-180}"

cd "${ROOT_DIR}"
ARGS=(
  --group-size "${GROUP_SIZE}"
  --timeout "${SUITE_TIMEOUT}"
)

if [[ -n "${PDTBAR_TEST_SHARD_INDEX:-}" || -n "${PDTBAR_TEST_SHARD_COUNT:-}" ]]; then
  ARGS+=(
    --shard-index "${PDTBAR_TEST_SHARD_INDEX:?PDTBAR_TEST_SHARD_COUNT requires PDTBAR_TEST_SHARD_INDEX}"
    --shard-count "${PDTBAR_TEST_SHARD_COUNT:?PDTBAR_TEST_SHARD_INDEX requires PDTBAR_TEST_SHARD_COUNT}"
  )
fi

exec python3 "${ROOT_DIR}/Scripts/ci_swift_test_by_suite.py" "${ARGS[@]}" "$@"
