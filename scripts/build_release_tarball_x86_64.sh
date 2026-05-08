#!/usr/bin/env bash
# Build the Linux x86_64 release tarball.
#
# Output: build/release/etl-linux-x86_64.tar.gz
#
# Contents of the tarball (all under etl-linux-x86_64/):
#   bin/etl              — self-contained CLI launcher (sets ETL_ROOT)
#   bin/etl-vm-etl       — pre-built ETL VM binary (only needs glibc)
#   compiler0/           — Python ETL compiler (compiler0 module)
#   compiler1/           — ETL compiler-1 sources (for etl compile/run)
#   runtime/             — C runtime sources (for etl compile/run)
#   scripts/             — bundled etl_cli.sh and build_etl.sh
#   docs/SPEC.md, README.md, docs/support-matrix.md
#   VERSION              — release version string
#
# Requirements at untar+run time: python3, cc (C11), glibc.
# The etl-vm-etl binary is statically linked against only glibc.
#
# Reproducible: tar uses --sort=name --owner=0 --group=0 --mtime.

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

cd "$REPO_ROOT"

VERSION="v0.1.0-rc1-dev"
ARCH="linux-x86_64"
DIST_NAME="etl-$ARCH"
STAGE="build/release/$DIST_NAME"
TARBALL="build/release/etl-$ARCH.tar.gz"

echo "release-tarball: staging into $STAGE ..."

# Clean and recreate staging directory.
rm -rf "$STAGE"
mkdir -p "$STAGE/bin" "$STAGE/compiler0" "$STAGE/compiler1" "$STAGE/runtime" "$STAGE/docs" "$STAGE/scripts"

# --- bin/etl-vm-etl: pre-built binary (only glibc dep) ---
if [ ! -x bin/etl-vm-etl ]; then
  echo "release-tarball: building bin/etl-vm-etl ..." >&2
  make bin/etl-vm-etl
fi
cp bin/etl-vm-etl "$STAGE/bin/etl-vm-etl"

# --- bin/etl: self-contained launcher ---
# The launcher sets ETL_ROOT and PYTHONPATH so:
#   - etl_cli.sh resolves REPO_ROOT to the untar'd tree via script location.
#   - python3 -m compiler0 finds the bundled compiler0 Python module.
cat > "$STAGE/bin/etl" <<'LAUNCHER'
#!/bin/sh
# ETL CLI launcher for the Linux x86_64 release tarball.
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

# --- runtime C sources (needed for etl compile) ---
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
echo "release-tarball: creating $TARBALL ..."
tar -C build/release \
    --sort=name \
    --owner=0 --group=0 \
    --mtime="2026-01-01 00:00:00" \
    -czf "$TARBALL" \
    "$DIST_NAME"

echo "release-tarball: OK  $TARBALL"
ls -lh "$TARBALL"
