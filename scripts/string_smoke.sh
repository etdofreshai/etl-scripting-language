#!/usr/bin/env bash
set -euo pipefail

td="$(mktemp -d)"
trap 'rm -rf "$td"' EXIT

cat > "$td/string.etl" <<'ETL'
fn main() i32
  let s i8[6] = "hello"
  ret sizeof(i32)
end
ETL

python3 -m compiler0 compile "$td/string.etl" -o "$td/string.c"
cc -Wall -Werror -Wno-unused-variable "$td/string.c" -o "$td/string"
set +e
"$td/string"
status=$?
set -e
if [ "$status" -ne 4 ]; then
  echo "string smoke: expected 4, got $status" >&2
  exit 1
fi
echo "string smoke: ok (program returned $status)"
