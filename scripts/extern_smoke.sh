#!/usr/bin/env bash
set -euo pipefail

td="$(mktemp -d)"
trap 'rm -rf "$td"' EXIT

cat > "$td/extern.etl" <<'ETL'
extern fn etl_print_i32(value i32)

fn main() i32
  etl_print_i32(42)
  ret 0
end
ETL

scripts/build_etl.sh "$td/extern.etl" "$td/extern"
set +e
stdout="$("$td/extern")"
status=$?
set -e
if [ "$status" -ne 0 ]; then
  echo "extern smoke: expected exit 0, got $status" >&2
  exit 1
fi
case "$stdout" in
  *42*) ;;
  *)
    echo "extern smoke: expected stdout to contain 42, got: $stdout" >&2
    exit 1
    ;;
esac
echo "extern smoke: ok (printed 42)"
