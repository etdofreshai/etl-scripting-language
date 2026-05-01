#!/usr/bin/env bash
# SDL3 headless graphics smoke test.
# Detects SDL3 via pkg-config. If unavailable, prints a skip notice and exits 0.
# If available, compiles examples/graphics/pixel_fill.etl through compiler-0,
# links with SDL3, runs headlessly, writes a PPM artifact, and validates pixels.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# --- SDL3 detection ---
if ! pkg-config --exists sdl3 2>/dev/null; then
  echo "sdl3-headless: SKIP (SDL3 not found via pkg-config)"
  echo "  To enable: install SDL3 development headers and libraries."
  echo "  See docs/graphics.md for setup instructions."
  exit 0
fi

echo "sdl3-headless: SDL3 $(pkg-config --modversion sdl3) detected"

# --- Build ---
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

mkdir -p "$repo_root/build/graphics"

src="$repo_root/examples/graphics/pixel_fill.etl"
c_path="$tmpdir/pixel_fill.c"
bin="$tmpdir/pixel_fill"

echo "sdl3-headless: compiling pixel_fill.etl ..."
python3 -m compiler0 compile "$src" -o "$c_path"

sdl3_cflags="$(pkg-config --cflags sdl3)"
sdl3_libs="$(pkg-config --libs sdl3)"

echo "sdl3-headless: linking with SDL3 ..."
cc -Wall -Werror $sdl3_cflags "$c_path" \
   "$repo_root/runtime/etl_runtime.c" \
   "$repo_root/runtime/etl_graphics_sdl3.c" \
   -I "$repo_root/runtime" \
   $sdl3_libs \
   -o "$bin"

# --- Run ---
echo "sdl3-headless: running pixel_fill ..."
stdout_file="$tmpdir/stdout"
set +e
"$bin" > "$stdout_file" 2>&1
status=$?
set -e

if [ "$status" -ne 0 ]; then
  echo "sdl3-headless: FAIL (exit $status)" >&2
  cat "$stdout_file" >&2
  exit 1
fi

# --- Validate pixel value ---
# etl_gfx_get_pixel(4,4) on a green pixel (0,255,0) => 0x00FF00 = 65280
pixel=$(head -1 "$stdout_file")
if [ "$pixel" -ne 65280 ]; then
  echo "sdl3-headless: FAIL (expected pixel 65280, got $pixel)" >&2
  exit 1
fi

# --- Validate PPM artifact ---
ppm="$repo_root/build/graphics/pixel_fill.ppm"
if [ ! -f "$ppm" ]; then
  echo "sdl3-headless: FAIL (PPM artifact not found at $ppm)" >&2
  exit 1
fi

# Validate PPM header
if ! head -1 "$ppm" | grep -q '^P6$'; then
  echo "sdl3-headless: FAIL (invalid PPM header)" >&2
  exit 1
fi

echo "sdl3-headless: PASS (pixel_fill rendered 8x8 PPM, green center verified)"
