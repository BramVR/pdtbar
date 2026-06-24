#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="${ROOT_DIR}/PDTBar.app"
APP_PROCESS_PATTERN="${APP_BUNDLE}/Contents/MacOS/PDTBar"
RAW_DEBUG_PROCESS_PATTERN="${ROOT_DIR}/.build/debug/pdtbar"
RAW_RELEASE_PROCESS_PATTERN="${ROOT_DIR}/.build/release/pdtbar"

log() { printf '%s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

is_running() {
  [[ -n "$(pdtbar_pids)" ]]
}

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

stop_pdtbar() {
  for _ in {1..25}; do
    kill_pdtbar_pids TERM
    if ! is_running; then
      return 0
    fi
    sleep 0.2
  done

  kill_pdtbar_pids KILL

  for _ in {1..25}; do
    if ! is_running; then
      return 0
    fi
    sleep 0.2
  done

  fail "Failed to stop existing PDTBar instances."
}

log "==> Killing existing PDTBar instances"
stop_pdtbar

log "==> Packaging PDTBar.app"
"${ROOT_DIR}/Scripts/package_app.sh" debug

log "==> Launching PDTBar.app"
open -n "${APP_BUNDLE}"

for _ in {1..20}; do
  if pgrep -f "${APP_PROCESS_PATTERN}" >/dev/null 2>&1; then
    log "OK: PDTBar is running from ${APP_PROCESS_PATTERN}"
    exit 0
  fi
  sleep 0.3
done

fail "PDTBar.app did not stay running from ${APP_PROCESS_PATTERN}"
