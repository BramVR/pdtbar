#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PROCESS_PATTERN="${ROOT_DIR}/PDTBar.app/Contents/MacOS/PDTBar"
RAW_DEBUG_PROCESS_PATTERN="${ROOT_DIR}/.build/debug/pdtbar"
RAW_RELEASE_PROCESS_PATTERN="${ROOT_DIR}/.build/release/pdtbar"

pid_cwd() {
  lsof -a -p "$1" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -n 1
}

pdtbar_pids() {
  {
    pgrep -f "${APP_PROCESS_PATTERN}" 2>/dev/null || true
    pgrep -f "${RAW_DEBUG_PROCESS_PATTERN}" 2>/dev/null || true
    pgrep -f "${RAW_RELEASE_PROCESS_PATTERN}" 2>/dev/null || true
    pgrep -f "PDTBar\\.app/Contents/MacOS/PDTBar|\\.build/(debug|release)/pdtbar" 2>/dev/null | while read -r pid; do
      [[ "$(pid_cwd "${pid}")" == "${ROOT_DIR}" ]] && printf '%s\n' "${pid}"
    done || true
  } | sort -u
}

kill_pdtbar_pids() {
  local signal="${1:-TERM}"
  local pid
  pdtbar_pids | while read -r pid; do
    kill "-${signal}" "${pid}" 2>/dev/null || true
  done
}

for _ in {1..25}; do
  kill_pdtbar_pids TERM
  if [[ -z "$(pdtbar_pids)" ]]; then
    printf '%s\n' "OK: PDTBar stopped."
    exit 0
  fi
  sleep 0.2
done

kill_pdtbar_pids KILL
for _ in {1..25}; do
  if [[ -z "$(pdtbar_pids)" ]]; then
    printf '%s\n' "OK: PDTBar stopped."
    exit 0
  fi
  sleep 0.2
done

printf '%s\n' "ERROR: Failed to stop all PDTBar instances." >&2
exit 1
