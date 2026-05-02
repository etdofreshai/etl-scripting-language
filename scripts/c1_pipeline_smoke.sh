#!/usr/bin/env bash
set -euo pipefail

td="$(mktemp -d)"
trap 'rm -rf "$td"' EXIT

echo "c1_pipeline: build compiler-1 main harness with compiler-0"
scripts/build_etl.sh compiler1/main.etl "$td/c1"

echo "c1_pipeline: run lexer prerequisite"
scripts/c1_lex_smoke.sh

echo "c1_pipeline: run parser prerequisite"
scripts/c1_parse_smoke.sh

if [ -x scripts/c1_sema_smoke.sh ]; then
  echo "c1_pipeline: run sema smoke"
  scripts/c1_sema_smoke.sh
else
  echo "c1_pipeline: SKIP scripts/c1_sema_smoke.sh (not present yet)"
fi

if [ -x scripts/c1_emit_c_smoke.sh ]; then
  echo "c1_pipeline: run C emitter smoke"
  scripts/c1_emit_c_smoke.sh
else
  echo "c1_pipeline: SKIP scripts/c1_emit_c_smoke.sh (not present yet)"
fi

echo "c1_pipeline: run C emitter control-flow smoke"
scripts/c1_emit_control_flow_smoke.sh

echo "c1_pipeline: run source-to-C smoke"
scripts/c1_source_to_c_smoke.sh

echo "c1_pipeline: run array source-to-C smoke"
scripts/c1_source_to_c_array_smoke.sh

echo "c1_pipeline: run array variable-index source-to-C smoke"
scripts/c1_source_to_c_array_var_index_smoke.sh

echo "c1_pipeline: run byte-array assignment source-to-C smoke"
scripts/c1_source_to_c_byte_array_assign_smoke.sh

echo "c1_pipeline: run byte-array parameter source-to-C smoke"
scripts/c1_source_to_c_byte_array_param_smoke.sh

echo "c1_pipeline: run byte-string source-to-C smoke"
scripts/c1_source_to_c_byte_string_smoke.sh

echo "c1_pipeline: run byte-string variable-index source-to-C smoke"
scripts/c1_source_to_c_byte_string_var_index_smoke.sh

echo "c1_pipeline: run byte-string extern source-to-C smoke"
scripts/c1_source_to_c_byte_string_extern_smoke.sh

echo "c1_pipeline: run struct-field source-to-C smoke"
scripts/c1_source_to_c_struct_field_smoke.sh

echo "c1_pipeline: run struct-array source-to-C smoke"
scripts/c1_source_to_c_struct_array_smoke.sh

echo "c1_pipeline: run extern-call source-to-C smoke"
scripts/c1_extern_call_smoke.sh

echo "c1_pipeline: run compiler-0 behavior placeholder"
scripts/build_etl.sh examples/add_main.etl "$td/add_main"
set +e
"$td/add_main" >/dev/null
status=$?
set -e

if [ "$status" -ne 5 ]; then
  echo "c1_pipeline: FAIL - expected examples/add_main.etl to return 5 via compiler-0, got $status" >&2
  exit 1
fi

echo "c1_pipeline: ok"
