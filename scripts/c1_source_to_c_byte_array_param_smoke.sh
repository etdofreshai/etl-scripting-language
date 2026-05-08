#!/usr/bin/env bash
set -euo pipefail

td="$(mktemp -d)"
emitted="/tmp/etl_c1_source_to_c_byte_array_param.c"
trap 'rm -rf "$td"; rm -f "$emitted"' EXIT

sed '/^fn main()/,$d' compiler1/main.etl > "$td/test_source_to_c_byte_array_param_all.etl"
cat compiler1/lex.etl >> "$td/test_source_to_c_byte_array_param_all.etl"
cat compiler1/parse.etl >> "$td/test_source_to_c_byte_array_param_all.etl"
cat compiler1/sema.etl >> "$td/test_source_to_c_byte_array_param_all.etl"
cat compiler1/emit_c.etl >> "$td/test_source_to_c_byte_array_param_all.etl"
cat compiler1/test_source_to_c_byte_array_param.etl >> "$td/test_source_to_c_byte_array_param_all.etl"

scripts/build_etl.sh "$td/test_source_to_c_byte_array_param_all.etl" "$td/test_source_to_c_byte_array_param"
"$td/test_source_to_c_byte_array_param"

if [ ! -s "$emitted" ]; then
  echo "c1_source_to_c_byte_array_param_smoke: FAIL - compiler-1 harness did not write emitted C" >&2
  exit 1
fi

cc -Wall -Werror "$emitted" -o "$td/c1_emitted_byte_array_param"
set +e
"$td/c1_emitted_byte_array_param"
status=$?
set -e

if [ "$status" -ne 96 ]; then
  echo "c1_source_to_c_byte_array_param_smoke: FAIL - expected emitted program exit 96, got $status" >&2
  exit 1
fi

echo "c1_source_to_c_byte_array_param_smoke: ok (compiler-1 emitted user-defined byte-array parameter C returning 96)"
