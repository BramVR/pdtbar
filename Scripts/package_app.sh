#!/usr/bin/env bash
set -euo pipefail

CONF="${1:-debug}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="PDTBar"
PRODUCT_NAME="pdtbar"
APP_BUNDLE="${ROOT_DIR}/${APP_NAME}.app"
APP_STAGE="${ROOT_DIR}/.build/package/${APP_NAME}.app"
BUNDLE_IDENTIFIER="com.bramvr.pdtbar.debug"

log() { printf '%s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

case "$(printf '%s' "${CONF}" | tr '[:upper:]' '[:lower:]')" in
  debug) CONF="debug" ;;
  release)
    CONF="release"
    BUNDLE_IDENTIFIER="com.bramvr.pdtbar"
    ;;
  *) fail "Unsupported build configuration: ${CONF} (expected debug or release)" ;;
esac

cd "${ROOT_DIR}"

log "==> Building ${PRODUCT_NAME} (${CONF})"
swift build -c "${CONF}" --product "${PRODUCT_NAME}"

BIN_DIR="$(swift build -c "${CONF}" --show-bin-path)"
SOURCE_BINARY="${BIN_DIR}/${PRODUCT_NAME}"
[[ -x "${SOURCE_BINARY}" ]] || fail "Built executable missing at ${SOURCE_BINARY}"

log "==> Creating ${APP_NAME}.app"
rm -rf "${APP_STAGE}"
mkdir -p "${APP_STAGE}/Contents/MacOS" "${APP_STAGE}/Contents/Resources"
cp "${SOURCE_BINARY}" "${APP_STAGE}/Contents/MacOS/${APP_NAME}"

cat > "${APP_STAGE}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>PDTBar</string>
    <key>CFBundleDisplayName</key>
    <string>PDTBar</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_IDENTIFIER}</string>
    <key>CFBundleExecutable</key>
    <string>PDTBar</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

plutil -lint "${APP_STAGE}/Contents/Info.plist" >/dev/null

SIGN_IDENTITY="${PDTBAR_APP_IDENTITY:-}"
if [[ -z "${SIGN_IDENTITY}" ]]; then
  SIGN_IDENTITY="-"
elif ! security find-identity -p codesigning -v 2>/dev/null | grep -F "${SIGN_IDENTITY}" >/dev/null 2>&1; then
  log "WARN: PDTBAR_APP_IDENTITY not found; falling back to ad-hoc signing."
  SIGN_IDENTITY="-"
fi

if command -v codesign >/dev/null 2>&1; then
  log "==> Signing ${APP_NAME}.app"
  codesign --force --sign "${SIGN_IDENTITY}" "${APP_STAGE}" >/dev/null
fi

rm -rf "${APP_BUNDLE}"
mv "${APP_STAGE}" "${APP_BUNDLE}"

log "OK: Created ${APP_BUNDLE}"
