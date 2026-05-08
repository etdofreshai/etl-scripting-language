#!/usr/bin/env bash
# cli_config_rules_smoke.sh — smoke test for the config_rules CLI example.
#
# Builds examples/cli/config_rules.etl (the host) with the full runtime
# (etl_host + etl_vm + etl_host_etl_api), assembles the bytecode compiler
# pipeline, runs the host against examples/cli/config_rules.input using
# examples/cli/config_rules.rules.etl as the rule, and diffs the output
# against examples/cli/config_rules.expected.
#
# Requires ETL_VM_ETL to be set (or defaults to bin/etl-vm-etl) so that
# the rule compilation goes through the runtime VM path.
#
# Gates VAL-CLI-003 (F3.3-rule-engine).
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

rule_file="examples/cli/config_rules.rules.etl"
input_file="examples/cli/config_rules.input"
expected_file="examples/cli/config_rules.expected"

for f in "$rule_file" "$input_file" "$expected_file"; do
  if [ ! -f "$f" ]; then
    echo "cli_config_rules_smoke: FAIL - missing $f" >&2
    exit 1
  fi
done

build_dir="$(mktemp -d)"
trap 'rm -rf "$build_dir"' EXIT

# ---------------------------------------------------------------------------
# Stage 1: build the bytecode driver pipeline (same as c1_runtime_compile_smoke).
# ---------------------------------------------------------------------------
echo "cli_config_rules_smoke: building bytecode driver"
bcd_src="$build_dir/c1_bytecode_pipeline.etl"
sed '/^fn main()/,$d' compiler1/main.etl >  "$bcd_src"
cat compiler1/lex.etl                    >> "$bcd_src"
cat compiler1/parse.etl                  >> "$bcd_src"
cat compiler1/sema.etl                   >> "$bcd_src"
cat compiler1/backend_defs.etl           >> "$bcd_src"
cat compiler1/emit_bytecode.etl          >> "$bcd_src"
cat compiler1/bytecode_driver.etl        >> "$bcd_src"
scripts/build_etl.sh "$bcd_src" "$build_dir/etl_bytecode_driver"

# ---------------------------------------------------------------------------
# Stage 2: compile config_rules.etl via the C backend, then link with the
# full host runtime (etl_host + etl_vm + etl_host_etl_api + etl_runtime + etc.)
# ---------------------------------------------------------------------------
echo "cli_config_rules_smoke: compiling config_rules host"
python3 -m compiler0 compile examples/cli/config_rules.etl \
    -o "$build_dir/config_rules.c"

cc -std=c11 -Wall -Wextra -Werror \
   "$build_dir/config_rules.c" \
   runtime/etl_host.c \
   runtime/etl_host_etl_api.c \
   runtime/etl_vm.c \
   runtime/etl_string.c \
   runtime/etl_dynarr.c \
   runtime/etl_etlval.c \
   runtime/etl_runtime.c \
   runtime/vm_bridge.c \
   -I runtime \
   -o "$build_dir/config_rules"

# ---------------------------------------------------------------------------
# Stage 3: run the host with the rule file and input, capture output.
# ETL_VM_ETL must be set so the rule goes through the runtime VM path;
# the [etl_host] log line on stderr confirms this.
# ---------------------------------------------------------------------------
etl_vm="${ETL_VM_ETL:-bin/etl-vm-etl}"
if [ ! -x "$etl_vm" ]; then
  echo "cli_config_rules_smoke: FAIL - ETL VM not found at $etl_vm" >&2
  exit 1
fi

echo "cli_config_rules_smoke: running rule engine (ETL_VM_ETL=$etl_vm)"
actual="$build_dir/config_rules.out"
ETL_BYTECODE_DRIVER="$build_dir/etl_bytecode_driver" \
ETL_VM_ETL="$etl_vm" \
"$build_dir/config_rules" "$rule_file" "$input_file" \
    >"$actual" 2>"$build_dir/stderr.log"
rc=$?
if [ "$rc" -ne 0 ]; then
  echo "cli_config_rules_smoke: FAIL - host exited $rc" >&2
  cat "$build_dir/stderr.log" >&2
  exit 1
fi

# Verify the VM path was actually used (etl_host.c logs to stderr).
if ! grep -q '\[etl_host\] using ETL VM' "$build_dir/stderr.log"; then
  echo "cli_config_rules_smoke: FAIL - no [etl_host] VM log in stderr; ETL_VM_ETL path not taken" >&2
  cat "$build_dir/stderr.log" >&2
  exit 1
fi
echo "cli_config_rules_smoke: confirmed ETL VM path used ($(grep -c '\[etl_host\]' "$build_dir/stderr.log") calls)"

# ---------------------------------------------------------------------------
# Stage 4: diff output against expected.
# ---------------------------------------------------------------------------
echo "cli_config_rules_smoke: diffing output against expected"
if ! diff -u "$expected_file" "$actual"; then
  echo "cli_config_rules_smoke: FAIL - output does not match expected" >&2
  exit 1
fi

echo "cli_config_rules_smoke: ok"
