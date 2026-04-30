#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

src="$tmpdir/if.etl"
out_c="$tmpdir/if.c"
out_bin="$tmpdir/if"

cat >"$src" <<'ETL'
fn max(a i32, b i32) i32
  if a > b
    ret a
  else
    ret b
  end
end

fn main() i32
  ret max(7, 3)
end
ETL

python3 -m compiler0 compile "$src" -o "$out_c"
cc -Wall -Werror "$out_c" -o "$out_bin"
set +e
"$out_bin"
status=$?
set -e

if [[ "$status" -ne 7 ]]; then
  echo "if smoke: expected exit 7, got $status" >&2
  exit 1
fi

printf 'if smoke: ok (program returned %s)\n' "$status"
