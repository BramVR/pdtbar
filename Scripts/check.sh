#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() {
  printf '\n==> %s\n' "$*"
}

run() {
  printf '+'
  printf ' %q' "$@"
  printf '\n'
  "$@"
}

check_scripts() {
  local script
  local pycache_dir="${ROOT_DIR}/.build/check-syntax"

  mkdir -p "${pycache_dir}"

  log "Checking shell script syntax"
  while IFS= read -r script; do
    run bash -n "${script}"
  done < <(find "${ROOT_DIR}/Scripts" -type f -name '*.sh' | sort)

  log "Checking Python script syntax"
  while IFS= read -r script; do
    run python3 -c 'import py_compile, sys; py_compile.compile(sys.argv[1], cfile=sys.argv[2], doraise=True)' \
      "${script}" "${pycache_dir}/$(basename "${script}").pyc"
  done < <(find "${ROOT_DIR}/Scripts" -type f -name '*.py' | sort)

  log "Checking Node script syntax"
  while IFS= read -r script; do
    run node --check "${script}"
  done < <(find "${ROOT_DIR}/Scripts" -type f -name '*.mjs' | sort)
}

usage() {
  printf 'Usage: %s [all|scripts|build|checks|tests]\n' "$(basename "$0")" >&2
}

cmd="${1:-all}"

cd "${ROOT_DIR}"

case "${cmd}" in
  all)
    check_scripts
    log "Building Swift package"
    run swift build
    log "Running deterministic PDTBar checks"
    run swift run pdtbar-checks
    log "Running Swift tests"
    run "${ROOT_DIR}/Scripts/test.sh"
    ;;
  scripts)
    check_scripts
    ;;
  build)
    log "Building Swift package"
    run swift build
    ;;
  checks)
    log "Running deterministic PDTBar checks"
    run swift run pdtbar-checks
    ;;
  tests)
    log "Running Swift tests"
    run "${ROOT_DIR}/Scripts/test.sh"
    ;;
  *)
    usage
    exit 2
    ;;
esac
