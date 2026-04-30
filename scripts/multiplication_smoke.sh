#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

src="$tmpdir/multiplication.etl"
out_c="$tmpdir/multiplication.c"
out_bin="$tmpdir/multiplication"

cat >"$src" <<'ETL'
fn main() i32
  let x i32 = 3 * (10 - 2) / 4
  ret x
end
ETL

python3 -m compiler0 compile "$src" -o "$out_c"
cc -Wall -Werror "$out_c" -o "$out_bin"
set +e
"$out_bin"
status=$?
set -e

if [[ "$status" -ne 6 ]]; then
  echo "multiplication smoke: expected exit 6, got $status" >&2
  exit 1
fi

printf 'multiplication smoke: ok (program returned %s)\n' "$status"
