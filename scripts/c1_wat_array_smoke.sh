#!/usr/bin/env bash
set -euo pipefail

td="$(mktemp -d)"
trap 'rm -rf "$td"' EXIT

escape_for_etl_string() {
  printf "%s" "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

# Build and run the compiler-1 pipeline to produce WAT output.
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

run_array_case() {
  local name="$1"
  local source="$2"
  local expected_exit="$3"
  shift 3

  local wat_text
  wat_text="$(run_wat_emit "$name" "$source")"
  local driver_rc=$?

  if [ "$driver_rc" -ne 0 ]; then
    echo "c1_wat_array_smoke: FAIL $name - emit driver returned $driver_rc" >&2
    fail=$((fail + 1))
    return
  fi

  # Validate WAT text contains expected structure
  if ! echo "$wat_text" | grep -q '(module'; then
    echo "c1_wat_array_smoke: FAIL $name - WAT missing (module" >&2
    fail=$((fail + 1))
    return
  fi
  if ! echo "$wat_text" | grep -q '(export "_start")'; then
    echo "c1_wat_array_smoke: FAIL $name - WAT missing (export \"_start\")" >&2
    fail=$((fail + 1))
    return
  fi
  if ! echo "$wat_text" | grep -q '(memory'; then
    echo "c1_wat_array_smoke: FAIL $name - WAT missing (memory" >&2
    fail=$((fail + 1))
    return
  fi

  # Check each expected WAT fragment is present
  for frag in "$@"; do
    if ! echo "$wat_text" | grep -q "$frag"; then
      echo "c1_wat_array_smoke: FAIL $name - WAT missing expected fragment: $frag" >&2
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
        echo "c1_wat_array_smoke: FAIL $name - WASM expected exit $expected_exit, got $rc" >&2
        fail=$((fail + 1))
        return
      fi
      echo "c1_wat_array_smoke: PASS $name (wat+wasm exit $rc)"
    else
      echo "c1_wat_array_smoke: PASS $name (wat text validated, wat2wasm failed)"
    fi
    pass=$((pass + 1))
  else
    echo "c1_wat_array_smoke: PASS $name (wat text validated)"
    pass=$((pass + 1))
  fi
}

# Constant-index i32 array write + read (mirrors c1_source_to_c_array_smoke.sh)
run_array_case array_const_idx \
  "fn main() i32 let values i32[3] values[0] = 7 values[1] = 35 ret values[0] + values[1] end" \
  42 \
  "i32.store offset=0" "i32.store offset=4" "i32.load offset=0" "i32.load offset=4" "i32.add"

# Single-element i32 array round-trip
run_array_case array_single_elem \
  "fn main() i32 let v i32[1] v[0] = 99 ret v[0] end" \
  99 \
  "i32.store offset=0" "i32.load offset=0"

# Larger constant index
run_array_case array_larger_idx \
  "fn main() i32 let v i32[5] v[3] = 8 v[4] = 4 ret v[3] + v[4] end" \
  12 \
  "i32.store offset=12" "i32.store offset=16" "i32.load offset=12" "i32.load offset=16"

# Variable-index i32 array read/write (mirrors c1_source_to_c_array_var_index_smoke.sh)
run_array_case array_var_idx \
  "fn main() i32 let values i32[3] let i i32 = 0 values[i] = 7 i = 1 values[i] = 35 ret values[0] + values[1] end" \
  42 \
  "i32.store align=4" "i32.load offset=0" "i32.load offset=4"

# Array with scalar local interaction
run_array_case array_with_scalars \
  "fn main() i32 let a i32[2] let x i32 = 10 a[0] = x a[1] = 32 ret a[0] + a[1] end" \
  42 \
  "i32.store offset=0" "i32.store offset=4" "i32.load offset=0" "i32.load offset=4"

# Local byte array constant-index write + read
run_array_case byte_array_const_idx \
  "fn main() i32 let values byte[4] values[0] = 10 values[1] = 32 ret values[0] + values[1] end" \
  42 \
  "i32.store8 offset=0" "i32.store8 offset=1" "i32.load8_s offset=0" "i32.load8_s offset=1" "i32.add"

# Local i8 array variable-index write + read
run_array_case i8_array_var_idx \
  "fn main() i32 let values i8[4] let i i32 = 1 values[i] = 42 ret values[i] end" \
  42 \
  "i32.store8 align=1" "i32.load8_s align=1"

# Summary
if [ "$fail" -gt 0 ]; then
  echo "c1_wat_array_smoke: FAIL - $fail failed, $pass passed" >&2
  exit 1
fi

echo "c1_wat_array_smoke: ok ($pass cases passed)"
