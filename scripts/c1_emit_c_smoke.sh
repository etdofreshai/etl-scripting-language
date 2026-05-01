#!/usr/bin/env bash
set -euo pipefail

td="$(mktemp -d)"
trap 'rm -rf "$td"' EXIT

sed '/^fn main()/,$d' compiler1/main.etl > "$td/test_emit_c_all.etl"
cat compiler1/lex.etl >> "$td/test_emit_c_all.etl"
cat compiler1/parse.etl >> "$td/test_emit_c_all.etl"
cat compiler1/emit_c.etl >> "$td/test_emit_c_all.etl"
cat compiler1/test_emit_c.etl >> "$td/test_emit_c_all.etl"

python3 -m compiler0 compile "$td/test_emit_c_all.etl" -o "$td/test_emit_c.c"
cc -Wall -Werror "$td/test_emit_c.c" -I runtime -o "$td/test_emit_c"

set +e
"$td/test_emit_c"
status=$?
set -e

if [ "$status" -ne 65 ]; then
  echo "c1_emit_c_smoke: FAIL - expected emitted C length exit 65, got $status" >&2
  exit 1
fi

echo "c1_emit_c_smoke: ok (fn main() i32 ret 1 + 2 * (9 - 4) end -> prototype plus arithmetic return C)"
