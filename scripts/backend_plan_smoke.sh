#!/usr/bin/env bash
set -euo pipefail

td="$(mktemp -d)"
trap 'rm -rf "$td"' EXIT

pass=0
fail=0

# --- Check 1: docs/backend-plan.md exists ---
if [ -f docs/backend-plan.md ]; then
  echo "backend_plan_smoke: backend-plan.md exists"
  pass=$((pass + 1))
else
  echo "backend_plan_smoke: FAIL — docs/backend-plan.md missing" >&2
  fail=$((fail + 1))
fi

# --- Check 2: backend_defs.etl compiles and EMIT_OK is 0 ---
sed '/^fn main()/,$d' compiler1/main.etl > "$td/test_defs.etl"
cat compiler1/backend_defs.etl >> "$td/test_defs.etl"
printf 'fn main() i32\n  ret EMIT_OK()\nend\n' >> "$td/test_defs.etl"
python3 -m compiler0 compile "$td/test_defs.etl" -o "$td/test_defs.c"
cc -Wall -Werror "$td/test_defs.c" -I runtime -o "$td/test_defs"
set +e
"$td/test_defs"
rc=$?
set -e
if [ "$rc" -eq 0 ]; then
  echo "backend_plan_smoke: backend_defs.etl compiles, EMIT_OK = 0"
  pass=$((pass + 1))
else
  echo "backend_plan_smoke: FAIL — EMIT_OK expected 0, got $rc" >&2
  fail=$((fail + 1))
fi

# --- Check 3: emit_asm.etl compiles and returns EMIT_ERR_BAD_AST ---
sed '/^fn main()/,$d' compiler1/main.etl > "$td/test_asm.etl"
cat compiler1/backend_defs.etl >> "$td/test_asm.etl"
cat compiler1/emit_asm.etl >> "$td/test_asm.etl"
printf 'fn main() i32\n  let source i8[131072]\n  let tokens Token[32768]\n  let out i8[1024]\n  let ast AstNode[32768]\n  ret emit_asm(source, tokens, ast, 0, out, 1024)\nend\n' >> "$td/test_asm.etl"
python3 -m compiler0 compile "$td/test_asm.etl" -o "$td/test_asm.c"
cc -Wall -Werror "$td/test_asm.c" -I runtime -o "$td/test_asm"
set +e
"$td/test_asm"
rc=$?
set -e
# -3 (EMIT_ERR_BAD_AST) mod 256 = 253
if [ "$rc" -eq 253 ]; then
  echo "backend_plan_smoke: emit_asm.etl compiles, returns EMIT_ERR_BAD_AST"
  pass=$((pass + 1))
else
  echo "backend_plan_smoke: FAIL — emit_asm expected exit 253, got $rc" >&2
  fail=$((fail + 1))
fi

# --- Check 4: emit_wasm.etl compiles and returns EMIT_ERR_BAD_AST ---
sed '/^fn main()/,$d' compiler1/main.etl > "$td/test_wasm.etl"
cat compiler1/backend_defs.etl >> "$td/test_wasm.etl"
cat compiler1/emit_wasm.etl >> "$td/test_wasm.etl"
printf 'fn main() i32\n  let source i8[131072]\n  let tokens Token[32768]\n  let out i8[1024]\n  let ast AstNode[32768]\n  ret emit_wasm(source, tokens, ast, 0, out, 1024)\nend\n' >> "$td/test_wasm.etl"
python3 -m compiler0 compile "$td/test_wasm.etl" -o "$td/test_wasm.c"
cc -Wall -Werror "$td/test_wasm.c" -I runtime -o "$td/test_wasm"
set +e
"$td/test_wasm"
rc=$?
set -e
# -3 (EMIT_ERR_BAD_AST) mod 256 = 253
if [ "$rc" -eq 253 ]; then
  echo "backend_plan_smoke: emit_wasm.etl compiles, returns EMIT_ERR_BAD_AST"
  pass=$((pass + 1))
else
  echo "backend_plan_smoke: FAIL — emit_wasm expected exit 253, got $rc" >&2
  fail=$((fail + 1))
fi

# --- Summary ---
if [ "$fail" -gt 0 ]; then
  echo "backend_plan_smoke: FAIL — $fail failed, $pass passed" >&2
  exit 1
fi

echo "backend_plan_smoke: ok ($pass checks passed)"
