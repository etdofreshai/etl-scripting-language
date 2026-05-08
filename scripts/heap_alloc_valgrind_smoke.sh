#!/usr/bin/env bash
# Verify heap_alloc_basic.etl produces a valgrind-clean binary via the C backend.
# Requires: valgrind on PATH; install with: sudo apt-get install -y valgrind
set -euo pipefail

if ! command -v valgrind >/dev/null 2>&1; then
  echo "heap_alloc_valgrind_smoke: SKIP valgrind not found (install with: sudo apt-get install -y valgrind)"
  exit 0
fi

td="$(mktemp -d)"
trap 'rm -rf "$td"' EXIT

fixture="tests/c1_corpus/heap_alloc_basic.etl"
c0_c="$td/heap_alloc_basic.c"
c0_exe="$td/heap_alloc_basic"

# Compile fixture via compiler0 → C → gcc
python3 -m compiler0 compile "$fixture" -o "$c0_c"
cc -std=c11 -Wall -Werror -g "$c0_c" runtime/etl_runtime.c -I runtime -o "$c0_exe"

echo "heap_alloc_valgrind_smoke: running valgrind on $c0_exe"
valgrind --error-exitcode=1 --leak-check=full --errors-for-leak-kinds=all "$c0_exe"
valgrind_exit=$?

if [ "$valgrind_exit" -ne 0 ]; then
  echo "heap_alloc_valgrind_smoke: FAIL valgrind reported errors (exit $valgrind_exit)"
  exit 1
fi

echo "heap_alloc_valgrind_smoke: PASS zero leaks and zero errors"
