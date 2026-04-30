#!/usr/bin/env bash
set -euo pipefail

td="$(mktemp -d)"
trap 'rm -rf "$td"' EXIT

# Build compiler-1 from ETL source via compiler-0 + C runtime
scripts/build_etl.sh compiler1/main.etl "$td/c1"

# Test 1: correct input "hello\n" -> prints "h", exits 0
set +e
out="$(echo "hello" | "$td/c1")"
rc=$?
set -e

if [ "$rc" -ne 0 ]; then
  echo "c1_smoke: FAIL — expected exit 0 for 'hello', got $rc" >&2
  exit 1
fi

case "$out" in
  h*)
    ;;
  *)
    echo "c1_smoke: FAIL — expected stdout starting with 'h', got: '$out'" >&2
    exit 1
    ;;
esac

# Test 2: wrong input -> exits 1
set +e
"$td/c1" <<< "wrong" >/dev/null 2>&1
rc=$?
set -e

if [ "$rc" -ne 1 ]; then
  echo "c1_smoke: FAIL — expected exit 1 for wrong input, got $rc" >&2
  exit 1
fi

echo "c1_smoke: ok (compiler-1 skeleton built and ran correctly)"
