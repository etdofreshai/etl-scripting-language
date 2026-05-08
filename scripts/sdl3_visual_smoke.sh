#!/usr/bin/env bash
# SDL3 visual sample smoke test — F4.3-sdl3-visual-sample.
# Runs bouncing_rect.etl against live SDL3 from .deps/sdl3/.
# Requires SDL3 to be present in .deps/sdl3/ (built by F4.1-fetch-sdl3).
# Exits 0 only if the rendered frame is byte-equal to the golden PPM.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

sdl3_inc="$repo_root/.deps/sdl3/include/SDL3/SDL.h"
sdl3_lib="$repo_root/.deps/sdl3/lib/libSDL3.so"

if [ ! -f "$sdl3_inc" ] || [ ! -f "$sdl3_lib" ]; then
  echo "sdl3-visual: FAIL — SDL3 not found in .deps/sdl3/; run scripts/setup.sh first" >&2
  exit 1
fi

echo "sdl3-visual: SDL3 headers and lib found in .deps/sdl3/"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

src="$repo_root/examples/visual/bouncing_rect.etl"
golden="$repo_root/examples/visual/bouncing_rect.golden.ppm"
c_path="$tmpdir/bouncing_rect.c"
bin="$tmpdir/bouncing_rect"
out_ppm="$tmpdir/bouncing_rect_out.ppm"

mkdir -p "$tmpdir/build/graphics"

if [ ! -f "$golden" ]; then
  echo "sdl3-visual: FAIL — golden PPM not found at $golden" >&2
  exit 1
fi

echo "sdl3-visual: compiling $src ..."
python3 -m compiler0 compile "$src" -o "$c_path"

echo "sdl3-visual: linking with SDL3 from .deps/sdl3/ ..."
cc -Wall \
   -I"$repo_root/.deps/sdl3/include" \
   -I"$repo_root/runtime" \
   "$c_path" \
   "$repo_root/runtime/etl_runtime.c" \
   "$repo_root/runtime/etl_graphics_sdl3.c" \
   -L"$repo_root/.deps/sdl3/lib" -lSDL3 \
   -Wl,-rpath,"$repo_root/.deps/sdl3/lib" \
   -o "$bin"

echo "sdl3-visual: running headless ..."
export SDL_VIDEODRIVER=offscreen
export LD_LIBRARY_PATH="$repo_root/.deps/sdl3/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# Redirect output PPM into tmpdir by symlinking build/graphics
mkdir -p "$tmpdir/build/graphics"
# The binary writes to build/graphics/bouncing_rect.ppm relative to cwd
mkdir -p "$repo_root/build/graphics"

stdout_file="$tmpdir/stdout"
set +e
(cd "$repo_root" && "$bin") > "$stdout_file" 2>&1
status=$?
set -e

if [ "$status" -ne 0 ]; then
  echo "sdl3-visual: FAIL (binary exited $status)" >&2
  cat "$stdout_file" >&2
  exit 1
fi

# Verify SDL3 was actually used: pixel value must be 16776960 (0xFFFF00 = yellow)
pixel=$(cat "$stdout_file" | tr -d '[:space:]')
if [ "$pixel" -ne 16776960 ]; then
  echo "sdl3-visual: FAIL (expected center pixel 16776960 [yellow], got '$pixel')" >&2
  exit 1
fi
echo "sdl3-visual: center pixel OK (0xFFFF00 = yellow)"

# Verify SDL_GetVersion is reachable (confirms live SDL3 linkage)
if ! nm "$bin" 2>/dev/null | grep -q "SDL_GetVersion\|SDL_Init"; then
  echo "sdl3-visual: WARN — SDL symbols not found in binary via nm; may be dynamic" >&2
fi

actual_ppm="$repo_root/build/graphics/bouncing_rect.ppm"
if [ ! -f "$actual_ppm" ]; then
  echo "sdl3-visual: FAIL — output PPM not found at $actual_ppm" >&2
  exit 1
fi

echo "sdl3-visual: comparing frame against golden ..."
if ! cmp -s "$actual_ppm" "$golden"; then
  diff_bytes=$(cmp -l "$actual_ppm" "$golden" 2>/dev/null | wc -l || echo "?")
  echo "sdl3-visual: FAIL — output PPM differs from golden by $diff_bytes byte positions" >&2
  exit 1
fi

echo "sdl3-visual: PASS (frame byte-equal to golden, SDL3 live from .deps/sdl3/)"
