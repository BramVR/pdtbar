#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="${ROOT_DIR}/PDTBar.app"
APP_PROCESS_PATTERN="${APP_BUNDLE}/Contents/MacOS/PDTBar"

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ -d "${APP_BUNDLE}" ]] || fail "PDTBar.app not found at ${APP_BUNDLE}; run ./Scripts/package_app.sh first"
[[ -x "${APP_BUNDLE}/Contents/MacOS/PDTBar" ]] || fail "PDTBar.app executable missing at ${APP_BUNDLE}/Contents/MacOS/PDTBar"

printf '%s\n' "==> Launching ${APP_BUNDLE}"
open -n "${APP_BUNDLE}"

for _ in {1..20}; do
  if pgrep -f "${APP_PROCESS_PATTERN}" >/dev/null 2>&1; then
    printf '%s\n' "OK: PDTBar is running from ${APP_PROCESS_PATTERN}"
    exit 0
  fi
  sleep 0.3
done

fail "PDTBar.app did not stay running from ${APP_PROCESS_PATTERN}"
