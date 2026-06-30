#!/usr/bin/env bash
set -euo pipefail

TAP="${PDTBAR_HOMEBREW_TAP:-bramvr/tap}"
CASK="${PDTBAR_HOMEBREW_CASK:-pdtbar}"
APP_NAME="${PDTBAR_HOMEBREW_APP_NAME:-PDTBar}"
APP_PATH="${PDTBAR_HOMEBREW_APP_PATH:-/Applications/${APP_NAME}.app}"
EXPECTED_VERSION="${PDTBAR_HOMEBREW_EXPECTED_VERSION:-}"
QUALIFIED_CASK="${TAP}/${CASK}"
APP_EXECUTABLE="${APP_PATH}/Contents/MacOS/${APP_NAME}"

log() { printf '%s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
without_leading_v() { printf '%s' "${1#v}"; }

command -v brew >/dev/null || fail "Homebrew is required."
command -v open >/dev/null || fail "macOS open is required."

cleanup() {
  if [[ "${PDTBAR_HOMEBREW_KEEP_RUNNING:-0}" != "1" ]]; then
    pkill -x "${APP_NAME}" >/dev/null 2>&1 || true
  fi
  if [[ "${PDTBAR_HOMEBREW_KEEP_INSTALLED:-0}" != "1" ]]; then
    brew uninstall --cask "${QUALIFIED_CASK}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

log "==> Refreshing ${TAP}"
brew uninstall --cask "${QUALIFIED_CASK}" >/dev/null 2>&1 || true
brew untap "${TAP}" >/dev/null 2>&1 || true
brew tap "${TAP}"
brew update

log "==> Inspecting ${QUALIFIED_CASK}"
brew info --cask "${QUALIFIED_CASK}"
if [[ -n "${EXPECTED_VERSION}" ]]; then
  expected_version="$(without_leading_v "${EXPECTED_VERSION}")"
  cask_version="$(
    brew info --cask --json=v2 "${QUALIFIED_CASK}" \
      | ruby -rjson -e 'puts JSON.parse($stdin.read).fetch("casks").fetch(0).fetch("version")'
  )"
  [[ "${cask_version}" == "${expected_version}" ]] \
    || fail "Expected ${QUALIFIED_CASK} version ${expected_version}, got ${cask_version}."
fi

log "==> Installing ${QUALIFIED_CASK}"
brew install --cask "${QUALIFIED_CASK}"
[[ -x "${APP_EXECUTABLE}" ]] || fail "Expected executable at ${APP_EXECUTABLE}"
codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
if [[ -n "${EXPECTED_VERSION}" ]]; then
  bundle_version="$(plutil -extract CFBundleShortVersionString raw "${APP_PATH}/Contents/Info.plist")"
  [[ "${bundle_version}" == "${expected_version}" ]] \
    || fail "Expected ${APP_NAME} bundle version ${expected_version}, got ${bundle_version}."
fi

log "==> Launching ${APP_NAME}"
pkill -x "${APP_NAME}" >/dev/null 2>&1 || true
for _ in {1..10}; do
  if ! pgrep -x "${APP_NAME}" >/dev/null; then
    break
  fi
  sleep 1
done
pgrep -x "${APP_NAME}" >/dev/null && fail "Existing ${APP_NAME} process did not stop before proof launch."

open -n "${APP_PATH}"

for _ in {1..20}; do
  while IFS= read -r pid; do
    command_path="$(ps -p "${pid}" -o command= 2>/dev/null || true)"
    case "${command_path}" in
      "${APP_EXECUTABLE}"*)
        log "OK: ${QUALIFIED_CASK} installed and ${APP_NAME} launched from ${APP_EXECUTABLE}."
        exit 0
        ;;
    esac
  done < <(pgrep -x "${APP_NAME}" || true)
  if pgrep -x "${APP_NAME}" >/dev/null; then
    log "Waiting for ${APP_NAME} process to report ${APP_EXECUTABLE}"
  fi
  sleep 1
done

fail "${APP_NAME} did not launch from ${APP_EXECUTABLE}."
