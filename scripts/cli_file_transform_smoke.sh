#!/usr/bin/env bash
# Smoke test for the file_transform CLI example (F3.2-file-transform).
# Builds examples/cli/file_transform.etl via the C backend, feeds
# examples/cli/file_transform.input into it, and diffs output against
# examples/cli/file_transform.expected.
# Also verifies that a missing input file yields exit code 1 (not a crash).
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

input="examples/cli/file_transform.input"
expected="examples/cli/file_transform.expected"

if [ ! -f "$input" ]; then
  echo "cli_file_transform_smoke: FAIL - missing $input" >&2
  exit 1
fi
if [ ! -f "$expected" ]; then
  echo "cli_file_transform_smoke: FAIL - missing $expected" >&2
  exit 1
fi

build_dir="$(mktemp -d)"
trap 'rm -rf "$build_dir"' EXIT

echo "cli_file_transform_smoke: building file_transform via C backend"
scripts/build_etl.sh examples/cli/file_transform.etl "$build_dir/file_transform"

echo "cli_file_transform_smoke: running round-trip (uppercase)"
actual="$build_dir/file_transform.out"
"$build_dir/file_transform" "$input" "$actual"
rc=$?
if [ "$rc" -ne 0 ]; then
  echo "cli_file_transform_smoke: FAIL - file_transform exited $rc (expected 0)" >&2
  exit 1
fi

echo "cli_file_transform_smoke: diffing output"
if ! diff -u "$expected" "$actual"; then
  echo "cli_file_transform_smoke: FAIL - output does not match expected" >&2
  exit 1
fi

echo "cli_file_transform_smoke: testing missing-file error path"
set +e
"$build_dir/file_transform" /tmp/etl_no_such_file_xyz.txt "$build_dir/no_out.txt" 2>/dev/null
missing_rc=$?
set -e
if [ "$missing_rc" -ne 1 ]; then
  echo "cli_file_transform_smoke: FAIL - missing-file expected exit 1, got $missing_rc" >&2
  exit 1
fi

echo "cli_file_transform_smoke: ok"
