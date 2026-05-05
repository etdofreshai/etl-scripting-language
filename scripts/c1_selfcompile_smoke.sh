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
# Stage 1: build a real c1 via concatenate-then-c0+cc.
#
# The historical c1 binary built from compiler1/main.etl alone is just the
# "hello\n" → "h" smoke skeleton — its fn main() does not run the
# lex→parse→sema→emit_c pipeline, so it cannot self-compile. The real
# self-hosting compiler is the concatenation of all c1 source files plus
# compiler1/driver.etl, which provides the actual stdin→stdout fn main().
#
# Concatenation order (kept identical to the input we pipe in stage 3):
#   main.etl prelude  (skeleton fn main() stripped via sed)
#   lex.etl
#   parse.etl
#   sema.etl
#   emit_c.etl
#   driver.etl  (real fn main(): /dev/stdin → lex → parse → sema → emit_c → /dev/stdout)
# ---------------------------------------------------------------------------
echo "c1_selfcompile_smoke: build real c1 (concatenated) via scripts/build_etl.sh"
c1_src="$td/c1_real_source.etl"
sed '/^fn main()/,$d' compiler1/main.etl >  "$c1_src"
cat compiler1/lex.etl                    >> "$c1_src"
cat compiler1/parse.etl                  >> "$c1_src"
cat compiler1/sema.etl                   >> "$c1_src"
cat compiler1/emit_c.etl                 >> "$c1_src"
cat compiler1/driver.etl                 >> "$c1_src"
scripts/build_etl.sh "$c1_src" "$td/c1"

# ---------------------------------------------------------------------------
# Stage 2: concatenate the SOURCE we will feed back into c1.
# This is the same canonical c1 source set, but as INPUT to the compiler we
# just built — i.e. c1 reading c1's own source. driver.etl is the real entry
# point, so it must be in the input too (and at the end so its fn main()
# overrides any earlier one stripped from main.etl by future refactors).
# ---------------------------------------------------------------------------
concat="$td/c1_full_source.etl"
sed '/^fn main()/,$d' compiler1/main.etl >  "$concat"
cat compiler1/lex.etl                    >> "$concat"
cat compiler1/parse.etl                  >> "$concat"
cat compiler1/sema.etl                   >> "$concat"
cat compiler1/emit_c.etl                 >> "$concat"
cat compiler1/driver.etl                 >> "$concat"

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
  # The driver.etl returns deterministic exit codes per failure phase:
  #   10 = etl_read_file failed
  #   11 = lex failed
  #   12 = parse failed
  #   13 = sema failed
  #   14 = emit_c failed
  #   15 = etl_write_file failed
  # Translate these into a hint so the next chunk has a clear target.
  case "$emit_rc" in
    10) blocker_summary="driver: etl_read_file failed reading /dev/stdin" ;;
    11) blocker_summary="driver: lex() failed on c1 source (likely token-buffer or unrecognized-token blocker)" ;;
    12) blocker_summary="driver: parse() failed on c1 source (likely AST-buffer or grammar blocker)" ;;
    13) blocker_summary="driver: sema() rejected c1 source (likely typed shape unsupported by current sema)" ;;
    14) blocker_summary="driver: emit_c() rejected c1 source (likely AST shape not yet emitted by emit_c.etl)" ;;
    15) blocker_summary="driver: etl_write_file failed writing /dev/stdout" ;;
  esac

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
