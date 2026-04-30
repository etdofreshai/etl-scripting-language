#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

src="$tmpdir/expression.etl"
out_c="$tmpdir/expression.c"
out_bin="$tmpdir/expression"

cat >"$src" <<'ETL'
fn dec(x i32) i32
  ret x - 1
end

fn add(a i32, b i32) i32
  ret a + b
end

fn main() i32
  let base i32 = add(dec(10), 1)
  ret (base + 2) - dec(3)
end
ETL

python3 -m compiler0 compile "$src" -o "$out_c"
cc -Wall -Werror "$out_c" -o "$out_bin"
set +e
"$out_bin"
status=$?
set -e

if [[ "$status" -ne 10 ]]; then
  echo "expression smoke: expected exit 10, got $status" >&2
  exit 1
fi

printf 'expression smoke: ok (program returned %s)\n' "$status"
