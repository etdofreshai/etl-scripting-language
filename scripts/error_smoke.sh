#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

bad_src="$tmpdir/bad.etl"
out_c="$tmpdir/out.c"
stderr_log="$tmpdir/stderr.log"

cat >"$bad_src" <<'ETL'
fn main() u32 {
  ret 0
}
ETL

printf 'previous generated C\n' >"$out_c"

set +e
python3 -m compiler0 compile "$bad_src" -o "$out_c" 2>"$stderr_log"
status=$?
set -e

if [[ "$status" -ne 1 ]]; then
  echo "error smoke: expected compiler exit 1, got $status" >&2
  exit 1
fi

if ! grep -Fq "etl0: error: $bad_src: 1:1: function 'main' must return i32" "$stderr_log"; then
  echo "error smoke: missing path-qualified semantic diagnostic" >&2
  cat "$stderr_log" >&2
  exit 1
fi

if [[ "$(cat "$out_c")" != "previous generated C" ]]; then
  echo "error smoke: failed compile modified existing output" >&2
  exit 1
fi

printf 'error smoke: ok (bad source failed safely)\n'
