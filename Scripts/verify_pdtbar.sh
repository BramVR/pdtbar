#!/usr/bin/env bash
# Prompt-free PDTBar instance for the verify-pdtbar skill.
# launch runs fixture mode; launch-scripted runs the product path over a --scripted-pdt script (in-memory
# credential, scripted sign-in, scripted API replies). Neither calls PDT, the Keychain, Accessibility, or Screen Recording.
# can-capture/capture are opt-in visual proof: they only preflight Screen Recording and use Accessibility when already granted.
# menu-walk/menu-smoke drive the real menu through submenus; they fail, never skip, when Accessibility or capture is missing.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${ROOT_DIR}/.build/debug/pdtbar"
APP_SOURCES=("${ROOT_DIR}/Sources/PDTBarApp" "${ROOT_DIR}/Sources/PDTBarAppSupport" "${ROOT_DIR}/Sources/PDTBarCore")
CAPTURE_SOURCES=("${ROOT_DIR}/Sources/PDTBarCapture" "${ROOT_DIR}/Sources/PDTBarSmokeProof" "${ROOT_DIR}/Sources/PDTBarCore")
MENU_PLAN="cohesive-ui"
MENU_FIXTURE="${ROOT_DIR}/docs/pdt/fixtures/concentration-pressure.json"
CAPTURE="${ROOT_DIR}/.build/debug/pdtbar-capture"
RUNS_DIR="${ROOT_DIR}/.build/verify-pdtbar"

usage() {
  cat >&2 <<'EOF'
usage:
  Scripts/verify_pdtbar.sh launch [fixture.json]   # prints run dir; default fixture quiet-no-pressure
  Scripts/verify_pdtbar.sh launch-scripted <script.json> [seed-snapshot.json]   # product path over a ScriptedPDTConnection
  Scripts/verify_pdtbar.sh doctor <run-dir>
  Scripts/verify_pdtbar.sh stop <run-dir>
  Scripts/verify_pdtbar.sh can-capture                                  # exit 0 yes, 3 no (with reason)
  Scripts/verify_pdtbar.sh capture screenshot <run-dir> <name>          # <run>/evidence/<name>.png
  Scripts/verify_pdtbar.sh capture record <run-dir> <name> <seconds>    # <run>/evidence/<name>.mov + -poster.png
  Scripts/verify_pdtbar.sh menu-walk <run-dir>      # walk the cohesive-ui plan; <run>/evidence/menu-walk/
  Scripts/verify_pdtbar.sh menu-smoke               # build, launch the plan fixture, menu-walk, stop
  Scripts/verify_pdtbar.sh menu-measure <fixture.json>   # build, launch, root menu rows + menu.png, stop
  Scripts/verify_pdtbar.sh menu-measure --scripted <script.json> <seed-snapshot.json>   # same over launch-scripted
EOF
  exit 64
}

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# Accept only a direct child of RUNS_DIR with launch's name shape; prints the canonical path.
resolve_run() {
  local name runs
  [[ -d "$1" ]] || fail "no run dir $1"
  name="$(basename "$1")"
  [[ "${name}" =~ ^[0-9]{8}-[0-9]{6}-[0-9]+$ ]] || fail "not a verify run dir: $1"
  runs="$(cd "${RUNS_DIR}" 2>/dev/null && pwd -P)" || fail "no runs dir ${RUNS_DIR}"
  [[ "$(cd "$1" && pwd -P)" == "${runs}/${name}" ]] || fail "run dir must be under ${RUNS_DIR}: $1"
  printf '%s\n' "${runs}/${name}"
}

suite_for() { printf 'com.pdtbar.verify.%s\n' "$(basename "$1")"; }

pid_command() { ps -ww -o command= -p "$1" 2>/dev/null || true; }

ours() {
  local pid="$1" run="$2" command
  command="$(pid_command "${pid}")"
  [[ "${command}" == "${APP} --fixture "*" --snapshot-dir ${run}/snapshots" \
    || "${command}" == "${APP} --app-support-dir ${run}/app-support --scripted-pdt ${run}/scripted-pdt.json" ]]
}

launch() {
  local fixture="${1:-${ROOT_DIR}/docs/pdt/fixtures/quiet-no-pressure.json}"
  [[ -x "${APP}" ]] || fail "missing ${APP}; run: swift build --product pdtbar"
  [[ -f "${fixture}" ]] || fail "missing fixture ${fixture}"
  fixture="$(cd "$(dirname "${fixture}")" && pwd)/$(basename "${fixture}")"

  mkdir -p "${RUNS_DIR}"
  local run
  run="$(cd "${RUNS_DIR}" && pwd -P)/$(date +%Y%m%d-%H%M%S)-$$"
  mkdir -p "${run}/snapshots" "${run}/app-support" "${run}/evidence"
  local suite
  suite="$(suite_for "${run}")"
  printf '%s\n' "${suite}" > "${run}/defaults-suite"
  printf '%s\n' "${fixture}" > "${run}/fixture"
  stat -f '%i %m' "${APP}" > "${run}/binary"

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

# The product path over a script. The copy's eventLog is <run>/events.log; ready means the
# first connection check ran and its outcome had a moment to render.
launch_scripted() {
  local script="${1:-}" seed="${2:-}"
  [[ -x "${APP}" ]] || fail "missing ${APP}; run: swift build --product pdtbar"
  [[ -f "${script}" ]] || fail "missing script ${script}"
  [[ -z "${seed}" || -f "${seed}" ]] || fail "missing seed snapshot ${seed}"

  mkdir -p "${RUNS_DIR}"
  local run suite
  run="$(cd "${RUNS_DIR}" && pwd -P)/$(date +%Y%m%d-%H%M%S)-$$"
  mkdir -p "${run}/snapshots" "${run}/app-support/pdtbar/state" "${run}/evidence"
  suite="$(suite_for "${run}")"
  printf '%s\n' "${suite}" > "${run}/defaults-suite"
  stat -f '%i %m' "${APP}" > "${run}/binary"
  python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); d["eventLog"]=sys.argv[3]; json.dump(d, open(sys.argv[2], "w"))' \
    "${script}" "${run}/scripted-pdt.json" "${run}/events.log"
  printf 'scripted: %s\n' "${script}" > "${run}/fixture"
  [[ -z "${seed}" ]] || cp "${seed}" "${run}/app-support/pdtbar/state/latest-portfolio-snapshot.json"

  PDTBAR_USER_DEFAULTS_SUITE="${suite}" \
    "${APP}" --app-support-dir "${run}/app-support" --scripted-pdt "${run}/scripted-pdt.json" \
    > "${run}/app.log" 2>&1 &
  printf '%s\n' "$!" > "${run}/pid"

  for _ in {1..50}; do
    if grep -qx check "${run}/events.log" 2>/dev/null && kill -0 "$(cat "${run}/pid")" 2>/dev/null; then
      sleep 1.5
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
  local run pid newest
  run="$(resolve_run "$1")"
  [[ -f "${run}/pid" ]] || fail "no pid file in ${run} (stopped or never launched)"
  pid="$(cat "${run}/pid")"
  printf 'run: %s\npid: %s\n' "${run}" "${pid}"
  kill -0 "${pid}" 2>/dev/null || fail "process ${pid} not running; see ${run}/app.log"
  ours "${pid}" "${run}" || fail "pid ${pid} is not this run's fixture app: $(pid_command "${pid}")"
  printf 'process: ours (%s)\n' "${APP}"
  # Only the app's own targets count; editing the capture tool or smoke proof must not mark the app stale.
  newest="$(find "${APP_SOURCES[@]}" -name '*.swift' -newer "${APP}" -print -quit)"
  [[ -z "${newest}" ]] || fail "stale build: ${newest} is newer than ${APP}; rebuild and relaunch"
  [[ "$(stat -f '%i %m' "${APP}")" == "$(cat "${run}/binary")" ]] || fail "binary rebuilt after launch; running process has old code; stop and relaunch"
  printf 'build: fresh (binary unchanged since launch; no app source newer)\n'
  if [[ -f "${run}/scripted-pdt.json" ]]; then
    grep -qx check "${run}/events.log" 2>/dev/null || fail "scripted run never checked the connection"
    printf 'events: %s\n' "$(tr '\n' ' ' < "${run}/events.log")"
  else
    [[ -s "${run}/snapshots/latest-portfolio-snapshot.json" ]] || fail "fixture snapshot not written"
    printf 'snapshot: %s\n' "${run}/snapshots/latest-portfolio-snapshot.json"
  fi
  printf 'fixture: %s\n' "$(cat "${run}/fixture")"
  printf 'other pdtbar processes (not ours, do not touch):\n'
  ps -axo pid=,comm= \
    | awk -v self="${pid}" '$1 != self && $0 ~ /(\/\.build\/(debug|release)\/pdtbar|PDTBar\.app\/Contents\/MacOS\/PDTBar)$/ { print "  " $0; n++ } END { if (!n) print "  none" }'
  printf 'doctor: ok\n'
}

stop() {
  local run pid suite
  run="$(resolve_run "$1")"
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
  # Derived from the validated run name, never read back from the run dir.
  suite="$(suite_for "${run}")"
  defaults delete "${suite}" >/dev/null 2>&1 || true
  rm -f "${HOME}/Library/Preferences/${suite}.plist"
  rm -rf "${run}/app-support"
  printf 'stopped: %s (evidence kept: snapshots/ evidence/ app.log)\n' "${run}"
}

require_capture_tool() {
  local newest
  [[ -x "${CAPTURE}" ]] || fail "missing ${CAPTURE}; run: swift build --product pdtbar-capture"
  newest="$(find "${CAPTURE_SOURCES[@]}" -name '*.swift' -newer "${CAPTURE}" -print -quit)"
  [[ -z "${newest}" ]] || fail "stale ${CAPTURE}; run: swift build --product pdtbar-capture"
}

can_capture() {
  require_capture_tool
  exec "${CAPTURE}" preflight
}

capture() {
  local mode="${1:-}" run name seconds report
  case "${mode}:$#" in
    screenshot:3 | record:4) ;;
    *) usage ;;
  esac
  require_capture_tool
  run="$(resolve_run "${2%/}")"
  name="$3"
  [[ "${name}" =~ ^[A-Za-z0-9._-]+$ ]] || fail "name must match ^[A-Za-z0-9._-]+$: ${name}"
  report="$(doctor "${run}" 2>&1)" || { printf '%s\n' "${report}" >&2; fail "doctor not ok for ${run}"; }
  if [[ "${mode}" == screenshot ]]; then
    "${CAPTURE}" screenshot --pid "$(cat "${run}/pid")" --out "${run}/evidence/${name}.png"
  else
    [[ "$4" =~ ^[0-9]{1,2}$ ]] && (( 10#$4 >= 1 && 10#$4 <= 30 )) || fail "seconds must be an integer 1..30: $4"
    seconds="$((10#$4))"
    "${CAPTURE}" record --pid "$(cat "${run}/pid")" --seconds "${seconds}" --out "${run}/evidence/${name}.mov"
  fi
}

menu_walk() {
  local run report
  require_capture_tool
  run="$(resolve_run "$1")"
  report="$(doctor "${run}" 2>&1)" || { printf '%s\n' "${report}" >&2; fail "doctor not ok for ${run}"; }
  "${CAPTURE}" walk --pid "$(cat "${run}/pid")" --plan "${MENU_PLAN}" --fixture "$(cat "${run}/fixture")" \
    --out-dir "${run}/evidence/menu-walk" \
    || fail "menu-walk did not prove the real menu (reason above); this gate never skips"
}

menu_smoke() {
  local run
  (cd "${ROOT_DIR}" && swift build --product pdtbar && swift build --product pdtbar-capture) >&2 || fail "build failed"
  # The walk proves the unfolded layout, so a small host display must not fold it (#296).
  run="$(PDTBAR_MENU_SCREEN_HEIGHT=100000 launch "${MENU_FIXTURE}" | sed -n 's/^ready: //p')"
  [[ -n "${run}" ]] || fail "launch did not report ready"
  # Expanded now: the EXIT trap runs after this function's locals are gone.
  trap "stop '${run}' >&2 || true" EXIT
  menu_walk "${run}"
  printf 'evidence: %s/evidence/menu-walk\n' "${run}"
}

menu_measure() {
  local fixture="$1" run
  (cd "${ROOT_DIR}" && swift build --product pdtbar && swift build --product pdtbar-capture) >&2 || fail "build failed"
  require_capture_tool
  if [[ "${fixture}" == --scripted ]]; then
    fixture="$2"
    run="$(launch_scripted "$2" "$3" | sed -n 's/^ready: //p')"
  else
    run="$(launch "${fixture}" | sed -n 's/^ready: //p')"
  fi
  [[ -n "${run}" ]] || fail "launch did not report ready"
  trap "stop '${run}' >&2 || true" EXIT
  # Scripted replies (retries included) finish after the first check; let the menu settle.
  [[ "$(cat "${run}/fixture")" != scripted:* ]] || sleep 3
  "${CAPTURE}" measure --pid "$(cat "${run}/pid")" --fixture "${fixture}" --out-dir "${run}/evidence/measure" \
    || fail "menu-measure did not capture the menu (reason above)"
  printf 'evidence: %s/evidence/measure\n' "${run}"
}

case "${1:-}" in
  launch) shift; launch "$@" ;;
  launch-scripted) [[ $# -ge 2 && $# -le 3 ]] || usage; shift; launch_scripted "$@" ;;
  doctor) [[ $# -eq 2 ]] || usage; doctor "${2%/}" ;;
  stop) [[ $# -eq 2 ]] || usage; stop "${2%/}" ;;
  can-capture) [[ $# -eq 1 ]] || usage; can_capture ;;
  capture) shift; capture "$@" ;;
  menu-walk) [[ $# -eq 2 ]] || usage; menu_walk "${2%/}" ;;
  menu-smoke) [[ $# -eq 1 ]] || usage; menu_smoke ;;
  menu-measure) [[ $# -eq 2 || ( $# -eq 4 && "$2" == --scripted ) ]] || usage; shift; menu_measure "$@" ;;
  *) usage ;;
esac
