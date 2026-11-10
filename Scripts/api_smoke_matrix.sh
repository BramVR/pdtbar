#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACTS="${1:-${ROOT_DIR}/.build/pdtbar-smoke-artifacts/api-matrix}"

cd "${ROOT_DIR}"
swift build --product pdtbar
swift build --product pdtbar-smoke

scratch="$(mktemp -d "${TMPDIR:-/tmp}/pdtbar-api-matrix.XXXXXX")"
trap 'rm -rf "${scratch}"' EXIT
mkdir -p "${scratch}/home" "${scratch}/tmp" "${ARTIFACTS}"

# Seatbelt checks rules in order and the last match wins, so the loopback
# allow must follow the network deny.
profile='(version 1)
(allow default)
(deny network-outbound (with send-signal SIGKILL) (remote ip))
(allow network-outbound (remote ip "localhost:*"))
(deny network-outbound (with send-signal SIGKILL) (remote unix-socket (path-literal "/private/var/run/mDNSResponder")))
(deny process-exec (with send-signal SIGKILL) (regex #"/(claude|codex|mcporter)$"))
(deny mach-lookup (with send-signal SIGKILL) (global-name-regex #"^com\.apple\.(SecurityServer|securityd\.)"))
(deny mach-lookup (global-name-regex #"^com\.apple\.tccd"))'

env -i HOME="${scratch}/home" TMPDIR="${scratch}/tmp" PATH=/usr/bin:/bin \
  /usr/bin/sandbox-exec -p "${profile}" \
  "${ROOT_DIR}/.build/debug/pdtbar-smoke" scripted-api-matrix \
  --app "${ROOT_DIR}/.build/debug/pdtbar" \
  --artifacts "${ARTIFACTS}" \
  --timeout 5
