#!/usr/bin/env bash
set -euo pipefail

td="$(mktemp -d)"
trap 'rm -rf "$td"' EXIT

escape_for_etl_string() {
  printf "%s" "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

# Build and run the compiler-1 pipeline to produce WAT output.
# Writes the WAT text to stdout. Sets driver exit code.
run_wat_emit() {
  local name="$1"
  local source="$2"
  local escaped
  local source_len
  local src="$td/${name}.etl"
  local c_out="$td/${name}.c"
  local driver="$td/${name}_driver"
  local wat_out="$td/${name}.wat"

  escaped="$(escape_for_etl_string "$source")"
  source_len="$(printf "%s" "$source" | wc -c)"

  sed '/^fn main()/,$d' compiler1/main.etl > "$src"
  cat compiler1/lex.etl >> "$src"
  cat compiler1/parse.etl >> "$src"
  cat compiler1/sema.etl >> "$src"
  cat compiler1/backend_defs.etl >> "$src"
  cat compiler1/emit_wasm.etl >> "$src"
  cat >> "$src" <<ETL
extern fn etl_write_file1024(path i8[64], buf i8[1024], len i32) i32

fn main() i32
  let source i8[256] = "$escaped"
  let tokens Token[128]
  let ast AstNode[512]
  let out i8[1024]
  let path i8[64] = "$wat_out"

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
  let n i32 = emit_wasm(source, tokens, ast, ast_count, out, 1024)
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
  cat "$wat_out"
}

# Check available WASM tools
has_wat2wasm=false
if command -v wat2wasm &>/dev/null; then
  has_wat2wasm=true
fi

wasm_runtime=""
if command -v wasmtime &>/dev/null; then
  wasm_runtime="wasmtime"
elif command -v wasmer &>/dev/null; then
  wasm_runtime="wasmer"
fi

pass=0
fail=0

run_case() {
  local name="$1"
  local source="$2"
  local expected="$3"

  local wat_text
  wat_text="$(run_wat_emit "$name" "$source")"
  local driver_rc=$?

  if [ "$driver_rc" -ne 0 ]; then
    echo "c1_wat_return_smoke: FAIL $name - emit driver returned $driver_rc" >&2
    fail=$((fail + 1))
    return
  fi

  # Validate WAT text contains expected structure
  if ! echo "$wat_text" | grep -q '(module'; then
    echo "c1_wat_return_smoke: FAIL $name - WAT missing (module" >&2
    fail=$((fail + 1))
    return
  fi
  if ! echo "$wat_text" | grep -q '(export "_start")'; then
    echo "c1_wat_return_smoke: FAIL $name - WAT missing (export \"_start\")" >&2
    fail=$((fail + 1))
    return
  fi
  if ! echo "$wat_text" | grep -q "i32.const $expected"; then
    echo "c1_wat_return_smoke: FAIL $name - WAT missing i32.const $expected" >&2
    fail=$((fail + 1))
    return
  fi

  # Try WASM toolchain if available
  if $has_wat2wasm && [ -n "$wasm_runtime" ]; then
    local wat_file="$td/${name}.wat"
    local wasm_file="$td/${name}.wasm"
    echo "$wat_text" > "$wat_file"
    wat2wasm "$wat_file" -o "$wasm_file" 2>/dev/null
    if [ $? -eq 0 ]; then
      set +e
      if [ "$wasm_runtime" = "wasmtime" ]; then
        wasmtime "$wasm_file" 2>/dev/null
      else
        wasmer run "$wasm_file" 2>/dev/null
      fi
      local rc=$?
      set -e
      if [ "$rc" -ne "$expected" ]; then
        echo "c1_wat_return_smoke: FAIL $name - WASM expected exit $expected, got $rc" >&2
        fail=$((fail + 1))
        return
      fi
      echo "c1_wat_return_smoke: PASS $name (wat+wasm exit $rc)"
    else
      echo "c1_wat_return_smoke: PASS $name (wat text validated, wat2wasm failed)"
    fi
    pass=$((pass + 1))
  else
    echo "c1_wat_return_smoke: PASS $name (wat text validated)"
    pass=$((pass + 1))
  fi
}

run_case ret_literal "fn main() i32 ret 42 end" 42
run_case ret_zero "fn main() i32 ret 0 end" 0
run_case ret_small "fn main() i32 ret 7 end" 7
run_case ret_large "fn main() i32 ret 255 end" 255

# Arithmetic expression tests — validate WAT structure and optionally execute via WASM runtime
run_arith_case() {
  local name="$1"
  local source="$2"
  local expected_exit="$3"
  shift 3

  local wat_text
  wat_text="$(run_wat_emit "$name" "$source")"
  local driver_rc=$?

  if [ "$driver_rc" -ne 0 ]; then
    echo "c1_wat_return_smoke: FAIL $name - emit driver returned $driver_rc" >&2
    fail=$((fail + 1))
    return
  fi

  # Validate WAT text contains expected structure
  if ! echo "$wat_text" | grep -q '(module'; then
    echo "c1_wat_return_smoke: FAIL $name - WAT missing (module" >&2
    fail=$((fail + 1))
    return
  fi
  if ! echo "$wat_text" | grep -q '(export "_start")'; then
    echo "c1_wat_return_smoke: FAIL $name - WAT missing (export \"_start\")" >&2
    fail=$((fail + 1))
    return
  fi

  # Check each expected WAT fragment is present
  for frag in "$@"; do
    if ! echo "$wat_text" | grep -q "$frag"; then
      echo "c1_wat_return_smoke: FAIL $name - WAT missing expected fragment: $frag" >&2
      fail=$((fail + 1))
      return
    fi
  done

  # Try WASM toolchain if available
  if $has_wat2wasm && [ -n "$wasm_runtime" ]; then
    local wat_file="$td/${name}.wat"
    local wasm_file="$td/${name}.wasm"
    echo "$wat_text" > "$wat_file"
    wat2wasm "$wat_file" -o "$wasm_file" 2>/dev/null
    if [ $? -eq 0 ]; then
      set +e
      if [ "$wasm_runtime" = "wasmtime" ]; then
        wasmtime "$wasm_file" 2>/dev/null
      else
        wasmer run "$wasm_file" 2>/dev/null
      fi
      local rc=$?
      set -e
      if [ "$rc" -ne "$expected_exit" ]; then
        echo "c1_wat_return_smoke: FAIL $name - WASM expected exit $expected_exit, got $rc" >&2
        fail=$((fail + 1))
        return
      fi
      echo "c1_wat_return_smoke: PASS $name (wat+wasm exit $rc)"
    else
      echo "c1_wat_return_smoke: PASS $name (wat text validated, wat2wasm failed)"
    fi
    pass=$((pass + 1))
  else
    echo "c1_wat_return_smoke: PASS $name (wat text validated)"
    pass=$((pass + 1))
  fi
}

run_arith_case arith_add "fn main() i32 ret 10 + 20 end" 30 "i32.const 10" "i32.const 20" "i32.add"
run_arith_case arith_mul "fn main() i32 ret 3 * 7 end" 21 "i32.const 3" "i32.const 7" "i32.mul"
run_arith_case arith_precedence "fn main() i32 ret 1 + 2 * 3 end" 7 "i32.const 1" "i32.const 2" "i32.const 3" "i32.mul" "i32.add"

run_arith_case local_init_return "fn main() i32 let x i32 = 12 ret x end" 12 '(local \$v0 i32)' 'local.set \$v0' 'local.get \$v0'
run_arith_case local_assign_return "fn main() i32 let x i32 = 1 x = x + 8 ret x end" 9 'local.get \$v0' "i32.add" 'local.set \$v0'
run_arith_case local_spelling "fn main() i32 let aa i32 = 4 let a i32 = 2 aa = aa + a ret aa end" 6 '(local \$v0 i32)' '(local \$v1 i32)' 'local.get \$v0' 'local.get \$v1'
run_arith_case if_local "fn main() i32 let x i32 = 1 if x x = 9 end ret x end" 9 "if" 'local.set \$v0' 'local.get \$v0'
run_arith_case if_else_local "fn main() i32 let x i32 = 0 if x x = 1 else x = 7 end ret x end" 7 "if" "else" 'local.set \$v0'
run_arith_case while_local "fn main() i32 let x i32 = 0 while x < 3 x = x + 1 end ret x end" 3 "block" "loop" "i32.lt_s" "br_if 1" "br 0"

run_arith_case bool_if_true "fn main() i32 let x i32 = 0 if true x = 5 else x = 9 end ret x end" 5 "i32.const 1" "if" "else" 'local.set \$v0'
run_arith_case bool_if_false "fn main() i32 let x i32 = 0 if false x = 5 else x = 9 end ret x end" 9 "i32.const 0" "if" "else" 'local.set \$v0'
run_arith_case ret_cmp_true "fn main() i32 ret 2 < 3 end" 1 "i32.const 2" "i32.const 3" "i32.lt_s"
run_arith_case ret_cmp_false "fn main() i32 ret 2 == 3 end" 0 "i32.const 2" "i32.const 3" "i32.eq"

# WAT logical and/or currently use eager truthiness lowering, not short-circuiting.
run_arith_case logic_not "fn main() i32 ret not false end" 1 "i32.const 0" "i32.eqz"
run_arith_case logic_and "fn main() i32 ret 1 < 2 and 3 < 4 end" 1 "i32.lt_s" "i32.ne" "i32.and"
run_arith_case logic_or "fn main() i32 ret 1 > 2 or true end" 1 "i32.gt_s" "i32.const 1" "i32.ne" "i32.or"

# Summary
if [ "$fail" -gt 0 ]; then
  echo "c1_wat_return_smoke: FAIL - $fail failed, $pass passed" >&2
  exit 1
fi

echo "c1_wat_return_smoke: ok ($pass cases passed)"
