#!/usr/bin/env bash
# Smoke test for the examples-cli gate: drives bin/etl through the CLI
# examples and asserts each program's exit code is forwarded faithfully.
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

# Ensure compiler-0 prerequisite builds at least once. build_etl.sh is
# the common path the rest of the toolchain uses, so calling it here
# pre-flights compiler-0 + cc + the runtime before bin/etl runs.
build_probe="$(mktemp -d)"
trap 'rm -rf "$build_probe"' EXIT
scripts/build_etl.sh examples/cli/hello.etl "$build_probe/hello_probe" >/dev/null

run_expect() {
  name="$1"
  expected="$2"
  shift 2

  echo "examples_cli_smoke: $name (expect exit $expected)"
  set +e
  "$@"
  status=$?
  set -e
  if [ "$status" -ne "$expected" ]; then
    echo "examples_cli_smoke: FAIL - $name expected exit $expected, got $status" >&2
    exit 1
  fi
}

hello="examples/cli/hello.etl"

echo "examples_cli_smoke: bin/etl check $hello"
bin/etl check "$hello"

run_expect "hello: bin/etl run $hello" 42 bin/etl run "$hello"
run_expect "calculator: bin/etl run examples/cli/calculator.etl (EOF -> 0)" 0 \
  bash -c 'bin/etl run examples/cli/calculator.etl < /dev/null'
run_expect "file_transform: bin/etl run examples/cli/file_transform.etl <in> <out>" 0 \
  bash -c 'tmp_out=$(mktemp); bin/etl run examples/cli/file_transform.etl examples/cli/file_transform.input "$tmp_out"; rc=$?; rm -f "$tmp_out"; exit $rc'
run_expect "config_rules: bin/etl run examples/cli/config_rules.etl" 5 \
  bin/etl run examples/cli/config_rules.etl

echo "examples_cli_smoke: ok"
