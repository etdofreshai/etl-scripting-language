#!/usr/bin/env bash
# triple_equiv_smoke.sh — assert identical exit codes across three pipelines:
#   c0/C  : compiler0 → C → native binary
#   c1/C  : compiler1 → C → native binary
#   c1-VM : compiler1 → bytecode → ETL VM (bin/etl-vm-etl)
#
# Exits 0 only if all fixtures pass AND at least 20 fixtures were checked.
#
# Excluded fixtures and reasons (documented per feature F2.3 constraint):
#   ret_unary_minus    : emit_bytecode does not support unary-minus literal
#   local_bool         : emit_bytecode does not support bool local type
#   local_i8           : emit_bytecode does not support i8 scalar local
#   local_i8_array     : emit_bytecode does not support i8 array indexing
#   local_array_sum    : emit_bytecode does not support array sum ops
#   local_array_loop   : emit_bytecode does not support array loop ops
#   i32_array_param    : emit_bytecode does not support i32 array params
#   if_logical_and     : emit_bytecode does not support &&/|| short-circuit ops
#   if_logical_or      : emit_bytecode does not support &&/|| short-circuit ops
#   full_word_aliases  : emit_bytecode does not support keyword-alias syntax
#   struct_decl        : c0 does not support struct types
#   field_access_fn    : c0 does not support struct types
#   struct_array       : c0 does not support struct types
#   string_local       : c0 does not support string types
#   string_multi       : c0 does not support string types
#   extern_typed_write : c0 does not support string types
#   string_heap_basic  : c0 does not support heap string ops
#   dynarr_basic       : c0 does not support dynamic array type
#   tagged_union_basic : c0 does not support tagged union type

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

td="$(mktemp -d)"
trap 'rm -rf "$td"' EXIT

# ── Build C VM oracle / ETL VM must already exist ─────────────────────────
echo "triple_equiv_smoke: checking bin/etl-vm-etl"
if [ ! -x bin/etl-vm-etl ]; then
  echo "triple_equiv_smoke: FAIL — bin/etl-vm-etl not found; run 'make backend-vm' first" >&2
  exit 1
fi

# ── Build C VM oracle driver ───────────────────────────────────────────────
echo "triple_equiv_smoke: building C VM oracle driver"
cc -std=c11 -Wall -Wextra \
  runtime/etl_vm_main.c runtime/etl_vm.c runtime/etl_string.c \
  runtime/etl_dynarr.c runtime/etl_etlval.c \
  -I runtime -o "$td/etl-vm-c"

# ── Build bytecode compiler pipeline ──────────────────────────────────────
echo "triple_equiv_smoke: building bytecode compiler pipeline"
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

# ── Helper: escape source text for ETL string literal ─────────────────────
escape_for_etl_string() {
  sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' "$1" | tr '\n' ' '
}

# ── Helper: build c1 harness that compiles an ETL source to C ─────────────
build_c1_harness() {
  local src_file="$1"
  local out_c_path="$2"
  local harness="$3"
  local source_text source_len
  source_text="$(escape_for_etl_string "$src_file")"
  source_len="$(tr '\n' ' ' < "$src_file" | wc -c)"

  sed '/^fn main()/,$d' compiler1/main.etl > "$harness"
  cat compiler1/lex.etl >> "$harness"
  cat compiler1/parse.etl >> "$harness"
  cat compiler1/sema.etl >> "$harness"
  cat compiler1/emit_c.etl >> "$harness"
  cat >> "$harness" <<EOF_HARNESS
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
EOF_HARNESS
}

run_program() {
  local exe="$1"
  set +e
  "$exe" >/dev/null 2>&1
  local status=$?
  set -e
  echo "$status"
}

# ── Fixture list ───────────────────────────────────────────────────────────
# All 20 fixtures pass: c0/C compile, c1/C compile, and bytecode → ETL VM.
# See exclusion notes at top of file for why other c1_corpus fixtures
# are not included here.
fixtures=(
  assign_local
  fn_params_two
  fn_recursive
  heap_alloc_basic
  if_logical_not
  large_bytecode
  let_arith
  let_chain
  let_simple
  local_bool_expr
  multi_fn_basic
  multi_fn_chain
  nested_let_block
  ret_add
  ret_arith_complex
  ret_complex
  ret_div_mod
  ret_literal
  ret_mul
  ret_nested
)

corpus_dir="tests/c1_corpus"
pass=0
fail=0
skip=0

echo "triple_equiv_smoke: running ${#fixtures[@]} fixtures"

for fixture in "${fixtures[@]}"; do
  src="$corpus_dir/${fixture}.etl"
  name="$fixture"

  if [ ! -f "$src" ]; then
    echo "  SKIP $name — source file missing"
    skip=$((skip + 1))
    continue
  fi

  # ── Pipeline 1: c0/C ────────────────────────────────────────────────────
  if ! python3 -m compiler0 compile "$src" -o "$td/${name}.c0.c" 2>/dev/null; then
    echo "  SKIP $name — c0 compile failed"
    skip=$((skip + 1))
    continue
  fi
  if ! cc -std=c11 -Wall -Werror "$td/${name}.c0.c" runtime/etl_runtime.c runtime/etl_string.c \
       -I runtime -o "$td/${name}.c0" 2>/dev/null; then
    echo "  SKIP $name — c0 cc failed"
    skip=$((skip + 1))
    continue
  fi
  c0_exit="$(run_program "$td/${name}.c0")"

  # ── Pipeline 2: c1/C ────────────────────────────────────────────────────
  build_c1_harness "$src" "$td/${name}.c1.c" "$td/${name}.c1_harness.etl"
  if ! scripts/build_etl.sh "$td/${name}.c1_harness.etl" "$td/${name}.c1h" 2>/dev/null; then
    echo "  SKIP $name — c1 harness build failed"
    skip=$((skip + 1))
    continue
  fi
  if ! "$td/${name}.c1h" 2>/dev/null; then
    echo "  SKIP $name — c1 harness run failed"
    skip=$((skip + 1))
    continue
  fi
  if [ ! -s "$td/${name}.c1.c" ]; then
    echo "  SKIP $name — c1 emitted no C"
    skip=$((skip + 1))
    continue
  fi
  if ! cc -std=c11 -Wall -Werror "$td/${name}.c1.c" runtime/etl_runtime.c runtime/etl_string.c \
       -I runtime -o "$td/${name}.c1" 2>/dev/null; then
    echo "  SKIP $name — c1 cc failed"
    skip=$((skip + 1))
    continue
  fi
  c1_exit="$(run_program "$td/${name}.c1")"

  # ── Pipeline 3: c1-bytecode → ETL VM ────────────────────────────────────
  if ! "$td/bc_driver" < "$src" > "$td/${name}.bc" 2>/dev/null || [ ! -s "$td/${name}.bc" ]; then
    echo "  SKIP $name — bytecode compilation failed"
    skip=$((skip + 1))
    continue
  fi
  set +e
  bin/etl-vm-etl < "$td/${name}.bc" >/dev/null 2>&1
  vm_exit=$?
  set -e

  # ── Assert all three equal ───────────────────────────────────────────────
  if [ "$c0_exit" -eq "$c1_exit" ] && [ "$c1_exit" -eq "$vm_exit" ]; then
    echo "  PASS $name (exit $c0_exit)"
    pass=$((pass + 1))
  else
    echo "  FAIL $name — c0/C=$c0_exit  c1/C=$c1_exit  c1-VM=$vm_exit" >&2
    fail=$((fail + 1))
  fi
done

total=$((pass + fail))
echo "triple_equiv_smoke: summary — $pass passed, $fail failed, $skip skipped (${total} compared)"

if [ "$fail" -ne 0 ]; then
  echo "triple_equiv_smoke: FAIL — $fail fixture(s) diverged across pipelines" >&2
  exit 1
fi

if [ "$pass" -lt 20 ]; then
  echo "triple_equiv_smoke: FAIL — only $pass fixtures passed (need ≥20)" >&2
  exit 1
fi

echo "triple_equiv_smoke: ok (≥20 fixtures, all three pipelines agree)"
