#!/usr/bin/env bash
set -euo pipefail

td="$(mktemp -d)"
trap 'rm -rf "$td"' EXIT

cat > "$td/sizeof.etl" <<'ETL'
type Pt struct
  x i32
  y i32
end

fn main() i32
  ret sizeof(Pt)
end
ETL

python3 -m compiler0 compile "$td/sizeof.etl" -o "$td/sizeof.c"
cc -Wall -Werror "$td/sizeof.c" -o "$td/sizeof"
set +e
"$td/sizeof"
status=$?
set -e
if [ "$status" -ne 8 ]; then
  echo "sizeof smoke: expected 8, got $status" >&2
  exit 1
fi
echo "sizeof smoke: ok (program returned $status)"
