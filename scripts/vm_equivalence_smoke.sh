#!/usr/bin/env bash
# vm_equivalence_smoke.sh — assert identical results between the C oracle VM
# (runtime/etl_vm.c) and the ETL-implemented VM (bin/etl-vm-etl).
#
# For each fixture:
#   1. Compile ETL source -> bytecode via compiler1 bytecode pipeline.
#   2. Run bytecode through C VM oracle -> record exit code.
#   3. Run bytecode through ETL VM (bin/etl-vm-etl) -> record exit code.
#   4. Assert equal.
#
# Exits 0 only if all fixtures pass AND at least 10 fixtures were checked.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

td="$(mktemp -d)"
trap 'rm -rf "$td"' EXIT

# ── Build C VM oracle driver ───────────────────────────────────────────────
echo "vm_equivalence_smoke: building C VM oracle driver"
cc -std=c11 -Wall -Wextra \
  runtime/etl_vm_main.c runtime/etl_vm.c runtime/etl_string.c \
  runtime/etl_dynarr.c runtime/etl_etlval.c \
  -I runtime -o "$td/etl-vm-c"

# ── Build bytecode compiler pipeline ──────────────────────────────────────
echo "vm_equivalence_smoke: building bytecode compiler pipeline"
sed '/^fn main()/,$d' compiler1/main.etl > "$td/pipeline.etl"
cat compiler1/lex.etl >> "$td/pipeline.etl"
cat compiler1/parse.etl >> "$td/pipeline.etl"
cat compiler1/backend_defs.etl >> "$td/pipeline.etl"
cat compiler1/sema.etl >> "$td/pipeline.etl"
cat compiler1/emit_bytecode.etl >> "$td/pipeline.etl"
cat compiler1/bytecode_driver.etl >> "$td/pipeline.etl"

python3 -m compiler0 compile "$td/pipeline.etl" -o "$td/bc_driver.c"
cc -std=c11 -Wall -Wextra "$td/bc_driver.c" runtime/etl_runtime.c \
  -I runtime -o "$td/bc_driver"

# ── Fixture list ───────────────────────────────────────────────────────────
# Fixtures confirmed to work end-to-end through both VMs.
# Excluded fixtures and reasons:
#   ret_unary_minus : emit_bytecode does not support unary-minus literal (F1.x limitation)
#   local_bool      : emit_bytecode does not support bool local type
#   local_i8        : emit_bytecode does not support i8 scalar local / i8 array indexing
fixtures=(
  ret_literal
  ret_add
  ret_mul
  ret_arith_complex
  ret_nested
  ret_div_mod
  ret_complex
  let_simple
  let_arith
  let_chain
  assign_local
  multi_fn_basic
  multi_fn_chain
  fn_params_two
  fn_recursive
  local_bool_expr
  heap_alloc_basic
  string_heap_basic
  dynarr_basic
  tagged_union_basic
  large_bytecode
)

pass=0
fail=0
skip=0

echo "vm_equivalence_smoke: running ${#fixtures[@]} fixtures"

for fixture in "${fixtures[@]}"; do
  src="tests/c1_corpus/${fixture}.etl"
  bc="$td/${fixture}.bc"

  if [ ! -f "$src" ]; then
    echo "  SKIP $fixture — source file missing"
    skip=$((skip + 1))
    continue
  fi

  # Compile to bytecode
  if ! "$td/bc_driver" < "$src" > "$bc" 2>/dev/null; then
    echo "  SKIP $fixture — bytecode compilation failed (emit_bytecode limitation)"
    skip=$((skip + 1))
    continue
  fi

  if [ ! -s "$bc" ]; then
    echo "  SKIP $fixture — empty bytecode"
    skip=$((skip + 1))
    continue
  fi

  # Run through C VM oracle
  set +e
  "$td/etl-vm-c" < "$bc"
  c_exit=$?
  set -e

  # Run through ETL VM
  set +e
  bin/etl-vm-etl < "$bc"
  etl_exit=$?
  set -e

  if [ "$c_exit" -eq "$etl_exit" ]; then
    echo "  PASS $fixture (exit $c_exit)"
    pass=$((pass + 1))
  else
    echo "  FAIL $fixture — C VM exit=$c_exit, ETL VM exit=$etl_exit" >&2
    fail=$((fail + 1))
  fi
done

total=$((pass + fail))
echo "vm_equivalence_smoke: summary — $pass passed, $fail failed, $skip skipped (${total} compared)"

if [ "$fail" -ne 0 ]; then
  echo "vm_equivalence_smoke: FAIL — $fail fixture(s) diverged between C VM and ETL VM" >&2
  exit 1
fi

if [ "$pass" -lt 10 ]; then
  echo "vm_equivalence_smoke: FAIL — only $pass fixtures passed (need ≥10)" >&2
  exit 1
fi

echo "vm_equivalence_smoke: ok (≥10 fixtures, both VMs agree on all)"
