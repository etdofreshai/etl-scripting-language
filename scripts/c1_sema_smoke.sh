#!/usr/bin/env bash
set -euo pipefail

td="$(mktemp -d)"
trap 'rm -rf "$td"' EXIT

sed '/^fn main()/,$d' compiler1/main.etl > "$td/test_sema_all.etl"
cat compiler1/lex.etl >> "$td/test_sema_all.etl"
cat compiler1/parse.etl >> "$td/test_sema_all.etl"
cat compiler1/sema.etl >> "$td/test_sema_all.etl"
cat compiler1/test_sema.etl >> "$td/test_sema_all.etl"

python3 -m compiler0 compile "$td/test_sema_all.etl" -o "$td/test_sema.c"
cc -Wall -Werror "$td/test_sema.c" -I runtime -o "$td/test_sema"

set +e
"$td/test_sema"
status=$?
set -e

if [ "$status" -ne 9 ]; then
  echo "c1_sema_smoke: FAIL - expected sema smoke exit 9, got $status" >&2
  exit 1
fi

echo "c1_sema_smoke: ok (parsed fn main accepted; hardcoded sema rejection ASTs rejected)"
