#!/usr/bin/env bash
set -euo pipefail

td="$(mktemp -d)"
trap 'rm -rf "$td"' EXIT

source_text='type Item structure value integer end fn main() i32 let items Item[2] items[0].value = 19 items[1].value = 20 let i i32 = 1 items[i].value = items[i].value + 3 ret items[0].value + items[i].value end'
source_len="$(printf "%s" "$source_text" | wc -c)"
wat_out="$td/struct_array.wat"
src="$td/struct_array_driver.etl"
c_out="$td/struct_array_driver.c"
driver="$td/struct_array_driver"

sed '/^fn main()/,$d' compiler1/main.etl > "$src"
cat compiler1/lex.etl >> "$src"
cat compiler1/parse.etl >> "$src"
cat compiler1/sema.etl >> "$src"
cat compiler1/backend_defs.etl >> "$src"
cat compiler1/emit_wasm.etl >> "$src"
cat >> "$src" <<ETL
extern fn etl_write_file1024(path i8[64], buf i8[1024], len i32) i32

fn main() i32
  let source i8[256] = "$source_text"
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

if [ ! -s "$wat_out" ]; then
  echo "c1_wat_struct_array_smoke: FAIL - compiler-1 harness did not write WAT" >&2
  exit 1
fi

for fragment in '(module' '(export "_start")' '(memory' 'i32.store offset=0' 'i32.store offset=4' 'i32.store offset=0' 'i32.load offset=0' 'i32.load offset=0' 'i32.const 4' 'i32.mul' 'i32.add'; do
  if ! grep -q "$fragment" "$wat_out"; then
    echo "c1_wat_struct_array_smoke: FAIL - WAT missing expected fragment: $fragment" >&2
    exit 1
  fi
done

if command -v wat2wasm >/dev/null 2>&1; then
  wasm_out="$td/struct_array.wasm"
  wat2wasm "$wat_out" -o "$wasm_out"
  if command -v wasmtime >/dev/null 2>&1; then
    set +e
    wasmtime "$wasm_out" >/dev/null 2>&1
    status=$?
    set -e
    if [ "$status" -ne 42 ]; then
      echo "c1_wat_struct_array_smoke: FAIL - expected WASM exit 42, got $status" >&2
      exit 1
    fi
    echo "c1_wat_struct_array_smoke: ok (wat+wasm exit 42)"
    exit 0
  fi
  if command -v wasmer >/dev/null 2>&1; then
    set +e
    wasmer run "$wasm_out" >/dev/null 2>&1
    status=$?
    set -e
    if [ "$status" -ne 42 ]; then
      echo "c1_wat_struct_array_smoke: FAIL - expected WASM exit 42, got $status" >&2
      exit 1
    fi
    echo "c1_wat_struct_array_smoke: ok (wat+wasm exit 42)"
    exit 0
  fi
  echo "c1_wat_struct_array_smoke: ok (wat2wasm validation only)"
  exit 0
fi

echo "c1_wat_struct_array_smoke: ok (wat text validated)"
