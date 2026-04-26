#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

c_path="$tmpdir/add_main.c"
exe_path="$tmpdir/add_main"

python3 -m compiler0.etl0 compile "$repo_root/examples/add_main.etl" -o "$c_path"
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
