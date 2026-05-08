#!/usr/bin/env bash
# c1_etl_vm_smoke.sh — smoke-test the ETL-implemented VM (bin/etl-vm-etl).
#
# Verifies:
#   1. vm.etl compiles via compiler0 to a working binary (bin/etl-vm-etl).
#   2. Three bytecode corpus fixtures run correctly:
#      a) return-0 program  (expected exit 0)
#      b) arithmetic program (ret_add: 10+20 → exit 30)
#      c) recursive function (fib(10) → exit 55)
#
# The ETL VM reads bytecode from stdin.

set -euo pipefail

td="$(mktemp -d)"
trap 'rm -rf "$td"' EXIT

echo "c1_etl_vm_smoke: building bin/etl-vm-etl"
make bin/etl-vm-etl >/dev/null 2>&1

echo "c1_etl_vm_smoke: building bytecode compiler pipeline"

# Build the bytecode compiler (compiler0 compiles compiler1's bytecode pass)
sed '/^fn main()/,$d' compiler1/main.etl > "$td/pipeline.etl"
cat compiler1/lex.etl >> "$td/pipeline.etl"
cat compiler1/parse.etl >> "$td/pipeline.etl"
cat compiler1/backend_defs.etl >> "$td/pipeline.etl"
cat compiler1/sema.etl >> "$td/pipeline.etl"
cat compiler1/emit_bytecode.etl >> "$td/pipeline.etl"
cat compiler1/bytecode_driver.etl >> "$td/pipeline.etl"

python3 -m compiler0 compile "$td/pipeline.etl" -o "$td/bc_driver.c"
cc -std=c11 -Wall -Wextra "$td/bc_driver.c" runtime/etl_runtime.c -I runtime -o "$td/bc_driver"

# ── Fixture 1: return-0 program ────────────────────────────────────────────
echo "c1_etl_vm_smoke: fixture 1 — return-0"
echo 'fn main() i32 ret 0 end' > "$td/ret0.etl"
"$td/bc_driver" < "$td/ret0.etl" > "$td/ret0.bc"

set +e
bin/etl-vm-etl < "$td/ret0.bc"
got=$?
set -e

if [ "$got" -ne 0 ]; then
  echo "c1_etl_vm_smoke: FAIL fixture1 — expected exit 0, got $got" >&2
  exit 1
fi
echo "c1_etl_vm_smoke: fixture 1 ok (exit 0)"

# ── Fixture 2: arithmetic (10 + 20 = 30) ───────────────────────────────────
echo "c1_etl_vm_smoke: fixture 2 — arithmetic (ret_add)"
"$td/bc_driver" < tests/c1_corpus/ret_add.etl > "$td/arith.bc"

set +e
bin/etl-vm-etl < "$td/arith.bc"
got=$?
set -e

if [ "$got" -ne 30 ]; then
  echo "c1_etl_vm_smoke: FAIL fixture2 — expected exit 30, got $got" >&2
  exit 1
fi
echo "c1_etl_vm_smoke: fixture 2 ok (exit 30)"

# ── Fixture 3: recursive function call (fib(10) = 55) ─────────────────────
echo "c1_etl_vm_smoke: fixture 3 — recursive fib (fn_recursive)"
"$td/bc_driver" < tests/c1_corpus/fn_recursive.etl > "$td/fib.bc"

set +e
bin/etl-vm-etl < "$td/fib.bc"
got=$?
set -e

if [ "$got" -ne 55 ]; then
  echo "c1_etl_vm_smoke: FAIL fixture3 — expected exit 55, got $got" >&2
  exit 1
fi
echo "c1_etl_vm_smoke: fixture 3 ok (exit 55)"

# ── Fixture 4: heap alloc/free (exit 0) ────────────────────────────────────
echo "c1_etl_vm_smoke: fixture 4 — heap alloc/free"
"$td/bc_driver" < tests/c1_corpus/heap_alloc_basic.etl > "$td/heap.bc"

set +e
bin/etl-vm-etl < "$td/heap.bc"
got=$?
set -e

if [ "$got" -ne 0 ]; then
  echo "c1_etl_vm_smoke: FAIL fixture4 — expected exit 0, got $got" >&2
  exit 1
fi
echo "c1_etl_vm_smoke: fixture 4 ok (exit 0)"


# ── Fixture 5: string heap (exit 0) ────────────────────────────────────────
echo "c1_etl_vm_smoke: fixture 5 — string_heap_basic (bridges: HSN/HSL/HSF/HA)"
"$td/bc_driver" < tests/c1_corpus/string_heap_basic.etl > "$td/strbasic.bc"

set +e
bin/etl-vm-etl < "$td/strbasic.bc"
got=$?
set -e

if [ "$got" -ne 0 ]; then
  echo "c1_etl_vm_smoke: FAIL fixture5 — expected exit 0, got $got" >&2
  exit 1
fi
echo "c1_etl_vm_smoke: fixture 5 ok (exit 0)"

# ── Fixture 6: dynarr basic (exit 0) ───────────────────────────────────────
echo "c1_etl_vm_smoke: fixture 6 — dynarr_basic (bridges: HDN/HDP/HDL/HDG/HDF)"
"$td/bc_driver" < tests/c1_corpus/dynarr_basic.etl > "$td/dynarrbasic.bc"

set +e
bin/etl-vm-etl < "$td/dynarrbasic.bc"
got=$?
set -e

if [ "$got" -ne 0 ]; then
  echo "c1_etl_vm_smoke: FAIL fixture6 — expected exit 0, got $got" >&2
  exit 1
fi
echo "c1_etl_vm_smoke: fixture 6 ok (exit 0)"

# ── Fixture 7: tagged union basic (exit 0) ─────────────────────────────────
echo "c1_etl_vm_smoke: fixture 7 — tagged_union_basic (bridges: HVI/HVB/HVP/HVT/HVF)"
"$td/bc_driver" < tests/c1_corpus/tagged_union_basic.etl > "$td/taggedbasic.bc"

set +e
bin/etl-vm-etl < "$td/taggedbasic.bc"
got=$?
set -e

if [ "$got" -ne 0 ]; then
  echo "c1_etl_vm_smoke: FAIL fixture7 — expected exit 0, got $got" >&2
  exit 1
fi
echo "c1_etl_vm_smoke: fixture 7 ok (exit 0)"

echo "c1_etl_vm_smoke: ok (ETL-VM executes all fixtures correctly)"
