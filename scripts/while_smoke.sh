#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

src="$tmpdir/while.etl"
out_c="$tmpdir/while.c"
out_bin="$tmpdir/while"

cat >"$src" <<'ETL'
fn main() i32
  let i i32 = 0
  let sum i32 = 0
  while i < 10
    sum = sum + i
    i = i + 1
  end
  ret sum
end
ETL

python3 -m compiler0 compile "$src" -o "$out_c"
cc -Wall -Werror "$out_c" -o "$out_bin"
set +e
"$out_bin"
status=$?
set -e

if [[ "$status" -ne 45 ]]; then
  echo "while smoke: expected exit 45, got $status" >&2
  exit 1
fi

printf 'while smoke: ok (program returned %s)\n' "$status"
