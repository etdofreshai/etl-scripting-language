#!/usr/bin/env bash
# Deterministic scripted-input runtime smoke test.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

src="$repo_root/examples/visual/scripted_input.etl"
expected="$repo_root/examples/visual/scripted_input.expected"
c_path="$tmpdir/scripted_input.c"
bin="$tmpdir/scripted_input"
stdout_file="$tmpdir/stdout"

python3 -m compiler0 compile "$src" -o "$c_path"
cc -std=c11 -Wall -Werror "$c_path" \
  "$repo_root/runtime/etl_runtime.c" \
  "$repo_root/runtime/etl_input.c" \
  -I "$repo_root/runtime" \
  -o "$bin"

set +e
(cd "$repo_root" && "$bin" > "$stdout_file" 2>&1)
status=$?
set -e

if [ "$status" -ne 0 ]; then
  echo "scripted_input_smoke: FAIL (exit $status)" >&2
  cat "$stdout_file" >&2
  exit 1
fi

if ! diff -u "$expected" "$stdout_file"; then
  echo "scripted_input_smoke: FAIL (stdout golden mismatch)" >&2
  exit 1
fi

echo "scripted_input_smoke: ok"
