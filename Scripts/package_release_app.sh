#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="PDTBar"
APP_BUNDLE="${ROOT_DIR}/${APP_NAME}.app"
ARCHES_VALUE="${ARCHES:-arm64 x86_64}"
OUT_DIR="${PDTBAR_RELEASE_OUT_DIR:-${ROOT_DIR}/.build/release-artifacts}"
REQUIRE_NOTARIZATION="${PDTBAR_REQUIRE_NOTARIZATION:-0}"
DITTO_BIN="${DITTO_BIN:-/usr/bin/ditto}"

log() { printf '%s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

release_arch_label() {
  local raw="${1:-arm64 x86_64}"
  local normalized
  local has_arm64=0
  local has_x86_64=0
  local arch

  normalized="$(printf '%s' "$raw" | tr ',' ' ')"
  for arch in $normalized; do
    case "$arch" in
      arm64) has_arm64=1 ;;
      x86_64) has_x86_64=1 ;;
    esac
  done

  if [[ "$has_arm64" == "1" && "$has_x86_64" == "1" ]]; then
    printf 'universal'
    return
  fi
  if [[ "$has_arm64" == "1" ]]; then
    printf 'arm64'
    return
  fi
  if [[ "$has_x86_64" == "1" ]]; then
    printf 'x86_64'
    return
  fi

  printf '%s' "$(printf '%s' "$normalized" | tr ' ' '+')"
}

require_env() {
  local name="$1"
  [[ -n "${!name:-}" ]] || fail "Missing ${name}; required for notarized public app archives."
}

TAG="${1:-${RELEASE_TAG:-}}"
[[ -n "$TAG" ]] || fail "Usage: $(basename "$0") <vX.Y.Z>"
[[ "$TAG" =~ ^v[0-9A-Za-z._-]+$ ]] || fail "Invalid release tag: ${TAG}"

VERSION="${TAG#v}"
if [[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){0,2} ]]; then
  BUNDLE_VERSION="${BASH_REMATCH[0]}"
else
  fail "Release tag must start with a numeric app version after v, got ${TAG}"
fi
ARCH_LABEL="$(release_arch_label "$ARCHES_VALUE")"
ARCHIVE_NAME="${APP_NAME}-macos-${ARCH_LABEL}-${VERSION}.zip"
ARCHIVE_PATH="${OUT_DIR}/${ARCHIVE_NAME}"
NOTARIZATION_READY=0

if [[ "$REQUIRE_NOTARIZATION" == "1" ]]; then
  require_env PDTBAR_APP_IDENTITY
  require_env APP_STORE_CONNECT_API_KEY_P8
  require_env APP_STORE_CONNECT_KEY_ID
  require_env APP_STORE_CONNECT_ISSUER_ID
  security find-identity -p codesigning -v 2>/dev/null | grep -F "${PDTBAR_APP_IDENTITY}" >/dev/null \
    || fail "PDTBAR_APP_IDENTITY is not installed in this keychain."
  NOTARIZATION_READY=1
fi

cd "${ROOT_DIR}"
mkdir -p "${OUT_DIR}"

log "==> Building release app archive ${ARCHIVE_NAME}"
PDTBAR_APP_VERSION="${BUNDLE_VERSION}" \
PDTBAR_APP_BUILD="${BUNDLE_VERSION}" \
ARCHES="${ARCHES_VALUE}" \
  "${ROOT_DIR}/Scripts/package_app.sh" release

[[ -d "${APP_BUNDLE}" ]] || fail "Missing ${APP_BUNDLE}"
[[ -x "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}" ]] || fail "Missing ${APP_NAME}.app executable"

if [[ "$NOTARIZATION_READY" == "1" ]]; then
  TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/pdtbar-notarize.XXXXXX")"
  chmod 700 "$TEMP_DIR"
  API_KEY_PATH="${TEMP_DIR}/pdtbar-api-key.p8"
  NOTARY_ZIP="${TEMP_DIR}/${APP_NAME}-notary.zip"
  trap 'rm -rf "$TEMP_DIR"' EXIT

  (
    umask 077
    printf '%s' "$APP_STORE_CONNECT_API_KEY_P8" | sed 's/\\n/\n/g' > "$API_KEY_PATH"
  )
  chmod 600 "$API_KEY_PATH"

  log "==> Submitting ${APP_NAME}.app for notarization"
  "$DITTO_BIN" --norsrc -c -k --keepParent "${APP_BUNDLE}" "${NOTARY_ZIP}"
  xcrun notarytool submit "${NOTARY_ZIP}" \
    --key "${API_KEY_PATH}" \
    --key-id "${APP_STORE_CONNECT_KEY_ID}" \
    --issuer "${APP_STORE_CONNECT_ISSUER_ID}" \
    --wait

  log "==> Stapling notarization ticket"
  xcrun stapler staple "${APP_BUNDLE}"
  xcrun stapler validate "${APP_BUNDLE}"
else
  log "WARN: Notarization skipped; set PDTBAR_REQUIRE_NOTARIZATION=1 for public release archives."
fi

log "==> Creating ${ARCHIVE_PATH}"
rm -f "${ARCHIVE_PATH}" "${ARCHIVE_PATH}.sha256"
xattr -cr "${APP_BUNDLE}" 2>/dev/null || true
find "${APP_BUNDLE}" -name '._*' -delete
"$DITTO_BIN" --norsrc -c -k --keepParent "${APP_BUNDLE}" "${ARCHIVE_PATH}"
(cd "${OUT_DIR}" && shasum -a 256 "${ARCHIVE_NAME}" > "${ARCHIVE_NAME}.sha256")

VERIFY_DIR="$(mktemp -d "${TMPDIR:-/tmp}/pdtbar-archive-check.XXXXXX")"
trap 'rm -rf "$VERIFY_DIR" "${TEMP_DIR:-}"' EXIT
"$DITTO_BIN" -x -k "${ARCHIVE_PATH}" "${VERIFY_DIR}"
[[ -x "${VERIFY_DIR}/${APP_NAME}.app/Contents/MacOS/${APP_NAME}" ]] \
  || fail "Archive does not contain ${APP_NAME}.app with executable."
codesign --verify --deep --strict --verbose=2 "${VERIFY_DIR}/${APP_NAME}.app" >/dev/null

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    printf 'archive=%s\n' "${ARCHIVE_PATH}"
    printf 'archive_name=%s\n' "${ARCHIVE_NAME}"
    printf 'out_dir=%s\n' "${OUT_DIR}"
  } >> "${GITHUB_OUTPUT}"
fi

log "OK: ${ARCHIVE_PATH}"
