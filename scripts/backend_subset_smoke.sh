#!/usr/bin/env bash
set -euo pipefail

td="$(mktemp -d)"
trap 'rm -rf "$td"' EXIT

escape_for_etl_string() {
  printf "%s" "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

build_emit_driver() {
  local backend="$1"
  local name="$2"
  local source="$3"
  local out_path="$4"
  local driver_src="$td/${backend}_${name}_driver.etl"
  local driver_bin="$td/${backend}_${name}_driver"
  local escaped
  local source_len

  escaped="$(escape_for_etl_string "$source")"
  source_len="$(printf "%s" "$source" | wc -c)"

  sed '/^fn main()/,$d' compiler1/main.etl > "$driver_src"
  cat compiler1/lex.etl >> "$driver_src"
  cat compiler1/parse.etl >> "$driver_src"
  cat compiler1/sema.etl >> "$driver_src"
  cat compiler1/backend_defs.etl >> "$driver_src"
  cat "compiler1/emit_${backend}.etl" >> "$driver_src"
  cat >> "$driver_src" <<EOF_DRIVER
extern fn etl_write_file1024(path i8[64], buf i8[1024], len i32) i32

fn main() i32
  let source i8[256] = "$escaped"
  let tokens Token[128]
  let ast AstNode[512]
  let out i8[1024]
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
  let emitted i32 = emit_${backend}(source, tokens, ast, ast_count, out, 1024)
  if emitted <= 0
    ret 4
  end
  let path i8[64] = "$out_path"
  if etl_write_file1024(path, out, emitted) < 0
    ret 5
  end
  ret 0
end
EOF_DRIVER

  scripts/build_etl.sh "$driver_src" "$driver_bin" >/dev/null
  "$driver_bin"
}

run_c_case() {
  local name="$1"
  local source="$2"
  local expected="$3"
  local emitted="$td/${name}.c"
  local bin="$td/${name}_c"

  build_emit_driver c "$name" "$source" "$emitted"
  cc -Wall -Werror "$emitted" -o "$bin"
  set +e
  "$bin" >/dev/null
  local status=$?
  set -e
  if [ "$status" -ne "$expected" ]; then
    echo "backend_subset_smoke: FAIL c/$name expected $expected, got $status" >&2
    exit 1
  fi
  echo "backend_subset_smoke: PASS c/$name (exit $status)"
}

run_asm_case() {
  local name="$1"
  local source="$2"
  local expected="$3"
  local emitted="$td/${name}.s"
  local obj="$td/${name}.o"
  local bin="$td/${name}_asm"

  build_emit_driver asm "$name" "$source" "$emitted"
  as --64 -o "$obj" "$emitted"
  cc -o "$bin" "$obj"
  set +e
  "$bin" >/dev/null
  local status=$?
  set -e
  if [ "$status" -ne "$expected" ]; then
    echo "backend_subset_smoke: FAIL asm/$name expected $expected, got $status" >&2
    cat "$emitted" >&2
    exit 1
  fi
  echo "backend_subset_smoke: PASS asm/$name (exit $status)"
}

run_wat_case() {
  local name="$1"
  local source="$2"
  local expected="$3"
  shift 3
  local emitted="$td/${name}.wat"
  local wasm="$td/${name}.wasm"

  build_emit_driver wasm "$name" "$source" "$emitted"
  if ! grep -q '(module' "$emitted"; then
    echo "backend_subset_smoke: FAIL wat/$name missing module" >&2
    exit 1
  fi
  if ! grep -q '(export "_start")' "$emitted"; then
    echo "backend_subset_smoke: FAIL wat/$name missing _start export" >&2
    exit 1
  fi
  for fragment in "$@"; do
    if ! grep -q "$fragment" "$emitted"; then
      echo "backend_subset_smoke: FAIL wat/$name missing fragment: $fragment" >&2
      cat "$emitted" >&2
      exit 1
    fi
  done

  if command -v wat2wasm >/dev/null 2>&1; then
    wat2wasm "$emitted" -o "$wasm"
    if command -v wasmtime >/dev/null 2>&1; then
      set +e
      wasmtime "$wasm" >/dev/null 2>&1
      local status=$?
      set -e
      if [ "$status" -ne "$expected" ]; then
        echo "backend_subset_smoke: FAIL wat/$name expected $expected, got $status" >&2
        exit 1
      fi
      echo "backend_subset_smoke: PASS wat/$name (wasmtime exit $status)"
      return
    fi
    if command -v wasmer >/dev/null 2>&1; then
      set +e
      wasmer run "$wasm" >/dev/null 2>&1
      local status=$?
      set -e
      if [ "$status" -ne "$expected" ]; then
        echo "backend_subset_smoke: FAIL wat/$name expected $expected, got $status" >&2
        exit 1
      fi
      echo "backend_subset_smoke: PASS wat/$name (wasmer exit $status)"
      return
    fi
    echo "backend_subset_smoke: PASS wat/$name (wat2wasm validation only)"
    return
  fi

  echo "backend_subset_smoke: PASS wat/$name (text validation only; wat2wasm unavailable)"
}

run_case() {
  local name="$1"
  local source="$2"
  local expected="$3"
  shift 3

  run_c_case "$name" "$source" "$expected"
  run_asm_case "$name" "$source" "$expected"
  run_wat_case "$name" "$source" "$expected" "$@"
}

run_case ret_literal "fn main() i32 ret 42 end" 42 "i32.const 42"
run_case ret_arithmetic "fn main() i32 ret 1 + 2 * 3 end" 7 "i32.const 1" "i32.const 2" "i32.const 3" "i32.mul" "i32.add"
run_case ret_comparison "fn main() i32 ret 2 < 3 end" 1 "i32.const 2" "i32.const 3" "i32.lt_s"
run_case ret_logical "fn main() i32 ret not false or 0 end" 1 "i32.const 0" "i32.eqz" "i32.or"

echo "backend_subset_smoke: ok (4 shared cases across C, ASM, and WAT)"
