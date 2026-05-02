#!/usr/bin/env bash
set -euo pipefail

td="$(mktemp -d)"
trap 'rm -rf "$td"' EXIT

corpus_dir="tests/c1_corpus"
fixtures=(
  ret_literal.etl
  ret_add.etl
  ret_mul.etl
  ret_arith_complex.etl
  ret_nested.etl
  ret_div_mod.etl
  ret_complex.etl
  let_simple.etl
  let_arith.etl
  let_chain.etl
  assign_local.etl
  ret_unary_minus.etl
  if_logical_and.etl
  if_logical_or.etl
  if_logical_not.etl
  full_word_aliases.etl
  multi_fn_basic.etl
  multi_fn_chain.etl
  fn_params_two.etl
  fn_recursive.etl
  local_array_sum.etl
)

pass=0
fail=0

escape_for_etl_string() {
  sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' "$1" | tr -d '\n'
}

build_c1_harness() {
  local src_file="$1"
  local out_c_path="$2"
  local harness="$3"
  local source_text
  local source_len
  source_text="$(escape_for_etl_string "$src_file")"
  source_len="$(printf "%s" "$source_text" | wc -c)"

  sed '/^fn main()/,$d' compiler1/main.etl > "$harness"
  cat compiler1/lex.etl >> "$harness"
  cat compiler1/parse.etl >> "$harness"
  cat compiler1/sema.etl >> "$harness"
  cat compiler1/emit_c.etl >> "$harness"
  cat >> "$harness" <<EOF_HARNESS
extern fn etl_write_file1024(path i8[64], buf i8[1024], len i32) i32

fn main() i32
  let source i8[256] = "$source_text"
  let tokens Token[128]
  let ast AstNode[512]
  let out i8[1024]
  let n i32 = lex(source, $source_len, tokens, 128)
  if n < 0
    ret 1
  end
  let an i32 = parse(tokens, n, ast, 512)
  if an < 0
    ret 2
  end
  if sema(source, tokens, ast, an) < 0
    ret 3
  end
  let emitted i32 = emit_c(source, tokens, ast, an, out, 1024)
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
  "$exe" >/dev/null
  local status=$?
  set -e
  echo "$status"
}

for fixture in "${fixtures[@]}"; do
  src="$corpus_dir/$fixture"
  name="${fixture%.etl}"
  c0_c="$td/${name}.c0.c"
  c1_c="$td/${name}.c1.c"
  c0_exe="$td/${name}.c0"
  c1_harness="$td/${name}.c1_harness.etl"
  c1_harness_exe="$td/${name}.c1_harness"
  c1_exe="$td/${name}.c1"

  if [ ! -f "$src" ]; then
    echo "c1_equiv_smoke: FAIL $fixture missing" >&2
    fail=$((fail + 1))
    continue
  fi

  python3 -m compiler0 compile "$src" -o "$c0_c"
  cc -std=c11 -Wall -Werror "$c0_c" -o "$c0_exe"

  build_c1_harness "$src" "$c1_c" "$c1_harness"
  scripts/build_etl.sh "$c1_harness" "$c1_harness_exe"
  "$c1_harness_exe"
  if [ ! -s "$c1_c" ]; then
    echo "c1_equiv_smoke: FAIL $fixture compiler-1 emitted no C" >&2
    fail=$((fail + 1))
    continue
  fi
  cc -std=c11 -Wall -Werror "$c1_c" -o "$c1_exe"

  c0_status="$(run_program "$c0_exe")"
  c1_status="$(run_program "$c1_exe")"
  if [ "$c0_status" = "$c1_status" ]; then
    echo "c1_equiv_smoke: PASS $fixture (exit $c0_status)"
    pass=$((pass + 1))
  else
    echo "c1_equiv_smoke: FAIL $fixture c0=$c0_status c1=$c1_status" >&2
    fail=$((fail + 1))
  fi
done

echo "c1_equiv_smoke: summary $pass/${#fixtures[@]} passed, $fail failed"
if [ "$fail" -ne 0 ]; then
  exit 1
fi
