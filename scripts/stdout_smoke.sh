#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

exe_path="$tmpdir/add_main_stdout"

python3 -m compiler0 compile "$repo_root/examples/add_main.etl" -o - \
  | cc -Wall -Werror -x c - -o "$exe_path"

set +e
"$exe_path"
status=$?
set -e

if [[ "$status" -ne 5 ]]; then
  echo "stdout smoke: expected exit code 5, got $status" >&2
  exit 1
fi

echo "stdout smoke: ok (example returned $status)"
