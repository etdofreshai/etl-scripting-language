#!/usr/bin/env bash
# Pure-C software framebuffer graphics smoke test.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

mkdir -p "$repo_root/build/graphics"

src="$repo_root/examples/graphics/software_framebuffer.etl"
c_path="$tmpdir/software_framebuffer.c"
bin="$tmpdir/software_framebuffer"
stdout_file="$tmpdir/stdout"

echo "software-graphics: compiling software_framebuffer.etl ..."
python3 -m compiler0 compile "$src" -o "$c_path"

echo "software-graphics: linking pure-C framebuffer ..."
cc -std=c11 -Wall -Werror "$c_path" \
   "$repo_root/runtime/etl_runtime.c" \
   "$repo_root/runtime/etl_graphics_software.c" \
   -I "$repo_root/runtime" \
   -o "$bin"

echo "software-graphics: running software_framebuffer ..."
set +e
"$bin" > "$stdout_file" 2>&1
status=$?
set -e

if [ "$status" -ne 0 ]; then
  echo "software-graphics: FAIL (exit $status)" >&2
  cat "$stdout_file" >&2
  exit 1
fi

expected="$tmpdir/expected"
cat > "$expected" <<'EOF'
16711680
65280
255
16777215
660510
EOF

if ! diff -u "$expected" "$stdout_file"; then
  echo "software-graphics: FAIL (unexpected pixel values)" >&2
  exit 1
fi

ppm="$repo_root/build/graphics/software_framebuffer.ppm"
if [ ! -f "$ppm" ]; then
  echo "software-graphics: FAIL (PPM artifact not found at $ppm)" >&2
  exit 1
fi

if ! head -1 "$ppm" | grep -q '^P6$'; then
  echo "software-graphics: FAIL (invalid PPM header)" >&2
  exit 1
fi

hash="$(sha256sum "$ppm" | awk '{print $1}')"
expected_hash="806589a4925e514031ae8f0bdebb7e357406a9a329fb430102872181ebb1a142"
if [ "$hash" != "$expected_hash" ]; then
  echo "software-graphics: FAIL (expected sha256 $expected_hash, got $hash)" >&2
  exit 1
fi

echo "software-graphics: PASS (4x4 PPM, pixels and sha256 verified)"
