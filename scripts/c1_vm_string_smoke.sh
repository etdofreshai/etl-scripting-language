#!/usr/bin/env bash
# Verify string_heap_*.etl fixtures compile and run under the VM backend (HS* opcodes).
set -euo pipefail

td="$(mktemp -d)"
trap 'rm -rf "$td"' EXIT

fixtures=(
  string_heap_basic.etl
  string_heap_concat.etl
  string_heap_eq.etl
)

# Build a VM runner
cat > "$td/vm_runner.c" <<'EOF_C'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "etl_vm.h"

int main(int argc, char **argv) {
  if (argc < 2) return 1;
  FILE *f = fopen(argv[1], "r");
  if (!f) return 2;
  char buf[4096];
  int n = (int)fread(buf, 1, sizeof(buf) - 1, f);
  fclose(f);
  if (n <= 0) return 3;
  buf[n] = 0;
  int32_t result = 0;
  int32_t rc = etl_vm_run_main_i32((const int8_t*)buf, n, &result);
  if (rc != 0) { fprintf(stderr, "vm error: %d\n", rc); return 4; }
  return (int)result;
}
EOF_C

cc -std=c11 -Wall -Werror -I runtime "$td/vm_runner.c" runtime/etl_vm.c runtime/etl_string.c runtime/etl_dynarr.c runtime/etl_etlval.c -o "$td/vm_runner"

pass=0
fail=0

# Strip comment lines before flattening: the harness embeds the fixture as a single-line
# string literal, so any '#' comment would consume everything after it on that line.
# source_len is computed from the post-strip text so lexer bounds stay correct.
escape_for_etl_string() {
  grep -v '^[[:space:]]*#' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr '\n' ' '
}

for fixture in "${fixtures[@]}"; do
  src="tests/c1_corpus/$fixture"
  name="${fixture%.etl}"
  bytecode_path="$td/${name}.bc"

  source_text="$(escape_for_etl_string "$src")"
  source_len="${#source_text}"

  harness="$td/${name}_bc_harness.etl"
  sed '/^fn main()/,$d' compiler1/main.etl > "$harness"
  cat compiler1/lex.etl >> "$harness"
  cat compiler1/parse.etl >> "$harness"
  cat compiler1/backend_defs.etl >> "$harness"
  cat compiler1/emit_bytecode.etl >> "$harness"
  cat >> "$harness" <<EOF_HARNESS

extern fn etl_write_file1024(path i8[64], buf i8[65536], len i32) i32

fn main() i32
  let source i8[131072] = "$source_text"
  let tokens Token[32768]
  let ast AstNode[32768]
  let out i8[65536]
  let n i32 = lex(source, $source_len, tokens, 32768)
  if n < 0
    ret 1
  end
  let an i32 = parse(tokens, n, ast, 32768)
  if an < 0
    ret 2
  end
  let emitted i32 = emit_bytecode(source, tokens, ast, an, out, 65536)
  if emitted < 0
    ret 3
  end
  let path i8[64] = "$bytecode_path"
  if etl_write_file1024(path, out, emitted) < 0
    ret 4
  end
  ret 0
end
EOF_HARNESS

  scripts/build_etl.sh "$harness" "$td/${name}_bc_harness"
  if ! "$td/${name}_bc_harness"; then
    echo "c1_vm_string_smoke: FAIL $fixture bytecode generation failed" >&2
    fail=$((fail + 1))
    continue
  fi

  if [ ! -s "$bytecode_path" ]; then
    echo "c1_vm_string_smoke: FAIL $fixture bytecode file empty or missing" >&2
    fail=$((fail + 1))
    continue
  fi

  set +e
  "$td/vm_runner" "$bytecode_path"
  vm_exit=$?
  set -e

  if [ "$vm_exit" -ne 0 ]; then
    echo "c1_vm_string_smoke: FAIL $fixture VM exit $vm_exit (expected 0)" >&2
    fail=$((fail + 1))
  else
    echo "c1_vm_string_smoke: PASS $fixture (VM exit 0)"
    pass=$((pass + 1))
  fi
done

echo "c1_vm_string_smoke: $pass passed, $fail failed"
if [ "$fail" -ne 0 ]; then
  exit 1
fi
