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
# M4: SDL3 (not yet implemented)
# ---------------------------------------------------------------------------
fetch_sdl3() {
  # TODO (M4): download & unpack SDL3 prebuilt into bin/sdl3/
  status "SDL3: not yet implemented (M4)"
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
  fetch_wasmtime
  fetch_wat2wasm
  fetch_qemu
  fetch_headless_chrome
  status "=== ETL L5 setup complete ==="
}

main "$@"
