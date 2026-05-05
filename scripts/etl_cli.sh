#!/bin/sh
# ETL command-line interface.
#
# Subcommands:
#   etl check FILE.etl             Run c1 lex+parse+sema on FILE.etl.
#   etl compile FILE.etl -o OUT    Compile FILE.etl to a native binary OUT.
#   etl run FILE.etl [ARGS...]     Compile to a temp binary, exec it.
#
# Implementation rules:
#   - check uses the c0-built compiler-1 lex/parse/sema pipeline.
#     The resulting binary is cached under build/etl_cli/.
#   - compile uses the durable c0 -> C -> cc path (compiler0/etl0.py
#     for C emission, then cc -std=c11 linking runtime/etl_runtime.c).
#   - run is compile + exec, forwarding the inner program's exit code.
#
# This script targets POSIX sh and assumes python3 and a C compiler
# are on PATH. No external dependencies beyond that.

set -eu

usage() {
  cat <<'USAGE'
usage: etl <command> [args]

Commands:
  check FILE.etl              Run c1 lex+parse+sema diagnostics on FILE.etl.
  compile FILE.etl -o OUT     Compile FILE.etl to a native binary at OUT.
  run FILE.etl [ARGS...]      Compile FILE.etl to a temp binary and exec it,
                              forwarding its exit code.
  --help, -h                  Show this message.

Environment:
  ETL_CC                      Override the C compiler used for compile/run
                              (default: cc).
  ETL_BUILD_DIR               Override cache dir for the c1 check binary
                              (default: <repo>/build/etl_cli).
USAGE
}

if [ "$#" -eq 0 ]; then
  usage >&2
  exit 2
fi

# Resolve repo root from the script's own location.
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$script_dir/.." && pwd)

CC_BIN="${ETL_CC:-cc}"
BUILD_DIR="${ETL_BUILD_DIR:-$REPO_ROOT/build/etl_cli}"
RUNTIME_C="$REPO_ROOT/runtime/etl_runtime.c"
RUNTIME_INC="$REPO_ROOT/runtime"

cmd="$1"
shift

case "$cmd" in
  -h|--help|help)
    usage
    exit 0
    ;;
esac

# Build the c1 check binary if absent, by combining compiler-1 lex/parse/sema
# with a small stdin-reading harness, then compiling via the c0 path.
build_c1_check() {
  c1_out="$BUILD_DIR/c1_check"
  if [ -x "$c1_out" ]; then
    return 0
  fi
  mkdir -p "$BUILD_DIR"
  c1_src="$BUILD_DIR/c1_check.etl"

  # Copy compiler1/main.etl prefix (Token/AstNode types, TK_/AN_ constants,
  # etl_read_file/etl_write_file extern decls) — drop its main.
  awk '/^fn main\(\)/{exit} {print}' "$REPO_ROOT/compiler1/main.etl" > "$c1_src"

  # Add the stdin reader extern not declared in main.etl.
  printf '\nextern fn etl_read_stdin(buf i8[131072], cap i32) i32\n\n' >> "$c1_src"

  cat "$REPO_ROOT/compiler1/lex.etl"   >> "$c1_src"
  cat "$REPO_ROOT/compiler1/parse.etl" >> "$c1_src"
  cat "$REPO_ROOT/compiler1/sema.etl"  >> "$c1_src"

  cat >> "$c1_src" <<'CHECK_MAIN'

fn main() i32
  let source i8[131072]
  let n i32 = etl_read_stdin(source, 131072)
  if n < 0
    ret 10
  end
  let tokens Token[32768]
  let ast AstNode[32768]
  let lexed i32 = lex(source, n, tokens, 32768)
  if lexed < 0
    ret 11
  end
  let parsed i32 = parse(tokens, lexed, ast, 32768)
  if parsed < 0
    ret 12
  end
  if sema(source, tokens, ast, parsed) < 0
    ret 13
  end
  ret 0
end
CHECK_MAIN

  (
    cd "$REPO_ROOT"
    scripts/build_etl.sh "$c1_src" "$c1_out"
  ) >/dev/null
}

# Compile FILE.etl to OUT via compiler0 + cc -std=c11.
do_compile() {
  src="$1"
  out="$2"
  if [ ! -f "$src" ]; then
    printf 'etl: error: source file not found: %s\n' "$src" >&2
    return 1
  fi
  c_path="$out.c"
  out_dir=$(dirname -- "$out")
  mkdir -p "$out_dir"
  python3 -m compiler0 compile "$src" -o "$c_path"
  "$CC_BIN" -std=c11 -Wall -Werror "$c_path" "$RUNTIME_C" -I "$RUNTIME_INC" -o "$out"
}

cmd_check() {
  if [ "$#" -ne 1 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    cat >&2 <<'CHECK_USAGE'
usage: etl check FILE.etl

Runs the compiler-1 lex+parse+sema pipeline on FILE.etl. Exits 0 on
accept, non-zero on reject.

Exit codes:
  0   accepted
  10  could not read source
  11  lex error
  12  parse error
  13  sema error
CHECK_USAGE
    return 2
  fi
  src="$1"
  if [ ! -f "$src" ]; then
    printf 'etl check: error: source file not found: %s\n' "$src" >&2
    return 1
  fi
  build_c1_check
  set +e
  "$BUILD_DIR/c1_check" < "$src"
  status=$?
  set -e
  case "$status" in
    0)
      printf 'etl check: %s: accepted\n' "$src"
      return 0
      ;;
    10)
      printf 'etl check: %s: failed to read source\n' "$src" >&2
      return "$status"
      ;;
    11)
      printf 'etl check: %s: lex error\n' "$src" >&2
      return "$status"
      ;;
    12)
      printf 'etl check: %s: parse error\n' "$src" >&2
      return "$status"
      ;;
    13)
      printf 'etl check: %s: sema error\n' "$src" >&2
      return "$status"
      ;;
    *)
      printf 'etl check: %s: rejected (exit %s)\n' "$src" "$status" >&2
      return "$status"
      ;;
  esac
}

cmd_compile() {
  src=""
  out=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -h|--help)
        cat >&2 <<'COMPILE_USAGE'
usage: etl compile FILE.etl -o OUT

Compiles FILE.etl to a native binary at OUT using compiler-0
(compiler0/etl0.py) plus cc -std=c11 linked against runtime/etl_runtime.c.
COMPILE_USAGE
        return 2
        ;;
      -o)
        if [ "$#" -lt 2 ]; then
          printf 'etl compile: error: -o requires an argument\n' >&2
          return 2
        fi
        out="$2"
        shift 2
        ;;
      -o*)
        out=${1#-o}
        shift
        ;;
      --output=*)
        out=${1#--output=}
        shift
        ;;
      --)
        shift
        ;;
      -*)
        printf 'etl compile: error: unknown option: %s\n' "$1" >&2
        return 2
        ;;
      *)
        if [ -z "$src" ]; then
          src="$1"
        else
          printf 'etl compile: error: unexpected argument: %s\n' "$1" >&2
          return 2
        fi
        shift
        ;;
    esac
  done
  if [ -z "$src" ] || [ -z "$out" ]; then
    printf 'usage: etl compile FILE.etl -o OUT\n' >&2
    return 2
  fi
  do_compile "$src" "$out"
}

cmd_run() {
  if [ "$#" -lt 1 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    cat >&2 <<'RUN_USAGE'
usage: etl run FILE.etl [ARGS...]

Compiles FILE.etl to a temporary binary, executes it, and forwards the
binary's exit code.
RUN_USAGE
    return 2
  fi
  src="$1"
  shift
  tmpdir=$(mktemp -d)
  # Cleanup on exit; ensure mktemp dir is removed even on error.
  trap 'rm -rf "$tmpdir"' EXIT INT HUP TERM
  bin_path="$tmpdir/etl_run"
  do_compile "$src" "$bin_path"
  set +e
  "$bin_path" "$@"
  status=$?
  set -e
  rm -rf "$tmpdir"
  trap - EXIT INT HUP TERM
  return "$status"
}

case "$cmd" in
  check)
    cmd_check "$@"
    ;;
  compile)
    cmd_compile "$@"
    ;;
  run)
    cmd_run "$@"
    ;;
  *)
    printf 'etl: unknown command: %s\n' "$cmd" >&2
    usage >&2
    exit 2
    ;;
esac
