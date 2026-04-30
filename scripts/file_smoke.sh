#!/usr/bin/env bash
set -euo pipefail

td="$(mktemp -d)"
trap 'rm -rf "$td"; rm -f /tmp/etl_smoke_data.bin' EXIT

cat > "$td/file.etl" <<'ETL'
extern fn etl_write_file(path i8[64], buf i8[64], len i32) i32
extern fn etl_read_file(path i8[64], buf i8[64], cap i32) i32

fn main() i32
  let path i8[64] = "/tmp/etl_smoke_data.bin"
  let outbuf i8[64] = "hello world"
  let w i32 = etl_write_file(path, outbuf, 11)
  if w < 0
    ret 1
  end
  let inbuf i8[64]
  let r i32 = etl_read_file(path, inbuf, 64)
  if r < 0
    ret 2
  end
  if r == 11
    ret 0
  end
  ret 3
end
ETL

scripts/build_etl.sh "$td/file.etl" "$td/file"
"$td/file"
echo "file smoke: ok (write/read returned 0)"
