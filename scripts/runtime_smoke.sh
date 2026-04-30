#!/usr/bin/env bash
set -euo pipefail

td="$(mktemp -d)"
trap 'rm -rf "$td"' EXIT

cat > "$td/runtime.etl" <<'ETL'
extern fn etl_alloc(bytes i32) ptr
extern fn etl_free(p ptr)
extern fn etl_is_null(p ptr) bool
extern fn etl_write_file(path i8[64], buf i8[64], len i32) i32
extern fn etl_read_file(path i8[64], buf i8[64], cap i32) i32

fn main() i32
  let buf ptr = etl_alloc(16)
  if etl_is_null(buf)
    ret 1
  end
  etl_free(buf)
  ret 0
end
ETL

scripts/build_etl.sh "$td/runtime.etl" "$td/runtime"
"$td/runtime"
echo "runtime smoke: ok (alloc/free returned 0)"
