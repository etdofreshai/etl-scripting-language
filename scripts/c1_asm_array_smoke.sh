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
  let source i8[256] = "$escaped"
  let tokens Token[128]
  let ast AstNode[512]
  let out i8[1024]
  let path i8[64] = "$asm_out"

  let token_count i32 = lex(source, $source_len, tokens, 128)
  if token_count < 0
    ret 1
  end
  let ast_count i32 = parse(tokens, token_count, ast, 512)
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

  scripts/build_etl.sh "$src" "$driver" >/dev/null
  "$driver"

  if ! as --64 -o "$obj_out" "$asm_out"; then
    echo "c1_asm_array_smoke: FAIL $name - assembler failed" >&2
    cat "$asm_out" >&2
    exit 1
  fi
  cc -no-pie "$obj_out" -o "$native"

  set +e
  "$native" >/dev/null
  local rc=$?
  set -e

  if [ "$rc" -ne "$expected" ]; then
    echo "c1_asm_array_smoke: FAIL $name - expected $expected, got $rc" >&2
    cat "$asm_out" >&2
    exit 1
  fi
  echo "c1_asm_array_smoke: PASS $name (exit $rc)"
}

run_case array_const_idx "fn main() i32 let values i32[3] values[0] = 7 values[1] = 35 ret values[0] + values[1] end" 42
run_case array_var_idx "fn main() i32 let values i32[3] let i i32 = 1 values[i] = 42 ret values[i] end" 42
run_case array_with_scalar "fn main() i32 let a i32[2] let x i32 = 10 a[0] = x a[1] = 32 ret a[0] + a[1] end" 42
run_case byte_array_const_idx "fn main() i32 let values byte[4] values[0] = 10 values[1] = 32 ret values[0] + values[1] end" 42
run_case i8_array_var_idx "fn main() i32 let values i8[4] let i i32 = 1 values[i] = 42 ret values[i] end" 42
run_case i8_array_string_literal_idx "fn main() i32 let text i8[4] = \"abc\" ret text[0] + text[1] - text[2] end" 96
run_case i8_array_param_const_idx "fn first(text i8[4]) i32 ret text[0] + text[1] - text[2] end fn main() i32 let text i8[4] = \"abc\" ret first(text) end" 96
run_case byte_array_param_var_idx "fn pick(text byte[4], i i32) i32 ret text[i] end fn main() i32 let text byte[4] text[0] = 10 text[1] = 42 ret pick(text, 1) end" 42

echo "c1_asm_array_smoke: ok"
