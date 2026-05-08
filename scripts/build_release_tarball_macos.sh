#!/usr/bin/env bash
# Build macOS release tarballs for x86_64 and arm64.
#
# Cross-compiles etl-vm-etl for both macOS targets via zig cc.
# No Apple SDK required — zig ships a built-in libc for macOS targets
# sufficient for our binary (no SDL3; core etl-vm-etl only).
#
# Outputs:
#   build/release/etl-macos-x86_64.tar.gz
#   build/release/etl-macos-arm64.tar.gz
#
# Build-validated only: the resulting Mach-O binaries are confirmed via
# magic-byte inspection but NOT executed (host is Linux, no macOS runner).
#
# zig cc macOS target notes:
#   -target x86_64-macos     — macOS 10.13+ x86_64 (zig default SDK version)
#   -target aarch64-macos    — macOS 11+ arm64
#   No -static flag: Mach-O does not support fully static executables the
#   same way ELF does; zig links against macOS system libc dynamically.
#   The binary ships as a standard Mach-O dynamically-linked executable.
#   Warning flags: -Wall/-Wextra are omitted for macOS targets because
#   zig's bundled clang is stricter about parentheses-equality warnings in
#   compiler0-generated C; suppression flags are used instead.

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

cd "$REPO_ROOT"

ZIG="$REPO_ROOT/.deps/zig/zig"
VERSION="v0.1.0-rc1-dev"

ETL_VM_ETL_RUNTIME="runtime/etl_runtime.c runtime/etl_string.c runtime/etl_dynarr.c runtime/etl_etlval.c runtime/vm_bridge.c"

# Helper: detect Mach-O by magic bytes (python3; `file` may not be available on Linux).
# Prints a descriptive string and exits 0 if Mach-O, exits 1 otherwise.
check_macho() {
  local BIN="$1"
  python3 - "$BIN" <<'PYEOF'
import sys

MAGIC_LABELS = {
    bytes([0xfe, 0xed, 0xfa, 0xce]): "Mach-O 32-bit executable (BE)",
    bytes([0xce, 0xfa, 0xed, 0xfe]): "Mach-O 32-bit executable (LE)",
    bytes([0xfe, 0xed, 0xfa, 0xcf]): "Mach-O 64-bit executable (BE)",
    bytes([0xcf, 0xfa, 0xed, 0xfe]): "Mach-O 64-bit executable (LE)",
    bytes([0xca, 0xfe, 0xba, 0xbe]): "Mach-O universal binary (fat, BE)",
    bytes([0xbe, 0xba, 0xfe, 0xca]): "Mach-O universal binary (fat, LE)",
}

path = sys.argv[1]
with open(path, 'rb') as f:
    magic = f.read(4)

label = MAGIC_LABELS.get(magic)
if label:
    print(f"{path}: {label}")
    sys.exit(0)
else:
    print(f"{path}: NOT Mach-O (magic bytes: {magic.hex()})", file=sys.stderr)
    sys.exit(1)
PYEOF
}

# Validate toolchain presence.
if [ ! -x "$ZIG" ]; then
  echo "build_release_tarball_macos: ERROR — zig not found at $ZIG" >&2
  echo "  Run: bash scripts/setup.sh" >&2
  exit 1
fi

echo "build_release_tarball_macos: using zig $("$ZIG" version)"

# Compile vm.etl → C once (shared by both targets).
mkdir -p build
echo "build_release_tarball_macos: compiling vm.etl → C ..."
python3 -m compiler0 compile compiler1/vm.etl -o build/vm_etl_macos.c

build_target() {
  local ZIG_TARGET="$1"   # e.g. x86_64-macos or aarch64-macos
  local LABEL="$2"         # e.g. x86_64 or arm64
  local DIST_NAME="etl-macos-$LABEL"
  local STAGE="build/release/$DIST_NAME"
  local TARBALL="build/release/etl-macos-$LABEL.tar.gz"
  local BIN_OUT="build/etl-vm-etl-macos-$LABEL"

  echo ""
  echo "build_release_tarball_macos: cross-compiling for $ZIG_TARGET ..."

  # zig cc macOS: suppress parentheses-equality warnings from compiler0-generated C.
  # -Wall/-Wextra are omitted because zig's clang is stricter on macOS targets.
  # shellcheck disable=SC2086
  "$ZIG" cc \
    -target "$ZIG_TARGET" \
    -std=c11 \
    -Wno-parentheses \
    -Wno-unused-variable \
    -Wno-unused-parameter \
    -Iruntime \
    -o "$BIN_OUT" \
    build/vm_etl_macos.c \
    $ETL_VM_ETL_RUNTIME

  echo "build_release_tarball_macos: verifying $ZIG_TARGET binary is Mach-O ..."
  check_macho "$BIN_OUT" || {
    echo "build_release_tarball_macos: FAIL — $BIN_OUT is not a Mach-O binary" >&2
    exit 1
  }

  echo "build_release_tarball_macos: staging $DIST_NAME ..."
  rm -rf "$STAGE"
  mkdir -p "$STAGE/bin" "$STAGE/compiler0" "$STAGE/compiler1" "$STAGE/runtime" \
           "$STAGE/docs" "$STAGE/scripts"

  cp "$BIN_OUT" "$STAGE/bin/etl-vm-etl"
  chmod +x "$STAGE/bin/etl-vm-etl"

  # Self-contained launcher.
  cat > "$STAGE/bin/etl" <<'LAUNCHER'
#!/bin/sh
# ETL CLI launcher for the macOS release tarball.
set -eu
_script=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ETL_ROOT=$(CDPATH= cd -- "$_script/.." && pwd)
export ETL_ROOT
if [ -n "${PYTHONPATH:-}" ]; then
  PYTHONPATH="$ETL_ROOT:$PYTHONPATH"
else
  PYTHONPATH="$ETL_ROOT"
fi
export PYTHONPATH
exec "$ETL_ROOT/scripts/etl_cli.sh" "$@"
LAUNCHER
  chmod +x "$STAGE/bin/etl"

  cp scripts/etl_cli.sh   "$STAGE/scripts/etl_cli.sh"
  cp scripts/build_etl.sh "$STAGE/scripts/build_etl.sh"

  cp compiler0/__init__.py "$STAGE/compiler0/__init__.py"
  cp compiler0/__main__.py "$STAGE/compiler0/__main__.py"
  cp compiler0/etl0.py     "$STAGE/compiler0/etl0.py"

  for f in compiler1/*.etl; do cp "$f" "$STAGE/compiler1/"; done
  for f in runtime/*.c runtime/*.h; do cp "$f" "$STAGE/runtime/"; done

  cp docs/SPEC.md           "$STAGE/docs/SPEC.md"
  cp docs/support-matrix.md "$STAGE/docs/support-matrix.md"
  cp README.md              "$STAGE/docs/README.md"

  printf '%s\n' "$VERSION" > "$STAGE/VERSION"

  echo "build_release_tarball_macos: creating $TARBALL ..."
  tar -C build/release \
      --sort=name \
      --owner=0 --group=0 \
      --mtime="2026-01-01 00:00:00" \
      -czf "$TARBALL" \
      "$DIST_NAME"

  echo "build_release_tarball_macos: OK  $TARBALL"
  ls -lh "$TARBALL"
}

build_target "x86_64-macos"  "x86_64"
build_target "aarch64-macos" "arm64"

echo ""
echo "build_release_tarball_macos: both macOS tarballs built successfully (build-validated, no execution)"
