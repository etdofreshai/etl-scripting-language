#!/usr/bin/env bash
set -euo pipefail

td="$(mktemp -d)"
trap 'rm -rf "$td"' EXIT

escape_for_etl_string() {
  printf "%s" "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

run_case() {
  local name="$1"
  local source="$2"
  local expected="$3"
  local escaped
  local source_len
  local src="$td/${name}.etl"
  local c_out="$td/${name}.c"
  local driver="$td/${name}_driver"
  local asm_out="$td/${name}.s"
  local obj_out="$td/${name}.o"
  local native="$td/${name}_native"

  escaped="$(escape_for_etl_string "$source")"
  source_len="$(printf "%s" "$source" | wc -c)"

  sed '/^fn main()/,$d' compiler1/main.etl > "$src"
  cat compiler1/lex.etl >> "$src"
  cat compiler1/parse.etl >> "$src"
  cat compiler1/sema.etl >> "$src"
  cat compiler1/backend_defs.etl >> "$src"
  cat compiler1/emit_asm.etl >> "$src"
  cat >> "$src" <<ETL
extern fn etl_write_file1024(path i8[64], buf i8[1024], len i32) i32

fn main() i32
  let source i8[131072] = "$escaped"
  let tokens Token[32768]
  let ast AstNode[32768]
  let out i8[1024]
  let path i8[64] = "$asm_out"

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
  let n i32 = emit_asm(source, tokens, ast, ast_count, out, 1024)
  if n <= 0
    ret 4
  end
  if etl_write_file1024(path, out, n) < 0
    ret 5
  end
  ret 0
end
ETL

  python3 -m compiler0 compile "$src" -o "$c_out"
  cc -Wall -Werror "$c_out" -I runtime runtime/etl_runtime.c -o "$driver"
  "$driver"

  if ! as "$asm_out" -o "$obj_out"; then
    echo "c1_asm_return_smoke: FAIL $name - assembler rejected output" >&2
    cat "$asm_out" >&2
    exit 1
  fi
  cc -no-pie "$obj_out" -o "$native"

  set +e
  "$native"
  local rc=$?
  set -e

  if [ "$rc" -ne "$expected" ]; then
    echo "c1_asm_return_smoke: FAIL $name - expected $expected, got $rc" >&2
    exit 1
  fi
  echo "c1_asm_return_smoke: PASS $name (exit $rc)"
}

run_case ret_literal "fn main() i32 ret 42 end" 42
run_case ret_add "fn main() i32 ret 10 + 20 end" 30
run_case ret_mul "fn main() i32 ret 3 * 7 end" 21
run_case ret_precedence "fn main() i32 ret 1 + 2 * 3 end" 7
run_case ret_div_mod "fn main() i32 ret 20 / 4 + 9 % 4 end" 6
run_case let_return "fn main() i32 let x i32 = 10 ret x end" 10
run_case let_chain "fn main() i32 let x i32 = 5 let y i32 = x + 3 ret y end" 8
run_case multi_local_names "fn main() i32 let a i32 = 2 let b i32 = 7 a = b + 3 ret a end" 10
run_case assign_return "fn main() i32 let x i32 = 1 x = x + 4 ret x end" 5
run_case if_assign "fn main() i32 let x i32 = 1 if x x = 9 end ret x end" 9
run_case if_true "fn main() i32 let x i32 = 1 if true x = 4 end ret x end" 4
run_case if_cmp "fn main() i32 let x i32 = 2 let y i32 = 5 if x < y x = y end ret x end" 5
run_case while_false "fn main() i32 let x i32 = 6 while false x = x + 1 end ret x end" 6
run_case while_countdown "fn main() i32 let x i32 = 3 while x x = x - 1 end ret x end" 0
run_case while_cmp "fn main() i32 let x i32 = 0 while x < 4 x = x + 1 end ret x end" 4
run_case cmp_eq "fn main() i32 ret 4 == 4 end" 1
run_case cmp_neq "fn main() i32 ret 4 != 5 end" 1
run_case cmp_lt "fn main() i32 ret 3 < 8 end" 1
run_case cmp_lte "fn main() i32 ret 8 <= 8 end" 1
run_case cmp_gt "fn main() i32 ret 9 > 2 end" 1
run_case cmp_gte "fn main() i32 ret 9 >= 9 end" 1
run_case cmp_false "fn main() i32 ret 9 < 2 end" 0
run_case not_bool "fn main() i32 ret not false end" 1
run_case and_bool "fn main() i32 ret true and false end" 0
run_case or_bool "fn main() i32 ret false or true end" 1
run_case logical_truthy "fn main() i32 ret 2 and 3 end" 1

echo "c1_asm_return_smoke: ok"
