#!/usr/bin/env bash
# scripts/setup.sh — ETL L5 mission bootstrap
# Idempotent: safe to re-run at any time.
# Creates ./bin/ and stubs fetch functions for future milestones.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$REPO_ROOT/bin"

# ---------------------------------------------------------------------------
# Utility
# ---------------------------------------------------------------------------
status() { printf '[setup] %s\n' "$*"; }

# ---------------------------------------------------------------------------
# bin/ directory
# ---------------------------------------------------------------------------
setup_bin() {
  if [ ! -d "$BIN_DIR" ]; then
    mkdir -p "$BIN_DIR"
    status "bin/: created $BIN_DIR"
  else
    status "bin/: already exists — skipped"
  fi
}

# ---------------------------------------------------------------------------
# M4: SDL3
# Pinned release: release-3.4.8
# Source tarball fetched from github.com/libsdl-org/SDL/releases
# Built with cmake into .deps/sdl3/ (no system install, no sudo).
#
# Layout after build:
#   .deps/sdl3/include/SDL3/SDL.h   — public headers
#   .deps/sdl3/lib/libSDL3.so       — shared library (or libSDL3.a)
#
# To link against SDL3 from make or cc:
#   cc -I.deps/sdl3/include foo.c -L.deps/sdl3/lib -lSDL3 -Wl,-rpath,$(pwd)/.deps/sdl3/lib
# Or set LD_LIBRARY_PATH=<repo>/.deps/sdl3/lib before running a binary.
# ---------------------------------------------------------------------------
SDL3_TAG="release-3.4.8"
SDL3_VERSION="3.4.8"
SDL3_TARBALL_URL="https://github.com/libsdl-org/SDL/releases/download/${SDL3_TAG}/SDL3-${SDL3_VERSION}.tar.gz"
SDL3_SRC_DIR="$REPO_ROOT/.deps/sdl3-src"
SDL3_PREFIX="$REPO_ROOT/.deps/sdl3"
SDL3_SENTINEL="$SDL3_PREFIX/include/SDL3/SDL.h"

fetch_sdl3() {
  # Fast idempotency check: if the sentinel header exists, skip everything.
  if [ -f "$SDL3_SENTINEL" ]; then
    status "SDL3: already built at $SDL3_PREFIX — skipped"
    return
  fi

  # Verify cmake is available.
  if ! command -v cmake &>/dev/null; then
    printf '[setup] ERROR: cmake not found. Install cmake (e.g. sudo apt install cmake) and re-run.\n' >&2
    exit 1
  fi

  status "SDL3: fetching source tarball (pinned $SDL3_TAG) ..."
  mkdir -p "$SDL3_SRC_DIR"

  local tarball="$REPO_ROOT/.deps/SDL3-${SDL3_VERSION}.tar.gz"
  if [ ! -f "$tarball" ]; then
    curl -fL "$SDL3_TARBALL_URL" -o "$tarball"
  fi

  status "SDL3: extracting ..."
  tar -xzf "$tarball" -C "$SDL3_SRC_DIR" --strip-components=1

  status "SDL3: configuring with cmake ..."
  local build_dir="$REPO_ROOT/.deps/sdl3-build"
  mkdir -p "$build_dir"
  cmake -S "$SDL3_SRC_DIR" -B "$build_dir" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$SDL3_PREFIX" \
    -DSDL_SHARED=ON \
    -DSDL_STATIC=ON \
    -DSDL_TEST=OFF \
    -DSDL_TESTS=OFF \
    -DSDL_EXAMPLES=OFF

  status "SDL3: building (this may take 5-15 minutes) ..."
  cmake --build "$build_dir" --config Release -- -j"$(nproc)"

  status "SDL3: installing to $SDL3_PREFIX ..."
  cmake --install "$build_dir"

  status "SDL3: build complete — $SDL3_PREFIX"
  status "SDL3: to use SDL3 binaries at runtime, set:"
  status "        export LD_LIBRARY_PATH=$SDL3_PREFIX/lib:\$LD_LIBRARY_PATH"
  status "      or link with -Wl,-rpath,$SDL3_PREFIX/lib"
}

# ---------------------------------------------------------------------------
# M4: SDL3 verification
# Compile and link a minimal program that calls SDL_GetVersion().
# A successful compile+link is sufficient (SDL_Init with video will fail
# in a headless environment, but that is expected).
# ---------------------------------------------------------------------------
verify_sdl3() {
  local test_c="$REPO_ROOT/.deps/sdl3_check.c"
  cat >"$test_c" <<'EOF'
#include <SDL3/SDL.h>
#include <stdio.h>
int main(void) {
    int ver = SDL_GetVersion();
    printf("SDL3 version: %d.%d.%d\n",
           SDL_VERSIONNUM_MAJOR(ver),
           SDL_VERSIONNUM_MINOR(ver),
           SDL_VERSIONNUM_MICRO(ver));
    return 0;
}
EOF
  status "SDL3 verify: compiling test program ..."
  cc -I"$SDL3_PREFIX/include" \
     "$test_c" \
     -L"$SDL3_PREFIX/lib" \
     -lSDL3 \
     -Wl,-rpath,"$SDL3_PREFIX/lib" \
     -o /tmp/etl_sdl3_check
  status "SDL3 verify: running /tmp/etl_sdl3_check ..."
  /tmp/etl_sdl3_check
  status "SDL3 verify: passed"
}

# ---------------------------------------------------------------------------
# M5: wasmtime + wat2wasm (not yet implemented)
# ---------------------------------------------------------------------------
fetch_wasmtime() {
  # TODO (M5): download wasmtime binary into bin/wasmtime
  status "wasmtime: not yet implemented (M5)"
}

fetch_wat2wasm() {
  # TODO (M5): download wat2wasm binary into bin/wat2wasm
  status "wat2wasm: not yet implemented (M5)"
}

# ---------------------------------------------------------------------------
# M6: qemu-aarch64-static (not yet implemented)
# ---------------------------------------------------------------------------
fetch_qemu() {
  # TODO (M6): download qemu-aarch64-static into bin/qemu-aarch64-static
  status "qemu-aarch64-static: not yet implemented (M6)"
}

# ---------------------------------------------------------------------------
# M6: headless Chrome / Playwright (not yet implemented)
# ---------------------------------------------------------------------------
fetch_headless_chrome() {
  # TODO (M6): install headless Chrome + Playwright into bin/chrome/
  status "headless Chrome / Playwright: not yet implemented (M6)"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  status "=== ETL L5 setup start ==="
  setup_bin
  fetch_sdl3
  verify_sdl3
  fetch_wasmtime
  fetch_wat2wasm
  fetch_qemu
  fetch_headless_chrome
  status "=== ETL L5 setup complete ==="
}

main "$@"
