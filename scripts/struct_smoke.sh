#!/usr/bin/env bash
set -euo pipefail

td="$(mktemp -d)"
trap 'rm -rf "$td"' EXIT

cat > "$td/struct.etl" <<'ETL'
type Point struct
  x i32
  y i32
end

fn main() i32
  let pts Point[3]
  let i i32 = 0
  while i < 3
    pts[i].x = i
    pts[i].y = i + 10
    i = i + 1
  end
  let sum i32 = 0
  let j i32 = 0
  while j < 3
    sum = sum + pts[j].x + pts[j].y
    j = j + 1
  end
  ret sum
end
ETL

python3 -m compiler0 compile "$td/struct.etl" -o "$td/struct.c"
cc -Wall -Werror "$td/struct.c" -o "$td/struct"
set +e
"$td/struct"
status=$?
set -e
if [ "$status" -ne 36 ]; then
  echo "struct smoke: expected 36, got $status" >&2
  exit 1
fi
echo "struct smoke: ok (program returned 36)"
