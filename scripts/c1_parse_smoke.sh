#!/usr/bin/env bash
set -euo pipefail

td="$(mktemp -d)"
trap 'rm -rf "$td"' EXIT

sed '/^fn main()/,$d' compiler1/main.etl > "$td/test_parse_all.etl"
cat compiler1/lex.etl >> "$td/test_parse_all.etl"
cat compiler1/parse.etl >> "$td/test_parse_all.etl"
cat compiler1/test_parse.etl >> "$td/test_parse_all.etl"

python3 -m compiler0 compile "$td/test_parse_all.etl" -o "$td/test_parse.c"
cc -Wall -Werror "$td/test_parse.c" -I runtime -o "$td/test_parse"

set +e
"$td/test_parse"
status=$?
set -e

if [ "$status" -ne 7 ]; then
  echo "c1_parse_smoke: FAIL - expected AST prefix exit 7, got $status" >&2
  exit 1
fi

echo "c1_parse_smoke: ok (fn main() i32 ret 42 end -> PARAMS TYPE INT RET LIST BLOCK FN ...)"
