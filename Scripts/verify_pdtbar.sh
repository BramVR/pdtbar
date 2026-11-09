#!/usr/bin/env bash
# Prompt-free PDTBar instance for the verify-pdtbar skill.
# Fixture mode only: never calls Claude, PDT, Keychain, Accessibility, or Screen Recording.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${ROOT_DIR}/.build/debug/pdtbar"
RUNS_DIR="${ROOT_DIR}/.build/verify-pdtbar"

usage() {
  cat >&2 <<'EOF'
usage:
  Scripts/verify_pdtbar.sh launch [fixture.json]   # prints run dir; default fixture quiet-no-pressure
  Scripts/verify_pdtbar.sh doctor <run-dir>
  Scripts/verify_pdtbar.sh stop <run-dir>
EOF
  exit 64
}

fail() { printf 'FAIL: %s\n' "$*"; exit 1; }

pid_command() { ps -ww -o command= -p "$1" 2>/dev/null || true; }

ours() {
  local pid="$1" run="$2"
  [[ "$(pid_command "${pid}")" == "${APP} --fixture "*" --snapshot-dir ${run}/snapshots" ]]
}

launch() {
  local fixture="${1:-${ROOT_DIR}/docs/pdt/fixtures/quiet-no-pressure.json}"
  [[ -x "${APP}" ]] || fail "missing ${APP}; run: swift build --product pdtbar"
  [[ -f "${fixture}" ]] || fail "missing fixture ${fixture}"
  fixture="$(cd "$(dirname "${fixture}")" && pwd)/$(basename "${fixture}")"

  local run="${RUNS_DIR}/$(date +%Y%m%d-%H%M%S)-$$"
  mkdir -p "${run}/snapshots" "${run}/app-support" "${run}/evidence"
  local suite="com.pdtbar.verify.$(basename "${run}")"
  printf '%s\n' "${suite}" > "${run}/defaults-suite"
  printf '%s\n' "${fixture}" > "${run}/fixture"
  stat -f '%i %m' "${APP}" > "${run}/binary"

  env -u PDTBAR_CLAUDE_READINESS -u PDTBAR_CLAUDE_BIN \
    PDTBAR_DISABLE_REAL_CLAUDE=1 \
    PDTBAR_APP_SUPPORT_DIR="${run}/app-support" \
    PDTBAR_USER_DEFAULTS_SUITE="${suite}" \
    "${APP}" --fixture "${fixture}" --snapshot-dir "${run}/snapshots" \
    > "${run}/app.log" 2>&1 &
  printf '%s\n' "$!" > "${run}/pid"

  for _ in {1..50}; do
    if [[ -f "${run}/snapshots/latest-portfolio-snapshot.json" ]] && kill -0 "$(cat "${run}/pid")" 2>/dev/null; then
      printf 'ready: %s\n' "${run}"
      return 0
    fi
    sleep 0.2
  done
  printf 'not ready after 10s; app.log:\n' >&2
  cat "${run}/app.log" >&2 || true
  stop "${run}" >&2 || true
  exit 1
}

doctor() {
  local run="$1" pid newest
  [[ -f "${run}/pid" ]] || fail "no pid file in ${run} (stopped or never launched)"
  pid="$(cat "${run}/pid")"
  printf 'run: %s\npid: %s\n' "${run}" "${pid}"
  kill -0 "${pid}" 2>/dev/null || fail "process ${pid} not running; see ${run}/app.log"
  ours "${pid}" "${run}" || fail "pid ${pid} is not this run's fixture app: $(pid_command "${pid}")"
  printf 'process: ours (%s)\n' "${APP}"
  newest="$(find "${ROOT_DIR}/Sources" -name '*.swift' -newer "${APP}" -print -quit)"
  [[ -z "${newest}" ]] || fail "stale build: ${newest} is newer than ${APP}; rebuild and relaunch"
  [[ "$(stat -f '%i %m' "${APP}")" == "$(cat "${run}/binary")" ]] || fail "binary rebuilt after launch; running process has old code; stop and relaunch"
  printf 'build: fresh (binary unchanged since launch; no Sources/*.swift newer)\n'
  [[ -s "${run}/snapshots/latest-portfolio-snapshot.json" ]] || fail "fixture snapshot not written"
  printf 'snapshot: %s\n' "${run}/snapshots/latest-portfolio-snapshot.json"
  printf 'fixture: %s\n' "$(cat "${run}/fixture")"
  printf 'other pdtbar processes (not ours, do not touch):\n'
  ps -axo pid=,comm= \
    | awk -v self="${pid}" '$1 != self && $0 ~ /(\/\.build\/(debug|release)\/pdtbar|PDTBar\.app\/Contents\/MacOS\/PDTBar)$/ { print "  " $0; n++ } END { if (!n) print "  none" }'
  printf 'doctor: ok\n'
}

stop() {
  local run="$1" pid
  [[ -d "${run}" ]] || fail "no run dir ${run}"
  if [[ -f "${run}/pid" ]]; then
    pid="$(cat "${run}/pid")"
    if kill -0 "${pid}" 2>/dev/null; then
      ours "${pid}" "${run}" || fail "pid ${pid} is not this run's app; refusing to kill: $(pid_command "${pid}")"
      kill -TERM "${pid}"
      for _ in {1..25}; do kill -0 "${pid}" 2>/dev/null || break; sleep 0.2; done
      kill -0 "${pid}" 2>/dev/null && fail "pid ${pid} ignored TERM"
    fi
    rm -f "${run}/pid"
  fi
  if [[ -f "${run}/defaults-suite" ]]; then
    defaults delete "$(cat "${run}/defaults-suite")" >/dev/null 2>&1 || true
    rm -f "${HOME}/Library/Preferences/$(cat "${run}/defaults-suite").plist"
  fi
  rm -rf "${run}/app-support"
  printf 'stopped: %s (evidence kept: snapshots/ evidence/ app.log)\n' "${run}"
}

case "${1:-}" in
  launch) shift; launch "$@" ;;
  doctor) [[ $# -eq 2 ]] || usage; doctor "${2%/}" ;;
  stop) [[ $# -eq 2 ]] || usage; stop "${2%/}" ;;
  *) usage ;;
esac
