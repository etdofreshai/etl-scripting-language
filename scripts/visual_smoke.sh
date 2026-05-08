#!/usr/bin/env bash
# Deterministic visual example smoke test.
# SDL3 is optional; if present in .deps/sdl3/ the live SDL3 branch runs;
# otherwise that section is skipped gracefully.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

run_case() {
  name="$1"
  src="$repo_root/examples/visual/$name.etl"
  expected_file="$repo_root/examples/visual/$name.expected"
  bin="$tmpdir/$name"

  if [ ! -f "$src" ]; then
    echo "visual_smoke: FAIL $name (missing source)" >&2
    exit 1
  fi
  if [ ! -f "$expected_file" ]; then
    echo "visual_smoke: FAIL $name (missing expected file)" >&2
    exit 1
  fi

  "$repo_root/bin/etl" compile "$src" -o "$bin"

  set +e
  "$bin" >/dev/null 2>&1
  status=$?
  set -e

  expected="$(tr -d '[:space:]' < "$expected_file")"
  if [ "$status" != "$expected" ]; then
    echo "visual_smoke: FAIL $name (expected exit $expected, got $status)" >&2
    exit 1
  fi
}

# 3-run determinism check for tick_demo
check_tick_demo_deterministic() {
  name="tick_demo"
  src="$repo_root/examples/visual/$name.etl"
  expected_file="$repo_root/examples/visual/$name.expected"
  bin="$tmpdir/${name}_det"

  "$repo_root/bin/etl" compile "$src" -o "$bin"

  expected="$(tr -d '[:space:]' < "$expected_file")"

  for run in 1 2 3; do
    set +e
    "$bin" >/dev/null 2>&1
    status=$?
    set -e
    if [ "$status" != "$expected" ]; then
      echo "visual_smoke: FAIL $name determinism run $run (expected exit $expected, got $status)" >&2
      exit 1
    fi
  done

  echo "visual_smoke: tick_demo 3-run determinism ok (exit $expected x3)"
}

run_case tick_demo
check_tick_demo_deterministic
run_case software_pixel
"$repo_root/scripts/scripted_input_smoke.sh"
"$repo_root/scripts/life_golden_smoke.sh"

sdl3_inc="$repo_root/.deps/sdl3/include/SDL3/SDL.h"
sdl3_lib="$repo_root/.deps/sdl3/lib/libSDL3.so"

if [ -f "$sdl3_inc" ] && [ -f "$sdl3_lib" ]; then
  echo "visual_smoke: SDL3 found in .deps/sdl3/, running live SDL3 smoke ..."
  "$repo_root/scripts/sdl3_visual_smoke.sh"
else
  echo "visual_smoke: SKIP sdl3 (.deps/sdl3 not present)"
fi

echo "visual_smoke: ok"
