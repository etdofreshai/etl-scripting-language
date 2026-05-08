#!/usr/bin/env bash
set -euo pipefail

td="$(mktemp -d)"
trap 'rm -rf "$td"' EXIT

source='fn add(a i32, b integer) i32 ret a + b end fn bump(x integer) integer ret add(x, 1) end fn main() i32 ret bump(41) end'
source_len="${#source}"
src="$td/driver.etl"
c_out="$td/driver.c"
driver="$td/driver"
asm_out="$td/out.s"
obj_out="$td/out.o"
bin_out="$td/out"

sed '/^fn main()/,$d' compiler1/main.etl > "$src"
cat compiler1/lex.etl >> "$src"
cat compiler1/parse.etl >> "$src"
cat compiler1/sema.etl >> "$src"
cat compiler1/backend_defs.etl >> "$src"
cat compiler1/emit_asm.etl >> "$src"
cat >> "$src" <<ETL
extern fn etl_write_file1024(path i8[64], buf i8[1024], len i32) i32

fn main() i32
  let source i8[131072] = "$source"
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

for fragment in \
  ".globl add" \
  "add:" \
  ".globl bump" \
  "bump:" \
  ".globl main" \
  "main:" \
  "call add" \
  "call bump"; do
  if ! grep -q "$fragment" "$asm_out"; then
    echo "c1_asm_function_call_smoke: FAIL missing ASM fragment: $fragment" >&2
    cat "$asm_out" >&2
    exit 1
  fi
done

as --64 -o "$obj_out" "$asm_out"
cc -o "$bin_out" "$obj_out"

set +e
"$bin_out"
status=$?
set -e

if [ "$status" -ne 42 ]; then
  echo "c1_asm_function_call_smoke: FAIL expected native exit 42, got $status" >&2
  cat "$asm_out" >&2
  exit 1
fi

echo "c1_asm_function_call_smoke: ok (native exit 42)"
