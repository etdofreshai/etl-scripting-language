#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

src="$tmpdir/logical.etl"
out_c="$tmpdir/logical.c"
out_bin="$tmpdir/logical"

cat >"$src" <<'ETL'
fn main() i32
  let a bool = true
  let b bool = false
  let c bool = not a
  let d bool = a and b
  let e bool = a or b
  let x i32 = 3
  let y i32 = -x
  ret 0
end
ETL

python3 -m compiler0 compile "$src" -o "$out_c"
cc -Wall -Werror -Wno-unused-variable "$out_c" -o "$out_bin"
set +e
"$out_bin"
status=$?
set -e

if [[ "$status" -ne 0 ]]; then
  echo "logical smoke: expected exit 0, got $status" >&2
  exit 1
fi

printf 'logical smoke: ok (program returned %s)\n' "$status"
