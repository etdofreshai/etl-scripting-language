#!/usr/bin/env bash
set -euo pipefail

td="$(mktemp -d)"
trap 'rm -rf "$td"' EXIT

sed '/^fn main()/,$d' compiler1/main.etl > "$td/test_emit_bytecode_all.etl"
cat compiler1/lex.etl >> "$td/test_emit_bytecode_all.etl"
cat compiler1/parse.etl >> "$td/test_emit_bytecode_all.etl"
cat compiler1/backend_defs.etl >> "$td/test_emit_bytecode_all.etl"
cat compiler1/emit_bytecode.etl >> "$td/test_emit_bytecode_all.etl"
cat compiler1/test_emit_bytecode.etl >> "$td/test_emit_bytecode_all.etl"

python3 -m compiler0 compile "$td/test_emit_bytecode_all.etl" -o "$td/test_emit_bytecode.c"
cc -Wall -Werror "$td/test_emit_bytecode.c" -I runtime -o "$td/test_emit_bytecode"

set +e
"$td/test_emit_bytecode"
status=$?
set -e

if [ "$status" -ne 51 ]; then
  echo "c1_emit_bytecode_smoke: FAIL - expected emitted bytecode length exit 51, got $status" >&2
  exit 1
fi

echo "c1_emit_bytecode_smoke: ok (integer return expression -> ETL function bytecode scaffold)"
