#!/usr/bin/env bash
# host_runtime_compile_smoke.sh — end-to-end smoke for the host bridge with ETL VM.
#
# Exercises F2.4-host-uses-etl-vm:
#   1. Builds the c1 bytecode driver (compiler1 -> bc_driver).
#   2. Builds bin/etl-vm-etl (ETL-implemented VM).
#   3. Compiles tests/host/runtime_compile_run.etl into a host program via
#      compiler0, linking runtime/etl_host.c + etl_host_etl_api.c + etl_vm.c.
#   4. Runs the host program with ETL_BYTECODE_DRIVER=<bc_driver> and
#      ETL_VM_ETL=<bin/etl-vm-etl>.  Asserts exit 0.
#
# The host program calls etl_compile_module("fn main() i32 ret 6 * 7 end")
# and etl_run_main_i32, then asserts the result is 42.
#
# Architecture: Approach A (subprocess).  etl_run_main_i32 forks bin/etl-vm-etl,
# passes bytecode on stdin, and reads the exit code as the i32 result.
# This is the default host execution path for M2.  The C oracle VM
# (runtime/etl_vm.c) is preserved for equivalence gates; it is used as fallback
# when ETL_VM_ETL is unset.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

td="$(mktemp -d)"
trap 'rm -rf "$td"' EXIT

echo "host_runtime_compile_smoke: building c1 bytecode driver"
bcd_src="$td/c1_bytecode_pipeline.etl"
sed '/^fn main()/,$d' compiler1/main.etl > "$bcd_src"
cat compiler1/lex.etl >> "$bcd_src"
cat compiler1/parse.etl >> "$bcd_src"
cat compiler1/sema.etl >> "$bcd_src"
cat compiler1/backend_defs.etl >> "$bcd_src"
cat compiler1/emit_bytecode.etl >> "$bcd_src"
cat compiler1/bytecode_driver.etl >> "$bcd_src"
scripts/build_etl.sh "$bcd_src" "$td/bc_driver"

echo "host_runtime_compile_smoke: building bin/etl-vm-etl"
make bin/etl-vm-etl

echo "host_runtime_compile_smoke: compiling tests/host/runtime_compile_run.etl"
python3 -m compiler0 compile tests/host/runtime_compile_run.etl -o "$td/runtime_compile_run.c"
cc -std=c11 -Wall -Wextra -Werror \
    "$td/runtime_compile_run.c" \
    runtime/etl_runtime.c \
    runtime/etl_host.c \
    runtime/etl_host_etl_api.c \
    runtime/etl_vm.c \
    runtime/etl_string.c \
    runtime/etl_dynarr.c \
    runtime/etl_etlval.c \
    -I runtime \
    -o "$td/runtime_compile_run"

echo "host_runtime_compile_smoke: running with ETL VM (ETL_VM_ETL=bin/etl-vm-etl)"
set +e
ETL_BYTECODE_DRIVER="$td/bc_driver" \
    ETL_VM_ETL="$REPO_ROOT/bin/etl-vm-etl" \
    "$td/runtime_compile_run"
run_exit=$?
set -e

if [ "$run_exit" -ne 0 ]; then
    echo "host_runtime_compile_smoke: FAIL — host program exited $run_exit (expected 0)" >&2
    exit 1
fi

echo "host_runtime_compile_smoke: PASS — etl_compile_module + etl_run_main_i32 via ETL VM returned 0"
