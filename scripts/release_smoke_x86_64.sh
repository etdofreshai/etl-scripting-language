#!/usr/bin/env bash
# Smoke-test the Linux x86_64 release tarball.
#
# Untars build/release/etl-linux-x86_64.tar.gz into a temporary directory,
# then compiles and runs a minimal ETL "hello-world" program:
#
#   fn main() i32 ret 42 end
#
# Verifies the compiled binary exits with code 42, then cleans up.
# Exits 0 on success, non-zero on any failure.

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

TARBALL="$REPO_ROOT/build/release/etl-linux-x86_64.tar.gz"

if [ ! -f "$TARBALL" ]; then
  echo "release_smoke_x86_64: FAIL — tarball not found: $TARBALL" >&2
  exit 1
fi

td=$(mktemp -d)
trap 'rm -rf "$td"' EXIT INT HUP TERM

echo "release_smoke_x86_64: unpacking $TARBALL into $td ..."
tar -xzf "$TARBALL" -C "$td"

ETL_DIST="$td/etl-linux-x86_64"

if [ ! -x "$ETL_DIST/bin/etl" ]; then
  echo "release_smoke_x86_64: FAIL — bin/etl not found or not executable" >&2
  exit 1
fi

if [ ! -x "$ETL_DIST/bin/etl-vm-etl" ]; then
  echo "release_smoke_x86_64: FAIL — bin/etl-vm-etl not found or not executable" >&2
  exit 1
fi

if [ ! -f "$ETL_DIST/VERSION" ]; then
  echo "release_smoke_x86_64: FAIL — VERSION file missing" >&2
  exit 1
fi

echo "release_smoke_x86_64: VERSION=$(cat "$ETL_DIST/VERSION")"

# Write a minimal ETL hello-world program.
HELLO_ETL="$td/hello.etl"
cat > "$HELLO_ETL" <<'ETL_SRC'
fn main() i32
  ret 42
end
ETL_SRC

# Compile and run from the clean temp tree (no repo context needed).
HELLO_BIN="$td/hello"

echo "release_smoke_x86_64: compiling $HELLO_ETL via $ETL_DIST/bin/etl ..."
# Use ETL_ROOT override so the bundled CLI finds its own compiler0/runtime.
ETL_ROOT="$ETL_DIST" \
ETL_BUILD_DIR="$td/etl_build" \
  "$ETL_DIST/bin/etl" compile "$HELLO_ETL" -o "$HELLO_BIN"

echo "release_smoke_x86_64: running compiled binary ..."
set +e
"$HELLO_BIN"
exit_code=$?
set -e

if [ "$exit_code" -ne 42 ]; then
  echo "release_smoke_x86_64: FAIL — expected exit 42, got $exit_code" >&2
  exit 1
fi

echo "release_smoke_x86_64: OK — exit code $exit_code as expected"
exit 0
