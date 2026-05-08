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
# M5: wasmtime
# Pinned release: v36.0.9 (bytecodealliance/wasmtime)
# Linux x86_64 tarball fetched from GitHub releases.
# Binary extracted to .deps/wasmtime (single executable, no sudo required).
# ---------------------------------------------------------------------------
WASMTIME_VERSION="v36.0.9"
WASMTIME_TARBALL="wasmtime-${WASMTIME_VERSION}-x86_64-linux.tar.xz"
WASMTIME_URL="https://github.com/bytecodealliance/wasmtime/releases/download/${WASMTIME_VERSION}/${WASMTIME_TARBALL}"
WASMTIME_DEST="$REPO_ROOT/.deps/wasmtime"

fetch_wasmtime() {
  if [ -f "$WASMTIME_DEST" ] && [ -x "$WASMTIME_DEST" ]; then
    status "wasmtime: already present at $WASMTIME_DEST — skipped"
    "$WASMTIME_DEST" --version
    return
  fi

  status "wasmtime: fetching ${WASMTIME_VERSION} ..."
  mkdir -p "$REPO_ROOT/.deps"
  local tarball="$REPO_ROOT/.deps/${WASMTIME_TARBALL}"
  if [ ! -f "$tarball" ]; then
    curl -fL "$WASMTIME_URL" -o "$tarball"
  fi

  status "wasmtime: extracting binary ..."
  # The tarball contains wasmtime-v*/wasmtime; extract that single file.
  local strip_dir
  strip_dir="$(tar -tJf "$tarball" 2>/dev/null | awk 'NR==1{print $1;exit}' | cut -d/ -f1)"
  tar -xJf "$tarball" -C "$REPO_ROOT/.deps" "${strip_dir}/wasmtime"
  mv "$REPO_ROOT/.deps/${strip_dir}/wasmtime" "$WASMTIME_DEST"
  rmdir "$REPO_ROOT/.deps/${strip_dir}" 2>/dev/null || true
  chmod +x "$WASMTIME_DEST"

  status "wasmtime: installed — verifying ..."
  "$WASMTIME_DEST" --version
  status "wasmtime: ok"
}

# ---------------------------------------------------------------------------
# M5: wat2wasm (from WABT)
# Pinned release: 1.0.41 (WebAssembly/wabt)
# Linux x64 tarball fetched from GitHub releases.
# Binary extracted to .deps/wat2wasm (single executable, no sudo required).
# ---------------------------------------------------------------------------
WABT_VERSION="1.0.41"
WABT_TARBALL="wabt-${WABT_VERSION}-linux-x64.tar.gz"
WABT_URL="https://github.com/WebAssembly/wabt/releases/download/${WABT_VERSION}/${WABT_TARBALL}"
WAT2WASM_DEST="$REPO_ROOT/.deps/wat2wasm"

fetch_wat2wasm() {
  if [ -f "$WAT2WASM_DEST" ] && [ -x "$WAT2WASM_DEST" ]; then
    status "wat2wasm: already present at $WAT2WASM_DEST — skipped"
    "$WAT2WASM_DEST" --version
    return
  fi

  status "wat2wasm: fetching WABT ${WABT_VERSION} ..."
  mkdir -p "$REPO_ROOT/.deps"
  local tarball="$REPO_ROOT/.deps/${WABT_TARBALL}"
  if [ ! -f "$tarball" ]; then
    curl -fL "$WABT_URL" -o "$tarball"
  fi

  status "wat2wasm: extracting binary ..."
  # The tarball contains wabt-*/bin/wat2wasm; extract that single file.
  local strip_dir
  strip_dir="$(tar -tzf "$tarball" 2>/dev/null | awk 'NR==1{print $1;exit}' | cut -d/ -f1)"
  tar -xzf "$tarball" -C "$REPO_ROOT/.deps" "${strip_dir}/bin/wat2wasm"
  mv "$REPO_ROOT/.deps/${strip_dir}/bin/wat2wasm" "$WAT2WASM_DEST"
  rm -rf "$REPO_ROOT/.deps/${strip_dir}" 2>/dev/null || true
  chmod +x "$WAT2WASM_DEST"

  status "wat2wasm: installed — verifying ..."
  "$WAT2WASM_DEST" --version
  status "wat2wasm: ok"
}

# ---------------------------------------------------------------------------
# M6: qemu-aarch64-static
# Pinned release: v7.2.0-1 (multiarch/qemu-user-static on GitHub)
# Single pre-built static binary for x86_64 Linux hosts.
# Fetched directly (no apt/sudo required).
# Destination: .deps/qemu-aarch64-static
#
# Recovery path if fetch fails:
#   1. Check https://github.com/multiarch/qemu-user-static/releases for a
#      newer tag and update QEMU_VERSION below.
#   2. Alternatively: apt-get install qemu-user-static (requires sudo) and
#      copy /usr/bin/qemu-aarch64-static to .deps/qemu-aarch64-static.
#   3. Or build from source: https://www.qemu.org/download/#source
# ---------------------------------------------------------------------------
QEMU_VERSION="v7.2.0-1"
QEMU_BINARY_URL="https://github.com/multiarch/qemu-user-static/releases/download/${QEMU_VERSION}/qemu-aarch64-static"
QEMU_DEST="$REPO_ROOT/.deps/qemu-aarch64-static"

fetch_qemu_aarch64() {
  if [ -f "$QEMU_DEST" ] && [ -x "$QEMU_DEST" ]; then
    status "qemu-aarch64-static: already present at $QEMU_DEST — skipped"
    return
  fi

  status "qemu-aarch64-static: fetching pinned ${QEMU_VERSION} ..."
  mkdir -p "$REPO_ROOT/.deps"

  if ! curl -fL "$QEMU_BINARY_URL" -o "$QEMU_DEST"; then
    printf '[setup] ERROR: failed to fetch qemu-aarch64-static from %s\n' "$QEMU_BINARY_URL" >&2
    printf '[setup] Recovery options:\n' >&2
    printf '[setup]   1. Check https://github.com/multiarch/qemu-user-static/releases for updated tag\n' >&2
    printf '[setup]      and update QEMU_VERSION in scripts/setup.sh\n' >&2
    printf '[setup]   2. sudo apt-get install qemu-user-static && cp /usr/bin/qemu-aarch64-static .deps/\n' >&2
    rm -f "$QEMU_DEST"
    exit 1
  fi

  chmod +x "$QEMU_DEST"
  status "qemu-aarch64-static: installed at $QEMU_DEST"
  # Minimal verify: print version (--version exits 0 for qemu-user-static).
  "$QEMU_DEST" --version | head -1 || true
  status "qemu-aarch64-static: ok"
}

# ---------------------------------------------------------------------------
# M6: zig cross-compilation toolchain
# Pinned release: 0.14.1 (ziglang.org)
# Linux x86_64 tarball. Extracted to .deps/zig/.
# Use: .deps/zig/zig cc -target aarch64-linux-gnu [sources]
#
# zig is a single binary that includes a complete cross-compile toolchain
# for aarch64-linux-gnu without any additional system packages.
# ---------------------------------------------------------------------------
ZIG_VERSION="0.14.1"
ZIG_TARBALL="zig-x86_64-linux-${ZIG_VERSION}.tar.xz"
ZIG_URL="https://ziglang.org/download/${ZIG_VERSION}/${ZIG_TARBALL}"
ZIG_DEST_DIR="$REPO_ROOT/.deps/zig"
ZIG_BINARY="$ZIG_DEST_DIR/zig"

fetch_zig() {
  if [ -f "$ZIG_BINARY" ] && [ -x "$ZIG_BINARY" ]; then
    status "zig: already present at $ZIG_BINARY — skipped"
    "$ZIG_BINARY" version
    return
  fi

  status "zig: fetching ${ZIG_VERSION} ..."
  mkdir -p "$REPO_ROOT/.deps"
  local tarball="$REPO_ROOT/.deps/${ZIG_TARBALL}"
  if [ ! -f "$tarball" ]; then
    curl -fL "$ZIG_URL" -o "$tarball"
  fi

  status "zig: extracting to $ZIG_DEST_DIR ..."
  # The tarball unpacks into zig-x86_64-linux-0.14.1/
  local strip_dir="zig-x86_64-linux-${ZIG_VERSION}"
  rm -rf "$ZIG_DEST_DIR"
  mkdir -p "$ZIG_DEST_DIR"
  tar -xJf "$tarball" -C "$REPO_ROOT/.deps"
  # Move extracted directory to .deps/zig/
  mv "$REPO_ROOT/.deps/${strip_dir}"/* "$ZIG_DEST_DIR/"
  rmdir "$REPO_ROOT/.deps/${strip_dir}" 2>/dev/null || true

  status "zig: installed — verifying ..."
  "$ZIG_BINARY" version
  status "zig: ok"
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
  fetch_qemu_aarch64
  fetch_zig
  fetch_headless_chrome
  status "=== ETL L5 setup complete ==="
}

main "$@"
