#!/usr/bin/env bash
set -euo pipefail

td="$(mktemp -d)"
trap 'rm -rf "$td"' EXIT

cat > "$td/full_words.etl" <<'ETL'
external function etl_alloc(bytes integer) pointer
external function etl_is_null(p pointer) boolean

type Pair structure
  left integer
  right byte
end

function main() integer
  let p pointer = etl_alloc(8)
  let b boolean = etl_is_null(p)
  if b
    return 1
  end
  let pair Pair
  pair.left = size(integer) + size(byte)
  return pair.left
end
ETL

python3 -m compiler0 compile "$td/full_words.etl" -o "$td/full_words.c"
cc -std=c11 -Wall -Werror -Iruntime "$td/full_words.c" runtime/etl_runtime.c -o "$td/full_words"

set +e
"$td/full_words" >/dev/null
status=$?
set -e

if [ "$status" -ne 5 ]; then
  echo "full_word_alias_smoke: expected 5, got $status" >&2
  exit 1
fi

echo "full_word_alias_smoke: ok (canonical full-word aliases compile and run)"
