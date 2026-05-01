#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
manifest="$repo_root/examples/selfeval/MANIFEST"
tmpdir="$(mktemp -d)"
pass=0
fail=0
total=0

cleanup() { rm -rf "$tmpdir"; }
trap cleanup EXIT

while read -r file expected description; do
  case "${file:-}" in
    ""|\#*) continue ;;
  esac

  total=$((total + 1))
  src="$repo_root/examples/selfeval/$file"
  golden="$repo_root/examples/selfeval/${file%.etl}.expected"
  out="$tmpdir/${file%.etl}"
  c_path="$out.c"

  printf 'selfeval: compiling %s ... ' "$file"

  if ! python3 -m compiler0 compile "$src" -o "$c_path" >/dev/null 2>&1; then
    printf 'FAIL (compile)\n'
    python3 -m compiler0 compile "$src" -o "$c_path" >&2
    fail=$((fail + 1))
    continue
  fi

  if ! cc -Wall -Werror "$c_path" "$repo_root/runtime/etl_runtime.c" \
       -I "$repo_root/runtime" -o "$out" >/dev/null 2>&1; then
    printf 'FAIL (cc)\n'
    cc -Wall -Werror "$c_path" "$repo_root/runtime/etl_runtime.c" \
       -I "$repo_root/runtime" -o "$out" >&2
    fail=$((fail + 1))
    continue
  fi

  stdout1="$tmpdir/${file%.etl}.run1"
  set +e
  "$out" > "$stdout1" 2>/dev/null
  status=$?
  set -e

  if [ "$status" -ne "$expected" ]; then
    printf 'FAIL (exit %d, expected %d)\n' "$status" "$expected"
    fail=$((fail + 1))
    continue
  fi

  if ! diff -q "$stdout1" "$golden" >/dev/null 2>&1; then
    printf 'FAIL (stdout mismatch)\n'
    diff "$stdout1" "$golden" >&2
    fail=$((fail + 1))
    continue
  fi

  stdout2="$tmpdir/${file%.etl}.run2"
  set +e
  "$out" > "$stdout2" 2>/dev/null
  status2=$?
  set -e

  if [ "$status2" -ne "$expected" ]; then
    printf 'FAIL (non-deterministic exit: %d then %d)\n' "$status" "$status2"
    fail=$((fail + 1))
    continue
  fi

  if ! diff -q "$stdout1" "$stdout2" >/dev/null 2>&1; then
    printf 'FAIL (non-deterministic output)\n'
    diff "$stdout1" "$stdout2" >&2
    fail=$((fail + 1))
    continue
  fi

  printf 'PASS (exit %d, deterministic) %s\n' "$status" "$description"
  pass=$((pass + 1))
done < "$manifest"

printf 'selfeval: %d/%d passed, %d failed\n' "$pass" "$total" "$fail"
[ "$fail" -eq 0 ]
