#!/usr/bin/env bash
set -euo pipefail

td="$(mktemp -d)"
bool_emitted="/tmp/etl_c1_source_to_c_bool_param.c"
i8_emitted="/tmp/etl_c1_source_to_c_i8_param.c"
byte_emitted="/tmp/etl_c1_source_to_c_byte_param.c"
trap 'rm -rf "$td"; rm -f "$bool_emitted" "$i8_emitted" "$byte_emitted"' EXIT

sed '/^fn main()/,$d' compiler1/main.etl > "$td/test_source_to_c_scalar_param_all.etl"
cat compiler1/lex.etl >> "$td/test_source_to_c_scalar_param_all.etl"
cat compiler1/parse.etl >> "$td/test_source_to_c_scalar_param_all.etl"
cat compiler1/sema.etl >> "$td/test_source_to_c_scalar_param_all.etl"
cat compiler1/emit_c.etl >> "$td/test_source_to_c_scalar_param_all.etl"
cat compiler1/test_source_to_c_scalar_param.etl >> "$td/test_source_to_c_scalar_param_all.etl"

scripts/build_etl.sh "$td/test_source_to_c_scalar_param_all.etl" "$td/test_source_to_c_scalar_param"
"$td/test_source_to_c_scalar_param"

run_case() {
  local name="$1"
  local emitted="$2"
  local exe="$td/$name"

  if [ ! -s "$emitted" ]; then
    echo "c1_source_to_c_scalar_param_smoke: FAIL - missing emitted C for $name" >&2
    exit 1
  fi

  cc -Wall -Werror "$emitted" -o "$exe"
  set +e
  "$exe"
  status=$?
  set -e

  if [ "$status" -ne 42 ]; then
    echo "c1_source_to_c_scalar_param_smoke: FAIL - $name expected exit 42, got $status" >&2
    exit 1
  fi
}

run_case bool_param "$bool_emitted"
run_case i8_param "$i8_emitted"
run_case byte_param "$byte_emitted"

echo "c1_source_to_c_scalar_param_smoke: ok (compiler-1 emitted bool/i8/byte scalar parameter C returning 42)"
