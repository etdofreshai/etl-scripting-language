#!/usr/bin/env bash
# Conway's Life golden smoke test — F4.4-phase6-complete.
# Builds life.etl with the software graphics backend, runs it deterministically,
# and byte-compares the output PPM against the committed golden.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

src="$repo_root/examples/visual/life.etl"
golden="$repo_root/examples/visual/life.golden.ppm"
c_path="$tmpdir/life.c"
bin="$tmpdir/life"

if [ ! -f "$src" ]; then
  echo "life-golden: FAIL — missing source $src" >&2
  exit 1
fi

if [ ! -f "$golden" ]; then
  echo "life-golden: FAIL — golden not found at $golden" >&2
  exit 1
fi

echo "life-golden: compiling $src ..."
python3 -m compiler0 compile "$src" -o "$c_path"

echo "life-golden: linking with software graphics backend ..."
cc -std=c11 -Wall -Wextra -Werror \
   "$c_path" \
   "$repo_root/runtime/etl_runtime.c" \
   "$repo_root/runtime/etl_graphics_software.c" \
   -I "$repo_root/runtime" \
   -o "$bin"

mkdir -p "$repo_root/build/graphics"

echo "life-golden: running (run 1) ..."
set +e
"$bin"
status=$?
set -e

if [ "$status" -ne 0 ]; then
  echo "life-golden: FAIL (binary exited $status)" >&2
  exit 1
fi

actual_ppm="$repo_root/build/graphics/life.ppm"
if [ ! -f "$actual_ppm" ]; then
  echo "life-golden: FAIL — output PPM not found at $actual_ppm" >&2
  exit 1
fi

echo "life-golden: comparing against golden ..."
if ! cmp -s "$actual_ppm" "$golden"; then
  diff_bytes=$(cmp -l "$actual_ppm" "$golden" 2>/dev/null | wc -l || echo "?")
  echo "life-golden: FAIL — output PPM differs from golden by $diff_bytes byte positions" >&2
  exit 1
fi

echo "life-golden: run 1 matches golden"

echo "life-golden: running (run 2, determinism check) ..."
"$bin"
if ! cmp -s "$actual_ppm" "$golden"; then
  echo "life-golden: FAIL — run 2 differs from golden (non-deterministic)" >&2
  exit 1
fi

echo "life-golden: PASS (Life golden matches, deterministic across 2 runs)"
