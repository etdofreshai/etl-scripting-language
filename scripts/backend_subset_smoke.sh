#!/usr/bin/env bash
# backend_subset_smoke.sh
#
# Shared backend subset smoke: compiles each fixture through all four
# compiler-1 backends (C, VM bytecode, ASM, WAT) and asserts exit codes match.
#
# Four-backend shared fixtures: ≥10 (currently 16).
# Three-backend fixtures (C/ASM/WAT only, VM excluded due to missing and/or
# opcode support): 2 (ret_logical, eager_and_truthy).
#
# Excluded fixture reasons:
#   ret_logical     — uses `or` binary op; emit_bytecode emits no `or` opcode;
#                     etl_vm.c dispatcher has no `or` case.
#   eager_and_truthy — uses `and` binary op; same gap as above.
#
set -euo pipefail

# Add .deps/ to PATH so that locally fetched wasmtime/wat2wasm are found.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export PATH="$REPO_ROOT/.deps:$PATH"

td="$(mktemp -d)"
trap 'rm -rf "$td"' EXIT

escape_for_etl_string() {
  printf "%s" "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

build_emit_driver() {
  local backend="$1"
  local name="$2"
  local source="$3"
  local out_path="$4"
  local driver_src="$td/${backend}_${name}_driver.etl"
  local driver_bin="$td/${backend}_${name}_driver"
  local escaped
  local out_cap
  local source_len

  escaped="$(escape_for_etl_string "$source")"
  source_len="$(printf "%s" "$source" | wc -c)"
  out_cap=1024
  if [ "$backend" = "c" ]; then
    out_cap=262144
  fi
  if [ "$backend" = "bytecode" ]; then
    out_cap=65536
  fi

  sed '/^fn main()/,$d' compiler1/main.etl > "$driver_src"
  cat compiler1/lex.etl >> "$driver_src"
  cat compiler1/parse.etl >> "$driver_src"
  cat compiler1/sema.etl >> "$driver_src"
  cat compiler1/backend_defs.etl >> "$driver_src"
  cat "compiler1/emit_${backend}.etl" >> "$driver_src"
  cat >> "$driver_src" <<EOF_DRIVER
extern fn etl_write_file1024(path i8[64], buf i8[$out_cap], len i32) i32

fn main() i32
  let source i8[131072] = "$escaped"
  let tokens Token[32768]
  let ast AstNode[32768]
  let out i8[$out_cap]
  let token_count i32 = lex(source, $source_len, tokens, 32768)
  if token_count < 0
    ret 1
  end
  let ast_count i32 = parse(tokens, token_count, ast, 32768)
  if ast_count < 0
    ret 2
  end
  if sema(source, tokens, ast, ast_count) < 0
    ret 3
  end
  let emitted i32 = emit_${backend}(source, tokens, ast, ast_count, out, $out_cap)
  if emitted <= 0
    ret 4
  end
  let path i8[64] = "$out_path"
  if etl_write_file1024(path, out, emitted) < 0
    ret 5
  end
  ret 0
end
EOF_DRIVER

  scripts/build_etl.sh "$driver_src" "$driver_bin" >/dev/null
  "$driver_bin"
}

# Build the shared VM run harness once (reused for all vm cases).
build_vm_harness() {
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
  cc -std=c11 -Wall -Wextra -Werror \
    "$td/run_vm.c" runtime/etl_vm.c runtime/etl_string.c \
    runtime/etl_dynarr.c runtime/etl_etlval.c \
    -I runtime -o "$td/run_vm"
}

run_c_case() {
  local name="$1"
  local source="$2"
  local expected="$3"
  local emitted="$td/${name}.c"
  local bin="$td/${name}_c"

  build_emit_driver c "$name" "$source" "$emitted"
  cc -Wall -Werror -I runtime "$emitted" -o "$bin"
  set +e
  "$bin" >/dev/null
  local status=$?
  set -e
  if [ "$status" -ne "$expected" ]; then
    echo "backend_subset_smoke: FAIL c/$name expected $expected, got $status" >&2
    exit 1
  fi
  echo "backend_subset_smoke: PASS c/$name (exit $status)"
}

run_asm_case() {
  local name="$1"
  local source="$2"
  local expected="$3"
  local emitted="$td/${name}.s"
  local obj="$td/${name}.o"
  local bin="$td/${name}_asm"

  build_emit_driver asm "$name" "$source" "$emitted"
  as --64 -o "$obj" "$emitted"
  cc -o "$bin" "$obj"
  set +e
  "$bin" >/dev/null
  local status=$?
  set -e
  if [ "$status" -ne "$expected" ]; then
    echo "backend_subset_smoke: FAIL asm/$name expected $expected, got $status" >&2
    cat "$emitted" >&2
    exit 1
  fi
  echo "backend_subset_smoke: PASS asm/$name (exit $status)"
}

run_wat_case() {
  local name="$1"
  local source="$2"
  local expected="$3"
  shift 3
  local emitted="$td/${name}.wat"
  local wasm="$td/${name}.wasm"

  build_emit_driver wasm "$name" "$source" "$emitted"
  if ! grep -q '(module' "$emitted"; then
    echo "backend_subset_smoke: FAIL wat/$name missing module" >&2
    exit 1
  fi
  if ! grep -q '(export "_start")' "$emitted"; then
    echo "backend_subset_smoke: FAIL wat/$name missing _start export" >&2
    exit 1
  fi
  for fragment in "$@"; do
    if ! grep -q "$fragment" "$emitted"; then
      echo "backend_subset_smoke: FAIL wat/$name missing fragment: $fragment" >&2
      cat "$emitted" >&2
      exit 1
    fi
  done

  if command -v wat2wasm >/dev/null 2>&1; then
    wat2wasm "$emitted" -o "$wasm"
    if command -v wasmtime >/dev/null 2>&1; then
      set +e
      wasmtime "$wasm" >/dev/null 2>&1
      local status=$?
      set -e
      if [ "$status" -ne "$expected" ]; then
        echo "backend_subset_smoke: FAIL wat/$name expected $expected, got $status" >&2
        exit 1
      fi
      echo "backend_subset_smoke: PASS wat/$name (wasmtime exit $status)"
      return
    fi
    if command -v wasmer >/dev/null 2>&1; then
      set +e
      wasmer run "$wasm" >/dev/null 2>&1
      local status=$?
      set -e
      if [ "$status" -ne "$expected" ]; then
        echo "backend_subset_smoke: FAIL wat/$name expected $expected, got $status" >&2
        exit 1
      fi
      echo "backend_subset_smoke: PASS wat/$name (wasmer exit $status)"
      return
    fi
    echo "backend_subset_smoke: PASS wat/$name (wat2wasm validation only)"
    return
  fi

  echo "backend_subset_smoke: PASS wat/$name (text validation only; wat2wasm unavailable)"
}

run_vm_case() {
  local name="$1"
  local source="$2"
  local expected="$3"
  local emitted="$td/${name}.bc"

  build_emit_driver bytecode "$name" "$source" "$emitted"
  set +e
  "$td/run_vm" "$emitted" >/dev/null
  local status=$?
  set -e
  if [ "$status" -ne "$expected" ]; then
    echo "backend_subset_smoke: FAIL vm/$name expected $expected, got $status" >&2
    exit 1
  fi
  echo "backend_subset_smoke: PASS vm/$name (exit $status)"
}

# run_case: all four backends — C, VM, ASM, WAT.
run_case() {
  local name="$1"
  local source="$2"
  local expected="$3"
  shift 3

  run_c_case "$name" "$source" "$expected"
  run_vm_case "$name" "$source" "$expected"
  run_asm_case "$name" "$source" "$expected"
  run_wat_case "$name" "$source" "$expected" "$@"
}

# run_case_3: three backends only — C, ASM, WAT (no VM).
# Used for fixtures that use and/or, which the bytecode emitter and VM runtime
# do not yet support.
run_case_3() {
  local name="$1"
  local source="$2"
  local expected="$3"
  shift 3

  run_c_case "$name" "$source" "$expected"
  run_asm_case "$name" "$source" "$expected"
  run_wat_case "$name" "$source" "$expected" "$@"
}

# Build the shared VM harness before running any cases.
build_vm_harness

# ── Shared four-backend fixtures (C + VM + ASM + WAT) ──────────────────────
# Count: 16 (satisfies ≥10 hard floor)
run_case ret_literal "fn main() i32 ret 42 end" 42 "i32.const 42"
run_case ret_arithmetic "fn main() i32 ret 1 + 2 * 3 end" 7 "i32.const 1" "i32.const 2" "i32.const 3" "i32.mul" "i32.add"
run_case local_init_return "fn main() i32 let x i32 = 12 ret x end" 12 '(local \$v0 i32)' 'local.set \$v0' 'local.get \$v0'
run_case local_assign_return "fn main() i32 let x i32 = 1 x = x + 8 ret x end" 9 'local.get \$v0' "i32.add" 'local.set \$v0'
run_case multi_local_assign "fn main() i32 let a i32 = 2 let b i32 = 7 a = b + 3 ret a end" 10 '(local \$v0 i32)' '(local \$v1 i32)' 'local.get \$v1' 'local.set \$v0'
run_case if_then_local "fn main() i32 let x i32 = 1 if x x = 9 end ret x end" 9 "if" 'local.set \$v0' 'local.get \$v0'
run_case if_else_local "fn main() i32 let x i32 = 0 if x x = 1 else x = 7 end ret x end" 7 "if" "else" 'local.set \$v0'
run_case while_count "fn main() i32 let x i32 = 0 while x < 4 x = x + 1 end ret x end" 4 "block" "loop" "i32.lt_s" "br_if 1" "br 0"
run_case cmp_eq "fn main() i32 ret 4 == 4 end" 1 "i32.const 4" "i32.eq"
run_case cmp_neq "fn main() i32 ret 4 != 5 end" 1 "i32.const 4" "i32.const 5" "i32.ne"
run_case cmp_lte "fn main() i32 ret 8 <= 8 end" 1 "i32.const 8" "i32.le_s"
run_case cmp_gt "fn main() i32 ret 9 > 2 end" 1 "i32.const 9" "i32.const 2" "i32.gt_s"
run_case cmp_gte "fn main() i32 ret 9 >= 9 end" 1 "i32.const 9" "i32.ge_s"
run_case cmp_false "fn main() i32 ret 9 < 2 end" 0 "i32.const 9" "i32.const 2" "i32.lt_s"
run_case ret_not_true "fn main() i32 ret not 0 end" 1 "i32.eqz"
run_case ret_not_false "fn main() i32 ret not 1 end" 0 "i32.eqz"

# ── Three-backend fixtures (C + ASM + WAT; VM excluded) ────────────────────
# Excluded from VM: emit_bytecode emits no `or`/`and` opcode; etl_vm.c
# dispatcher has no matching case for those operators.
run_case_3 ret_logical "fn main() i32 ret not false or 0 end" 1 "i32.const 0" "i32.eqz" "i32.or"
run_case_3 eager_and_truthy "fn main() i32 ret 2 and 3 end" 1 "i32.const 2" "i32.const 3" "i32.and"

echo "backend_subset_smoke: ok (16 four-backend cases + 2 three-backend cases across C, VM, ASM, and WAT)"
