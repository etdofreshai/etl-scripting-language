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

cc -std=c11 -Wall -Wextra -Werror "$emitted" runtime/etl_runtime.c -I runtime -o "$td/c1_extern_call"
stdout="$("$td/c1_extern_call")"

if [ "$stdout" != "42" ]; then
  echo "c1_extern_call_smoke: FAIL - expected stdout 42, got: $stdout" >&2
  exit 1
fi

echo "c1_extern_call_smoke: ok (compiler-1 emitted extern call C and printed 42)"
