#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="${ROOT_DIR}/.build/lint-tools/bin"

check_shell_scripts() {
  local count=0
  local script
  for script in "${ROOT_DIR}"/Scripts/*.sh; do
    [[ -f "$script" ]] || continue
    bash -n "$script"
    count=$((count + 1))
  done
  printf 'shell scripts OK: %d files\n' "$count"
}

check_workflow_yaml() {
  ruby -e 'require "yaml"; ARGV.each { |p| YAML.load_file(p); puts "workflow OK: #{p}" }' "${ROOT_DIR}"/.github/workflows/*.yml
}

check_package_manifest() {
  (cd "$ROOT_DIR" && swift package describe --type json >/dev/null)
}

run_swiftlint() {
  # Check the config before downloading the tool: no point fetching ~10MB to then bail.
  if [[ ! -f "${ROOT_DIR}/.swiftlint.yml" ]]; then
    printf 'ERROR: .swiftlint.yml is required; SwiftLint cannot run without the repo configuration.\n' >&2
    exit 1
  fi
  "${ROOT_DIR}/Scripts/install_lint_tools.sh" swiftlint
  # CLT-only installs need this SourceKit framework path; full-Xcode CI supplies its own.
  if [[ "$(uname -s)" == "Darwin" ]] \
    && [[ "$(xcode-select -p 2>/dev/null || true)" == "/Library/Developer/CommandLineTools" ]]; then
    export DYLD_FRAMEWORK_PATH="/Library/Developer/CommandLineTools/usr/lib${DYLD_FRAMEWORK_PATH:+:${DYLD_FRAMEWORK_PATH}}"
  fi
  (cd "$ROOT_DIR" && "${BIN_DIR}/swiftlint" lint --strict --config .swiftlint.yml)
}

run_portable_checks() {
  check_shell_scripts
  check_workflow_yaml
  check_package_manifest
}

cmd="${1:-lint}"

case "$cmd" in
  lint|lint-linux)
    run_portable_checks
    run_swiftlint
    ;;
  lint-macos)
    run_portable_checks
    ;;
  format)
    printf 'No formatter configured for this repo.\n'
    ;;
  *)
    printf 'Usage: %s [lint|lint-linux|lint-macos|format]\n' "$(basename "$0")" >&2
    exit 2
    ;;
esac
