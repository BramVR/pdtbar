#!/usr/bin/env bash
# Run TLC on one PDTBar TLA+ model with a pinned, checksummed tla2tools.jar.
# Usage: Scripts/formal/tlc.sh <Spec.tla> [<Spec.cfg>] [extra TLC args...]
set -euo pipefail

TLA_VERSION="1.7.4"
TLA_SHA256="936a262061c914694dfd669a543be24573c45d5aa0ff20a8b96b23d01e050e88"
CACHE_DIR="${PDTBAR_TLA_CACHE:-$HOME/.cache/tlaplus}"
JAR="$CACHE_DIR/tla2tools-$TLA_VERSION.jar"

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <Spec.tla> [<Spec.cfg>] [extra TLC args...]" >&2
  exit 2
fi

if ! command -v java >/dev/null 2>&1; then
  echo "tlc.sh: java not found; install a JDK 11+ (e.g. mise use java@temurin-25)" >&2
  exit 2
fi

if [[ ! -f "$JAR" ]]; then
  mkdir -p "$CACHE_DIR"
  curl -fsSL -o "$JAR.tmp" "https://github.com/tlaplus/tlaplus/releases/download/v$TLA_VERSION/tla2tools.jar"
  mv "$JAR.tmp" "$JAR"
fi
actual="$(shasum -a 256 "$JAR" | awk '{print $1}')"
if [[ "$actual" != "$TLA_SHA256" ]]; then
  echo "tlc.sh: checksum mismatch for $JAR ($actual)" >&2
  exit 2
fi

spec="$1"; shift
cfg="${spec%.tla}.cfg"
if [[ $# -gt 0 && "$1" == *.cfg ]]; then
  cfg="$1"; shift
fi

spec_dir="$(cd "$(dirname "$spec")" && pwd)"
meta_dir="$(mktemp -d "${TMPDIR:-/tmp}/pdtbar-tlc.XXXXXX")"
trap 'rm -rf "$meta_dir"' EXIT

cd "$spec_dir"
java -XX:+UseParallelGC -cp "$JAR" tlc2.TLC \
  -config "$(basename "$cfg")" -metadir "$meta_dir" -workers auto -cleanup \
  "$@" "$(basename "$spec")"
