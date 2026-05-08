#!/usr/bin/env bash
# Verify heap_alloc_basic.etl produces a valgrind-clean binary via the C backend.
# Requires: valgrind on PATH; install with: sudo apt-get install -y valgrind
set -euo pipefail

if ! command -v valgrind >/dev/null 2>&1; then
  echo "heap_alloc_valgrind_smoke: SKIP valgrind not found (install with: sudo apt-get install -y valgrind)"
  exit 0
fi

td="$(mktemp -d)"
trap 'rm -rf "$td"' EXIT

fixture="tests/c1_corpus/heap_alloc_basic.etl"
c0_c="$td/heap_alloc_basic.c"
c0_exe="$td/heap_alloc_basic"

# Compile fixture via compiler0 → C → gcc
python3 -m compiler0 compile "$fixture" -o "$c0_c"
cc -std=c11 -Wall -Werror -g "$c0_c" runtime/etl_runtime.c -I runtime -o "$c0_exe"

echo "heap_alloc_valgrind_smoke: running valgrind on $c0_exe"
valgrind --error-exitcode=1 --leak-check=full --errors-for-leak-kinds=all "$c0_exe"
valgrind_exit=$?

if [ "$valgrind_exit" -ne 0 ]; then
  echo "heap_alloc_valgrind_smoke: FAIL valgrind reported errors on heap_alloc_basic (exit $valgrind_exit)"
  exit 1
fi

echo "heap_alloc_valgrind_smoke: PASS heap_alloc_basic zero leaks and zero errors"

# Also run valgrind on the string fixtures (use compiler-1; compiler-0 lacks str type)
# Strip comment lines before flattening: the harness embeds the fixture as a single-line
# string literal, so any '#' comment would consume everything after it on that line.
# source_len is computed from the post-strip text so lexer bounds stay correct.
escape_for_etl_string() {
  grep -v '^[[:space:]]*#' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr '\n' ' '
}
for str_fixture in string_heap_basic string_heap_concat string_heap_eq; do
  str_c="$td/${str_fixture}.c"
  str_exe="$td/${str_fixture}"
  src_file="tests/c1_corpus/${str_fixture}.etl"
  source_text="$(escape_for_etl_string "$src_file")"
  source_len="${#source_text}"
  harness="$td/${str_fixture}_c_harness.etl"
  harness_exe="$td/${str_fixture}_c_harness"
  sed '/^fn main()/,$d' compiler1/main.etl > "$harness"
  cat compiler1/lex.etl >> "$harness"
  cat compiler1/parse.etl >> "$harness"
  cat compiler1/sema.etl >> "$harness"
  cat compiler1/emit_c.etl >> "$harness"
  cat >> "$harness" <<EOF_HARNESS
extern fn etl_write_file1024(path i8[64], buf i8[262144], len i32) i32

fn main() i32
  let source i8[131072] = "$source_text"
  let tokens Token[32768]
  let ast AstNode[32768]
  let out i8[262144]
  let n i32 = lex(source, $source_len, tokens, 32768)
  if n < 0
    ret 1
  end
  let an i32 = parse(tokens, n, ast, 32768)
  if an < 0
    ret 2
  end
  if sema(source, tokens, ast, an) < 0
    ret 3
  end
  let emitted i32 = emit_c(source, tokens, ast, an, out, 262144)
  if emitted < 0
    ret 4
  end
  let path i8[64] = "$str_c"
  if etl_write_file1024(path, out, emitted) < 0
    ret 5
  end
  ret 0
end
EOF_HARNESS
  scripts/build_etl.sh "$harness" "$harness_exe"
  "$harness_exe"
  cc -std=c11 -Wall -Werror -g "$str_c" runtime/etl_runtime.c runtime/etl_string.c -I runtime -o "$str_exe"
  echo "heap_alloc_valgrind_smoke: running valgrind on $str_exe"
  valgrind --error-exitcode=1 --leak-check=full --errors-for-leak-kinds=all "$str_exe"
  str_exit=$?
  if [ "$str_exit" -ne 0 ]; then
    echo "heap_alloc_valgrind_smoke: FAIL $str_fixture valgrind errors (exit $str_exit)"
    exit 1
  fi
  echo "heap_alloc_valgrind_smoke: PASS $str_fixture zero leaks and zero errors"
done


# Also run valgrind on the dynarr fixtures (use compiler-1; compiler-0 lacks dynarr type)
for dynarr_fixture in dynarr_basic dynarr_grow dynarr_set; do
  dynarr_c="$td/${dynarr_fixture}.c"
  dynarr_exe="$td/${dynarr_fixture}"
  src_file="tests/c1_corpus/${dynarr_fixture}.etl"
  source_text="$(escape_for_etl_string "$src_file")"
  source_len="${#source_text}"
  harness="$td/${dynarr_fixture}_c_harness.etl"
  harness_exe="$td/${dynarr_fixture}_c_harness"
  sed '/^fn main()/,$d' compiler1/main.etl > "$harness"
  cat compiler1/lex.etl >> "$harness"
  cat compiler1/parse.etl >> "$harness"
  cat compiler1/sema.etl >> "$harness"
  cat compiler1/emit_c.etl >> "$harness"
  cat >> "$harness" <<EOF_HARNESS
extern fn etl_write_file1024(path i8[64], buf i8[262144], len i32) i32

fn main() i32
  let source i8[131072] = "$source_text"
  let tokens Token[32768]
  let ast AstNode[32768]
  let out i8[262144]
  let n i32 = lex(source, $source_len, tokens, 32768)
  if n < 0
    ret 1
  end
  let an i32 = parse(tokens, n, ast, 32768)
  if an < 0
    ret 2
  end
  if sema(source, tokens, ast, an) < 0
    ret 3
  end
  let emitted i32 = emit_c(source, tokens, ast, an, out, 262144)
  if emitted < 0
    ret 4
  end
  let path i8[64] = "$dynarr_c"
  if etl_write_file1024(path, out, emitted) < 0
    ret 5
  end
  ret 0
end
EOF_HARNESS
  scripts/build_etl.sh "$harness" "$harness_exe"
  "$harness_exe"
  cc -std=c11 -Wall -Werror -g "$dynarr_c" runtime/etl_runtime.c runtime/etl_string.c runtime/etl_dynarr.c -I runtime -o "$dynarr_exe"
  echo "heap_alloc_valgrind_smoke: running valgrind on $dynarr_exe"
  valgrind --error-exitcode=1 --leak-check=full --errors-for-leak-kinds=all "$dynarr_exe"
  dynarr_exit=$?
  if [ "$dynarr_exit" -ne 0 ]; then
    echo "heap_alloc_valgrind_smoke: FAIL $dynarr_fixture valgrind errors (exit $dynarr_exit)"
    exit 1
  fi
  echo "heap_alloc_valgrind_smoke: PASS $dynarr_fixture zero leaks and zero errors"
done


# Also run valgrind on the tagged_union fixtures (use compiler-1; requires etl_etlval runtime)
for tagged_fixture in tagged_union_basic tagged_union_dispatch; do
  tagged_c="$td/${tagged_fixture}.c"
  tagged_exe="$td/${tagged_fixture}"
  src_file="tests/c1_corpus/${tagged_fixture}.etl"
  source_text="$(escape_for_etl_string "$src_file")"
  source_len="${#source_text}"
  harness="$td/${tagged_fixture}_c_harness.etl"
  harness_exe="$td/${tagged_fixture}_c_harness"
  sed '/^fn main()/,$d' compiler1/main.etl > "$harness"
  cat compiler1/lex.etl >> "$harness"
  cat compiler1/parse.etl >> "$harness"
  cat compiler1/sema.etl >> "$harness"
  cat compiler1/emit_c.etl >> "$harness"
  cat >> "$harness" <<EOF_HARNESS
extern fn etl_write_file1024(path i8[64], buf i8[262144], len i32) i32

fn main() i32
  let source i8[131072] = "$source_text"
  let tokens Token[32768]
  let ast AstNode[32768]
  let out i8[262144]
  let n i32 = lex(source, $source_len, tokens, 32768)
  if n < 0
    ret 1
  end
  let an i32 = parse(tokens, n, ast, 32768)
  if an < 0
    ret 2
  end
  if sema(source, tokens, ast, an) < 0
    ret 3
  end
  let emitted i32 = emit_c(source, tokens, ast, an, out, 262144)
  if emitted < 0
    ret 4
  end
  let path i8[64] = "$tagged_c"
  if etl_write_file1024(path, out, emitted) < 0
    ret 5
  end
  ret 0
end
EOF_HARNESS
  scripts/build_etl.sh "$harness" "$harness_exe"
  "$harness_exe"
  cc -std=c11 -Wall -Werror -g "$tagged_c" runtime/etl_runtime.c runtime/etl_string.c runtime/etl_dynarr.c runtime/etl_etlval.c -I runtime -o "$tagged_exe"
  echo "heap_alloc_valgrind_smoke: running valgrind on $tagged_exe"
  valgrind --error-exitcode=1 --leak-check=full --errors-for-leak-kinds=all "$tagged_exe"
  tagged_exit=$?
  if [ "$tagged_exit" -ne 0 ]; then
    echo "heap_alloc_valgrind_smoke: FAIL $tagged_fixture valgrind errors (exit $tagged_exit)"
    exit 1
  fi
  echo "heap_alloc_valgrind_smoke: PASS $tagged_fixture zero leaks and zero errors"
done

echo "heap_alloc_valgrind_smoke: PASS all fixtures"
