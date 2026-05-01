#!/usr/bin/env bash
set -euo pipefail

td="$(mktemp -d)"
trap 'rm -rf "$td"' EXIT

escape_for_etl_string() {
  printf "%s" "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

run_case() {
  local name="$1"
  local source="$2"
  local expected="$3"
  local escaped
  local source_len
  local harness="$td/${name}.etl"
  local emitted="$td/${name}.c"
  local harness_bin="$td/${name}_harness"
  local emitted_bin="$td/${name}_emitted"

  escaped="$(escape_for_etl_string "$source")"
  source_len="$(printf "%s" "$source" | wc -c)"

  sed '/^fn main()/,$d' compiler1/main.etl > "$harness"
  cat compiler1/lex.etl >> "$harness"
  cat compiler1/parse.etl >> "$harness"
  cat compiler1/sema.etl >> "$harness"
  cat compiler1/emit_c.etl >> "$harness"
  cat >> "$harness" <<EOF_HARNESS
extern fn etl_write_file1024(path i8[64], buf i8[1024], len i32) i32

fn main() i32
  let source i8[256] = "$escaped"
  let tokens Token[128]
  let ast AstNode[512]
  let out i8[1024]
  let n i32 = lex(source, $source_len, tokens, 128)
  if n < 0
    ret 1
  end
  let an i32 = parse(tokens, n, ast, 512)
  if an < 0
    ret 2
  end
  if sema(ast, an) < 0
    ret 3
  end
  let emitted i32 = emit_c(ast, an, out, 1024)
  if emitted < 0
    ret 4
  end
  let path i8[64] = "$emitted"
  if etl_write_file1024(path, out, emitted) < 0
    ret 5
  end
  ret 0
end
EOF_HARNESS

  scripts/build_etl.sh "$harness" "$harness_bin"
  "$harness_bin"
  if [ ! -s "$emitted" ]; then
    echo "c1_emit_control_flow_smoke: FAIL $name - no emitted C" >&2
    exit 1
  fi
  cc -Wall -Werror "$emitted" -o "$emitted_bin"
  set +e
  "$emitted_bin" >/dev/null
  local status=$?
  set -e
  if [ "$status" -ne "$expected" ]; then
    echo "c1_emit_control_flow_smoke: FAIL $name - expected $expected, got $status" >&2
    exit 1
  fi
  echo "c1_emit_control_flow_smoke: PASS $name (exit $status)"
}

run_case let_ret "fn main() i32 let x i32 = 3 + 4 ret x end" 7
run_case if_else "fn main() i32 let x i32 = 0 if 1 x = 5 else x = 2 end ret x end" 5
run_case while_loop "fn main() i32 let x i32 = 0 while x < 5 x = x + 1 end ret x end" 5

echo "c1_emit_control_flow_smoke: ok"
