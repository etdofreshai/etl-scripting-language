#!/usr/bin/env bash
# Smoke test for the calculator REPL (F3.1-calculator-repl).
# Builds examples/cli/calculator.etl via the C backend, feeds
# examples/cli/calculator.input into it, and diffs stdout against
# examples/cli/calculator.expected.  Errors on malformed lines go to
# stderr and are intentionally ignored by the diff.
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

input="examples/cli/calculator.input"
expected="examples/cli/calculator.expected"

if [ ! -f "$input" ]; then
  echo "cli_calculator_smoke: FAIL - missing $input" >&2
  exit 1
fi
if [ ! -f "$expected" ]; then
  echo "cli_calculator_smoke: FAIL - missing $expected" >&2
  exit 1
fi

build_dir="$(mktemp -d)"
trap 'rm -rf "$build_dir"' EXIT

echo "cli_calculator_smoke: building calculator via C backend"
scripts/build_etl.sh examples/cli/calculator.etl "$build_dir/calculator"

echo "cli_calculator_smoke: running calculator"
actual="$build_dir/calculator.out"
"$build_dir/calculator" < "$input" > "$actual" 2>/dev/null
rc=$?
if [ "$rc" -ne 0 ]; then
  echo "cli_calculator_smoke: FAIL - calculator exited $rc (expected 0)" >&2
  exit 1
fi

echo "cli_calculator_smoke: diffing output"
if ! diff -u "$expected" "$actual"; then
  echo "cli_calculator_smoke: FAIL - output does not match expected" >&2
  exit 1
fi

echo "cli_calculator_smoke: ok"
