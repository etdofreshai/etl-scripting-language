#!/usr/bin/env bash
set -euo pipefail

td="$(mktemp -d)"
trap 'rm -rf "$td"; rm -f /tmp/etl_c1_vm_return.bc' EXIT

bytecode_path="/tmp/etl_c1_vm_return.bc"

sed '/^fn main()/,$d' compiler1/main.etl > "$td/c1_bytecode_pipeline.etl"
cat compiler1/lex.etl >> "$td/c1_bytecode_pipeline.etl"
cat compiler1/parse.etl >> "$td/c1_bytecode_pipeline.etl"
cat compiler1/backend_defs.etl >> "$td/c1_bytecode_pipeline.etl"
cat compiler1/emit_bytecode.etl >> "$td/c1_bytecode_pipeline.etl"
cat >> "$td/c1_bytecode_pipeline.etl" <<HARNESS
extern fn etl_write_file1024(path i8[64], buf i8[1024], len i32) i32

fn main() i32
  let source i8[131072] = "fn main() i32 ret 1 + 2 * (9 - 4) end"
  let tokens Token[32768]
  let ast AstNode[32768]
  let out i8[1024]
  let n i32 = lex(source, 37, tokens, 32768)
  if n < 0
    ret 1
  end
  let an i32 = parse(tokens, n, ast, 32768)
  if an < 0
    ret 2
  end
  let emitted i32 = emit_bytecode(source, tokens, ast, an, out, 1024)
  if emitted < 0
    ret 3
  end
  let path i8[64] = "$bytecode_path"
  if etl_write_file1024(path, out, emitted) < 0
    ret 4
  end
  ret 0
end
HARNESS

python3 -m compiler0 compile "$td/c1_bytecode_pipeline.etl" -o "$td/c1_bytecode_pipeline.c"
cc -Wall -Werror "$td/c1_bytecode_pipeline.c" runtime/etl_runtime.c -I runtime -o "$td/c1_bytecode_pipeline"
"$td/c1_bytecode_pipeline"

if [ "$(wc -c < "$bytecode_path")" -ne 51 ]; then
  echo "c1_vm_return_smoke: FAIL - expected 51 byte bytecode output" >&2
  exit 1
fi

if [ "$(tr -d '\n' < "$bytecode_path")" != "ETLB1;T1;Dmain,0;Cmain;R;@main;I1;I2;I9;I4;-;*;+;R;" ]; then
  echo "c1_vm_return_smoke: FAIL - unexpected bytecode payload" >&2
  exit 1
fi

cc -std=c11 -Wall -Wextra -Werror runtime/test_vm.c runtime/etl_vm.c -I runtime -o "$td/test_vm"
"$td/test_vm"

echo "c1_vm_return_smoke: ok (compiler-1 stack bytecode executes via minimal ETL VM)"
