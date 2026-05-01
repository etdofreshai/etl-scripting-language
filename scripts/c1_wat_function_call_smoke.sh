#!/usr/bin/env bash
set -euo pipefail

td="$(mktemp -d)"
trap 'rm -rf "$td"' EXIT

escape_for_etl_string() {
  printf "%s" "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

run_wat_emit() {
  local source="$1"
  local escaped
  local source_len
  local src="$td/driver.etl"
  local c_out="$td/driver.c"
  local driver="$td/driver"
  local wat_out="$td/out.wat"

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

source='fn add(a i32, b integer) i32 ret a + b end fn bump(x integer) integer ret add(x, 1) end fn main() i32 ret bump(41) end'
wat_text="$(run_wat_emit "$source")"

for fragment in \
  '(func $add (param $v0 i32) (param $v1 i32) (result i32)' \
  '(func $bump (param $v0 i32) (result i32)' \
  '(func $main (export "_start") (result i32)' \
  'local.get $v0' \
  'local.get $v1' \
  'call $add' \
  'call $bump'; do
  if ! echo "$wat_text" | grep -q "$fragment"; then
    echo "c1_wat_function_call_smoke: FAIL missing WAT fragment: $fragment" >&2
    echo "$wat_text" >&2
    exit 1
  fi
done

if command -v wat2wasm >/dev/null 2>&1; then
  wat2wasm "$td/out.wat" -o "$td/out.wasm"
  if command -v wasmtime >/dev/null 2>&1; then
    set +e
    wasmtime "$td/out.wasm" >/dev/null 2>&1
    status=$?
    set -e
    if [ "$status" -ne 42 ]; then
      echo "c1_wat_function_call_smoke: FAIL expected wasmtime exit 42, got $status" >&2
      exit 1
    fi
    echo "c1_wat_function_call_smoke: ok (wat+wasm exit 42)"
    exit 0
  fi
  if command -v wasmer >/dev/null 2>&1; then
    set +e
    wasmer run "$td/out.wasm" >/dev/null 2>&1
    status=$?
    set -e
    if [ "$status" -ne 42 ]; then
      echo "c1_wat_function_call_smoke: FAIL expected wasmer exit 42, got $status" >&2
      exit 1
    fi
    echo "c1_wat_function_call_smoke: ok (wat+wasm exit 42)"
    exit 0
  fi
  echo "c1_wat_function_call_smoke: ok (wat2wasm validation only)"
  exit 0
fi

echo "c1_wat_function_call_smoke: ok (wat text validated)"
