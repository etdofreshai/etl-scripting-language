#!/usr/bin/env bash
# Validate the macOS release tarballs (build-validated only; no execution).
#
# For each macOS architecture (x86_64, arm64):
#   1. Verify the tarball exists.
#   2. Untar to a temp dir.
#   3. Check magic bytes of bin/etl-vm-etl and assert "Mach-O" appears.
#   4. Do NOT execute the binary (host is Linux).
#
# Note: `file` may not be installed on the Linux CI host; we use python3
# to inspect the 4-byte Mach-O magic header directly.
#
# Exits 0 if both tarballs validate as Mach-O, non-zero otherwise.

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

cd "$REPO_ROOT"

# Check Mach-O magic bytes via python3.
# Prints a descriptive label and exits 0 if Mach-O; exits 1 otherwise.
py_check_macho() {
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

pass=0
fail=0

validate_target() {
  local LABEL="$1"
  local TARBALL="build/release/etl-macos-$LABEL.tar.gz"
  local DIST_NAME="etl-macos-$LABEL"

  echo "release_validate_macos: checking $TARBALL ..."

  # 1. Verify tarball exists.
  if [ ! -f "$TARBALL" ]; then
    echo "  [FAIL] $TARBALL not found" >&2
    fail=$((fail + 1))
    return
  fi
  echo "  tarball: OK ($(ls -lh "$TARBALL" | awk '{print $5}'))"

  # 2. Untar to temp dir.
  local td
  td=$(mktemp -d)
  tar -xzf "$TARBALL" -C "$td"

  local BIN="$td/$DIST_NAME/bin/etl-vm-etl"
  if [ ! -f "$BIN" ]; then
    echo "  [FAIL] bin/etl-vm-etl not found inside tarball" >&2
    fail=$((fail + 1))
    rm -rf "$td"
    return
  fi

  # 3. Check magic bytes (Mach-O detection via python3).
  local MAGIC_OUT
  if MAGIC_OUT=$(py_check_macho "$BIN" 2>&1); then
    echo "  magic: $MAGIC_OUT"
    echo "  [PASS] $LABEL — Mach-O confirmed"
    pass=$((pass + 1))
  else
    echo "  [FAIL] $LABEL — $MAGIC_OUT" >&2
    fail=$((fail + 1))
  fi

  rm -rf "$td"
}

validate_target "x86_64"
validate_target "arm64"

echo ""
echo "release_validate_macos: $pass/2 passed, $fail failed"

if [ "$fail" -gt 0 ]; then
  echo "release_validate_macos: FAIL" >&2
  exit 1
fi

echo "release_validate_macos: OK — both macOS Mach-O tarballs validated (build-validated only; not executed on Linux host)"
exit 0
