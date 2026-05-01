#!/usr/bin/env bash
set -euo pipefail

td="$(mktemp -d)"
emitted="/tmp/etl_c1_extern_call.c"
trap 'rm -rf "$td"; rm -f "$emitted"' EXIT

sed '/^fn main()/,$d' compiler1/main.etl > "$td/test_extern_call_all.etl"
cat compiler1/lex.etl >> "$td/test_extern_call_all.etl"
cat compiler1/parse.etl >> "$td/test_extern_call_all.etl"
cat compiler1/sema.etl >> "$td/test_extern_call_all.etl"
cat compiler1/emit_c.etl >> "$td/test_extern_call_all.etl"
cat compiler1/test_extern_call.etl >> "$td/test_extern_call_all.etl"

scripts/build_etl.sh "$td/test_extern_call_all.etl" "$td/test_extern_call"
"$td/test_extern_call"

if [ ! -s "$emitted" ]; then
  echo "c1_extern_call_smoke: FAIL - compiler-1 harness did not write emitted C" >&2
  exit 1
fi

cat > "$td/identity_i32.c" <<'C'
int etl_identity_i32(int value) {
  return value;
}
C
cc -std=c11 -Wall -Wextra -Werror "$emitted" "$td/identity_i32.c" runtime/etl_runtime.c -I runtime -o "$td/c1_extern_call"

set +e
stdout="$("$td/c1_extern_call")"
status=$?
set -e

if [ "$stdout" != "42" ]; then
  echo "c1_extern_call_smoke: FAIL - expected stdout 42, got: $stdout" >&2
  exit 1
fi

if [ "$status" -ne 42 ]; then
  echo "c1_extern_call_smoke: FAIL - expected exit 42 from return-valued extern call, got: $status" >&2
  exit 1
fi

echo "c1_extern_call_smoke: ok (compiler-1 emitted void and return-valued extern call C)"
