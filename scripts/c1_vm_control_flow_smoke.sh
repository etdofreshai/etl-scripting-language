#!/usr/bin/env bash
# c1_vm_control_flow_smoke.sh
#
# Equivalence smoke for the bootstrap ETL VM control-flow subset.
#
# For each tiny ETL source program below, this script compiles and runs the
# program three ways and asserts all three exit codes match the expected
# value:
#
#   1. c0 path:   compiler-0 -> C -> cc -> exe -> exit code
#   2. c1/C path: compiler-1 emit_c (built via c0) -> C -> cc -> exe
#   3. c1/VM:    compiler-1 emit_bytecode (built via c0) -> bytecode file
#                -> tiny C harness over runtime/etl_vm.c -> exit code
#
# Coverage exercised here:
#   - comparisons
#   - if / elif / else
#   - while loops over local assignment
#
set -euo pipefail

td="$(mktemp -d)"
trap 'rm -rf "$td"' EXIT

# Build a tiny VM harness that reads a bytecode file and runs the VM.
# Exit code is the i32 result truncated to the lowest 8 bits, matching how
# the c0/c1 native paths exit with their `ret` value.
cat > "$td/run_vm.c" <<'CHARNESS'
#include "etl_vm.h"
#include <stdio.h>
#include <stdlib.h>

#define ETL_VM_RUN_MAX (1 << 16)

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: run_vm <bytecode_file>\n");
        return 200;
    }
    FILE *f = fopen(argv[1], "rb");
    if (!f) {
        perror("fopen");
        return 201;
    }
    static int8_t buf[ETL_VM_RUN_MAX];
    size_t n = fread(buf, 1, ETL_VM_RUN_MAX, f);
    int eof = feof(f);
    fclose(f);
    if (!eof) {
        fprintf(stderr, "run_vm: bytecode larger than %d bytes\n", ETL_VM_RUN_MAX);
        return 202;
    }
    int32_t result = 0;
    int32_t status = etl_vm_run_main_i32(buf, (int32_t)n, &result);
    if (status != 0) {
        fprintf(stderr, "run_vm: vm error %d\n", status);
        return 203;
    }
    if (result < 0 || result > 255) {
        fprintf(stderr, "run_vm: result %d out of u8 range\n", result);
        return 204;
    }
    return (int)result;
}
CHARNESS

cc -std=c11 -Wall -Wextra -Werror "$td/run_vm.c" runtime/etl_vm.c -I runtime -o "$td/run_vm"

run_program() {
  local exe="$1"
  set +e
  "$exe" >/dev/null
  local status=$?
  set -e
  echo "$status"
}

run_vm_program() {
  local bc_path="$1"
  set +e
  "$td/run_vm" "$bc_path" >/dev/null 2>&1
  local status=$?
  set -e
  echo "$status"
}

build_c1_emit_c_harness() {
  local source_text="$1"
  local source_len="$2"
  local out_c_path="$3"
  local harness="$4"

  sed '/^fn main()/,$d' compiler1/main.etl > "$harness"
  cat compiler1/lex.etl >> "$harness"
  cat compiler1/parse.etl >> "$harness"
  cat compiler1/sema.etl >> "$harness"
  cat compiler1/emit_c.etl >> "$harness"
  cat >> "$harness" <<EOF
extern fn etl_write_file1024(path i8[64], buf i8[262144], len i32) i32

fn main() i32
  let source i8[131072] = "$source_text"
  let tokens Token[32768]
  let ast AstNode[32768]
  let out i8[262144]
  let n i32 = lex(source, $source_len, tokens, 32768)
  if n < 0
    ret 1
  end
  let an i32 = parse(tokens, n, ast, 32768)
  if an < 0
    ret 2
  end
  if sema(source, tokens, ast, an) < 0
    ret 3
  end
  let emitted i32 = emit_c(source, tokens, ast, an, out, 262144)
  if emitted < 0
    ret 4
  end
  let path i8[64] = "$out_c_path"
  if etl_write_file1024(path, out, emitted) < 0
    ret 5
  end
  ret 0
end
EOF
}

build_c1_emit_bytecode_harness() {
  local source_text="$1"
  local source_len="$2"
  local out_bc_path="$3"
  local harness="$4"

  sed '/^fn main()/,$d' compiler1/main.etl > "$harness"
  cat compiler1/lex.etl >> "$harness"
  cat compiler1/parse.etl >> "$harness"
  cat compiler1/backend_defs.etl >> "$harness"
  cat compiler1/emit_bytecode.etl >> "$harness"
  cat >> "$harness" <<EOF
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
  let path i8[64] = "$out_bc_path"
  if etl_write_file1024(path, out, emitted) < 0
    ret 4
  end
  ret 0
end
EOF
}

run_case() {
  local name="$1"
  local source="$2"
  local expected="$3"

  local src="$td/${name}.etl"
  printf '%s' "$source" > "$src"
  local source_text
  source_text="$(printf '%s' "$source" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
  local source_len="${#source}"

  # 1. c0 native path
  local c0_c="$td/${name}.c0.c"
  local c0_exe="$td/${name}.c0"
  python3 -m compiler0 compile "$src" -o "$c0_c"
  cc -std=c11 -Wall -Werror "$c0_c" runtime/etl_runtime.c -I runtime -o "$c0_exe"
  local c0_status
  c0_status="$(run_program "$c0_exe")"

  # 2. c1/C path: c1 emits C, cc compiles, run native
  local c1_c="$td/${name}.c1.c"
  local c1_harness="$td/${name}.c1_emit_c_harness.etl"
  local c1_harness_exe="$td/${name}.c1_emit_c_harness"
  local c1_exe="$td/${name}.c1"
  build_c1_emit_c_harness "$source_text" "$source_len" "$c1_c" "$c1_harness"
  scripts/build_etl.sh "$c1_harness" "$c1_harness_exe"
  "$c1_harness_exe"
  if [ ! -s "$c1_c" ]; then
    echo "c1_vm_control_flow_smoke: FAIL $name compiler-1 emitted no C" >&2
    exit 1
  fi
  cc -std=c11 -Wall -Werror "$c1_c" runtime/etl_runtime.c -I runtime -o "$c1_exe"
  local c1_status
  c1_status="$(run_program "$c1_exe")"

  # 3. c1/VM path: c1 emits bytecode, tiny harness runs it through etl_vm.c
  local c1_bc_path="$td/${name}.bc"
  local c1_bc_harness="$td/${name}.c1_emit_bytecode_harness.etl"
  local c1_bc_harness_exe="$td/${name}.c1_emit_bytecode_harness"
  build_c1_emit_bytecode_harness "$source_text" "$source_len" "$c1_bc_path" "$c1_bc_harness"
  scripts/build_etl.sh "$c1_bc_harness" "$c1_bc_harness_exe"
  "$c1_bc_harness_exe"
  if [ ! -s "$c1_bc_path" ]; then
    echo "c1_vm_control_flow_smoke: FAIL $name compiler-1 emitted no bytecode" >&2
    exit 1
  fi
  local vm_status
  vm_status="$(run_vm_program "$c1_bc_path")"

  if [ "$c0_status" != "$expected" ] || [ "$c1_status" != "$expected" ] || [ "$vm_status" != "$expected" ]; then
    echo "c1_vm_control_flow_smoke: FAIL $name expected=$expected c0=$c0_status c1=$c1_status vm=$vm_status" >&2
    exit 1
  fi
  echo "c1_vm_control_flow_smoke: PASS $name (exit $expected on c0, c1/C, c1/VM)"
}

run_case "if_else" "fn main() i32 let x i32 = 7 if x > 5 ret 1 end ret 0 end" "1"

run_case "elif_chain" "fn main() i32 let x i32 = 5 if x > 9 ret 9 elif x > 3 ret 3 else ret 0 end end" "3"

run_case "while_loop" "fn main() i32 let i i32 = 0 let s i32 = 0 while i < 5 s = s + i i = i + 1 end ret s end" "10"

echo "c1_vm_control_flow_smoke: ok (c0/c1-C/c1-VM equivalence over if/elif/else/while)"
