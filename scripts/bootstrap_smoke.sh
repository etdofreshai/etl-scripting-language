#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

c_path="$tmpdir/add_main.c"
exe_path="$tmpdir/add_main"

python3 -m compiler0 compile "$repo_root/examples/add_main.etl" -o "$c_path"

if ! diff -u "$repo_root/tests/fixtures/add_main.c" "$c_path"; then
  echo "bootstrap smoke: generated C differs from golden fixture" >&2
  exit 1
fi

cc -Wall -Werror "$c_path" -o "$exe_path"

set +e
"$exe_path"
status=$?
set -e

if [[ "$status" -ne 5 ]]; then
  echo "bootstrap smoke: expected exit code 5, got $status" >&2
  exit 1
fi

echo "bootstrap smoke: ok (example returned $status)"
