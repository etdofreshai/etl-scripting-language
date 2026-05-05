#!/usr/bin/env bash
# Deterministic visual example smoke test.
# SDL3 is optional; default success path uses only the CLI and c0/C backend.
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

run_case tick_demo
run_case software_pixel

if pkg-config --exists sdl3 2>/dev/null || [ -f /usr/include/SDL3/SDL.h ]; then
  echo "visual_smoke: SDL3 installed (optional SDL3 branch covered by graphics-headless)"
else
  echo "visual_smoke: SKIP sdl3 (SDL3 not installed)"
fi

echo "visual_smoke: ok"
