#!/usr/bin/env bash
set -euo pipefail

td="$(mktemp -d)"
trap 'rm -rf "$td"' EXIT

source_text='type Pair structure left integer right integer end fn main() i32 let p Pair p.left = 19 p.right = 23 ret p.left + p.right end'
source_len="$(printf "%s" "$source_text" | wc -c)"
asm_out="$td/struct_field.s"
obj_out="$td/struct_field.o"
native="$td/struct_field_native"
src="$td/struct_field_driver.etl"
c_out="$td/struct_field_driver.c"
driver="$td/struct_field_driver"

sed '/^fn main()/,$d' compiler1/main.etl > "$src"
cat compiler1/lex.etl >> "$src"
cat compiler1/parse.etl >> "$src"
cat compiler1/sema.etl >> "$src"
cat compiler1/backend_defs.etl >> "$src"
cat compiler1/emit_asm.etl >> "$src"
cat >> "$src" <<ETL
extern fn etl_write_file1024(path i8[64], buf i8[1024], len i32) i32

fn main() i32
  let source i8[131072] = "$source_text"
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

if [ ! -s "$asm_out" ]; then
  echo "c1_asm_struct_field_smoke: FAIL - compiler-1 harness did not write ASM" >&2
  exit 1
fi

for fragment in 'mov $19, %rax' 'mov %rax, -8(%rbp)' 'mov $23, %rax' 'mov %rax, -4(%rbp)' 'mov -8(%rbp), %rax' 'mov -4(%rbp), %rax' 'add %rcx, %rax'; do
  if ! grep -q "$fragment" "$asm_out"; then
    echo "c1_asm_struct_field_smoke: FAIL - ASM missing expected fragment: $fragment" >&2
    cat "$asm_out" >&2
    exit 1
  fi
done

if ! as --64 -o "$obj_out" "$asm_out"; then
  echo "c1_asm_struct_field_smoke: FAIL - assembler failed" >&2
  cat "$asm_out" >&2
  exit 1
fi
cc -no-pie "$obj_out" -o "$native"

set +e
"$native" >/dev/null
status=$?
set -e

if [ "$status" -ne 42 ]; then
  echo "c1_asm_struct_field_smoke: FAIL - expected native exit 42, got $status" >&2
  cat "$asm_out" >&2
  exit 1
fi

echo "c1_asm_struct_field_smoke: ok (native exit 42)"
