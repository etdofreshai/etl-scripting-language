#!/usr/bin/env bash
set -euo pipefail

td="$(mktemp -d)"
trap 'rm -rf "$td"' EXIT

# ETL v0 has no imports yet. Build one translation unit from compiler-1 shared
# declarations, the lexer implementation, and this smoke's main function.
sed '/^fn main()/,$d' compiler1/main.etl > "$td/test_lex_all.etl"
cat compiler1/lex.etl >> "$td/test_lex_all.etl"
cat compiler1/test_lex.etl >> "$td/test_lex_all.etl"

python3 -m compiler0 compile "$td/test_lex_all.etl" -o "$td/test_lex.c"
cc -Wall -Werror "$td/test_lex.c" -I runtime -o "$td/test_lex"

set +e
"$td/test_lex"
status=$?
set -e

if [ "$status" -ne 9 ]; then
  echo "c1_lex_smoke: FAIL - expected token count exit 9, got $status" >&2
  exit 1
fi

echo "c1_lex_smoke: ok (fn main() i32 ret 42 end -> FN IDENT LPAREN RPAREN IDENT RET INT END EOF)"
