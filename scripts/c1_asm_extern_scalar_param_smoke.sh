#!/usr/bin/env bash
set -euo pipefail

td="$(mktemp -d)"
trap 'rm -rf "$td"' EXIT

source='extern fn accept_bool(flag bool) i32 extern fn accept_boolean(flag boolean) i32 extern fn plus_i8(ch i8) i32 extern fn accept_byte(ch byte) i32 fn main() i32 ret accept_bool(true) + accept_boolean(false) + plus_i8(40) + accept_byte(0) end'
source_len="${#source}"
src="$td/driver.etl"
c_out="$td/driver.c"
driver="$td/driver"
asm_out="$td/out.s"
obj_out="$td/out.o"
helper_obj="$td/helper.o"
helper_c="$td/helper.c"
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
  let source i8[256] = "$source"
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

python3 -m compiler0 compile "$src" -o "$c_out"
cc -Wall -Werror "$c_out" -I runtime runtime/etl_runtime.c -o "$driver"
"$driver"

for fragment in \
  ".globl main" \
  "call accept_bool" \
  "call accept_boolean" \
  "call plus_i8" \
  "call accept_byte"; do
  if ! grep -q "$fragment" "$asm_out"; then
    echo "c1_asm_extern_scalar_param_smoke: FAIL missing ASM fragment: $fragment" >&2
    cat "$asm_out" >&2
    exit 1
  fi
done

for fragment in \
  ".globl accept_bool" \
  ".globl accept_boolean" \
  ".globl plus_i8" \
  ".globl accept_byte"; do
  if grep -q "$fragment" "$asm_out"; then
    echo "c1_asm_extern_scalar_param_smoke: FAIL emitted a body for an extern declaration" >&2
    cat "$asm_out" >&2
    exit 1
  fi
done

cat > "$helper_c" <<'C'
#include <stdbool.h>

int accept_bool(bool flag) {
  return flag ? 1 : 10;
}

int accept_boolean(bool flag) {
  return flag ? 10 : 0;
}

int plus_i8(signed char ch) {
  return ch + 1;
}

int accept_byte(signed char ch) {
  return ch;
}
C

as --64 -o "$obj_out" "$asm_out"
cc -std=c11 -Wall -Wextra -Werror -c "$helper_c" -o "$helper_obj"
cc -o "$bin_out" "$obj_out" "$helper_obj"

set +e
"$bin_out"
status=$?
set -e

if [ "$status" -ne 42 ]; then
  echo "c1_asm_extern_scalar_param_smoke: FAIL expected native exit 42, got $status" >&2
  cat "$asm_out" >&2
  exit 1
fi

echo "c1_asm_extern_scalar_param_smoke: ok (native extern bool/i8/byte scalar params exit 42)"
