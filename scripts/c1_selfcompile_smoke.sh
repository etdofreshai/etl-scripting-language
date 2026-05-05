#!/usr/bin/env bash
# c1_selfcompile_smoke.sh — probe the c1→c2 self-compile chain.
#
# Builds the c0-built c1 binary via scripts/build_etl.sh, concatenates the
# canonical c1 source files (main + lex + parse + sema + emit_c), pipes
# that source into c1, captures emitted C, and tries to cc the result into
# a c2 candidate binary. On full success, writes a PASS manifest. On any
# failure (c1-emit phase or cc phase), records the first blocker with a
# stderr excerpt to build/fixedpoint/selfcompile-status.md.
#
# This probe is allowed to fail loudly today; the recorded blocker drives
# the next chunk of fixed-point work.

set -euo pipefail

mkdir -p build/fixedpoint

td="$(mktemp -d)"
trap 'rm -rf "$td"' EXIT

emit_out="build/fixedpoint/c1_self.c"
emit_err="build/fixedpoint/c1_self.stderr"
cc_err="build/fixedpoint/c1_self.cc.stderr"
status_pass="build/fixedpoint/c1_self_status.md"
status_blocker="build/fixedpoint/selfcompile-status.md"
c2_bin="build/fixedpoint/c2"

# Clean prior outputs so a stale artifact never masks today's failure.
rm -f "$emit_out" "$emit_err" "$cc_err" "$status_pass" "$status_blocker" "$c2_bin"

# ---------------------------------------------------------------------------
# Stage 1: build c1 via the canonical c0+cc pipeline.
# scripts/build_etl.sh runs python -m compiler0 compile … && cc … and is the
# canonical way to build the c1 binary. We build from compiler1/main.etl, the
# same entrypoint scripts/c1_pipeline_smoke.sh and scripts/c1_smoke.sh use.
# ---------------------------------------------------------------------------
echo "c1_selfcompile_smoke: build c1 via scripts/build_etl.sh"
scripts/build_etl.sh compiler1/main.etl "$td/c1"

# ---------------------------------------------------------------------------
# Stage 2: concatenate the canonical c1 source set.
# Order matches docs/fixed-point-plan.md "Stage A" description and the
# concatenation order used by scripts/c1_source_to_c_smoke.sh:
#   main.etl  +  lex.etl  +  parse.etl  +  sema.etl  +  emit_c.etl
# ---------------------------------------------------------------------------
concat="$td/c1_full_source.etl"
cat compiler1/main.etl    >  "$concat"
cat compiler1/lex.etl     >> "$concat"
cat compiler1/parse.etl   >> "$concat"
cat compiler1/sema.etl    >> "$concat"
cat compiler1/emit_c.etl  >> "$concat"

concat_bytes=$(wc -c < "$concat")
echo "c1_selfcompile_smoke: concatenated c1 source = ${concat_bytes} bytes"

# ---------------------------------------------------------------------------
# Stage 3: feed the concatenated source to c1, capture emitted C + stderr.
# c1 reads from /dev/stdin via etl_read_file in compiler1/main.etl. We
# redirect stdin from the concat file and capture stdout/stderr.
# ---------------------------------------------------------------------------
echo "c1_selfcompile_smoke: piping concatenated source into c1"
set +e
"$td/c1" < "$concat" > "$emit_out" 2> "$emit_err"
emit_rc=$?
set -e

emit_bytes=0
if [ -f "$emit_out" ]; then
  emit_bytes=$(wc -c < "$emit_out")
fi

if [ "$emit_rc" -ne 0 ] || [ "$emit_bytes" -eq 0 ]; then
  blocker_summary="c1 emit phase exited with code ${emit_rc} (emitted ${emit_bytes} bytes)"
  # Heuristic: the current compiler1/main.etl is still the "hello\n" → "h"
  # skeleton that exits 1 silently for any input that is not exactly
  # "hello\n". If we observe rc=1, no stdout, and no stderr, name that
  # specific blocker so the next chunk has a clear target.
  if [ "$emit_rc" -eq 1 ] && [ "$emit_bytes" -eq 0 ] && [ ! -s "$emit_err" ]; then
    blocker_summary="compiler1/main.etl is still the 'hello\\n' → 'h' skeleton harness; it does not yet implement a compile-from-stdin driver (lex/parse/sema/emit_c → /dev/stdout)"
  fi

  {
    echo "# c1 self-compile smoke status: BLOCKED at c1-emit"
    echo
    echo "- Phase: **c1-emit**"
    echo "- c1 exit code: \`${emit_rc}\`"
    echo "- Emitted C size: \`${emit_bytes}\` bytes"
    echo "- Concatenated source size: \`${concat_bytes}\` bytes"
    echo "- Concatenation order: main.etl + lex.etl + parse.etl + sema.etl + emit_c.etl"
    echo
    echo "## First blocker"
    echo
    echo "${blocker_summary}"
    echo
    echo "## c1 stderr (first 30 lines)"
    echo
    echo '```'
    if [ -s "$emit_err" ]; then
      head -n 30 "$emit_err"
    else
      echo "(empty)"
    fi
    echo '```'
  } > "$status_blocker"

  echo "c1_selfcompile_smoke: FAIL — first blocker (c1-emit, rc=${emit_rc}): ${blocker_summary}; see ${status_blocker}" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Stage 4: cc the emitted C into a c2 candidate, linking the runtime.
# ---------------------------------------------------------------------------
echo "c1_selfcompile_smoke: emitted C looks non-empty (${emit_bytes} bytes); invoking cc"
set +e
cc -std=c11 -Wall -Wextra -Werror "$emit_out" runtime/etl_runtime.c -o "$c2_bin" 2> "$cc_err"
cc_rc=$?
set -e

if [ "$cc_rc" -ne 0 ]; then
  first_err=$(grep -m1 -E ': (error|fatal error):' "$cc_err" 2>/dev/null || true)
  if [ -z "$first_err" ]; then
    first_err=$(head -n1 "$cc_err" 2>/dev/null || true)
  fi
  if [ -z "$first_err" ]; then
    first_err="(cc produced no stderr output)"
  fi

  {
    echo "# c1 self-compile smoke status: BLOCKED at cc"
    echo
    echo "- Phase: **cc**"
    echo "- cc exit code: \`${cc_rc}\`"
    echo "- Emitted C size: \`${emit_bytes}\` bytes"
    echo "- cc command: \`cc -std=c11 -Wall -Wextra -Werror ${emit_out} runtime/etl_runtime.c -o ${c2_bin}\`"
    echo
    echo "## First blocker"
    echo
    echo "First cc error: ${first_err}"
    echo
    echo "## cc stderr (first 30 lines)"
    echo
    echo '```'
    head -n 30 "$cc_err"
    echo '```'
  } > "$status_blocker"

  echo "c1_selfcompile_smoke: FAIL — first blocker (cc, rc=${cc_rc}): ${first_err}; see ${status_blocker}" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Stage 5: full success — record manifest and exit 0.
# ---------------------------------------------------------------------------
sha=$(sha256sum "$emit_out" | awk '{print $1}')
{
  echo "# c1 self-compile smoke status: PASS"
  echo
  echo "## Manifest"
  echo
  echo "- c1_self.c sha256: \`${sha}\`"
  echo "- c1_self.c bytes: \`${emit_bytes}\`"
  echo "- concatenated source bytes: \`${concat_bytes}\`"
  echo "- c2 binary: \`${c2_bin}\`"
  echo "- concatenation order: main.etl + lex.etl + parse.etl + sema.etl + emit_c.etl"
} > "$status_pass"

echo "c1_selfcompile_smoke: ok"
