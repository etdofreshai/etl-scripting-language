#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: scripts/build_etl.sh SOURCE.etl OUTPUT" >&2
  exit 2
fi

src="$1"
out="$2"
runtime="${ETL_RUNTIME:-runtime/etl_runtime.c}"
c_path="${out}.c"

python3 -m compiler0 compile "$src" -o "$c_path"
cc -Wall -Werror "$c_path" "$runtime" -I runtime -o "$out"
