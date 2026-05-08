#!/usr/bin/env bash
# c1_bootstrap_smoke.sh — c0 → c1 → c2 → c3 → c4 fixed-point chain probe.
#
# Builds upon scripts/c1_selfcompile_smoke.sh, which produces a c2 binary
# from c1's emitted C. This script extends that into a multi-stage chain:
#
#   c1 (built by c0)        — already exists after selfcompile probe
#   c2 = cc(c1.emit(c1.src)) — built by selfcompile probe
#   c3 = cc(c2.emit(c1.src)) — built here
#   c4 = cc(c3.emit(c1.src)) — built here
#
# The fixed-point criterion is byte-identical emitted C across stages:
# sha256(c1_self.c) == sha256(c2_self.c) == sha256(c3_self.c). Three
# stages agreeing means c1 has reached self-compilation fixed point and
# c0 can be frozen as a historical bootstrap.
#
# Today, this script will fail at the precondition phase because
# scripts/c1_selfcompile_smoke.sh itself currently fails at the emit_c
# stage (compiler1/emit_c.etl does not yet emit some AST shape used in
# c1 source). When that gap closes, this script automatically advances.
#
# The probe is allowed to fail loudly. The recorded status drives the
# next chunk of fixed-point work.

set -euo pipefail

mkdir -p build/fixedpoint

td="$(mktemp -d)"
trap 'rm -rf "$td"' EXIT

status_file="build/fixedpoint/bootstrap-status.md"
log_file="build/fixedpoint/bootstrap.log"

c1_self="build/fixedpoint/c1_self.c"
c2_self="build/fixedpoint/c2_self.c"
c3_self="build/fixedpoint/c3_self.c"
c2_bin="build/fixedpoint/c2"
c3_bin="build/fixedpoint/c3"
c4_bin="build/fixedpoint/c4"

# Clean prior outputs so a stale artifact never masks today's failure.
rm -f "$c2_self" "$c3_self" "$c3_bin" "$c4_bin" "$status_file" "$log_file"

ts() { date -u "+%Y-%m-%dT%H:%M:%SZ"; }
log() { echo "$(ts) $*" | tee -a "$log_file"; }

# ---------------------------------------------------------------------------
# Stage 0: precondition — selfhost-selfcompile must be green.
# That probe builds c1, emits c1's C as build/fixedpoint/c1_self.c, and ccs
# it into build/fixedpoint/c2. If that fails, the chain cannot start.
# ---------------------------------------------------------------------------
log "stage 0: run scripts/c1_selfcompile_smoke.sh as precondition"
set +e
scripts/c1_selfcompile_smoke.sh > "$td/sc.out" 2> "$td/sc.err"
sc_rc=$?
set -e

if [ "$sc_rc" -ne 0 ]; then
  blocker_excerpt="(no selfcompile-status.md found)"
  if [ -s "build/fixedpoint/selfcompile-status.md" ]; then
    blocker_excerpt="$(head -n 30 build/fixedpoint/selfcompile-status.md)"
  fi
  {
    echo "# c1 bootstrap chain status: BLOCKED-AT-SELFCOMPILE"
    echo
    echo "- Phase: precondition (selfhost-selfcompile)"
    echo "- selfhost-selfcompile exit code: \`${sc_rc}\`"
    echo
    echo "## Recorded blocker"
    echo
    echo '```'
    echo "$blocker_excerpt"
    echo '```'
    echo
    echo "Bootstrap chain cannot start until c1 self-compile is green."
  } > "$status_file"
  echo "c1_bootstrap_smoke: FAIL — c1 self-compile not yet green; bootstrap chain cannot start; see ${status_file}" >&2
  exit 1
fi

# After selfcompile success, c2_bin and c1_self.c exist.
if [ ! -x "$c2_bin" ] || [ ! -s "$c1_self" ]; then
  echo "c1_bootstrap_smoke: FAIL — selfcompile succeeded but c2 or c1_self.c missing" >&2
  exit 2
fi

# Reconstruct the canonical concatenated c1 source (same content the
# selfcompile probe used). Mirrors scripts/c1_selfcompile_smoke.sh stage 2.
c1_src="$td/c1_full_source.etl"
sed '/^fn main()/,$d' compiler1/main.etl >  "$c1_src"
cat compiler1/lex.etl                    >> "$c1_src"
cat compiler1/parse.etl                  >> "$c1_src"
cat compiler1/sema.etl                   >> "$c1_src"
cat compiler1/emit_c.etl                 >> "$c1_src"
cat compiler1/driver.etl                 >> "$c1_src"

c1_sha=$(sha256sum "$c1_self" | awk '{print $1}')
log "stage 0: precondition OK (c1_self.c sha=${c1_sha:0:12}, c2 binary ready)"

# ---------------------------------------------------------------------------
# Stage 1: c2 emits its own version of c1's C, link as c3.
# ---------------------------------------------------------------------------
log "stage 1: c2 < c1_full_source.etl > c2_self.c, then cc -> c3"
set +e
"$c2_bin" < "$c1_src" > "$c2_self" 2> "$td/c2.err"
c2_rc=$?
set -e
if [ "$c2_rc" -ne 0 ] || [ ! -s "$c2_self" ]; then
  {
    echo "# c1 bootstrap chain status: BLOCKED-AT-C2-EMIT"
    echo
    echo "- Stage: c2 emit"
    echo "- c2 exit code: \`${c2_rc}\`"
    echo "- c2_self.c size: \`$(wc -c < "$c2_self" 2>/dev/null || echo 0)\`"
    echo
    echo "## c2 stderr (first 30 lines)"
    echo '```'
    if [ -s "$td/c2.err" ]; then head -n 30 "$td/c2.err"; else echo "(empty)"; fi
    echo '```'
  } > "$status_file"
  echo "c1_bootstrap_smoke: FAIL — c2 emit failed (rc=${c2_rc}); see ${status_file}" >&2
  exit 1
fi
c2_sha=$(sha256sum "$c2_self" | awk '{print $1}')
log "stage 1: c2 emitted ${c2_self} sha=${c2_sha:0:12}"

set +e
cc -std=c11 -Wall -Werror "$c2_self" runtime/etl_runtime.c -I runtime -o "$c3_bin" 2> "$td/cc3.err"
cc3_rc=$?
set -e
if [ "$cc3_rc" -ne 0 ]; then
  {
    echo "# c1 bootstrap chain status: BLOCKED-AT-C3-CC"
    echo
    echo "- Stage: cc(c2_self.c) -> c3"
    echo "- cc exit code: \`${cc3_rc}\`"
    echo
    echo "## cc stderr (first 30 lines)"
    echo '```'
    head -n 30 "$td/cc3.err"
    echo '```'
  } > "$status_file"
  echo "c1_bootstrap_smoke: FAIL — c3 cc failed (rc=${cc3_rc}); see ${status_file}" >&2
  exit 1
fi
log "stage 1: c3 binary ready"

# ---------------------------------------------------------------------------
# Stage 2: c3 emits c1's C, link as c4.
# ---------------------------------------------------------------------------
log "stage 2: c3 < c1_full_source.etl > c3_self.c, then cc -> c4"
set +e
"$c3_bin" < "$c1_src" > "$c3_self" 2> "$td/c3.err"
c3_rc=$?
set -e
if [ "$c3_rc" -ne 0 ] || [ ! -s "$c3_self" ]; then
  {
    echo "# c1 bootstrap chain status: BLOCKED-AT-C3-EMIT"
    echo
    echo "- Stage: c3 emit"
    echo "- c3 exit code: \`${c3_rc}\`"
    echo
    echo "## c3 stderr (first 30 lines)"
    echo '```'
    if [ -s "$td/c3.err" ]; then head -n 30 "$td/c3.err"; else echo "(empty)"; fi
    echo '```'
  } > "$status_file"
  echo "c1_bootstrap_smoke: FAIL — c3 emit failed (rc=${c3_rc}); see ${status_file}" >&2
  exit 1
fi
c3_sha=$(sha256sum "$c3_self" | awk '{print $1}')
log "stage 2: c3 emitted ${c3_self} sha=${c3_sha:0:12}"

set +e
cc -std=c11 -Wall -Werror "$c3_self" runtime/etl_runtime.c -I runtime -o "$c4_bin" 2> "$td/cc4.err"
cc4_rc=$?
set -e
if [ "$cc4_rc" -ne 0 ]; then
  {
    echo "# c1 bootstrap chain status: BLOCKED-AT-C4-CC"
    echo
    echo "- Stage: cc(c3_self.c) -> c4"
    echo "- cc exit code: \`${cc4_rc}\`"
    echo
    echo "## cc stderr (first 30 lines)"
    echo '```'
    head -n 30 "$td/cc4.err"
    echo '```'
  } > "$status_file"
  echo "c1_bootstrap_smoke: FAIL — c4 cc failed (rc=${cc4_rc}); see ${status_file}" >&2
  exit 1
fi
log "stage 2: c4 binary ready"

# ---------------------------------------------------------------------------
# Stage 3: fixed-point check.
# ---------------------------------------------------------------------------
log "stage 3: fixed-point hash compare c1 vs c2 vs c3 emitted C"

if [ "$c1_sha" != "$c2_sha" ] || [ "$c2_sha" != "$c3_sha" ]; then
  {
    echo "# c1 bootstrap chain status: BLOCKED-AT-FIXEDPOINT"
    echo
    echo "- Stage: fixed-point hash compare"
    echo "- c1_self.c sha256: \`${c1_sha}\`"
    echo "- c2_self.c sha256: \`${c2_sha}\`"
    echo "- c3_self.c sha256: \`${c3_sha}\`"
    echo
    echo "Hashes differ across stages. The compiler is not yet at fixed point."
    echo "Likely cause: emit_c is not yet deterministic across self-compilation"
    echo "or some semantic detail differs between c1 (built by c0) and c2 (built by c1)."
  } > "$status_file"
  echo "c1_bootstrap_smoke: FAIL — fixed point not reached: stages disagree; see ${status_file}" >&2
  exit 2
fi

# All three identical. PASS.
{
  echo "# c1 bootstrap chain status: PASS"
  echo
  echo "Three consecutive bootstraps produced byte-identical emitted C."
  echo "compiler-1 has reached self-compilation fixed point."
  echo
  echo "## Manifest"
  echo
  echo "- c1_self.c sha256: \`${c1_sha}\`"
  echo "- c2_self.c sha256: \`${c2_sha}\`"
  echo "- c3_self.c sha256: \`${c3_sha}\`"
  echo "- c2 binary: \`${c2_bin}\`"
  echo "- c3 binary: \`${c3_bin}\`"
  echo "- c4 binary: \`${c4_bin}\`"
  echo
  echo "## Bootstrap log"
  echo
  echo '```'
  cat "$log_file"
  echo '```'
} > "$status_file"

log "stage 3: PASS — three-stage fixed point achieved (sha=${c1_sha:0:12})"
echo "c1_bootstrap_smoke: ok (c1=c2=c3 emitted-C hashes match; ${c1_sha:0:12})"
