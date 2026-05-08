#!/usr/bin/env bash
# Verify heap_alloc_basic.etl compiles and runs under the VM backend (HA;/HF; opcodes).
set -euo pipefail

td="$(mktemp -d)"
trap 'rm -rf "$td"' EXIT

fixture="tests/c1_corpus/heap_alloc_basic.etl"
bytecode_path="$td/heap_alloc_basic.bc"

# Build a harness that lexes/parses/emits-bytecode for the fixture
source_text="$(sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' "$fixture" | tr '\n' ' ')"
source_len="$(tr '\n' ' ' < "$fixture" | wc -c)"

harness="$td/heap_alloc_bc_harness.etl"
sed '/^fn main()/,$d' compiler1/main.etl > "$harness"
cat compiler1/lex.etl >> "$harness"
cat compiler1/parse.etl >> "$harness"
cat compiler1/backend_defs.etl >> "$harness"
cat compiler1/emit_bytecode.etl >> "$harness"
cat >> "$harness" <<EOF_HARNESS
extern fn etl_write_file1024(path i8[64], buf i8[1024], len i32) i32

fn main() i32
  let source i8[131072] = "$source_text"
  let tokens Token[32768]
  let ast AstNode[32768]
  let out i8[1024]
  let n i32 = lex(source, $source_len, tokens, 32768)
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
EOF_HARNESS

scripts/build_etl.sh "$harness" "$td/heap_alloc_bc_harness"
"$td/heap_alloc_bc_harness"

if [ ! -s "$bytecode_path" ]; then
  echo "c1_vm_heap_alloc_smoke: FAIL bytecode file empty or missing" >&2
  exit 1
fi

# Build a VM runner
cat > "$td/vm_runner.c" <<'EOF_C'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "etl_vm.h"

int main(int argc, char **argv) {
  if (argc < 2) return 1;
  FILE *f = fopen(argv[1], "r");
  if (!f) return 2;
  char buf[4096];
  int n = (int)fread(buf, 1, sizeof(buf) - 1, f);
  fclose(f);
  if (n <= 0) return 3;
  buf[n] = 0;
  int32_t result = 0;
  int32_t rc = etl_vm_run_main_i32((const int8_t*)buf, n, &result);
  if (rc != 0) { fprintf(stderr, "vm error: %d\n", rc); return 4; }
  return (int)result;
}
EOF_C

cc -std=c11 -Wall -Werror -I runtime "$td/vm_runner.c" runtime/etl_vm.c -o "$td/vm_runner"

set +e
"$td/vm_runner" "$bytecode_path"
vm_exit=$?
set -e

if [ "$vm_exit" -ne 0 ]; then
  echo "c1_vm_heap_alloc_smoke: FAIL VM exit $vm_exit (expected 0)" >&2
  exit 1
fi

echo "c1_vm_heap_alloc_smoke: PASS heap_alloc_basic.etl via VM backend (exit 0)"
