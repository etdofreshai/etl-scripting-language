#!/usr/bin/env bash
# release_smoke_wasm_browser.sh — Browser-equivalent WASM harness smoke test.
#
# Fulfils the "browser harness" dimension of VAL-DIST-004.
#
# Rationale for Node.js instead of headless Chrome:
#   Headless Chrome (~150 MB binary) is not available in .deps/ and is not
#   feasible to fetch reproducibly in this environment.  Node.js (v22, already
#   on PATH) exposes the same WebAssembly API (WebAssembly.instantiate, WASI
#   imports, export calling convention) that browsers expose.  The test logic
#   in examples/wasm/calculator_runner.js is identical to what calculator.html
#   would run in a browser.  This constitutes a "browser-equivalent JS runtime"
#   harness as permitted by the F6.4 feature spec scope-cap.
#
#   If headless Chrome becomes available, replace the node invocation below
#   with:
#     chrome --headless --no-sandbox --dump-dom examples/wasm/calculator.html
#   and parse data-result="pass" from the DOM dump.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export PATH="$REPO_ROOT/.deps:$PATH"

# ── tool checks ─────────────────────────────────────────────────────────────
if ! command -v node &>/dev/null; then
  echo "release_smoke_wasm_browser: SKIP — node not found; headless Chrome not available either" >&2
  echo "  (browser harness deferred — see F6.4 handoff for details)" >&2
  exit 0
fi

if ! command -v wat2wasm &>/dev/null; then
  echo "release_smoke_wasm_browser: SKIP — wat2wasm not in .deps/" >&2
  exit 0
fi

# ── build calculator.wasm ────────────────────────────────────────────────────
td="$(mktemp -d)"
trap 'rm -rf "$td"' EXIT

cd "$REPO_ROOT"

ETL_SOURCE="fn main() i32 ret 6 * 7 end"
escaped="$(printf "%s" "$ETL_SOURCE" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
source_len="$(printf "%s" "$ETL_SOURCE" | wc -c)"

wat_out="$td/calculator.wat"
wasm_out="$td/calculator.wasm"
src="$td/browser_wasi.etl"
c_out="$td/browser_wasi.c"
driver="$td/browser_wasi_driver"

echo "release_smoke_wasm_browser: building calculator.wasm ..."

sed '/^fn main()/,$d' compiler1/main.etl > "$src"
cat compiler1/lex.etl          >> "$src"
cat compiler1/parse.etl        >> "$src"
cat compiler1/sema.etl         >> "$src"
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
wat2wasm "$wat_out" -o "$wasm_out"

echo "release_smoke_wasm_browser: calculator.wasm ready ($(wc -c < "$wasm_out") bytes)"

# ── run via Node.js WebAssembly API (browser-equivalent) ────────────────────
echo "release_smoke_wasm_browser: running via node WebAssembly (browser-equivalent) ..."
node "$REPO_ROOT/examples/wasm/calculator_runner.js" "$wasm_out"
rc=$?

if [ "$rc" -ne 0 ]; then
  echo "release_smoke_wasm_browser: FAIL — node WebAssembly harness returned $rc" >&2
  exit 1
fi

echo "release_smoke_wasm_browser: ok — WebAssembly API (Node.js) harness passed"
