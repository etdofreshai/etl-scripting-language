#!/usr/bin/env bash
set -euo pipefail

td="$(mktemp -d)"
trap 'rm -rf "$td"' EXIT

src="$td/test_asm_return.etl"
c_out="$td/test_asm_return.c"
driver="$td/test_asm_return"
asm_out="$td/test_asm_return.s"
obj_out="$td/test_asm_return.o"
native="$td/test_asm_return_native"
literal=42

sed '/^fn main()/,$d' compiler1/main.etl > "$src"
cat compiler1/backend_defs.etl >> "$src"
cat compiler1/emit_asm.etl >> "$src"
cat >> "$src" <<ETL
extern fn etl_write_file1024(path i8[64], buf i8[1024], len i32) i32

fn main() i32
  let ast AstNode[512]
  let out i8[1024]
  let path i8[64] = "$asm_out"

  ast[0].kind = AN_INT()
  ast[0].a = $literal
  ast[1].kind = AN_RET()
  ast[1].a = 0
  ast[2].kind = AN_LIST()
  ast[2].a = 1
  ast[2].b = -1
  ast[3].kind = AN_BLOCK()
  ast[3].a = 2
  ast[3].b = 1
  ast[4].kind = AN_BLOCK()
  ast[4].a = -1
  ast[4].b = 0
  ast[5].kind = AN_FN()
  ast[5].b = 4
  ast[5].c = 3
  ast[6].kind = AN_LIST()
  ast[6].a = 5
  ast[6].b = -1
  ast[7].kind = AN_PROGRAM()
  ast[7].a = 6
  ast[7].b = 1

  let n i32 = emit_asm(ast, 8, out, 1024)
  if n <= 0
    ret 1
  end
  if etl_write_file1024(path, out, n) < 0
    ret 2
  end
  ret 0
end
ETL

python3 -m compiler0 compile "$src" -o "$c_out"
cc -Wall -Werror "$c_out" -I runtime runtime/etl_runtime.c -o "$driver"
"$driver"

as "$asm_out" -o "$obj_out"
ld "$obj_out" -o "$native"

set +e
"$native"
rc=$?
set -e

if [ "$rc" -ne "$literal" ]; then
  echo "c1_asm_return_smoke: FAIL - expected exit $literal, got $rc" >&2
  exit 1
fi

echo "c1_asm_return_smoke: ok (return literal $literal)"
