#!/usr/bin/env bash
# release_smoke_wasi.sh — End-to-end WASI smoke: ETL source → WAT → WASM → wasmtime.
#
# Validates VAL-DIST-004 (WASM/WASI path).  Uses a small deterministic ETL
# program (6 * 7 = 42) as the subject, since the calculator REPL requires
# stdin/stdout externs that are not WASI-portable without extra shims.
#
# The "browser" dimension of VAL-DIST-004 is covered by
# scripts/release_smoke_wasm_browser.sh which runs the same .wasm via Node.js
# WebAssembly API (see that script for the full rationale).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export PATH="$REPO_ROOT/.deps:$PATH"

# ── tool checks ─────────────────────────────────────────────────────────────
if ! command -v wat2wasm &>/dev/null; then
  echo "release_smoke_wasi: SKIP — wat2wasm not found in .deps/ or PATH" >&2
  exit 0
fi
if ! command -v wasmtime &>/dev/null; then
  echo "release_smoke_wasi: SKIP — wasmtime not found in .deps/ or PATH" >&2
  exit 0
fi

# ── temp workspace ───────────────────────────────────────────────────────────
td="$(mktemp -d)"
trap 'rm -rf "$td"' EXIT

cd "$REPO_ROOT"

# ── helper: escape ETL string literal ───────────────────────────────────────
escape_for_etl_string() {
  printf "%s" "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

# ── ETL source (deterministic: returns 42 = 6 * 7) ──────────────────────────
ETL_SOURCE="fn main() i32 ret 6 * 7 end"
EXPECTED_EXIT=42

echo "release_smoke_wasi: compiling ETL → WAT ..."

escaped="$(escape_for_etl_string "$ETL_SOURCE")"
source_len="$(printf "%s" "$ETL_SOURCE" | wc -c)"

wat_out="$td/calc.wat"
wasm_out="$td/calc.wasm"
src="$td/calc_wasi.etl"
c_out="$td/calc_wasi.c"
driver="$td/calc_wasi_driver"

# Build the c1 emit driver (same pattern used in c1_wat_return_smoke.sh)
sed '/^fn main()/,$d' compiler1/main.etl > "$src"
cat compiler1/lex.etl     >> "$src"
cat compiler1/parse.etl   >> "$src"
cat compiler1/sema.etl    >> "$src"
cat compiler1/backend_defs.etl >> "$src"
cat compiler1/emit_wasm.etl    >> "$src"

cat >> "$src" <<ETL
extern fn etl_write_file1024(path i8[64], buf i8[1024], len i32) i32

fn main() i32
  let source i8[131072] = "$escaped"
  let tokens Token[32768]
  let ast AstNode[32768]
  let out i8[1024]
  let path i8[64] = "$wat_out"

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

if [ ! -f "$wat_out" ]; then
  echo "release_smoke_wasi: FAIL — WAT file not produced" >&2
  exit 1
fi

echo "release_smoke_wasi: WAT produced ($(wc -c < "$wat_out") bytes)"

# ── WAT → WASM ──────────────────────────────────────────────────────────────
echo "release_smoke_wasi: wat2wasm → WASM ..."
wat2wasm "$wat_out" -o "$wasm_out"

echo "release_smoke_wasi: WASM produced ($(wc -c < "$wasm_out") bytes)"

# ── wasmtime execute (WASI) ──────────────────────────────────────────────────
echo "release_smoke_wasi: running via wasmtime (WASI) ..."
set +e
wasmtime "$wasm_out"
actual_exit=$?
set -e

echo "release_smoke_wasi: wasmtime exit code = $actual_exit (expected $EXPECTED_EXIT)"

if [ "$actual_exit" -ne "$EXPECTED_EXIT" ]; then
  echo "release_smoke_wasi: FAIL — expected exit $EXPECTED_EXIT, got $actual_exit" >&2
  exit 1
fi

echo "release_smoke_wasi: ok — ETL→WAT→WASM→wasmtime exit $actual_exit matches expected $EXPECTED_EXIT"
