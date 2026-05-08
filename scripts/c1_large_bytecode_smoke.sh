#!/usr/bin/env bash
# c1_large_bytecode_smoke.sh — verifies that the 65536-byte bytecode buffer
# can emit > 1024 bytes of bytecode (F2.0 regression guard).
#
# Compiles tests/c1_corpus/large_bytecode.etl via both backends and asserts:
#   1. Bytecode size > 1024 bytes (buffer expansion is exercised).
#   2. Both c0 and c1/VM backends return exit 42.

set -euo pipefail

td="$(mktemp -d)"
trap 'rm -rf "$td"' EXIT

src="tests/c1_corpus/large_bytecode.etl"
bc_path="$td/large_bytecode.bc"

# Build a file-reading VM runner (same pattern as c1_vm_function_smoke.sh)
cat > "$td/run_vm.c" << 'CVMEOF'
#include "etl_vm.h"
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#define ETL_VM_RUN_MAX (1 << 16)
int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "usage: run_vm <bytecode_file>\n"); return 1; }
    FILE *f = fopen(argv[1], "rb");
    if (!f) { fprintf(stderr, "run_vm: cannot open %s\n", argv[1]); return 1; }
    static int8_t buf[ETL_VM_RUN_MAX];
    size_t n = fread(buf, 1, ETL_VM_RUN_MAX, f);
    fclose(f);
    if (n == ETL_VM_RUN_MAX) { fprintf(stderr, "run_vm: bytecode larger than %d bytes\n", ETL_VM_RUN_MAX); return 1; }
    int32_t result = 0;
    int32_t status = etl_vm_run_main_i32(buf, (int32_t)n, &result);
    if (status != 0) { fprintf(stderr, "run_vm: vm error %d\n", status); return 1; }
    if (result < 0 || result > 255) { fprintf(stderr, "run_vm: result %d out of u8 range\n", result); return 1; }
    return (int)result;
}
CVMEOF
cc -std=c11 -Wall -Wextra -Werror "$td/run_vm.c" runtime/etl_vm.c runtime/etl_string.c runtime/etl_dynarr.c runtime/etl_etlval.c -I runtime -o "$td/run_vm"

# --- 1. c0 (native C) backend ---
c0_bin="$td/large_bytecode_c0"
scripts/build_etl.sh "$src" "$c0_bin"
set +e
"$c0_bin" >/dev/null 2>&1
c0_status=$?
set -e
if [ "$c0_status" -ne 42 ]; then
  echo "c1_large_bytecode_smoke: FAIL c0 returned $c0_status (expected 42)" >&2
  exit 1
fi

# --- 2. c1 bytecode emission pipeline ---
harness="$td/bc_harness.etl"
sed '/^fn main()/,$d' compiler1/main.etl > "$harness"
cat compiler1/lex.etl >> "$harness"
cat compiler1/parse.etl >> "$harness"
cat compiler1/sema.etl >> "$harness"
cat compiler1/backend_defs.etl >> "$harness"
cat compiler1/emit_bytecode.etl >> "$harness"
cat >> "$harness" <<HARNESS_EOF
extern fn etl_write_file1024(path i8[64], buf i8[65536], len i32) i32

fn main() i32
  let stdin_path i8[64] = "/dev/stdin"
  let source i8[131072]
  let n_read i32 = etl_read_file(stdin_path, source, 131072)
  if n_read < 0
    ret 10
  end
  let tokens Token[32768]
  let ast AstNode[32768]
  let out i8[65536]
  let n_tok i32 = lex(source, n_read, tokens, 32768)
  if n_tok < 0
    ret 11
  end
  let an i32 = parse(tokens, n_tok, ast, 32768)
  if an < 0
    ret 12
  end
  if sema(source, tokens, ast, an) < 0
    ret 13
  end
  let n_out i32 = emit_bytecode(source, tokens, ast, an, out, 65536)
  if n_out < 0
    ret 14
  end
  let path i8[64] = "$bc_path"
  if etl_write_file1024(path, out, n_out) < 0
    ret 15
  end
  ret 0
end
HARNESS_EOF

harness_bin="$td/bc_harness"
scripts/build_etl.sh "$harness" "$harness_bin"
"$harness_bin" < "$src"

bc_size="$(wc -c < "$bc_path")"
if [ "$bc_size" -le 1024 ]; then
  echo "c1_large_bytecode_smoke: FAIL bytecode too small: $bc_size bytes (expected >1024)" >&2
  exit 1
fi

# --- 3. VM backend ---
set +e
"$td/run_vm" "$bc_path" >/dev/null 2>&1
vm_status=$?
set -e

if [ "$vm_status" -ne 42 ]; then
  echo "c1_large_bytecode_smoke: FAIL VM returned $vm_status (expected 42, bc=$bc_size bytes)" >&2
  exit 1
fi

echo "c1_large_bytecode_smoke: ok (bc=$bc_size bytes > 1024; c0=$c0_status VM=$vm_status)"
