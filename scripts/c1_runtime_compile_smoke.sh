#!/usr/bin/env bash
# c1_runtime_compile_smoke.sh — runtime host bridge equivalence smoke.
#
# Exercises runtime/etl_host.c end-to-end: an AOT-compiled C host
# program (test_host) calls etl_compile_module + etl_run_main_i32 to
# compile and execute small ETL source strings via the embedded VM.
#
# For each test program, the harness compares the host result against
# the c0/native result. They must match — that proves the runtime
# compile-and-run path is observationally equivalent to AOT compilation.

set -euo pipefail

td="$(mktemp -d)"
trap 'rm -rf "$td"' EXIT

# ---------------------------------------------------------------------------
# Stage 1: build the c1 bytecode driver (concatenated c1 source + bytecode_driver.etl).
# Same concatenation pattern as scripts/c1_selfcompile_smoke.sh, but appending
# compiler1/bytecode_driver.etl instead of compiler1/driver.etl as the entry point.
# ---------------------------------------------------------------------------
bcd_src="$td/c1_bytecode_pipeline.etl"
sed '/^fn main()/,$d' compiler1/main.etl >  "$bcd_src"
cat compiler1/lex.etl                    >> "$bcd_src"
cat compiler1/parse.etl                  >> "$bcd_src"
cat compiler1/sema.etl                   >> "$bcd_src"
cat compiler1/backend_defs.etl           >> "$bcd_src"
cat compiler1/emit_bytecode.etl          >> "$bcd_src"
cat compiler1/bytecode_driver.etl        >> "$bcd_src"

bcd_bin="$td/etl_bytecode_driver"
scripts/build_etl.sh "$bcd_src" "$bcd_bin"

# ---------------------------------------------------------------------------
# Stage 2: build the host harness: test_host + etl_host + etl_vm + runtime.
# ---------------------------------------------------------------------------
host_bin="$td/etl_host"
cc -std=c11 -Wall -Wextra -Werror \
   runtime/test_host.c runtime/etl_host.c runtime/etl_vm.c runtime/etl_runtime.c \
   -I runtime -o "$host_bin"

# ---------------------------------------------------------------------------
# Stage 3: run a series of ETL source strings through both c0/native and the
# runtime host bridge; assert exit codes match.
# ---------------------------------------------------------------------------

run_case() {
  local name="$1"
  local source="$2"
  local expected="$3"

  # c0 path: write source to a file and AOT-compile via build_etl.sh.
  local c0_src="$td/${name}.etl"
  printf '%s' "$source" > "$c0_src"
  local c0_bin="$td/${name}.c0"
  scripts/build_etl.sh "$c0_src" "$c0_bin"
  set +e
  "$c0_bin" >/dev/null
  local c0_status=$?
  set -e

  # host path: pass source as argv[1] to test_host, which pipes it through
  # etl_compile_module + etl_run_main_i32.
  set +e
  ETL_BYTECODE_DRIVER="$bcd_bin" "$host_bin" "$source" >/dev/null
  local host_status=$?
  set -e

  if [ "$c0_status" != "$expected" ] || [ "$host_status" != "$expected" ]; then
    echo "c1_runtime_compile_smoke: FAIL $name (expected=$expected c0=$c0_status host=$host_status)" >&2
    exit 1
  fi
  echo "c1_runtime_compile_smoke: PASS $name (exit $expected on c0/native and runtime-compile host)"
}

# Case 1: integer expression return (matches the VM expr smoke).
run_case "expr_return" "fn main() i32 ret 1 + 2 * (9 - 4) end" "11"

# Case 2: let with init + return local (locals path through host bridge).
run_case "let_return" "fn main() i32 let x i32 = 7 + 5 ret x end" "12"

# Case 3: control flow (if/else through host bridge).
run_case "if_return" "fn main() i32 let x i32 = 7 if x > 5 ret 1 end ret 0 end" "1"

# Case 4: function call (CALL/RET path through host bridge).
run_case "call_return" "fn add(a i32, b i32) i32 ret a + b end fn main() i32 ret add(20, 22) end" "42"

echo "c1_runtime_compile_smoke: ok (4 cases through etl_compile_module + etl_run_main_i32)"
