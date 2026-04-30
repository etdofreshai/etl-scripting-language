#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

src="$tmpdir/fib.etl"
out_c="$tmpdir/fib.c"
out_bin="$tmpdir/fib"

cat >"$src" <<'ETL'
fn fib(n i32) i32
  if n < 2
    ret n
  end
  let a i32 = 0
  let b i32 = 1
  let i i32 = 2
  while i <= n
    let t i32 = a + b
    a = b
    b = t
    i = i + 1
  end
  ret b
end

fn main() i32
  ret fib(10)
end
ETL

python3 -m compiler0 compile "$src" -o "$out_c"
cc -Wall -Werror "$out_c" -o "$out_bin"
set +e
"$out_bin"
status=$?
set -e

if [[ "$status" -ne 55 ]]; then
  echo "fib smoke: expected exit 55, got $status" >&2
  exit 1
fi

printf 'fib smoke: ok (program returned %s)\n' "$status"
