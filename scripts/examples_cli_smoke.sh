#!/usr/bin/env bash
# Smoke test for the examples-cli gate: drives bin/etl through the
# trivial examples/cli/hello.etl fixture (check + run, asserting the
# program's exit code is forwarded faithfully).
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

# Ensure compiler-0 prerequisite builds at least once. build_etl.sh is
# the common path the rest of the toolchain uses, so calling it here
# pre-flights compiler-0 + cc + the runtime before bin/etl runs.
build_probe="$(mktemp -d)"
trap 'rm -rf "$build_probe"' EXIT
scripts/build_etl.sh examples/cli/hello.etl "$build_probe/hello_probe" >/dev/null

src="examples/cli/hello.etl"

echo "examples_cli_smoke: bin/etl check $src"
bin/etl check "$src"

echo "examples_cli_smoke: bin/etl run $src (expect exit 42)"
set +e
bin/etl run "$src"
status=$?
set -e
if [ "$status" -ne 42 ]; then
  echo "examples_cli_smoke: FAIL - expected bin/etl run to forward exit 42, got $status" >&2
  exit 1
fi

echo "examples_cli_smoke: ok"
