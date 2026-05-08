#!/usr/bin/env bash
# Smoke-test the Linux aarch64 release under qemu-aarch64-static.
#
# For a subset of ≥5 c1 corpus fixtures:
#   1. Compile ETL source → C (via compiler0)
#   2. Cross-compile C → aarch64-linux-musl ELF (via zig cc)
#   3. Run under .deps/qemu-aarch64-static
#   4. Verify exit code matches expected value
#
# All compilation is done in a temporary directory; nothing persistent is
# written to the repo.  Exits 0 on success, non-zero on any failure.
#
# Fixture subset and expected exit codes:
#   ret_literal.etl      → 42
#   let_simple.etl       → 42
#   let_arith.etl        → 42   (6*7)
#   ret_add.etl          → 30   (10+20)
#   fn_params_two.etl    → 42   (add(20,22))
#   ret_mul.etl          → 42   (6*7)
#   assign_local.etl     → 7

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

cd "$REPO_ROOT"

ZIG="$REPO_ROOT/.deps/zig/zig"
QEMU="$REPO_ROOT/.deps/qemu-aarch64-static"
CORPUS_DIR="$REPO_ROOT/tests/c1_corpus"

# ---------------------------------------------------------------------------
# Validate prerequisites
# ---------------------------------------------------------------------------
if [ ! -x "$ZIG" ]; then
  echo "release_smoke_aarch64: FAIL — zig not found at $ZIG" >&2
  echo "  Run: bash scripts/setup.sh" >&2
  exit 1
fi

if [ ! -x "$QEMU" ]; then
  echo "release_smoke_aarch64: FAIL — qemu-aarch64-static not found at $QEMU" >&2
  echo "  Run: bash scripts/setup.sh" >&2
  exit 1
fi

echo "release_smoke_aarch64: zig $("$ZIG" version)"
echo "release_smoke_aarch64: qemu $("$QEMU" --version 2>&1 | head -1)"

# ---------------------------------------------------------------------------
# Fixture table: (fixture_name, expected_exit_code)
# All exit codes are reduced mod 256 (process exit code semantics).
# ---------------------------------------------------------------------------
declare -A EXPECTED_EXIT
EXPECTED_EXIT[ret_literal.etl]=42
EXPECTED_EXIT[let_simple.etl]=42
EXPECTED_EXIT[let_arith.etl]=42
EXPECTED_EXIT[ret_add.etl]=30
EXPECTED_EXIT[fn_params_two.etl]=42
EXPECTED_EXIT[ret_mul.etl]=42
EXPECTED_EXIT[assign_local.etl]=7

FIXTURES=(
  ret_literal.etl
  let_simple.etl
  let_arith.etl
  ret_add.etl
  fn_params_two.etl
  ret_mul.etl
  assign_local.etl
)

ETL_VM_ETL_RUNTIME="$REPO_ROOT/runtime/etl_runtime.c $REPO_ROOT/runtime/etl_string.c $REPO_ROOT/runtime/etl_dynarr.c $REPO_ROOT/runtime/etl_etlval.c $REPO_ROOT/runtime/vm_bridge.c"

# ---------------------------------------------------------------------------
# Scratch directory (cleaned up on exit)
# ---------------------------------------------------------------------------
td=$(mktemp -d)
trap 'rm -rf "$td"' EXIT INT HUP TERM

echo "release_smoke_aarch64: using scratch dir $td"

pass=0
fail=0
total=${#FIXTURES[@]}

for fixture in "${FIXTURES[@]}"; do
  src="$CORPUS_DIR/$fixture"
  if [ ! -f "$src" ]; then
    echo "  [SKIP] $fixture — source not found at $src"
    continue
  fi

  expected="${EXPECTED_EXIT[$fixture]}"

  # Step 1: ETL → C via compiler0
  c_out="$td/${fixture%.etl}.c"
  if ! python3 -m compiler0 compile "$src" -o "$c_out" 2>/dev/null; then
    echo "  [FAIL] $fixture — compiler0 failed to compile to C" >&2
    fail=$((fail + 1))
    continue
  fi

  # Step 2: C → aarch64 ELF via zig cc (musl, static)
  bin_out="$td/${fixture%.etl}"
  # shellcheck disable=SC2086
  if ! "$ZIG" cc \
      -target aarch64-linux-musl \
      -std=c11 \
      -Wno-unused-variable -Wno-unused-parameter \
      -I"$REPO_ROOT/runtime" \
      -o "$bin_out" \
      "$c_out" \
      $ETL_VM_ETL_RUNTIME 2>/dev/null; then
    echo "  [FAIL] $fixture — zig cc cross-compile failed" >&2
    fail=$((fail + 1))
    continue
  fi

  # Step 3: run under qemu-aarch64-static
  set +e
  "$QEMU" "$bin_out"
  actual=$?
  set -e

  # Step 4: verify exit code
  if [ "$actual" -eq "$expected" ]; then
    echo "  [PASS] $fixture — exit $actual (expected $expected)"
    pass=$((pass + 1))
  else
    echo "  [FAIL] $fixture — exit $actual (expected $expected)" >&2
    fail=$((fail + 1))
  fi
done

echo ""
echo "release_smoke_aarch64: $pass/$total passed, $fail failed"

if [ "$fail" -gt 0 ]; then
  echo "release_smoke_aarch64: FAIL" >&2
  exit 1
fi

if [ "$pass" -lt 5 ]; then
  echo "release_smoke_aarch64: FAIL — fewer than 5 fixtures passed (got $pass)" >&2
  exit 1
fi

echo "release_smoke_aarch64: OK"
exit 0
