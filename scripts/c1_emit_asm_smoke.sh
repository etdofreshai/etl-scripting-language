#!/usr/bin/env bash
set -euo pipefail

td="$(mktemp -d)"
emitted_s="/tmp/etl_c1_emit_asm.s"
trap 'rm -rf "$td"; rm -f "$emitted_s"' EXIT

# --- Build the compiler-1 ASM pipeline ---
# Concatenate: main.etl (without its main) + lex + parse + backend_defs + emit_asm + test harness
sed '/^fn main()/,$d' compiler1/main.etl > "$td/c1_asm_pipeline.etl"
cat compiler1/lex.etl >> "$td/c1_asm_pipeline.etl"
cat compiler1/parse.etl >> "$td/c1_asm_pipeline.etl"
cat compiler1/backend_defs.etl >> "$td/c1_asm_pipeline.etl"
cat compiler1/emit_asm.etl >> "$td/c1_asm_pipeline.etl"
cat >> "$td/c1_asm_pipeline.etl" <<'HARNESS'
extern fn etl_write_file1024(path i8[64], buf i8[1024], len i32) i32

fn main() i32
  let source i8[256] = "fn main() i32 ret 7 + 5 * 2 end"
  let tokens Token[128]
  let ast AstNode[512]
  let out i8[1024]
  let n i32 = lex(source, 31, tokens, 128)
  if n < 0
    ret 1
  end
  let an i32 = parse(tokens, n, ast, 512)
  if an < 0
    ret 2
  end
  let emitted i32 = emit_asm(ast, an, out, 1024)
  if emitted < 0
    ret 3
  end
  let path i8[64] = "/tmp/etl_c1_emit_asm.s"
  if etl_write_file1024(path, out, emitted) < 0
    ret 4
  end
  ret 0
end
HARNESS

# --- Compile the pipeline through compiler-0 ---
python3 -m compiler0 compile "$td/c1_asm_pipeline.etl" -o "$td/c1_asm_pipeline.c"
cc -Wall -Werror "$td/c1_asm_pipeline.c" runtime/etl_runtime.c -I runtime -o "$td/c1_asm_pipeline"

# --- Run the pipeline to emit assembly ---
"$td/c1_asm_pipeline"

if [ ! -s "$emitted_s" ]; then
  echo "c1_emit_asm_smoke: FAIL - no assembly emitted" >&2
  exit 1
fi

# --- Assemble and link the emitted .s file ---
as --64 -o "$td/emitted.o" "$emitted_s"
cc -o "$td/emitted" "$td/emitted.o"

# --- Run the emitted binary and check exit code ---
# 7 + 5 * 2 = 17, but exit code = 17 & 0xFF = 17
set +e
"$td/emitted"
status=$?
set -e

if [ "$status" -ne 17 ]; then
  echo "c1_emit_asm_smoke: FAIL - expected exit 17 (7+5*2), got $status" >&2
  cat "$emitted_s" >&2
  exit 1
fi

echo "c1_emit_asm_smoke: ok (fn main() i32 ret 7 + 5 * 2 end -> x86-64 asm -> exit 17)"
