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

  log "Running packaging script tests"
  run node --test "${ROOT_DIR}/Scripts/package-app.test.mjs"
}

# Committed descriptor proofs drifted from the code and needed regeneration
# commits (#219, #289); fail when the renderer no longer draws them.
check_proofs() {
  local out="${ROOT_DIR}/.build/check-proofs"
  local stale=0
  mkdir -p "${out}"

  log "Checking committed descriptor proofs"
  run swift run pdtbar-smoke menu-polish-proof --output "${out}/menu-polish-proof.svg" >/dev/null
  run swift run pdtbar-smoke fixture-proof --output "${out}/fixture-proof.svg" >/dev/null
  if ! cmp -s "${out}/menu-polish-proof.svg" "${ROOT_DIR}/docs/smoke/menu-polish-proof.svg"; then
    printf 'ERROR: docs/smoke/menu-polish-proof.svg is stale. Run: swift run pdtbar-smoke menu-polish-proof --output docs/smoke/menu-polish-proof.svg\n' >&2
    stale=1
  fi
  if ! cmp -s "${out}/fixture-proof.svg" "${ROOT_DIR}/docs/smoke/fixture-proof.svg"; then
    printf 'ERROR: docs/smoke/fixture-proof.svg is stale. Run: swift run pdtbar-smoke fixture-proof\n' >&2
    stale=1
  fi
  return "${stale}"
}

# Every model needs a check.sh, so a new model cannot skip CI. A model that
# replays past bugs in mutations.sh must still catch every one.
check_formal() {
  local dir
  local failed=0

  for dir in "${ROOT_DIR}"/formal/*/; do
    dir="${dir%/}"
    log "Checking formal model $(basename "${dir}")"
    if [[ ! -x "${dir}/check.sh" ]]; then
      printf 'ERROR: %s has no executable check.sh. Add one that exits nonzero when the model fails.\n' "${dir#"${ROOT_DIR}"/}" >&2
      failed=1
      continue
    fi
    run "${dir}/check.sh" || failed=1
    if [[ -f "${dir}/mutations.sh" ]]; then
      run bash "${dir}/mutations.sh" || failed=1
    fi
  done
  return "${failed}"
}

GATE=(lint scripts build tests checks proofs smoke-api formal)

check_gate_matches_ci() {
  local ci_steps gate_steps
  ci_steps="$(ruby -ryaml -e 'YAML.load_file(ARGV[0])["jobs"].each_value { |job| (job["steps"] || []).each { |step| step["run"].to_s.scan(%r{^\./Scripts/check\.sh (\S+)$}) { |m| puts m[0] } } }' "${ROOT_DIR}/.github/workflows/ci.yml")"
  gate_steps="$(printf '%s\n' "${GATE[@]}")"
  if [[ "${ci_steps}" != "${gate_steps}" ]]; then
    printf 'ERROR: .github/workflows/ci.yml runs check.sh steps [%s] but GATE in Scripts/check.sh is [%s]. CI and ./Scripts/check.sh must run one gate, in the same order: change both.\n' \
      "$(tr '\n' ' ' <<<"${ci_steps}")" "$(tr '\n' ' ' <<<"${gate_steps}")" >&2
    return 1
  fi
}

run_step() {
  case "$1" in
    lint) log "Linting"; run "${ROOT_DIR}/Scripts/lint.sh" ;;
    scripts) check_scripts; check_gate_matches_ci ;;
    build) log "Building Swift package"; run swift build ;;
    tests) log "Running Swift tests"; run "${ROOT_DIR}/Scripts/test.sh" ;;
    checks) log "Running deterministic PDTBar checks"; run swift run pdtbar-checks ;;
    proofs) check_proofs ;;
    smoke-api) log "Running scripted API smoke matrix"; run "${ROOT_DIR}/Scripts/api_smoke_matrix.sh" ;;
    formal) check_formal ;;
    *) return 2 ;;
  esac
}

usage() {
  printf 'Usage: %s [all|%s]\n' "$(basename "$0")" "$(IFS='|'; printf '%s' "${GATE[*]}")" >&2
}

cmd="${1:-all}"

cd "${ROOT_DIR}"

if [[ "${cmd}" == all ]]; then
  for step in "${GATE[@]}"; do
    run_step "${step}"
  done
  log "Gate passed: ${GATE[*]}"
elif [[ " ${GATE[*]} " == *" ${cmd} "* ]]; then
  run_step "${cmd}"
else
  usage
  exit 2
fi
