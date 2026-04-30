#!/usr/bin/env bash
set -u

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
manifest="$repo_root/tests/etl_corpus/MANIFEST"
tmpdir="$(mktemp -d)"
passes=0
failures=0
total=0

cleanup() {
  rm -rf "$tmpdir"
  rm -f /tmp/etl_corpus_file_ops.bin
}
trap cleanup EXIT

while read -r file expected description; do
  case "${file:-}" in
    ""|\#*) continue ;;
  esac

  total=$((total + 1))
  src="$repo_root/tests/etl_corpus/$file"
  out="$tmpdir/${file%.etl}"
  c_path="$out.c"

  if ! python3 -m compiler0 compile "$src" -o "$c_path" >/tmp/etl_corpus_compile.log 2>&1; then
    printf 'corpus smoke: FAIL %s (compile failed)\n' "$file" >&2
    cat /tmp/etl_corpus_compile.log >&2
    failures=$((failures + 1))
    continue
  fi

  if ! cc -Wall -Werror "$c_path" "$repo_root/runtime/etl_runtime.c" -I "$repo_root/runtime" -o "$out" >/tmp/etl_corpus_cc.log 2>&1; then
    printf 'corpus smoke: FAIL %s (cc failed)\n' "$file" >&2
    cat /tmp/etl_corpus_cc.log >&2
    failures=$((failures + 1))
    continue
  fi

  "$out" >/tmp/etl_corpus_stdout.log 2>/tmp/etl_corpus_stderr.log
  status=$?
  if [ "$status" -eq "$expected" ]; then
    printf 'corpus smoke: PASS %s (exit %s) %s\n' "$file" "$status" "$description"
    passes=$((passes + 1))
  else
    printf 'corpus smoke: FAIL %s (expected %s, got %s) %s\n' "$file" "$expected" "$status" "$description" >&2
    if [ -s /tmp/etl_corpus_stdout.log ]; then
      sed 's/^/stdout: /' /tmp/etl_corpus_stdout.log >&2
    fi
    if [ -s /tmp/etl_corpus_stderr.log ]; then
      sed 's/^/stderr: /' /tmp/etl_corpus_stderr.log >&2
    fi
    failures=$((failures + 1))
  fi
done < "$manifest"

printf 'corpus smoke: summary %s/%s passed, %s failed\n' "$passes" "$total" "$failures"
[ "$failures" -eq 0 ]
