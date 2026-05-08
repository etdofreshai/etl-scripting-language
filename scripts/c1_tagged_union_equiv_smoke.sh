#!/usr/bin/env bash
# Verify tagged_union_*.etl fixtures produce identical exit codes via
# compiler-1 C backend and VM backend.
# compiler-0 is intentionally excluded: it does not support the etlval opaque type.
set -euo pipefail

td="$(mktemp -d)"
trap 'rm -rf "$td"' EXIT

fixtures=(
  tagged_union_basic.etl
  tagged_union_dispatch.etl
)

pass=0
fail=0

# Build VM runner (includes etl_etlval for HV* opcodes)
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

escape_for_etl_string() {
  sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' "$1" | tr '\n' ' '
}

build_c1_harness() {
  local src_file="$1"
  local out_c_path="$2"
  local out_bc_path="$3"
  local harness_c="$4"
  local harness_bc="$5"
  local source_text
  local source_len
  source_text="$(escape_for_etl_string "$src_file")"
  source_len="$(tr '\n' ' ' < "$src_file" | wc -c)"

  # Harness for C emission
  sed '/^fn main()/,$d' compiler1/main.etl > "$harness_c"
  cat compiler1/lex.etl >> "$harness_c"
  cat compiler1/parse.etl >> "$harness_c"
  cat compiler1/sema.etl >> "$harness_c"
  cat compiler1/emit_c.etl >> "$harness_c"
  cat >> "$harness_c" <<EOF_HARNESS
extern fn etl_write_file1024(path i8[64], buf i8[262144], len i32) i32

fn main() i32
  let source i8[131072] = "$source_text"
  let tokens Token[32768]
  let ast AstNode[32768]
  let out i8[262144]
  let n i32 = lex(source, $source_len, tokens, 32768)
  if n < 0
    ret 1
  end
  let an i32 = parse(tokens, n, ast, 32768)
  if an < 0
    ret 2
  end
  if sema(source, tokens, ast, an) < 0
    ret 3
  end
  let emitted i32 = emit_c(source, tokens, ast, an, out, 262144)
  if emitted < 0
    ret 4
  end
  let path i8[64] = "$out_c_path"
  if etl_write_file1024(path, out, emitted) < 0
    ret 5
  end
  ret 0
end
EOF_HARNESS

  # Harness for bytecode emission
  sed '/^fn main()/,$d' compiler1/main.etl > "$harness_bc"
  cat compiler1/lex.etl >> "$harness_bc"
  cat compiler1/parse.etl >> "$harness_bc"
  cat compiler1/backend_defs.etl >> "$harness_bc"
  cat compiler1/emit_bytecode.etl >> "$harness_bc"
  cat >> "$harness_bc" <<EOF_HARNESS2

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
  let path i8[64] = "$out_bc_path"
  if etl_write_file1024(path, out, emitted) < 0
    ret 4
  end
  ret 0
end
EOF_HARNESS2
}

for fixture in "${fixtures[@]}"; do
  src="tests/c1_corpus/$fixture"
  name="${fixture%.etl}"
  c1_c="$td/${name}.c1.c"
  c1_exe="$td/${name}.c1"
  bc_path="$td/${name}.bc"
  harness_c="$td/${name}_c_harness.etl"
  harness_c_exe="$td/${name}_c_harness"
  harness_bc="$td/${name}_bc_harness.etl"
  harness_bc_exe="$td/${name}_bc_harness"

  if [ ! -f "$src" ]; then
    echo "c1_tagged_union_equiv_smoke: FAIL $fixture missing" >&2
    fail=$((fail + 1))
    continue
  fi

  build_c1_harness "$src" "$c1_c" "$bc_path" "$harness_c" "$harness_bc"

  scripts/build_etl.sh "$harness_c" "$harness_c_exe"
  "$harness_c_exe"
  if [ ! -s "$c1_c" ]; then
    echo "c1_tagged_union_equiv_smoke: FAIL $fixture compiler-1 emitted no C" >&2
    fail=$((fail + 1))
    continue
  fi
  cc -std=c11 -Wall -Werror "$c1_c" runtime/etl_runtime.c runtime/etl_string.c runtime/etl_dynarr.c runtime/etl_etlval.c -I runtime -o "$c1_exe"

  scripts/build_etl.sh "$harness_bc" "$harness_bc_exe"
  "$harness_bc_exe"
  if [ ! -s "$bc_path" ]; then
    echo "c1_tagged_union_equiv_smoke: FAIL $fixture bytecode file empty or missing" >&2
    fail=$((fail + 1))
    continue
  fi

  set +e
  "$c1_exe" >/dev/null 2>&1
  c1_status=$?
  "$td/vm_runner" "$bc_path"
  vm_status=$?
  set -e

  if [ "$c1_status" = "$vm_status" ]; then
    echo "c1_tagged_union_equiv_smoke: PASS $fixture (C=$c1_status VM=$vm_status)"
    pass=$((pass + 1))
  else
    echo "c1_tagged_union_equiv_smoke: FAIL $fixture C=$c1_status VM=$vm_status" >&2
    fail=$((fail + 1))
  fi
done

echo "c1_tagged_union_equiv_smoke: $pass passed, $fail failed"
if [ "$fail" -ne 0 ]; then
  exit 1
fi
