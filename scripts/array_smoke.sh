#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

src="$tmpdir/array.etl"
out_c="$tmpdir/array.c"
out_bin="$tmpdir/array"

cat >"$src" <<'ETL'
fn main() i32
  let buf i32[5]
  let i i32 = 0
  while i < 5
    buf[i] = i * i
    i = i + 1
  end
  let sum i32 = 0
  let j i32 = 0
  while j < 5
    sum = sum + buf[j]
    j = j + 1
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

if [[ "$status" -ne 30 ]]; then
  echo "array smoke: expected exit 30, got $status" >&2
  exit 1
fi

printf 'array smoke: ok (program returned %s)\n' "$status"
