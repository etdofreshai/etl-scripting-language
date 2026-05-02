#!/usr/bin/env bash
set -euo pipefail

td="$(mktemp -d)"
trap 'rm -rf "$td"; rm -f /tmp/etl_c1_emit_asm_*.s' EXIT

run_case() {
  local name="$1"
  local source="$2"
  local expected="$3"
  local source_len="${#source}"
  local emitted_s="/tmp/etl_c1_emit_asm_${name}.s"

  # --- Build the compiler-1 ASM pipeline ---
  # Concatenate: main.etl (without its main) + lex + parse + backend_defs + emit_asm + test harness
  sed '/^fn main()/,$d' compiler1/main.etl > "$td/c1_asm_pipeline_${name}.etl"
  cat compiler1/lex.etl >> "$td/c1_asm_pipeline_${name}.etl"
  cat compiler1/parse.etl >> "$td/c1_asm_pipeline_${name}.etl"
  cat compiler1/backend_defs.etl >> "$td/c1_asm_pipeline_${name}.etl"
  cat compiler1/emit_asm.etl >> "$td/c1_asm_pipeline_${name}.etl"
  cat >> "$td/c1_asm_pipeline_${name}.etl" <<HARNESS
extern fn etl_write_file1024(path i8[64], buf i8[1024], len i32) i32

fn main() i32
  let source i8[256] = "$source"
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
  let emitted i32 = emit_asm(source, tokens, ast, an, out, 1024)
  if emitted < 0
    ret 3
  end
  let path i8[64] = "$emitted_s"
  if etl_write_file1024(path, out, emitted) < 0
    ret 4
  end
  ret 0
end
HARNESS

  # --- Compile the pipeline through compiler-0 ---
  python3 -m compiler0 compile "$td/c1_asm_pipeline_${name}.etl" -o "$td/c1_asm_pipeline_${name}.c"
  cc -Wall -Werror "$td/c1_asm_pipeline_${name}.c" runtime/etl_runtime.c -I runtime -o "$td/c1_asm_pipeline_${name}"

  # --- Run the pipeline to emit assembly ---
  "$td/c1_asm_pipeline_${name}"

  if [ ! -s "$emitted_s" ]; then
    echo "c1_emit_asm_smoke: FAIL - no assembly emitted for $name" >&2
    exit 1
  fi

  # --- Assemble and link the emitted .s file ---
  as --64 -o "$td/emitted_${name}.o" "$emitted_s"
  cc -o "$td/emitted_${name}" "$td/emitted_${name}.o"

  # --- Run the emitted binary and check exit code ---
  set +e
  "$td/emitted_${name}"
  status=$?
  set -e

  if [ "$status" -ne "$expected" ]; then
    echo "c1_emit_asm_smoke: FAIL - $name expected exit $expected, got $status" >&2
    cat "$emitted_s" >&2
    exit 1
  fi
}

run_case "arith" "fn main() i32 ret 7 + 5 * 2 end" 17
run_case "elif_true" "fn main() i32 let x i32 = 0 if false x = 1 elif true x = 7 else x = 9 end ret x end" 7
run_case "elif_else" "fn main() i32 let x i32 = 0 if false x = 1 elif false x = 7 else x = 9 end ret x end" 9
run_case "elif_order" "fn main() i32 let x i32 = 0 if false x = 1 elif true x = 7 elif true x = 9 else x = 11 end ret x end" 7
run_case "i32_call" "fn add(a i32, b integer) i32 ret a + b end fn main() i32 ret add(40, 2) end" 42
run_case "bool_param" "fn choose(flag bool) i32 if flag ret 42 end ret 7 end fn main() i32 ret choose(true) end" 42
run_case "boolean_param" "fn choose(flag boolean) i32 if flag ret 42 end ret 7 end fn main() i32 ret choose(false) end" 7
run_case "i8_param" "fn plus_one(ch i8) i32 ret ch + 1 end fn main() i32 ret plus_one(41) end" 42
run_case "byte_param" "fn plus_one(ch byte) i32 ret ch + 1 end fn main() i32 ret plus_one(41) end" 42

echo "c1_emit_asm_smoke: ok (arithmetic, if/elif/else chains, i32 helper calls, and scalar helper params -> x86-64 asm)"
