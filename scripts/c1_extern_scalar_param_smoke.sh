#!/usr/bin/env bash
set -euo pipefail

td="$(mktemp -d)"
emitted="/tmp/etl_c1_extern_scalar_param.c"
trap 'rm -rf "$td"; rm -f "$emitted"' EXIT

sed '/^fn main()/,$d' compiler1/main.etl > "$td/test_extern_scalar_param_all.etl"
cat compiler1/lex.etl >> "$td/test_extern_scalar_param_all.etl"
cat compiler1/parse.etl >> "$td/test_extern_scalar_param_all.etl"
cat compiler1/sema.etl >> "$td/test_extern_scalar_param_all.etl"
cat compiler1/emit_c.etl >> "$td/test_extern_scalar_param_all.etl"
cat compiler1/test_extern_scalar_param.etl >> "$td/test_extern_scalar_param_all.etl"

scripts/build_etl.sh "$td/test_extern_scalar_param_all.etl" "$td/test_extern_scalar_param"
"$td/test_extern_scalar_param"

if [ ! -s "$emitted" ]; then
  echo "c1_extern_scalar_param_smoke: FAIL - compiler-1 harness did not write emitted C" >&2
  exit 1
fi

grep -F 'int accept_bool(bool);' "$emitted" >/dev/null
grep -F 'int plus_one(signed char);' "$emitted" >/dev/null

cat > "$td/scalar_helpers.c" <<'C'
#include <stdbool.h>

int accept_bool(bool flag) {
  return flag ? 42 : 7;
}

int plus_one(signed char ch) {
  return ch + 1;
}
C

cc -std=c11 -Wall -Wextra -Werror "$emitted" "$td/scalar_helpers.c" -o "$td/c1_extern_scalar_param"

set +e
"$td/c1_extern_scalar_param"
status=$?
set -e

if [ "$status" -ne 42 ]; then
  echo "c1_extern_scalar_param_smoke: FAIL - expected emitted program exit 42, got $status" >&2
  exit 1
fi

echo "c1_extern_scalar_param_smoke: ok (compiler-1 emitted extern bool/i8 scalar C parameters)"
