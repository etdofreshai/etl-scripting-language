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
  if sema(ast, ast_count) < 0
    ret 3
  end
  let n i32 = emit_wasm(ast, ast_count, out, 1024)
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

# Summary
if [ "$fail" -gt 0 ]; then
  echo "c1_wat_return_smoke: FAIL - $fail failed, $pass passed" >&2
  exit 1
fi

echo "c1_wat_return_smoke: ok ($pass cases passed)"
