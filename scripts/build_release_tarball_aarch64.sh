#!/usr/bin/env bash
# Build the Linux aarch64 release tarball.
#
# Cross-compiles etl-vm-etl for aarch64-linux-gnu via zig cc (no sudo, no
# system cross-toolchain required — zig ships a complete aarch64 toolchain).
#
# Output: build/release/etl-linux-aarch64.tar.gz
#
# Contents of the tarball (all under etl-linux-aarch64/):
#   bin/etl              — self-contained CLI launcher (sets ETL_ROOT)
#   bin/etl-vm-etl       — aarch64 ELF, statically linked against musl libc
#   compiler0/           — Python ETL compiler (compiler0 module)
#   compiler1/           — ETL compiler-1 sources (for etl compile/run)
#   runtime/             — C runtime sources (for etl compile/run)
#   scripts/             — bundled etl_cli.sh and build_etl.sh
#   docs/SPEC.md, README.md, docs/support-matrix.md
#   VERSION              — release version string
#
# Requirements at untar+run time (aarch64 host or qemu-aarch64-static):
#   python3, cc (C11, aarch64 native), glibc or musl.
#   The etl-vm-etl binary is statically linked against musl (via zig cc).
#
# Reproducible: tar uses --sort=name --owner=0 --group=0 --mtime.

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

cd "$REPO_ROOT"

ZIG_CC="$REPO_ROOT/.deps/zig/zig"
QEMU="$REPO_ROOT/.deps/qemu-aarch64-static"

VERSION="v0.1.0-rc1-dev"
ARCH="linux-aarch64"
DIST_NAME="etl-$ARCH"
STAGE="build/release/$DIST_NAME"
TARBALL="build/release/etl-$ARCH.tar.gz"

# Validate toolchain presence.
if [ ! -x "$ZIG_CC" ]; then
  echo "build_release_tarball_aarch64: ERROR — zig not found at $ZIG_CC" >&2
  echo "  Run: bash scripts/setup.sh" >&2
  exit 1
fi

echo "release-tarball-aarch64: using zig cc $("$ZIG_CC" version) for aarch64-linux-musl cross-compile"

ETL_VM_ETL_RUNTIME="runtime/etl_runtime.c runtime/etl_string.c runtime/etl_dynarr.c runtime/etl_etlval.c runtime/vm_bridge.c"

echo "release-tarball-aarch64: staging into $STAGE ..."

# Clean and recreate staging directory.
rm -rf "$STAGE"
mkdir -p "$STAGE/bin" "$STAGE/compiler0" "$STAGE/compiler1" "$STAGE/runtime" "$STAGE/docs" "$STAGE/scripts"

# --- bin/etl-vm-etl: cross-compiled aarch64 binary ---
echo "release-tarball-aarch64: cross-compiling etl-vm-etl for aarch64-linux-musl ..."

# First compile vm.etl to C (using native compiler0).
mkdir -p build
python3 -m compiler0 compile compiler1/vm.etl -o build/vm_etl_aarch64.c

# Cross-compile with zig cc targeting aarch64-linux-musl (static, no glibc dep).
# shellcheck disable=SC2086
"$ZIG_CC" cc \
  -target aarch64-linux-musl \
  -std=c11 \
  -Wall -Wextra \
  -Iruntime \
  -o build/etl-vm-etl-aarch64 \
  build/vm_etl_aarch64.c \
  $ETL_VM_ETL_RUNTIME

echo "release-tarball-aarch64: verifying cross-compiled binary is aarch64 ELF ..."
file build/etl-vm-etl-aarch64
# Confirm it's an aarch64 ELF.
file build/etl-vm-etl-aarch64 | grep -q "aarch64\|ARM aarch64" || {
  echo "release-tarball-aarch64: FAIL — binary is not aarch64 ELF" >&2
  exit 1
}

cp build/etl-vm-etl-aarch64 "$STAGE/bin/etl-vm-etl"
chmod +x "$STAGE/bin/etl-vm-etl"

# --- bin/etl: self-contained launcher (same shell script, arch-neutral) ---
cat > "$STAGE/bin/etl" <<'LAUNCHER'
#!/bin/sh
# ETL CLI launcher for the Linux aarch64 release tarball.
# Sets ETL_ROOT and PYTHONPATH relative to this script so compiler0,
# compiler1, and runtime are found without any additional environment setup.

set -eu

# Resolve the root of the unpacked ETL distribution.
_script=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ETL_ROOT=$(CDPATH= cd -- "$_script/.." && pwd)
export ETL_ROOT

# Ensure python3 can find the bundled compiler0 module.
if [ -n "${PYTHONPATH:-}" ]; then
  PYTHONPATH="$ETL_ROOT:$PYTHONPATH"
else
  PYTHONPATH="$ETL_ROOT"
fi
export PYTHONPATH

# Delegate to the bundled CLI implementation.
exec "$ETL_ROOT/scripts/etl_cli.sh" "$@"
LAUNCHER
chmod +x "$STAGE/bin/etl"

# --- scripts/: bundled CLI scripts ---
cp scripts/etl_cli.sh  "$STAGE/scripts/etl_cli.sh"
cp scripts/build_etl.sh "$STAGE/scripts/build_etl.sh"

# --- compiler0 Python module ---
cp compiler0/__init__.py "$STAGE/compiler0/__init__.py"
cp compiler0/__main__.py "$STAGE/compiler0/__main__.py"
cp compiler0/etl0.py    "$STAGE/compiler0/etl0.py"

# --- compiler1 ETL sources (needed for etl check + compile internals) ---
for f in compiler1/*.etl; do
  cp "$f" "$STAGE/compiler1/"
done

# --- runtime C sources (needed for etl compile on aarch64 host) ---
for f in runtime/*.c runtime/*.h; do
  cp "$f" "$STAGE/runtime/"
done

# --- docs ---
cp docs/SPEC.md            "$STAGE/docs/SPEC.md"
cp docs/support-matrix.md  "$STAGE/docs/support-matrix.md"
cp README.md               "$STAGE/docs/README.md"

# --- VERSION ---
printf '%s\n' "$VERSION" > "$STAGE/VERSION"

# --- Tarball ---
echo "release-tarball-aarch64: creating $TARBALL ..."
tar -C build/release \
    --sort=name \
    --owner=0 --group=0 \
    --mtime="2026-01-01 00:00:00" \
    -czf "$TARBALL" \
    "$DIST_NAME"

echo "release-tarball-aarch64: OK  $TARBALL"
ls -lh "$TARBALL"
