#!/bin/bash
# Runs the self-checks that don't need audio or a model.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
swiftc -parse-as-library -Onone src/HallucinationFilter.swift tests/FilterCheck.swift -o "$OUT/check"
"$OUT/check"
