#!/usr/bin/env bash
set -euo pipefail

td="$(mktemp -d)"
emitted="/tmp/etl_c1_source_to_c_byte_string_extern.c"
trap 'rm -rf "$td"; rm -f "$emitted"' EXIT

sed '/^fn main()/,$d' compiler1/main.etl > "$td/test_source_to_c_byte_string_extern_all.etl"
cat compiler1/lex.etl >> "$td/test_source_to_c_byte_string_extern_all.etl"
cat compiler1/parse.etl >> "$td/test_source_to_c_byte_string_extern_all.etl"
cat compiler1/sema.etl >> "$td/test_source_to_c_byte_string_extern_all.etl"
cat compiler1/emit_c.etl >> "$td/test_source_to_c_byte_string_extern_all.etl"
cat compiler1/test_source_to_c_byte_string_extern.etl >> "$td/test_source_to_c_byte_string_extern_all.etl"

scripts/build_etl.sh "$td/test_source_to_c_byte_string_extern_all.etl" "$td/test_source_to_c_byte_string_extern"
"$td/test_source_to_c_byte_string_extern"

if [ ! -s "$emitted" ]; then
  echo "c1_source_to_c_byte_string_extern_smoke: FAIL - compiler-1 harness did not write emitted C" >&2
  exit 1
fi

cat > "$td/sum_bytes.c" <<'C'
int etl_sum_bytes(signed char *buf) {
  return (int)buf[0] + (int)buf[1] + (int)buf[2] - (int)buf[3];
}
C

cc -Wall -Werror "$emitted" "$td/sum_bytes.c" -o "$td/c1_emitted_byte_string_extern"
set +e
"$td/c1_emitted_byte_string_extern"
status=$?
set -e

if [ "$status" -ne 38 ]; then
  echo "c1_source_to_c_byte_string_extern_smoke: FAIL - expected emitted program exit 38, got $status" >&2
  exit 1
fi

echo "c1_source_to_c_byte_string_extern_smoke: ok (compiler-1 emitted byte string local passed to extern C pointer parameter)"
