#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmpdir="$(mktemp -d)"
cleanup() { rm -rf "$tmpdir"; }
trap cleanup EXIT

src="$repo_root/examples/selfeval/trace_artifact.etl"
golden_stdout="$repo_root/examples/selfeval/trace_artifact.expected"
golden_artifact="$repo_root/examples/selfeval/trace_artifact.artifact"
build_dir="$repo_root/build/selfeval"
artifact="$build_dir/trace_artifact.csv"
expected_status=15
expected_sha="cc1c12aecf2110626992b8fa09fe1b63cc32b9f15b986021b20b18cb4b76c2e8"
out="$tmpdir/trace_artifact"
c_path="$out.c"

mkdir -p "$build_dir"
rm -f "$artifact"

printf 'selfeval-trace: compiling trace_artifact.etl ... '
python3 -m compiler0 compile "$src" -o "$c_path" >/dev/null
cc -Wall -Werror "$c_path" "$repo_root/runtime/etl_runtime.c" \
  -I "$repo_root/runtime" -o "$out" >/dev/null
printf 'PASS\n'

run_trace() {
  local stdout_path="$1"
  local artifact_copy="$2"

  rm -f "$artifact"
  set +e
  "$out" > "$stdout_path" 2>/dev/null
  local status=$?
  set -e

  if [ "$status" -ne "$expected_status" ]; then
    printf 'selfeval-trace: FAIL (exit %d, expected %d)\n' "$status" "$expected_status" >&2
    return 1
  fi

  if ! diff -q "$stdout_path" "$golden_stdout" >/dev/null 2>&1; then
    printf 'selfeval-trace: FAIL (stdout mismatch)\n' >&2
    diff "$stdout_path" "$golden_stdout" >&2
    return 1
  fi

  if [ ! -f "$artifact" ]; then
    printf 'selfeval-trace: FAIL (missing artifact %s)\n' "$artifact" >&2
    return 1
  fi

  if ! diff -q "$artifact" "$golden_artifact" >/dev/null 2>&1; then
    printf 'selfeval-trace: FAIL (artifact mismatch)\n' >&2
    diff "$artifact" "$golden_artifact" >&2
    return 1
  fi

  local sha
  sha="$(sha256sum "$artifact" | awk '{print $1}')"
  if [ "$sha" != "$expected_sha" ]; then
    printf 'selfeval-trace: FAIL (artifact sha256 %s, expected %s)\n' "$sha" "$expected_sha" >&2
    return 1
  fi

  cp "$artifact" "$artifact_copy"
}

run_trace "$tmpdir/run1.stdout" "$tmpdir/run1.artifact"
run_trace "$tmpdir/run2.stdout" "$tmpdir/run2.artifact"

if ! diff -q "$tmpdir/run1.stdout" "$tmpdir/run2.stdout" >/dev/null 2>&1; then
  printf 'selfeval-trace: FAIL (non-deterministic stdout)\n' >&2
  diff "$tmpdir/run1.stdout" "$tmpdir/run2.stdout" >&2
  exit 1
fi

if ! diff -q "$tmpdir/run1.artifact" "$tmpdir/run2.artifact" >/dev/null 2>&1; then
  printf 'selfeval-trace: FAIL (non-deterministic artifact)\n' >&2
  diff "$tmpdir/run1.artifact" "$tmpdir/run2.artifact" >&2
  exit 1
fi

sha="$(sha256sum "$artifact" | awk '{print $1}')"
printf 'selfeval-trace: PASS (exit %d, stdout golden, artifact sha256=%s, deterministic)\n' "$expected_status" "$sha"
